# Security

Four handlers from the [Middleware](middleware.md) table guard an application.
None is in the default stack; each honours `only` and `exclude`.

Bearer tokens, JWTs, API keys and OAuth2's password flow are
[dependencies](dependencies-and-auth.md) a route names, rather than
handlers, so they appear in the [OpenAPI document](openapi.md).

```iyi
import web/iyi_web/basic_auth::{BasicAuthHandler}
import web/iyi_web/rate_limit::{RateLimitHandler}
import web/iyi_web/request_id::{RequestIdHandler}
import web/iyi_web/security_headers::{SecurityHeadersHandler}

use RequestIdHandler.new
use SecurityHeadersHandler.new(content_security_policy: "default-src 'self'")
use RateLimitHandler.new(limit: 60, period: 60)

admin = BasicAuthHandler.new("admin", Program.env("ADMIN_PASSWORD") || raise "ADMIN_PASSWORD is not set")
admin.only ["/admin", "/admin/*"], "*"
use admin

get "/admin" do |env|
  "Signed in as " + env.get("basic_auth.username").to_s
end
```

**Basic authentication.** `BasicAuthHandler.new(username, password, realm:
"Restricted")` accepts one fixed user, comparing in constant time;
`BasicAuthHandler.new(realm: "API") { |user, password| ... }` accepts whatever
the block does. Missing, malformed or refused credentials get `401` with
`WWW-Authenticate: Basic realm="...", charset="UTF-8"`; accepted ones store
the user name under `"basic_auth.username"`. The password crosses the wire
on every request, so serve it over HTTPS. Kemal has this as the
kemal-basic-auth shard.

**Security headers.** `SecurityHeadersHandler.new` sends
`X-Content-Type-Options: nosniff`, `X-Frame-Options: SAMEORIGIN`,
`Referrer-Policy: strict-origin-when-cross-origin` and
`Cross-Origin-Opener-Policy: same-origin`. The named arguments
`content_type_options`, `frame_options`, `referrer_policy`,
`cross_origin_opener_policy`, `content_security_policy` and
`strict_transport_security` replace a value; `nil` leaves a header out. HSTS
is only sent over TLS, or when a proxy sends `X-Forwarded-Proto: https`. The
headers are set before the route runs, so a route can overwrite one (a page
meant to be framed sets its own `X-Frame-Options`) or delete it, and streamed
responses carry them. Static files are served before `use` handlers; add the
handler with `use SecurityHeadersHandler.new, 0` to cover them too.

**Request ids.** `RequestIdHandler.new` keeps an incoming `X-Request-Id` of up
to 128 letters, digits and `-_.:@+=/`, and replaces any other with a fresh
UUID rather than cleaning it up. The id is sent back in the same header,
stored under `"request_id"`, and appended to the request's log line:
`GET / 200 0.17ms 6f1c...`. `header:`, `max_length:` and `trust_incoming:
false` (always make a new one) change that.

**Rate limiting.** `RateLimitHandler.new(limit: 60, period: 60)` lets each
client address make `limit` requests per `period` seconds, counted in fixed
windows. Every response carries `RateLimit-Limit`, `RateLimit-Remaining` and
`RateLimit-Reset` (seconds); past the limit the answer is `429` with
`Retry-After`. At most `max_keys` (default 10,000) windows are held: ended
ones are dropped, and when all are open the oldest gives way. The counters
are one table every worker counts in, behind a lock each request takes
once. Behind a
reverse proxy every request has the proxy's address, so pass a block that
picks the key; trust `X-Forwarded-For` only when a proxy you run sets it,
and answer nil to leave a request unlimited:

```iyi
use RateLimitHandler.new(limit: 100, period: 60) { |ctx|
  forwarded = ctx.request.headers["X-Forwarded-For"]?
  forwarded ? forwarded.split(",").last.strip : ctx.request.remote_address
}
```

`clock:` takes a block answering milliseconds, which is how a test moves time
without sleeping.
