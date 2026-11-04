# Observability: metrics and tracing

Two handlers answer "what is the server doing": `MetricsHandler` counts and
times every request for Prometheus, and `TraceHandler` records a span per
request for OpenTelemetry. Both run on every worker and never make a request
wait for a scraper or a collector. `examples/observability.iyi` uses both.

```iyi
import web/iyi_web/dsl::*
import web/iyi_web/metrics::{MetricsHandler}
import web/iyi_web/tracing::{TraceHandler, OtlpHttpExporter}

use MetricsHandler.new, 0
use TraceHandler.new(OtlpHttpExporter.new("http://localhost:4318/v1/traces", service_name: "shop")), 1

get "/orders/:id" do |env|
  "order " + env.params.url["id"]
end

run
```

Placed first (`use handler, 0`), they see every request, static files and
those other handlers answer themselves included. Placed with a plain `use`
they come after request logging and static files, and see what reaches the
router.

## Metrics

`MetricsHandler` counts into a registry - `METRICS`, the process's own,
unless given another - and serves it at `/metrics` (`GET` and `HEAD`) in
Prometheus' text exposition format, version 0.0.4. The scrape itself is not
counted.

```sh
curl localhost:3000/metrics
```

```
# HELP http_requests_total HTTP requests answered, by method, route pattern and status.
# TYPE http_requests_total counter
http_requests_total{method="GET",route="/orders/:id",status="200"} 1
http_requests_total{method="GET",route="/orders/:id",status="404"} 1
http_requests_total{method="POST",route="/orders",status="201"} 1
# HELP http_request_duration_seconds Time from the request reaching this handler to the response being ready, by method and route pattern.
# TYPE http_request_duration_seconds histogram
http_request_duration_seconds_bucket{method="GET",route="/orders/:id",le="0.005"} 2
...
http_request_duration_seconds_bucket{method="GET",route="/orders/:id",le="10"} 2
http_request_duration_seconds_bucket{method="GET",route="/orders/:id",le="+Inf"} 2
http_request_duration_seconds_sum{method="GET",route="/orders/:id"} 0.0004077
http_request_duration_seconds_count{method="GET",route="/orders/:id"} 2
# HELP http_requests_in_flight HTTP requests being handled now.
# TYPE http_requests_in_flight gauge
http_requests_in_flight 0
```

- **`route` is the pattern, never the path.** `/orders/1` and `/orders/2`
  are both `route="/orders/:id"`. Every distinct label value is a series of
  its own in Prometheus, and raw paths would give it one per order. A
  request no route matched - a 404, a static file, one a handler answered
  itself - is `route="unrouted"`.
- **Buckets** are Prometheus' defaults, 5 ms to 10 s
  (`DEFAULT_BUCKETS`), cumulative, ending with `+Inf`.
- **A panic** that leaves the chain is counted as the 500 it becomes.
- `only` and `exclude` work as on every handler: a request the handler is
  not for is neither counted nor timed.

| Argument | Default | |
|---|---|---|
| `registry` | `METRICS` | Where the HTTP families are registered and what `/metrics` serves. |
| `path` | `"/metrics"` | Where the page is served. |
| `buckets` | `DEFAULT_BUCKETS` | Upper bounds of the duration histogram, in seconds, increasing. |
| `unrouted` | `"unrouted"` | The `route` label of a request no route matched. |

To keep the page from the public, serve it on a path only the scraper knows
(`MetricsHandler.new(path: "/internal/metrics")`) or put a handler that
checks a token in front of it.

### Your own metrics

```iyi
import web/iyi_web/metrics::{METRICS}

ORDERS  = METRICS.counter("orders_created_total", "Orders taken, by item.", ["item"])
QUEUED  = METRICS.gauge("jobs_queued", "Jobs waiting.")
LATENCY = METRICS.histogram("payment_seconds", "Payment provider latency.", buckets: [0.1, 0.5, 1.0, 5.0])

post "/orders" do |env|
  ORDERS.inc([env.params.body["item"]? || "unknown"])
  QUEUED.inc
  "ok"
end
```

