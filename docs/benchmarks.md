# Benchmarks

## Across frameworks

`bench/compare/` runs the same four endpoints in iyi-web, FastAPI, Express,
Kemal and Go's `net/http` on one machine and loads each with
[oha](https://github.com/hatoo/oha). (`bench/run.sh` is a different thing:
it times [iyi-web against itself](#iyi-web-against-itself) for regressions.)

| Endpoint | Answer |
|---|---|
| `GET /plaintext` | `Hello, World!` as `text/plain` |
| `GET /json` | `{"message":"Hello, World!"}` |
| `GET /users/42?fields=name,email` | `{"id":42,"name":"user-42","fields":"name,email"}`: a path parameter parsed as an integer and a query parameter |
| `GET /db` | `{"id":N,"randomNumber":M}`: TechEmpower's single query, `SELECT id, randomnumber FROM world WHERE id = $1` for a random id from 1 to 10,000, through a connection pool |

```sh
bash bench/compare/run.sh                               # every framework, 10 s per endpoint
bash bench/compare/run.sh --duration 5 --only iyi-web,go
bash bench/compare/run.sh --db postgres://user:pw@host/bench   # an existing PostgreSQL
bash bench/compare/run.sh --no-db                       # leave /db out
bash bench/compare/run.sh --help                        # warm-up, connections, workers, port, output
```

### The database

`/db` needs PostgreSQL. The runner takes `DATABASE_URL` (or `--db URL`);
without one it starts a PostgreSQL of its own from the binaries the
`pgserver` Python package ships (`pip install pgserver`): data in
`bench/compare/.build/pgdata`, made with `initdb` the first time, listening
on `127.0.0.1:5499` with trust authentication, stopped when the run ends.
Either way it creates and fills `world(id integer primary key, randomnumber
integer)` with 10,000 rows when the table is not there (with `psql`), and
checks it holds all of them. With no database to be had, `/db` is left out
of the run with the reason printed and written into the results.

Every server gets the same number of connections, 4 per worker (48 with
12 workers): iyi-web (iyilang/db pool, iyilang/pg driver), Kemal
(crystal-db pool, crystal-pg driver) and Go (pgx/v5 `pgxpool`) share one
pool of 48 across their threads; FastAPI (asyncpg) and Express (`pg` Pool)
open a pool of 4 in each of their 12 worker processes. The runner passes
the URL and the size as `DATABASE_URL` and `DB_POOL_SIZE`; each app opens
its pool at start and only then has a `/db` route.

The iyi-web app is a project of its own (`bench/compare/iyiweb/iyi.mod`, as
`examples/postgres` is), so iyi-web itself does not depend on the database
packages.

### What the runner does

For each framework in turn:

1. Skips it, with the reason, when its toolchain is missing: `node` for
   Express, `crystal` for Kemal, `go`, or FastAPI/uvicorn/asyncpg not
   importable. The skip is recorded in the results, so a missing row says
   why.
2. Builds it for release: `iyi build --release`, `crystal build --release`,
   `go build`, `npm install` for Express. Kemal's shards (kemal, crystal-pg,
   crystal-db and theirs) are installed with `shards install`; where shards
   cannot run (on Windows it needs symlinks, so Developer Mode or an
   elevated shell) the runner clones the same versions into `lib/` with git
   and says so.
3. Starts it on its own port, serving on every core the way each is
   deployed: iyi-web, Kemal (Crystal's default execution context resized to
   the core count) and Go with threads; FastAPI under uvicorn with one
   worker process per core and `httptools`; Express with one `node:cluster`
   worker per core. Request logging is off everywhere.
4. Checks every endpoint's status, `Content-Type` and body, and that
   `/users/abc` is refused with a 4xx; `/db` is asked eight times and must
   answer `200`, JSON with exactly `id` and `randomNumber`, both from 1 to
   10,000, and not the same id every time. A framework that answers wrongly
   is reported failed and not timed: doing less work is not winning.
5. Warms each endpoint up (3 s), then measures it (10 s) at 64 keep-alive
   connections: requests per second that got a `200`, p50 and p99 latency,
   and non-200 answers or connection errors (requests cut off when the
   timer ends are not errors).
6. Stops it (on Windows, with every process it started).

Results go to `bench/compare/results.json` and `bench/compare/results.md`
(both ignored by git).

### Results

Measured 2026-11-04 with `bash bench/compare/run.sh` (defaults, the
database started by the runner), on the `roadmap` branch, after checking
that no `iyi` or `crystal` build or test was running:

| Framework | `/plaintext` req/s | `/json` req/s | `/users/42` req/s | `/db` req/s |
|---|---:|---:|---:|---:|
| iyi-web | 76644 | 77563 | 70941 | 37579 |
| FastAPI | 32994 | 30485 | 27400 | 14282 |
| Express | skipped: node not found on PATH | | | |
| Kemal | 11326 | 11359 | 11214 | 10820 |
| Go net/http | 73899 | 68833 | 65278 | 38026 |

| Framework | Endpoint | req/s | p50 ms | p99 ms | non-200 / errors |
|---|---|---:|---:|---:|---:|
| iyi-web | `/plaintext` | 76644 | 0.616 | 3.997 | 0 |
| iyi-web | `/json` | 77563 | 0.604 | 3.927 | 0 |
| iyi-web | `/users/42?fields=name,email` | 70941 | 0.630 | 4.750 | 0 |
| iyi-web | `/db` | 37579 | 1.186 | 8.259 | 0 |
| FastAPI | `/plaintext` | 32994 | 1.562 | 6.020 | 0 |
| FastAPI | `/json` | 30485 | 1.808 | 6.069 | 0 |
| FastAPI | `/users/42?fields=name,email` | 27400 | 1.998 | 7.373 | 0 |
| FastAPI | `/db` | 14282 | 3.057 | 31.942 | 0 |
| Kemal | `/plaintext` | 11326 | 4.356 | 20.763 | 0 |
| Kemal | `/json` | 11359 | 4.398 | 20.082 | 0 |
| Kemal | `/users/42?fields=name,email` | 11214 | 4.407 | 20.529 | 0 |
| Kemal | `/db` | 10820 | 5.295 | 14.964 | 0 |
| Go | `/plaintext` | 73899 | 0.525 | 5.513 | 0 |
| Go | `/json` | 68833 | 0.548 | 6.165 | 0 |
| Go | `/users/42?fields=name,email` | 65278 | 0.573 | 6.709 | 0 |
| Go | `/db` | 38026 | 1.244 | 9.073 | 0 |

- Machine: Windows 10.0.26200.9711, QEMU Virtual CPU version 2.5+, 12
  logical cores, a virtual machine.
- iyi-web from this checkout (0.5.1 plus the roadmap work) on iyi 0.20.1,
  iyilang/db 0.4.0 and iyilang/pg 0.4.0; FastAPI 0.162.0, uvicorn 0.54.0,
  httptools 0.9.0, asyncpg 0.32.0, Python 3.12.10; Kemal 1.15.0,
  crystal-pg 0.31.0 and crystal-db 0.15.0 on Crystal 1.22.0; Go 1.27.3 with
  pgx 5.12.0; oha 1.16.0.
- Database: PostgreSQL 16.2 (pgserver's build) on the same machine and the
  same 12 cores, `max_connections=100`; 48 connections per server as
  described above.
- 64 connections, 3 s warm-up and 10 s measured per endpoint, 12 workers
  per server.

### Reading these numbers

- **One machine, loopback, Windows.** oha and, for `/db`, PostgreSQL ran
  on the same 12 cores as the server, so every number includes their share
  of the CPU. Windows loopback and its socket stack are slower than
  Linux's, and each runtime's Windows I/O path is a different code path
  from its Linux one. These numbers rank the frameworks on this machine;
  they are not what any of them does on a Linux server with a separate
  load generator and database.
- **Run it more than once.** A full run about an hour earlier the same
  day, with the same apps (iyi-web still on its keep-alive default) and
  nothing else of ours running, gave every
  framework about a quarter more: iyi-web 94,000-101,000 req/s on the
  first three endpoints, Go 84,000-93,000, FastAPI 36,000-42,000, Kemal
  15,000-16,000; on `/db` Go 52,000, FastAPI 18,000, Kemal 15,000
  (iyi-web's `/db` in that run hit the keep-alive problem below). The full
  run just before the one above, with the keep-alive setting, came within
  about 15% of it (iyi-web 79,000-87,000 and 43,300 on `/db`, Go
  69,000-70,000 and 38,800). The order held; the virtual machine's host
  load moves the absolute numbers. Quote a number only after repeating it.
- **`/db` is where iyi-web and Go meet.** With a query on every request
  the round trip to PostgreSQL dominates, and iyi-web and Go come out even
  (37,600 and 38,000 here); FastAPI keeps about half of its `/json` rate,
  Kemal nearly all of its, which was low to begin with.
- **Keep-alive parity.** iyi-web closes a keep-alive connection after 100
  requests by default (`max_keepalive_requests`); the other servers do not
  cap keep-alive requests. Under oha that is hundreds of new connections a
  second, and their client-side TIME_WAITs used up Windows' 16,384
  ephemeral ports within a run: the endpoint measured after about 40 s of
  load got thousands of connection errors (`os error 10048`). The bench app
  therefore sets `max_keepalive_requests` to its maximum, so iyi-web keeps
  connections as the others do. The table this one replaced (three
  endpoints, 100,281 / 96,859 / 95,052 req/s for iyi-web, which finished
  under the port limit) was measured with the default of 100.
- **Kemal on Windows.** Kemal served about 10,200 req/s on `/json` with one
  thread (`CRYSTAL_WORKERS=1`) and about 12,400 with twelve: Crystal's
  Windows event loop, not Kemal's routing, is the likely limit here. Kemal
  on Linux is a different result.
- **Express was not measured** because Node.js is not installed on this
  machine. Its app (`bench/compare/express/`, Express 5 under
  `node:cluster`, `pg` for `/db`) and the runner's support for it are
  there; on a machine with `node` it runs like the rest.
- **FastAPI** refuses `/users/abc` with `422` (its `id: int` validation),
  the others with `404`; the check accepts any 4xx.

### Files

```
bench/compare/
  run.sh             builds run.iyi and runs it
  run.iyi            the runner
  iyiweb/app.iyi     iyi-web (iyi.mod: iyi-web from this checkout, iyilang/db, iyilang/pg)
  fastapi/app.py     FastAPI (requirements.txt: fastapi, uvicorn, httptools, asyncpg)
  express/app.js     Express (package.json: express, pg)
  kemal/src/app.cr   Kemal (shard.yml: kemal, crystal-pg)
  go/main.go         Go net/http (go.mod, go.sum: pgx/v5)
```

## iyi-web against itself

`bench/` measures the framework itself, with nothing but iyi:

```sh
bash bench/run.sh              # build with --release, run both parts
bash bench/run.sh --repeat 3   # three runs of each, for compare's medians
bash bench/run.sh --help       # durations, connections, port, a filter
```

- `bench/micro.iyi` times the paths every request takes with `std/benchmark`:
  route lookup in a tree of about a hundred static, parameter and wildcard
  routes (`radix.*`, `router.*`), parsing a request off the wire with
  std/http's parser as the server does (`wire.get`, `wire.post_form`; before
  the move onto std/http these were `intake.*`), query, form and JSON
  parameters (`params.*`), the header table (`headers.*`), and a whole
  in-process dispatch through `RouteHandler` (`dispatch.*`) and through
  `handler_chain` (`chain.*`). Each case is checked once before it is
  timed, so one that stops doing its job aborts rather than reporting a
  fast nothing.
- `bench/load.iyi` is a load generator for Linux and Windows alike (no `wrk`):
  N tasks, one keep-alive connection each, request `bench/server.iyi`'s hello,
  JSON and parameter routes for a fixed time and report req/s, p50 and p99
  latency, and errors. The client runs on one thread, so the numbers compare
  two builds on one machine; they are not a ceiling.
- `bench/run.sh` writes every result to `bench/results.json` (ignored by git):
  one object per microbenchmark (`ns_per_op`, `ops_per_sec`, `rsd_pct`) and
  per end-to-end target (`rps`, `p50_us`, `p99_us`, `errors`).
- `bench/compare.iyi` reads two result files (or comma-separated lists of
  repeated runs), compares each side's median, and prints a Markdown table; it
  exits 1 when a microbenchmark is more than `--threshold` percent (30) slower
  and every head run is slower than every base run.

On a pull request CI runs the pull request's benchmarks against the base
branch and against the pull request, in three alternating rounds on one runner
at 2 s per case, puts the comparison in the job summary, and fails on such a
regression. End-to-end changes are shown, not gated: loopback timings move by
more than that between identical runs. A push to master keeps its results as
the `bench-results` artifact.

### Before and after the move onto std/http

The transport moved from iyi-web's own HTTP/1.1 reader onto std/http's
connection handler (`Server.handle`). `bench/run.sh` before and after, on
the same machine (a busy one, so read the end-to-end rows as a direction,
not a number):

| Case | Before | After |
|---|---:|---:|
| Request parse, GET (`intake.get` → `wire.get`) | 5966 ns | 3397 ns |
| Request parse, form POST (`intake.post_form` → `wire.post_form`) | 2267 ns | 1688 ns |
| End to end, hello | 22,064 req/s | 28,242 req/s |
| End to end, JSON | 21,083 req/s | 29,245 req/s |
| End to end, parameter route | 25,310 req/s | 27,004 req/s |

A request head is no longer copied into a string and parsed a second time.
The cross-framework table above was measured after the move.
