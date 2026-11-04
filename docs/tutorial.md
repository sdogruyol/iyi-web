# Tutorial: a typed JSON API

This tutorial builds a small notes API from an empty directory to a
release build. By the end it has typed routes that read and check their
input before any of your code runs, state shared safely by every core, an
OpenAPI document with a docs page, sign-in with JWTs, in-process tests and
Prometheus metrics.

Every step's code was compiled, and its test run, against this version of
iyi-web; the answers shown are what the program printed.

You need [iyi](https://iyi-lang.com) 0.20.1 or later and the `iyi-web`
command ([installing it](cli.md#installing)).

## 1. A new project

```sh
iyi-web new notes --api
cd notes
iyi test
iyi-web dev
```

`iyi-web new --api` writes a JSON API over an in-memory store, already as
typed routes:

```
notes/
  iyi.mod            requires iyi-web as `web`
  app.iyi            mounts the routes and runs
  routes/notes.iyi   the routes, as a function that builds a Router
  app_test.iyi       in-process tests
```

`iyi test` passes as it is, and `iyi-web dev` serves
http://localhost:3000, building again and restarting whenever a file is
saved. Leave it running: each step below is live as soon as you save.

`app.iyi` is short. The routes live in a module so that the program and
its test can both load them:

```iyi
# notes: an iyi-web application. The routes are in routes/notes.iyi;
# app_test.iyi tests them without opening a port.
#
#   iyi run app.iyi            serves http://localhost:3000 (-p to change)
#   iyi-web dev                rebuilds and restarts on every save
#   iyi test                   runs app_test.iyi
#   iyi build --release app.iyi -o app
module app

import web/iyi_web/dsl::*
import routes/notes::*

mount note_routes

run
```

## 2. Typed routes

The generated routes do not parse a parameter or match on an error by
hand. A typed route says what it reads, and iyi-web reads it before the
block runs ([Typed routes](typed-routes.md)). This is `note_routes` in
`routes/notes.iyi`:

```iyi
pub def note_routes : Router
  notes = Store.new { {} of Int32 => Note }
  last_id = Atomic(Int32).new(0)
  router = Router.new

  router.get "/notes", response: Array(Note) do |env|
    notes.values
  end

  router.get "/notes/:id", path: Int32, response: Note do |env, id|
    notes[id]? || StatusError.new(404)
  end

  router.post "/notes", body: NoteInput, response: Note, status: 201 do |env, input|
    note = Note.new(last_id.add(1) + 1, input.title.strip, input.done)
    notes.update { |all| all[note.id] = note; nil }
    note
  end

  router.delete "/notes/:id", path: Int32, status: 204 do |env, id|
    notes.update { |all| all.delete(id) } ? nil : StatusError.new(404)
  end

  router.error 404 do |env|
    env.json({"error" => "not found"})
  end

  router
end
```

- `path: Int32` reads the `:id` capture as a number, and the block gets it
  as `id`. `/notes/abc` is answered `422` before the block runs.
- `body: NoteInput` reads the JSON body into `NoteInput` and runs its
  `Validate` rules; the block only ever sees a valid one.
- `response: Note` says what the route answers, and writes it as JSON with
  the `status:` given. A `StatusError` returned beside it is answered with
  its own status: here the JSON `404` page.

```sh
curl -X POST localhost:3000/notes -H 'Content-Type: application/json' -d '{"title":"Buy milk"}'
# 201 {"id":1,"title":"Buy milk","done":false}
curl localhost:3000/notes/9
# 404 {"error":"not found"}
curl -H 'Accept: application/json' localhost:3000/notes/abc
# 422 {"error":"invalid path parameters: id must be an integer","fields":{"id":"must be an integer"}}
```

## 3. Validation and the query string

`NoteInput`'s rules run once its body has been read, and every rule that
fails is reported in one `422`. Add a rule that keeps markup out of titles
(the regex needs `import std/regex::{Regex}` at the top of the file):

```iyi
impl Validate for NoteInput
  def validate(v : Validator) : Nil
    v.required("title", title)
    v.length("title", title, max: 80)
    v.format("title", title, /\A[^<>]*\z/, "must not contain < or >")
  end
end
```

A query string is read into a type the same way. Add a filter for
`GET /notes?done=false&limit=10`, with a rule of its own:

```iyi
# `GET /notes?done=false&limit=10`: the query string, read into a type
# the way a body is.
struct NoteFilter
  getter done : Bool?
  getter limit : Int32 = 20
  derive serializable
end

impl Validate for NoteFilter
  def validate(v : Validator) : Nil
    v.range("limit", limit, min: 1, max: 100)
  end
end
```

and let the list route read it:

```iyi
  router.get "/notes", query: NoteFilter, response: Array(Note) do |env, filter|
    every = notes.values
    wanted = filter.done
    found = wanted.nil? ? every : every.select { |note| note.done == wanted }
    found.first(filter.limit)
  end
```

```sh
curl -X POST localhost:3000/notes -H 'Content-Type: application/json' -d '{"title":7}'
# 422 {"error":"invalid body: title must be a string","fields":{"title":"must be a string"}}
curl -X POST localhost:3000/notes -H 'Content-Type: application/json' -d '{"title":"<b>"}'
# 422 {"error":"invalid body: title must not contain < or >","fields":{"title":"must not contain < or >"}}
curl -X POST localhost:3000/notes -H 'Content-Type: application/json' -d '{"title":'
# 400 {"error":"malformed JSON: unexpected end of input at line 1, column 10"}
curl -H 'Accept: application/json' 'localhost:3000/notes?limit=500'
# 422 {"error":"invalid query parameters: limit must be between 1 and 100","fields":{"limit":"must be between 1 and 100"}}
curl 'localhost:3000/notes?done=true'
```

[Parameters](parameters.md#validation) lists every rule.

## 4. State every core shares: `Store`

The routes run on whichever core is free, so the notes are behind a lock,
and the compiler refuses a route that touches a bare `Hash` ([Every
core](every-core.md)). The scaffold keeps them in a [`Store`](state.md), a
table behind a lock that hands out copies:

- `notes.values` is a copy of every note, taken under the lock;
- `notes[id]?` reads one entry;
- `update` changes the table with the lock held and answers what its block
  answers: `nil` after a store, the removed note (or `nil`) after a
  delete.

Ids come from an `Atomic`, so no two requests get the same one. A
`Mutex` from `std/mutex` would work too, but each call would need an
`.or_panic` and a `List` copy before the values may leave the lock;
`Store` does both.

## 5. OpenAPI and the docs page

One line in `app.iyi`, after the `mount`, serves an OpenAPI 3.1 document of
every route and Swagger UI to read it:

```iyi
# /openapi.json, made from the routes, and Swagger UI at /docs.
openapi("Notes API", "1.0.0", description: "A small typed JSON API.")
```

The document is made from the routes and the types they declare, so
there is nothing to keep in step. `summary:` and `tags:` add the words a
reader wants:

```iyi
  router.get "/notes", query: NoteFilter, response: Array(Note), summary: "List notes", tags: ["notes"] do |env, filter|
    # ...
  end

  router.get "/notes/:id", path: Int32, response: Note, summary: "One note", tags: ["notes"] do |env, id|
    # ...
  end

  router.post "/notes", body: NoteInput, response: Note, status: 201, summary: "Write a note", tags: ["notes"] do |env, input|
    # ...
  end

  router.delete "/notes/:id", path: Int32, status: 204, summary: "Remove a note", tags: ["notes"] do |env, id|
    # ...
  end
```

```sh
curl localhost:3000/openapi.json
open http://localhost:3000/docs
```

The document lists `/notes` and `/notes/{id}` with their parameters,
`Note` and `NoteInput` as schemas, and the `400`, `415` and `422` answers
the framework gives on its own. See [OpenAPI](openapi.md).

## 6. Signing in: a JWT and a dependency

Anyone may read notes; writing and deleting should need a signed-in user.
Add `routes/auth.iyi`: a token route speaking OAuth2's password flow, and
`CURRENT_USER`, a [dependency](dependencies-and-auth.md) that turns a
bearer token into the name it was issued to, or answers `401`:

```iyi
# Signing in, and who a request is from. `POST /token` takes OAuth2's
# password form and answers a JWT; `CURRENT_USER` turns the bearer token a
# request sends into the name it was issued to, or a 401.
module routes/auth

import std/time::{Span}
import std/password::{Bcrypt}
import web/iyi_web/router::{Router}
import web/iyi_web/context::{Context}
import web/iyi_web/openapi::{SecurityScheme}
import web/iyi_web/deps::{Dep}
import web/iyi_web/auth::*
import web/iyi_web/jwt::{JWT, Claims}

# Signs every token. Set JWT_SECRET in production: whoever knows the
# secret can sign a token for anyone.
pub SECRET = Program.env("JWT_SECRET") || "development only: thirty-two bytes or more"

# One account, its password kept as a bcrypt hash.
ACCOUNT  = "ada"
PASSWORD = Bcrypt.hash(Program.env("ADA_PASSWORD") || "lovelace", 10)

# The document describes the token as OAuth2's password flow, so the
# /docs page's "Authorize" button signs in by itself.
TOKEN = jwt_auth(SECRET, security: SecurityScheme.oauth2_password("/token"))

def current_user(env : Context) : String | AuthError
  claims = TOKEN.resolve(env)!
  claims.sub || AuthError.new(401, "the token names nobody")
end

pub CURRENT_USER = Dep.new(security: TOKEN.security) { |env| current_user(env) }

pub def auth_routes : Router
  router = Router.new

  router.post "/token", summary: "Sign in", tags: ["auth"] do |env|
    grant = password_grant(env)
    next grant if grant.is_a?(OAuthError)
    # The hash is checked whatever the name, so a wrong name takes as long
    # as a wrong password.
    matched = Bcrypt.verify(grant.password, PASSWORD)
    if grant.username == ACCOUNT && matched
      hour = Span.new(hours: 1)
      token_response(env, JWT.sign(Claims.new(sub: grant.username, expires_in: hour), SECRET), hour)
      nil
    else
      OAuthError.new("invalid_grant")
    end
  end

  router
end
```

A route names what it needs with `deps:`, and the block gets its value
after the others. Give `Note` an author:

```iyi
pub struct Note
  getter id : Int32
  getter title : String
  getter done : Bool
  getter author : String
  derive serializable

  def initialize(@id : Int32, @title : String, @done : Bool, @author : String)
  end
end
```

and require a user to write or delete, in `routes/notes.iyi` (with
`import routes/auth::{CURRENT_USER}` at the top):

```iyi
  router.post "/notes", body: NoteInput, response: Note, deps: CURRENT_USER, status: 201, summary: "Write a note", tags: ["notes"] do |env, input, user|
    note = Note.new(last_id.add(1) + 1, input.title.strip, input.done, user)
    notes.update { |all| all[note.id] = note; nil }
    note
  end
```

```iyi
  router.delete "/notes/:id", path: Int32, deps: CURRENT_USER, status: 204, summary: "Remove a note", tags: ["notes"] do |env, id, user|
    notes.update { |all| all.delete(id) } ? nil : StatusError.new(404)
  end
```

Mount the token route in `app.iyi`, beside the notes:

```iyi
import web/iyi_web/dsl::*
import routes/auth::*
import routes/notes::*

mount auth_routes
mount note_routes
```

```sh
curl -X POST localhost:3000/notes -H 'Content-Type: application/json' -d '{"title":"Buy milk"}'
# 401 {"error":"missing bearer token"}
curl -X POST localhost:3000/token -d 'grant_type=password&username=ada&password=lovelace'
# 200 {"access_token":"eyJhbGciOiJIUzI1NiIs...","token_type":"bearer","expires_in":3600}
TOKEN=eyJhbGciOiJIUzI1NiIs...   # the access_token it answered
curl -X POST localhost:3000/notes -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"title":"Buy milk"}'
# 201 {"id":1,"title":"Buy milk","done":false,"author":"ada"}
```

On the docs page, "Authorize" now asks for a username and a password and
fetches the token itself.

## 7. Tests

The harness sends requests to a router in-process, without opening a port
([Testing](testing.md)). Replace `app_test.iyi`:

```iyi
# `iyi test` runs every *_test.iyi: exit 0 passes. The harness sends
# requests straight to the routers, so no port is opened.
module app_test

import std/time::{Span}
import web/iyi_web/router::{RouteHandler}
import web/iyi_web/harness::*
import web/iyi_web/jwt::{JWT, Claims}
import routes/auth::*
import routes/notes::*

JSON_TYPE = "application/json"

auth = RouteHandler.new(auth_routes)
app = RouteHandler.new(note_routes)

# The token route: the right password gets a token, a wrong one
# `invalid_grant`.
signed_in = dispatch(auth, form_request("POST", "/token", "grant_type=password&username=ada&password=lovelace")).response
assert signed_in.status_code == 200
assert signed_in.body.includes?("access_token")
refused = dispatch(auth, form_request("POST", "/token", "grant_type=password&username=ada&password=nope")).response
assert refused.status_code == 400

# The notes routes take any token signed with SECRET, so a test signs its
# own rather than going through /token each time.
TOKEN = JWT.sign(Claims.new(sub: "ada", expires_in: Span.new(hours: 1)), SECRET)

def post_note(app : RouteHandler, body : String, token : String?)
  request = http_request("POST", "/notes", body: body, content_type: JSON_TYPE)
  request.headers["Authorization"] = "Bearer " + token if token
  dispatch(app, request).response
end

# Writing needs a token; reading does not.
assert post_note(app, %({"title":"Buy milk"}), nil).status_code == 401
created = post_note(app, %({"title":" Buy milk "}), TOKEN)
assert created.status_code == 201
assert created.body == %({"id":1,"title":"Buy milk","done":false,"author":"ada"})
assert dispatch(app, "GET", "/notes/1").response.body == created.body
assert dispatch(app, "GET", "/notes").response.body == "[" + created.body + "]"

# What the typed routes refuse before a block runs.
assert post_note(app, %({"title":"  "}), TOKEN).status_code == 422
assert post_note(app, %({"title":"<b>"}), TOKEN).status_code == 422
assert post_note(app, %({"title":), TOKEN).status_code == 400
assert dispatch(app, http_request("GET", "/notes", query: "limit=0")).response.status_code == 422
assert dispatch(app, "GET", "/notes/abc").response.status_code == 422

# Deleting answers 204 once, then 404 as JSON.
delete = http_request("DELETE", "/notes/1")
delete.headers["Authorization"] = "Bearer " + TOKEN
assert dispatch(app, delete).response.status_code == 204
missing = dispatch(app, delete).response
assert missing.status_code == 404
assert missing.body == %({"error":"not found"})
```

```sh
iyi test
# 1 passed, 0 failed
```

The test signs its own token with `SECRET`, so only the token route's own
checks go through `/token`.

## 8. Metrics

`MetricsHandler` counts every request by method, route pattern and status,
times it, and serves the numbers at `/metrics` for Prometheus to scrape
([Observability](observability.md)). In `app.iyi`, after the imports
(`import web/iyi_web/metrics::{MetricsHandler}`):

```iyi
# First in the chain, so every request is counted; /metrics answers them.
use MetricsHandler.new, 0
```

A counter of your own is one line in `routes/notes.iyi`
(`import web/iyi_web/metrics::{METRICS}`), above `note_routes`:

```iyi
NOTES_WRITTEN = METRICS.counter("notes_written_total", "Notes written, by author.", ["author"])
```

counted where a note is written:

```iyi
  router.post "/notes", body: NoteInput, response: Note, deps: CURRENT_USER, status: 201, summary: "Write a note", tags: ["notes"] do |env, input, user|
    note = Note.new(last_id.add(1) + 1, input.title.strip, input.done, user)
    notes.update { |all| all[note.id] = note; nil }
    NOTES_WRITTEN.inc([user])
    note
  end
```

```sh
curl localhost:3000/metrics
# notes_written_total{author="ada"} 1
# http_requests_total{method="POST",route="/notes",status="201"} 1
# http_requests_total{method="GET",route="/notes/:id",status="422"} 1
# ...
```

## 9. Deploying

```sh
iyi build --release app.iyi -o app
JWT_SECRET=... ADA_PASSWORD=... IYI_WEB_ENV=production ./app -p 8080
```

The build is one native binary with the routes, the docs page and every
dependency compiled in. In production, set `JWT_SECRET` to 32 or more
random bytes and keep it out of the source. `IYI_WEB_ENV=production`
hides panic messages from error pages. The program serves on every core
(`-w` or `IYI_WORKERS` change how many), stops gracefully on `INT` and
`TERM`, and sits well behind a reverse proxy; see
[Deployment](deployment.md) and [Configuration](configuration.md).

## The finished routes

`routes/notes.iyi` as it stands at the end:

```iyi
# A JSON API over an in-memory store, as typed routes: each route says
# what it reads and what it answers, and iyi-web reads it before the block
# runs.
module routes/notes

import std/json::{serializable}
import std/regex::{Regex}
import web/iyi_web/router::{Router}
import web/iyi_web/failure::{StatusError}
import web/iyi_web/metrics::{METRICS}
import web/iyi_web/store::{Store}
import web/iyi_web/validation::{Validate, Validator}
import routes/auth::{CURRENT_USER}

# What a client sends. A field with a default may be left out.
struct NoteInput
  getter title : String
  getter done : Bool = false
  derive serializable
end

impl Validate for NoteInput
  def validate(v : Validator) : Nil
    v.required("title", title)
    v.length("title", title, max: 80)
    v.format("title", title, /\A[^<>]*\z/, "must not contain < or >")
  end
end

# `GET /notes?done=false&limit=10`: the query string, read into a type
# the way a body is.
struct NoteFilter
  getter done : Bool?
  getter limit : Int32 = 20
  derive serializable
end

impl Validate for NoteFilter
  def validate(v : Validator) : Nil
    v.range("limit", limit, min: 1, max: 100)
  end
end

# What the API answers with.
pub struct Note
  getter id : Int32
  getter title : String
  getter done : Bool
  getter author : String
  derive serializable

  def initialize(@id : Int32, @title : String, @done : Bool, @author : String)
  end
end

NOTES_WRITTEN = METRICS.counter("notes_written_total", "Notes written, by author.", ["author"])

pub def note_routes : Router
  notes = Store.new { {} of Int32 => Note }
  last_id = Atomic(Int32).new(0)
  router = Router.new

  router.get "/notes", query: NoteFilter, response: Array(Note), summary: "List notes", tags: ["notes"] do |env, filter|
    every = notes.values
    wanted = filter.done
    found = wanted.nil? ? every : every.select { |note| note.done == wanted }
    found.first(filter.limit)
  end

  router.get "/notes/:id", path: Int32, response: Note, summary: "One note", tags: ["notes"] do |env, id|
    notes[id]? || StatusError.new(404)
  end

  router.post "/notes", body: NoteInput, response: Note, deps: CURRENT_USER, status: 201, summary: "Write a note", tags: ["notes"] do |env, input, user|
    note = Note.new(last_id.add(1) + 1, input.title.strip, input.done, user)
    notes.update { |all| all[note.id] = note; nil }
    NOTES_WRITTEN.inc([user])
    note
  end

  router.delete "/notes/:id", path: Int32, deps: CURRENT_USER, status: 204, summary: "Remove a note", tags: ["notes"] do |env, id, user|
    notes.update { |all| all.delete(id) } ? nil : StatusError.new(404)
  end

  router.error 404 do |env|
    env.json({"error" => "not found"})
  end

  router
end
```

## Where next

- [Typed routes](typed-routes.md): headers, parameter structs, enums and
  the order in which things are answered.
- [Dependencies and auth](dependencies-and-auth.md): composing providers,
  API keys, admin checks.
- [Lifecycle and background tasks](lifecycle-and-background.md): opening a
  database pool at start, work done after the response.
- [Databases](database.md): the same API on Postgres.
- `examples/openapi_auth.iyi`: users with roles, an admin-only route and an
  API-key client.
