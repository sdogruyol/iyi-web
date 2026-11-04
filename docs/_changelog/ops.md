### Added

- `on_start do ... end` and `on_stop do ... end` in the DSL
  (`iyi_web/lifecycle`), FastAPI's `lifespan` as two hooks. Start hooks run
  in order before the server is bound; one that answers an `Error` or panics
  stops the start, and the program exits 1 naming the hook's file and line
  (`could not start: on_start (app.iyi:3) failed: ...`). Stop hooks run
  after the drain and the background tasks, the last written first; one
  that fails is reported and the rest still run. Blocks are checked like a
  route's; `workers: 1` keeps one unchecked without putting the server on
  one thread. `Lifecycle`, `lifecycle_hook` and `LIFECYCLE` run hooks as a
  value, for tests.
- Background tasks (`iyi_web/background`): `env.background { }` in a route
  and `background { }` anywhere run work off the request path on whichever
  worker is free. A panic is caught, reported on standard error (or through
  `on_panic`) and counted; it never reaches the server. The stop waits up to
  `shutdown_timeout` for queued and running tasks, then cancels the rest,
  before the `on_stop` hooks. Outside a running server the work runs at
  once, isolated. `Background` is the runner as a value (`run`, `close`,
  `pending`, `panics`, `completed`, `running?`, `closing?`); `BACKGROUND`
  is the process's, started beside the listener by `run`.
- `Store(T)` (`iyi_web/store`): shared state every worker may change
  without the `Mutex` showing. `read`, `update` and `replace` run a block
  under the lock; `values`, `keys`, `to_a`, `to_h`, `[]?`, `size`, `get`
  and `set` copy out what a route wants. `Share`, so routes, handlers and
  background tasks capture it on every core.
- Prometheus metrics (`iyi_web/metrics`): `MetricsHandler` counts
  `http_requests_total{method,route,status}`, times
  `http_request_duration_seconds{method,route}` over Prometheus' default
  buckets and gauges `http_requests_in_flight`, labelling by route pattern
  (`/users/:id`), never by raw path, and serves the text exposition format
  at `/metrics`. `MetricsRegistry` (`METRICS` by default) makes `Counter`s,
  `Gauge`s, `Histogram`s and `gauge_function`s of an application's own; each
  family is behind its own lock.
- Tracing (`iyi_web/tracing`): `TraceHandler` records a span per request,
  the child of an incoming W3C `traceparent` (version `ff`, upper-case hex,
  zero ids and bad lengths refused) with its `tracestate` passed on, named by
  route pattern, with OpenTelemetry's HTTP attributes; `current_span(env)`
  adds the route's own attributes and events, and `Span#traceparent` carries
  the trace downstream. Spans go through a bounded `BatchSpanProcessor`
  drained by a background task, flushed when the server stops, to a
  `SpanExporter`: `OtlpHttpExporter` posts OTLP/HTTP JSON to a collector,
  `JsonLinesExporter` writes one JSON line per span.
- `examples/observability.iyi`: a `Store`, metrics, tracing to a collector
  or standard output, background work and start/stop hooks together.
- Guides in `docs/`: `lifecycle-and-background.md`, `state.md`,
  `observability.md` and `plugins.md` (writing, testing and publishing a
  handler package).

### Changed

- `Context` imports `iyi_web/background` for `Context#background`, and
  `iyi_web/log`'s `STDOUT_LOCK` is exported so other writers to standard
  output share the request log's lock.
- `run` runs the background runner beside the listener and, after the
  drain, closes it and runs the `on_stop` hooks before returning.
