# Middleware

Requests pass through request logging, static files, the middleware added with
`use` in the order it was added, and then the router.

```iyi
import web/iyi_web/cors::{CORSHandler}
import web/iyi_web/override::{OverrideMethodHandler}

gzip true
use OverrideMethodHandler.new
use "/api", CORSHandler.new(origin: "https://app.example.com")
```

`use handler` runs a handler for every request; `use "/api", handler` or
`use "/api", [first, second]` runs it for `/api` and every path under it.
`use handler, 0` places a handler at an index of the finished chain, 0 being
before request logging.

| Handler | Module | Purpose |
|---|---|---|
| `CompressHandler` | `web/iyi_web/compress` | Compresses textual responses of 860 bytes or more with gzip or deflate when `Accept-Encoding` allows it. `gzip true` adds it. |
| `CORSHandler` | `web/iyi_web/cors` | Sets `Access-Control-Allow-Origin` and answers preflight requests with `204`. Takes `origin` (default `*`), `methods`, `headers` (default `*`) and `max_age` (seconds as a string, default `"86400"`). |
| `OverrideMethodHandler` | `web/iyi_web/override` | Treats a form `POST` with `_method` set to `PUT`, `PATCH` or `DELETE` as that method. |
| `SessionHandler` | `web/iyi_web/session` | Keeps an encrypted session in a cookie. See [Sessions](sessions-and-csrf.md). |
| `CSRFHandler` | `web/iyi_web/csrf` | Refuses unsafe requests without the session's CSRF token with `403`. See [CSRF](sessions-and-csrf.md#csrf). |
| `LogHandler` | `web/iyi_web/log` | Writes one line per request to `config.logger`. Added by default; `logging false` removes it. |
| `StaticHandler` | `web/iyi_web/static` | Serves the public folder. Added by default; `serve_static false` removes it. |
| `SecurityHeadersHandler` | `web/iyi_web/security_headers` | Sets `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `Cross-Origin-Opener-Policy` and, when given, `Content-Security-Policy` and `Strict-Transport-Security`. See [Security](security.md). |
| `BasicAuthHandler` | `web/iyi_web/basic_auth` | HTTP Basic authentication; `401` with a challenge otherwise. See [Security](security.md). |
| `RequestIdHandler` | `web/iyi_web/request_id` | Keeps or makes an `X-Request-Id`, echoes it and logs it. See [Security](security.md). |
| `RateLimitHandler` | `web/iyi_web/rate_limit` | Limits requests per client address or chosen key; `429` with `Retry-After` past the limit. See [Security](security.md). |
| `MetricsHandler` | `web/iyi_web/metrics` | Counts and times every request by method, route pattern and status, and serves Prometheus metrics at `/metrics`. See [Observability](observability.md). |
| `TraceHandler` | `web/iyi_web/tracing` | One span per request, W3C `traceparent` in and out, exported in batches over OTLP/HTTP or as JSON lines. See [Observability](observability.md). |

To write your own, subclass `Handler`, override `call`, and pass the request
on with `call_next`. A handler that does not call `call_next` ends the chain.
`only` and `exclude` record which paths and methods a handler is for, using
the filter path syntax; `only_match?` and `exclude_match?` answer for the
current request, and `applies?` combines them the way the built-in handlers
do (an empty `only` meaning every path):

```iyi
import web/iyi_web/handler::{Handler}
import web/iyi_web/context::{Context}

class RequireToken < Handler
  @token : String

  def initialize(@token : String)
    super()
    only ["/api/*"], "*"
    exclude ["/api/health"], "*"
  end

  pub def call(ctx : Context) : Nil
    return call_next(ctx) unless only_match?(ctx)
    return call_next(ctx) if exclude_match?(ctx)
    if ctx.request.headers["Authorization"]? == "Bearer " + @token
      call_next(ctx)
    else
      ctx.halt(401, "Unauthorized")
    end
  end
end

token = Program.env("API_TOKEN") || raise "API_TOKEN is not set"
use RequireToken.new(token)
```

[Writing and publishing a plugin](plugins.md) packages a handler as a
module other applications add with `iyi get`.