| Type | Methods |
|---|---|
| `Counter` | `inc(labels = [] of String, by = 1.0)`, `value(labels)`. Only goes up: a negative `by` panics. |
| `Gauge` | `set(value, labels)`, `inc(labels, by)`, `dec(labels, by)`, `value(labels)`. |
| `Histogram` | `observe(value, labels)`. |

Label values are given in the order the label names were. `gauge_function`
registers a gauge whose value a block answers when the page is written - a
queue's length, a pool's free connections:

```iyi
METRICS.gauge_function("db_pool_free", "Free database connections.") { POOL.free.to_f64 }
```

Every family is `Share`: its series are behind a lock of its own, so
requests counting into different families never wait for each other.
Registering a name twice answers the family already there when the kind,
labels and buckets agree, and panics when they do not. Names are checked
(`[a-zA-Z_:][a-zA-Z0-9_:]*`; labels `[a-zA-Z_][a-zA-Z0-9_]*`, not
starting `__`; no `le` on a histogram), and so is the number of label values
on every call. Help text and label values are escaped as the format asks
(`\\`, `\"`, `\n`). `MetricsRegistry.new` makes a registry of its own, for a
test or a second page; `registry.expose` is the page as a `String`.

A Prometheus job for it:

```yaml
scrape_configs:
  - job_name: shop
    static_configs:
      - targets: ["localhost:3000"]
```

## Tracing

`TraceHandler` gives every request a span and hands it, finished, to an
exporter.

### Propagation

An incoming `traceparent` header (W3C Trace Context) that parses makes the
request's span a child of the caller's: the same trace id, the caller's span
as the parent, the caller's sampled flag, and a span id of its own. A header
that does not parse is ignored and the span starts a new trace:

- not `VERSION-TRACEID-PARENTID-FLAGS` with 2, 32, 16 and 2 lower-case hex
  digits;
- version `ff`, which the specification forbids;
- a trace id or parent id of all zeros;
- a version `00` header longer than 55 characters. A later version may
  carry more after a `-`, which is ignored.

`tracestate` is kept when the `traceparent` was valid and it is: list members
trimmed and joined with `,`, empty ones dropped; one with more than 32
members, a key twice, or a key or value outside the grammar is discarded
whole. New ids come from the operating system's random source
(`web/iyi_web/token`), never all zeros.

To carry the trace to the next service, send the span's `traceparent`:

```iyi
get "/checkout" do |env|
  headers = {} of String => String
  if span = current_span(env)
    headers["traceparent"] = span.traceparent    # 00-<trace>-<this span>-01
  end
  HTTP.request("POST", "http://payments/charge", headers, "...")
  "ok"
end
```

`parse_traceparent` and `parse_tracestate` are exported for code that reads
the headers itself.

### The span

The span is named after the route pattern, `GET /orders/:id`, or the method
alone when no route matched. Its attributes follow OpenTelemetry's HTTP
semantic conventions:

| Attribute | Value |
|---|---|
| `http.request.method` | `GET` |
| `url.path` | `/orders/7` |
| `http.route` | `/orders/:id`, when a route matched |
| `http.response.status_code` | `200` |
| `server.address` | the `Host` header without its port |
| `error.type` | the status, for a 5xx answer (`panic` for a panic that left the chain) |

A 5xx answer also marks the span failed (`HTTP 503`). `current_span(env)` is
the request's span, for the route's own attributes and events;
`env.get("trace_id")` is its trace id, for a log line:

```iyi
get "/orders/:id" do |env|
  if span = current_span(env)
    span.set_attribute("order.id", env.params.url["id"])
    span.add_event("cache miss", {"layer" => "redis"} of String => AttributeValue)
    span.error("payment declined") if declined
  end
  "..."
end
```

An attribute is a `String`, an `Int32` or `Int64`, a `Float64` or a `Bool`.
`TraceHandler.new(exporter, sample: false)` records no new traces, only the
ones a caller sampled; a span that is not sampled is never exported. Keep
probes out of the traces with `exclude`:

```iyi
tracer = TraceHandler.new(exporter)
tracer.exclude ["/health", "/metrics"]
use tracer, 0
```

### Export

