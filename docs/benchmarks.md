# Benchmarks

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
