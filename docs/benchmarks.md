# Benchmarks

## Across frameworks

`bench/compare/` runs the same three endpoints in iyi-web, FastAPI, Express,
Kemal and Go's `net/http` on one machine and loads each with
[oha](https://github.com/hatoo/oha). (`bench/run.sh` is a different thing:
it times [iyi-web against itself](#iyi-web-against-itself) for regressions.)

| Endpoint | Answer |
|---|---|
| `GET /plaintext` | `Hello, World!` as `text/plain` |
| `GET /json` | `{"message":"Hello, World!"}` |
| `GET /users/42?fields=name,email` | `{"id":42,"name":"user-42","fields":"name,email"}`: a path parameter parsed as an integer and a query parameter |

```sh
bash bench/compare/run.sh                               # every framework, 10 s per endpoint
bash bench/compare/run.sh --duration 5 --only iyi-web,go
bash bench/compare/run.sh --help                        # warm-up, connections, workers, port, output
```

The runner (`bench/compare/run.iyi`, built and started by `run.sh`) does,
for each framework in turn:

1. Skips it, with the reason, when its toolchain is missing: `node` for
   Express, `crystal` for Kemal, `go`, or FastAPI/uvicorn not importable.
   The skip is recorded in the results, so a missing row says why.
2. Builds it for release: `iyi build --release`, `crystal build --release`,
   `go build`, `npm install` for Express. Kemal's shards are installed with
   `shards install`; where shards cannot run (on Windows it needs symlinks,
   so Developer Mode or an elevated shell) the runner clones the same
   versions into `lib/` with git and says so.
3. Starts it on its own port, serving on every core the way each is
   deployed: iyi-web, Kemal (Crystal's default execution context resized to
   the core count) and Go with threads; FastAPI under uvicorn with one
   worker process per core and `httptools`; Express with one `node:cluster`
   worker per core. Request logging is off everywhere.
4. Checks every endpoint's status, `Content-Type` and body, and that
   `/users/abc` is refused with a 4xx. A framework that answers wrongly is
   reported failed and not timed: doing less work is not winning.
5. Warms each endpoint up (3 s), then measures it (10 s) at 64 keep-alive
   connections: requests per second that got a `200`, p50 and p99 latency,
   and non-200 answers or connection errors (requests cut off when the
   timer ends are not errors).
6. Stops it (on Windows, with every process it started).

Results go to `bench/compare/results.json` and `bench/compare/results.md`
(both ignored by git).

### Results

Measured 2026-11-04 with `bash bench/compare/run.sh` (defaults):

| Framework | `/plaintext` req/s | `/json` req/s | `/users/42` req/s |
|---|---:|---:|---:|
| iyi-web | 59754 | 53627 | 68612 |
| FastAPI | 26627 | 27704 | 22848 |
| Express | skipped: node not found on PATH | | |
| Kemal | 12406 | 12374 | 12927 |
| Go net/http | 64358 | 51612 | 55107 |

| Framework | Endpoint | req/s | p50 ms | p99 ms | non-200 / errors |
|---|---|---:|---:|---:|---:|
| iyi-web | `/plaintext` | 59754 | 0.685 | 8.652 | 0 |
| iyi-web | `/json` | 53627 | 0.694 | 9.649 | 228 |
| iyi-web | `/users/42?fields=name,email` | 68612 | 0.617 | 6.719 | 0 |
| FastAPI | `/plaintext` | 26627 | 1.554 | 21.301 | 0 |
| FastAPI | `/json` | 27704 | 1.540 | 20.352 | 0 |
| FastAPI | `/users/42?fields=name,email` | 22848 | 1.757 | 22.111 | 0 |
| Kemal | `/plaintext` | 12406 | 3.804 | 20.751 | 0 |
| Kemal | `/json` | 12374 | 3.940 | 19.536 | 0 |
| Kemal | `/users/42?fields=name,email` | 12927 | 3.817 | 17.927 | 0 |
| Go | `/plaintext` | 64358 | 0.421 | 8.767 | 0 |
| Go | `/json` | 51612 | 0.437 | 11.920 | 0 |
| Go | `/users/42?fields=name,email` | 55107 | 0.423 | 11.067 | 0 |

- Machine: Windows 10.0.26200.9711, QEMU Virtual CPU version 2.5+, 12
  logical cores, a virtual machine.
- iyi-web from this checkout (0.5.1 plus the roadmap work) on iyi 0.20.1;
  FastAPI 0.162.0, uvicorn 0.54.0, httptools 0.9.0, Python 3.12.10; Kemal
  1.15.0 on Crystal 1.22.0; Go 1.27.3; oha 1.16.0.
- 64 connections, 3 s warm-up and 10 s measured per endpoint, 12 workers
  per server.

### Reading these numbers

- **One machine, loopback, Windows.** oha ran on the same 12 cores as the
  server, so every number includes the client's share of the CPU. Windows
  loopback and its socket stack are slower than Linux's, and each runtime's
  Windows I/O path is a different code path from its Linux one. These
  numbers rank the frameworks on this machine; they are not what any of
  them does on a Linux server with a separate load generator.
- **The machine was not quiet.** Other builds and test suites were running
  on it during the run. A shorter trial run earlier the same day (2 s per
  endpoint) gave iyi-web about 87,000-90,000 req/s and Go about
  69,000-77,000 req/s on the same endpoints, with Kemal at about 13,000:
  the order held, the absolute numbers moved by a third. Run it more than
  once before quoting a number.
- **Kemal on Windows.** Kemal served about 10,200 req/s on `/json` with one
  thread (`CRYSTAL_WORKERS=1`) and about 12,400 with twelve: Crystal's
  Windows event loop, not Kemal's routing, is the likely limit here. Kemal
  on Linux is a different result.
- **iyi-web's 228 errors on `/json`.** 228 of about 536,000 requests in
  that run were not answered `200`; the trial run, the other two endpoints
  and the other frameworks had none. The run did not record which errors
  they were, and this has not been reproduced or explained yet.
- **Express was not measured** because Node.js is not installed on this
  machine. Its app (`bench/compare/express/`, Express 5 under
  `node:cluster`) and the runner's support for it are there; on a machine
  with `node` it runs like the rest.
- **FastAPI** refuses `/users/abc` with `422` (its `id: int` validation),
  the others with `404`; the check accepts any 4xx.

### Files

```
bench/compare/
  run.sh             builds run.iyi and runs it
  run.iyi            the runner
  iyiweb/app.iyi     iyi-web
  fastapi/app.py     FastAPI (requirements.txt: fastapi, uvicorn, httptools)
  express/app.js     Express (package.json)
  kemal/src/app.cr   Kemal (shard.yml)
  go/main.go         Go net/http (go.mod)
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
`bench/compare` with iyi-web alone after the move gave 65,780 req/s on
`/plaintext`, 60,286 on `/json` and 81,050 on `/users/42`, with no
non-200 answers; the cross-framework table above predates it.