A finished span goes to a `BatchSpanProcessor`, which a request never waits
on:

- the queue is bounded (`max_queue`, 2048): a span past it is dropped and
  counted (`processor.dropped`), never waited for;
- a [background task](lifecycle-and-background.md) sends up to `batch_size`
  spans (512) at a time, once a batch is full or `delay` (2 s) has passed
  since the first span waiting;
- when the server stops, the background drain lets that task send what is
  left at once, before the `on_stop` hooks run;
- `tracer.flush` sends everything queued now, from wherever it is called.
  Outside a running server - a harness test - there is no background task:
  a full batch is sent on the request's task, and the rest waits for
  `flush`.

```iyi
TraceHandler.new(exporter, max_queue: 4096, batch_size: 256, delay: Span.milliseconds(500))
```

Two exporters come with it:

- **`OtlpHttpExporter.new(url, service_name: "shop", headers: {...}, timeout_ms: 10_000)`**
  posts each batch as OTLP/HTTP JSON (`ExportTraceServiceRequest`, ids in
  hex, 64-bit integers as strings, span kind server) to an OpenTelemetry
  Collector's `http://HOST:4318/v1/traces`, or a vendor's endpoint with its
  key in `headers`. A refused or failed post is reported on standard error
  with its status and the batch is dropped, not retried; `sent` and
  `failed` count batches.
- **`JsonLinesExporter.new`** writes one JSON object per span per line to
  standard output, under the lock request log lines are written under.
  `JsonLinesExporter.to { |line| ... }` sends the lines elsewhere.

What `examples/observability.iyi` posted to a collector for
`curl -H 'traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01' -H 'tracestate: rojo=00f067aa0ba902b7' localhost:3000/orders/1`
(shortened):

```json
{"resourceSpans": [{
  "resource": {"attributes": [{"key": "service.name", "value": {"stringValue": "observability-example"}}]},
  "scopeSpans": [{"scope": {"name": "iyi_web/tracing"}, "spans": [{
    "traceId": "4bf92f3577b34da6a3ce929d0e0e4736",
    "spanId": "478035727faa2e17",
    "parentSpanId": "00f067aa0ba902b7",
    "traceState": "rojo=00f067aa0ba902b7",
    "name": "GET /orders/:id",
    "kind": 2,
    "startTimeUnixNano": "1793812240684904500",
    "endTimeUnixNano": "1793812240685070500",
    "attributes": [
      {"key": "order.id", "value": {"intValue": "1"}},
      {"key": "http.request.method", "value": {"stringValue": "GET"}},
      {"key": "url.path", "value": {"stringValue": "/orders/1"}},
      {"key": "http.route", "value": {"stringValue": "/orders/:id"}},
      {"key": "http.response.status_code", "value": {"intValue": "200"}},
      {"key": "server.address", "value": {"stringValue": "localhost"}}
    ],
    "events": [{"timeUnixNano": "1793812240685057600", "name": "order found", "attributes": []}],
    "status": {"code": 0}
  }]}]
}]}
```

### An exporter of your own

`SpanExporter` is a trait with one requirement. An exporter is called from a
background task, one batch at a time, so it must be `Share`: no field
assigned after `initialize`, counts in an `Atomic`, tables behind a `Mutex`.

```iyi
import web/iyi_web/tracing::{SpanExporter, SpanData}

class SlowSpans
  @threshold_ns : Int64

  def initialize(@threshold_ns : Int64)
  end

  def export(spans : Array(SpanData)) : Nil
    spans.each do |span|
      took = span.end_unix_nano - span.start_unix_nano
      puts "slow: #{span.name} #{took // 1_000_000}ms" if took > @threshold_ns
    end
  end
end

impl SpanExporter for SlowSpans
end

use TraceHandler.new(SlowSpans.new(250_000_000_i64)), 0
```

`SpanData` carries `trace_id`, `span_id`, `parent_span_id`, `tracestate`,
`name`, `start_unix_nano`, `end_unix_nano`, `attributes` (with
`attribute(key)` to look one up), `events` and `error`; `to_json_line` and
`otlp_json(spans, service_name)` write it as the two built-in exporters do.
