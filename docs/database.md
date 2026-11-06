# Databases

iyi-web has no database layer of its own and will not grow one. The iyi
packages for that already exist and are what this page uses:

| Package | What it is |
|---|---|
| [iyilang/db](https://github.com/iyilang/db) | The common interface: `Db.open`, a connection pool (`Database`), `exec` / `query` / `scalar`, transactions, rows read into your types |
| [iyilang/pg](https://github.com/iyilang/pg) | PostgreSQL driver, `postgres://` URLs, `$1` placeholders |
| [iyilang/mysql](https://github.com/iyilang/mysql) | MySQL driver, `mysql://` URLs, `?` placeholders |

`examples/postgres/` is a whole application built this way: a JSON API over
PostgreSQL with a pool, migrations that run when it starts and a smoke
script. This page walks through what it does and why.

## Adding the packages

```sh
iyi get github.com/iyilang/pg --as pg
iyi get github.com/iyilang/db --as db
```

```
require github.com/sdogruyol/iyi-web v0.5.1 as web
require github.com/iyilang/db v0.4.0 as db
require github.com/iyilang/pg v0.4.0 as pg
```

`import pg` registers the driver for `postgres://` and `postgresql://`;
`import db` gives `Db.open`. Both lines are needed: a package that another
package requires is not in scope in your files until you import it.

## One pool, opened at start

```iyi
import db
import pg
import db/db/core::{Database}
import db/db/errors::{DBError}
import web/iyi_web/dsl::*

url = ENV["DATABASE_URL"]? || "postgres:///"

database = case opened = Db.open(url)
           in Database then opened
           in DBError
             STDERR.puts "cannot open " + url + ": " + opened.message
             exit 1
           end
```

`Db.open` answers a `Database`, which is a pool, or a `DBError`: errors are
values, so a database that is down at start is a branch you write, not an
exception you forget. Stopping before `run` is the better default than a
server that answers `503` to everything.

The pool is configured in the URL's query string:

```
postgres://app:secret@db.internal/shop?max_pool_size=20&max_idle_pool_size=20&checkout_timeout=2
```

| Option | Default | |
|---|---|---|
| `max_pool_size` | 0 (unlimited) | Connections open at most. Set it: PostgreSQL's own limit is per server. |
| `max_idle_pool_size` | 1 | Connections kept open when idle. With the default, every connection but one is closed after a burst and opened again for the next; under steady load set it to `max_pool_size`. |
| `initial_pool_size` | 1 | Opened by `Db.open`. |
| `checkout_timeout` | 5.0 | Seconds a request waits for a free connection before the query answers a `DBError`. |
| `retry_attempts`, `retry_delay` | 1, 0.2 | Reconnecting a lost connection. |

The driver's own options go in the same string (`sslmode`,
`application_name`, `connect_timeout`, ...), and anything missing comes
from `PGHOST`, `PGUSER`, `PGPASSWORD` and the rest, as libpq takes them.
See the [pg README](https://github.com/iyilang/pg#usage).

## Handing the pool to routes

Routes run on every core at once, and the compiler checks what each route
block captures. A `Database` is `Share` - the pool decides under a `Mutex`
which task gets which connection - so routes may capture it and the server
keeps every core. Build the router in a function that takes the pool:

```iyi
# routes.iyi
module routes

import db/db/core::{Database}
import db/db/errors::{DBError}
import web/iyi_web/router::{Router}
import web/iyi_web/failure::{StatusError}
import todos::*

pub def todo_routes(db : Database) : Router
  router = Router.new

  router.get "/todos/:id" do |env|
    id = env.params.url["id"].to_i64?
    case todo = (id ? find_todo(db, id) : nil)
    in DBError then todo
    in Todo    then env.json(todo)
    in Nil     then StatusError.new(404)
    end
  end

  router
end
```

```iyi
# app.iyi
mount todo_routes(database)
run
```

The pool is an argument rather than a constant, so the program decides which
database (from `DATABASE_URL`), and a test can hand in another.

## Queries

Keep the SQL in functions that answer a value or a `DBError`, and nothing
about HTTP:

```iyi
module todos

import std/json::{serializable}
import db/db/core::{Database}
import db/db/errors::{DBError}
import db/db/serializable::{db_serializable}

pub struct Todo
  getter id : Int64
  getter title : String
  getter done : Bool
  derive db_serializable   # read from a row, column by column
  derive serializable      # written as JSON by env.json
end

pub def find_todo(db : Database, id : Int64) : Todo | Nil | DBError
  db.query_one?("SELECT id, title, done FROM todos WHERE id = $1", id, as: Todo)
end

pub def create_todo(db : Database, title : String, done : Bool) : Todo | DBError
  db.query_one("INSERT INTO todos (title, done) VALUES ($1, $2) RETURNING id, title, done", title, done, as: Todo)
end

pub def delete_todo(db : Database, id : Int64) : Bool | DBError
  db.exec("DELETE FROM todos WHERE id = $1", id)!.rows_affected > 0
end
```

- `query_all(sql, args..., as: T)`, `query_one`, `query_one?` (nil for no
  row) read rows into a type that derives `db_serializable`, a
  `Tuple(...)`, a `NamedTuple(...)` or a scalar type.
- `exec` answers an `ExecResult` with `rows_affected`.
- `!` hands a `DBError` up at once, so a function of several statements
  reads as its statements.
- Arguments are bound, never spliced into the SQL.
- `db.transaction { |tx| ... }` commits when the block answers a value and
  rolls back when it answers an error or leaves early; run its statements
  on `tx.connection`.

The body a client sends is a separate type, checked by `Validate` before
the route sees it, so a bad request never reaches the database:

```iyi
pub struct NewTodo
  getter title : String
  getter done : Bool = false
  derive serializable
end

impl Validate for NewTodo
  def validate(v : Validator) : Nil
    v.required("title", title)
    v.length("title", title, max: 200)
  end
end

router.post "/todos" do |env|
  case input = env.params.json_as(NewTodo)
  in BodyError then input                    # 400, 415 or 422
  in NewTodo
    case todo = create_todo(db, input.title, input.done)
    in DBError then todo
    in Todo    then env.status(201).json(todo)
    end
  end
end
```

## Database errors as responses

A route that returns a `DBError` hands it to the error pages. One page for
the type turns every failed query into the same answer:

```iyi
import web/iyi_web/log::{StdoutLogger}

LOG = StdoutLogger.new

router.error DBError do |env, err|
  LOG.write("database error: " + (err.message.empty? ? err.class.to_s : err.message))
  env.response.status_code = 503
  env.json({"error" => "database unavailable"})
end
```

The client gets `503` and no detail; the log gets the message. The line
goes through `StdoutLogger`, which writes under the request log's lock:
`STDERR.puts` inside a route is refused by the compiler, since standard
error is not safe to write from every core at once. Some errors carry no
message (a refused connection), hence the type name.

## Migrations when the program starts

`examples/postgres/migrations.iyi` keeps the schema as numbered steps and
applies the ones not yet recorded, before the server listens:

```iyi
MIGRATIONS = List.new([
  {1, "CREATE TABLE todos (
         id         bigserial PRIMARY KEY,
         title      text NOT NULL CHECK (length(title) BETWEEN 1 AND 200),
         done       boolean NOT NULL DEFAULT false,
         created_at timestamptz NOT NULL DEFAULT now()
       )"},
  {2, "CREATE INDEX todos_open ON todos (id) WHERE NOT done"},
])

pub def migrate(db : Database) : Int32 | DBError
  db.exec("CREATE TABLE IF NOT EXISTS schema_migrations (version integer PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())")!
  applied = 0
  MIGRATIONS.each do |step|
    version, sql = step
    ran = db.transaction { |tx| apply(tx, version, sql) }!
    applied += 1 if ran == true
  end
  applied
end

private def apply(tx : Transaction, version : Int32, sql : String) : Bool | DBError
  conn = tx.connection
  conn.exec("SELECT pg_advisory_xact_lock($1)", LOCK_KEY)!
  return false if conn.query_one?("SELECT version FROM schema_migrations WHERE version = $1", version, as: Int32)!
  conn.exec(sql)!
  conn.exec("INSERT INTO schema_migrations (version) VALUES ($1)", version)!
  true
end
```

- Each step runs in a transaction with its own record: a step that fails
  leaves nothing behind and runs again at the next start.
- The advisory lock makes several copies of the program starting at once
  (replicas behind a load balancer) apply each step once: the second waits
  for the first, then finds the step recorded.
- A released step is never edited; a schema change is a new step.

```iyi
case applied = migrate(database)
in Int32
  puts "migrations: " + applied.to_s + " applied" if applied > 0
in DBError
  STDERR.puts "migration failed: " + applied.message
  exit 1
end
```

## The example

```
examples/postgres/
  iyi.mod           requires iyi-web, iyilang/db and iyilang/pg
  app.iyi           opens the pool, migrates, mounts, runs
  migrations.iyi    the schema steps
  todos.iyi         Todo, NewTodo, TodoChange and one function per statement
  routes.iyi        GET/POST /todos, GET/PATCH/DELETE /todos/:id, GET /health
  smoke.sh          curl through every route against a running server
```

It is a project of its own, so iyi-web does not depend on the database
packages. Its `iyi.mod` builds iyi-web from this checkout with
`replace github.com/sdogruyol/iyi-web => ../..`; copied elsewhere, delete
that line.

```sh
cd examples/postgres
export DATABASE_URL='postgres://postgres:secret@127.0.0.1:5432/todos?max_pool_size=16&max_idle_pool_size=16'
iyi run app.iyi -- -p 3000          # migrations: 2 applied
bash smoke.sh http://localhost:3000
```

```
ok   health: 200 {"status":"ok"}
ok   create: 201 {"id":1,"title":"Write the smoke test","done":false}
ok   show: 200 {"id":1,"title":"Write the smoke test","done":false}
ok   list: 200 [{"id":1,"title":"Write the smoke test","done":false}]
ok   blank title: 422 {"error":"invalid body: title is required","fields":{"title":"is required"}}
ok   missing title: 422 {"error":"invalid body: title is required","fields":{"title":"is required"}}
ok   not JSON: 400 {"error":"malformed JSON: unexpected end of input at line 1, column 10"}
ok   mark done: 200 {"id":1,"title":"Write the smoke test","done":true}
ok   rename: 200 {"id":1,"title":"Renamed","done":true}
ok   blank rename: 422 {"error":"invalid body: title is required","fields":{"title":"is required"}}
ok   delete: 204
ok   deleted: 404 {"error":"not found"}
ok   delete again: 404 {"error":"not found"}
ok   not an id: 404 {"error":"not found"}
ok   patch nothing: 404 {"error":"not found"}
all passed
```

That run was against PostgreSQL 16.2 on Windows (the portable build the
`pgserver` Python package ships). A second start applied no migrations;
with the database stopped under the running server, `/todos/2` and
`/health` answered `503 {"error":"database unavailable"}`; and with the
database up, `oha -z 5s -c 64` on `GET /todos/2` (`max_pool_size=16`)
answered 124,800 requests, all `200`, at about 24,800 req/s on the
12-core machine.

## MySQL

The same code with the other driver: `import mysql` instead of `import pg`,
a `mysql://` URL, and `?` where PostgreSQL writes `$1`.

```sh
iyi get github.com/iyilang/mysql --as mysql
```

iyilang/mysql has no release tag yet, so `iyi get` writes a pseudo-version
of its latest commit:

```
require github.com/iyilang/db v0.4.0 as db
require github.com/iyilang/mysql v0.0.0-20261019162642-e6b3cebe6a96 as mysql
```

```iyi
import db
import mysql

database = Db.open("mysql://app:secret@127.0.0.1/shop?max_pool_size=16").or_panic
todo = database.query_one?("SELECT id, title, done FROM todos WHERE id = ?", 1_i64, as: Todo)
```

At that commit a program that opens a MySQL pool builds, with two warnings
from inside the driver: the compiler reports that two of its tables
(`SUPPORTED_PLUGINS` and `COLLATIONS_IDS_BY_NAME`), reached from the pool's
connection factory on every worker, are not `Share`. The fix the compiler
names (a `List`, or `@[SafeReach]` saying why it is safe) belongs in the
driver, not in your program. The PostgreSQL driver builds without warnings.
The MySQL lines on this page were built, not run against a server.

The migration lock above is PostgreSQL's; on MySQL, `GET_LOCK('migrations',
60)` and `RELEASE_LOCK` on the same connection do the same job.
