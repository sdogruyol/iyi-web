# iyi-web

The web framework for [iyi](https://iyi-lang.com).

```iyi
module app

import web/iyi_web/dsl::*

get "/" do |env|
  "Hello, world!"
end

run
```

iyi-web serves HTTP/1.1, HTTP/2 and HTTPS from native iyi programs. Routes
are blocks, middleware is a class, and settings live in a single `config`
value. It began as a port of [Kemal](https://kemalcr.com) to iyi and keeps
Kemal's DSL; [iyi-web-vs-kemal.md](iyi-web-vs-kemal.md) records where the
two differ.

**Documentation: [the docs site](docs/index.md)**, starting with the
[tutorial](docs/tutorial.md).

## Why iyi-web

- **Data races are compile errors.** Every request runs on whichever core is
  free, and the compiler checks each block you register where you write it:
  a route that touches a bare `Array` from several threads does not build,
  and the error names the variable and the two ways out - a
  [`Store`](docs/state.md) or `workers: 1` ([Every core](docs/every-core.md)).
- **Typed routes and OpenAPI.** A route says what it reads - the path, the
  query string, headers, a JSON body - and what it answers; iyi-web reads
  and validates it before your block runs, answers `400`/`415`/`422` naming
  each bad field, and makes an OpenAPI 3.1 document with Swagger UI from the
  same declarations ([Typed routes](docs/typed-routes.md),
  [OpenAPI](docs/openapi.md)).
- **Batteries included.** Dependencies and auth (JWT, OAuth2 password flow,
  API keys), sessions and CSRF, templates that escape by default, metrics
  and tracing, lifecycle hooks and background tasks, an in-process test
  harness, and an `iyi-web` command that scaffolds a project and rebuilds it
  on every save.
- **One native binary.** `iyi build --release` compiles the routes,
  templates and docs page into a program that starts at once and serves
  every core ([Benchmarks](docs/benchmarks.md)).

## A typed route and its OpenAPI document

```iyi
import std/json::{serializable}
import web/iyi_web/dsl::*

struct Page
  getter limit : Int32 = 3
  getter tag : String?
  derive serializable
end

get "/users/:id/notes", path: Int32, query: Page, response: Array(String) do |env, id, page|
  (1..page.limit).map { |n| "note #{n} of user #{id}" + (page.tag ? " tagged #{page.tag}" : "") }
end

openapi("Notes API", "1.0.0")   # /openapi.json, and Swagger UI at /docs

run
```

```sh
curl 'localhost:3000/users/7/notes?tag=work'
# ["note 1 of user 7 tagged work","note 2 of user 7 tagged work","note 3 of user 7 tagged work"]
curl -H 'Accept: application/json' 'localhost:3000/users/7/notes?limit=many'
# 422 {"error":"invalid query parameters: limit must be an integer","fields":{"limit":"must be an integer"}}
curl localhost:3000/openapi.json   # id, limit and tag, typed; Swagger UI at /docs
```

## Features

**Routing and input**

- Routes for `GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `OPTIONS`, `HEAD` and
  `QUERY`, with named and wildcard path segments
- Typed routes: `path:`, `query:`, `headers:` and `body:` read into your own
  types, `response:` and `status:` for the answer, and `env.params.int(...)`
  and friends for one parameter at a time
- URL, query-string, form, JSON and `multipart/form-data` parameters, with
  file uploads streamed to disk as they arrive
- JSON bodies read into your own types, with validation and `400`/`422`
  answers that name each bad field
- Before and after filters for every route, a path pattern or a single method
- Error pages per status code and per error type, automatic `404` and `405`
  responses, a `500` page for a route that panics, and errors that carry
  their own status
- Composable routers with `mount` and `namespace`

**APIs**

- An OpenAPI 3.1 document made from the routes, and a Swagger UI page
- Dependencies (`deps:`), resolved once per request before the route runs
- Bearer tokens, HS256 JWTs, API keys and OAuth2's password flow, each in
  the OpenAPI document as a security scheme

**Pages**

- Templates with layouts and partials, compiled into the program, escaping
  every value they print unless it is marked as markup
- Encrypted cookie sessions with secret rotation, and CSRF protection
- Static files with `ETag`, `304 Not Modified`, byte ranges, gzip at any size
  and precompressed `.gz` copies, streamed from disk
- File downloads, cookies, redirects and early responses with `halt`

**Around requests**

- Middleware for every request or for a path prefix
- Response compression, CORS and HTML form method override
- Basic authentication, security headers, request ids and per-client rate
  limiting
- `on_start` and `on_stop` hooks, and background tasks that run after the
  response
- `Store`: shared state every worker reads and changes, behind one lock
- Prometheus metrics at `/metrics`, and W3C trace context tracing exported
  over OTLP/HTTP
- An in-process test harness: requests sent to a router without a socket

**Transport** ([Transport](docs/transport.md))

- HTTP/1.1 and HTTP/2 on the same port: h2c with prior knowledge in the
  clear, h2 by ALPN over TLS, through iyi's `std/http`
- HTTPS and `wss://` with iyi's own TLS 1.3 and 1.2, mutual TLS with client
  certificates, and certificates from Let's Encrypt (`config.autocert`)
- Request bodies streamed to the route as they arrive (`stream_bodies`)
- zstd or gzip responses, negotiated per client (`config.compress`)
- Each request served on whichever core is free, checked for data races
  when the program compiles
- Streaming responses and server-sent events
- WebSockets, with an `Origin` check and sends from any fiber
- Persistent connections, graceful shutdown on `INT` and `TERM`, and
  timeouts for slow and idle clients
- IPv4, IPv6 and unix-socket listeners
- Command-line flags for host, port, workers, TLS versions and client CAs

**Tooling**

- `iyi-web new` writes a project (plain, `--api` or `--full`) whose test
  passes out of the box; `iyi-web dev` rebuilds and restarts it on every save
- An example on PostgreSQL with a connection pool and migrations
- A benchmark of iyi-web, FastAPI, Express, Kemal and Go on the same
  endpoints

## Requirements

[iyi](https://iyi-lang.com) 0.20.1 or later: `spawn_parallel`, the pool
every connection is served on, and the `@[Share(serial: workers, crossing: ...)]`
mark every registration carries, so a refusal is made on your line and names
both ways past it.

## Installation

iyi-web is an iyi module. Add it to your project under the short name `web`,
which the examples use:

```sh
iyi get github.com/sdogruyol/iyi-web --as web
```

That writes one line to `iyi.mod`:

```
require github.com/sdogruyol/iyi-web v0.5.1 as web
```

and `web/iyi_web/...` then names iyi-web's modules. `iyi get -u` moves to
the latest release. [Installation](docs/installation.md) has the details.

## Quick start

With the [`iyi-web` command](docs/cli.md):

```sh
iyi-web new app           # --api for a JSON API, --full for pages and assets
cd app
iyi test                  # the generated test passes
iyi-web dev               # serves http://localhost:3000, rebuilds on save
```

Or by hand, with the program at the top of this page saved as `app.iyi`:

```sh
mkdir app && cd app
iyi init app
iyi get github.com/sdogruyol/iyi-web --as web
iyi run app.iyi
```

The server listens on http://localhost:3000. Pass `-p 8080` or set `PORT` to
use another port.

## Documentation

The guide lives in [`docs/`](docs/index.md) and builds into a site with
`mkdocs serve` (`pip install mkdocs-material`).

| | |
|---|---|
| Start | [Installation](docs/installation.md), [Tutorial](docs/tutorial.md), [The `iyi-web` command](docs/cli.md) |
| Routes and input | [Routing](docs/routing.md), [Parameters](docs/parameters.md), [Typed routes](docs/typed-routes.md), [Requests and responses](docs/requests-and-responses.md), [Errors](docs/errors.md), [Routers](docs/routers.md) |
| Pages | [Templates](docs/templates.md), [Static files](docs/static-files.md), [Sessions and CSRF](docs/sessions-and-csrf.md) |
| Real time | [WebSockets and server-sent events](docs/websockets-and-sse.md) |
| APIs | [OpenAPI](docs/openapi.md), [Dependencies and auth](docs/dependencies-and-auth.md), [Databases](docs/database.md) |
| Around requests | [Middleware](docs/middleware.md), [Security](docs/security.md), [Lifecycle and background tasks](docs/lifecycle-and-background.md), [Observability](docs/observability.md), [Writing a plugin](docs/plugins.md) |
| Concurrency | [Every core](docs/every-core.md), [Shared state with `Store`](docs/state.md) |
| Running it | [Configuration](docs/configuration.md), [Testing](docs/testing.md), [Deployment](docs/deployment.md) |
| Reference | [Modules](docs/modules.md), [Benchmarks](docs/benchmarks.md), [Changelog](CHANGELOG.md) |

## Examples

`examples/` holds small programs, each on one topic. They import iyi-web by
its path inside this repository, `iyi_web/dsl` where an application writes
`web/iyi_web/dsl`, so run them from the repository root; arguments for the
program go after `--`:

```sh
iyi run examples/json_api.iyi
iyi run examples/json_api.iyi -- -p 8080
```

| Example | Shows |
|---|---|
| [`hello.iyi`](examples/hello.iyi) | The smallest application |
| [`json_api.iyi`](examples/json_api.iyi) | A CRUD API over an in-memory store, every route typed, with its OpenAPI document |
| [`typed_json.iyi`](examples/typed_json.iyi) | `body:`, `query:` and `path:` with `Validate` rules and `response:` types, the `400`/`415`/`422` answers, and notes kept in a `Store` |
| [`openapi_auth.iyi`](examples/openapi_auth.iyi) | A notes API with users and roles: OAuth2's password flow issuing JWTs, user and admin providers, an API-key client, and the docs page whose "Authorize" signs in |
| [`forms_and_uploads.iyi`](examples/forms_and_uploads.iyi) | Form fields, multipart uploads with limits, and `_method` override |
| [`templates.iyi`](examples/templates.iyi) | Views in `examples/views/` with a layout, `content_for`, a partial and autoescape |
| [`routers.iyi`](examples/routers.iyi) | `Router`, `mount`, `namespace`, router filters and error pages |
| [`middleware.iyi`](examples/middleware.iyi) | A custom `Handler` with `only` and `exclude`, CORS, gzip and static files from `examples/public/` |
| [`streaming_and_sse.iyi`](examples/streaming_and_sse.iyi) | `flush`, chunked responses and server-sent events |
| [`websocket_chat.iyi`](examples/websocket_chat.iyi) | A chat room over `ws`, broadcasting to every member |
| [`cookies_and_context.iyi`](examples/cookies_and_context.iyi) | Cookies, redirects and `env.set` / `env.get`, with a value of the application's own type |
| [`sessions_and_csrf.iyi`](examples/sessions_and_csrf.iyi) | Sign-in and sign-out with an encrypted cookie session, and forms guarded by `CSRFHandler` |
| [`security.iyi`](examples/security.iyi) | Basic auth on `/admin`, security headers, request ids and a per-address rate limit |
| [`observability.iyi`](examples/observability.iyi) | A `Store`, Prometheus metrics, a trace span per request sent to a collector, a background task and start/stop hooks |
| [`testing.iyi`](examples/testing.iyi) | Routes in their own module, tested in-process by `testing_test.iyi` |
| [`postgres/`](examples/postgres/app.iyi) | A JSON API on PostgreSQL with a connection pool and migrations, a project of its own ([Databases](docs/database.md)) |

Each file's opening comment lists `curl` commands to try. `iyi test examples`
runs the example test.

## Benchmarks

`bench/compare/` serves the same four endpoints from iyi-web, FastAPI,
Express, Kemal and Go's `net/http` on one machine, the fourth a PostgreSQL
query through a connection pool. On a 12-core Windows virtual machine,
iyi-web answered 71,000-78,000 requests a second on the plain endpoints,
ahead of Go's `net/http` (65,000-74,000), FastAPI (27,000-33,000) and Kemal
(about 11,000); on the database query iyi-web and Go were even (37,600 and
38,000), FastAPI 14,300, Kemal 10,800. [Benchmarks](docs/benchmarks.md) has
the tables, the setup and what the numbers do not say: an hour earlier the
same machine gave every framework about a quarter more.

`bench/run.sh` times iyi-web against itself, and CI compares every pull
request with its base branch so a slower hot path fails the build.

## Development

```sh
iyi test iyi_web
iyi test examples
iyi run examples/hello.iyi
bash bench/run.sh
mkdocs build --strict          # the docs site; pip install mkdocs-material
```

`iyi_web/refused_test.iyi` checks what the compiler says to the programs
in `iyi_web/refused`: each is refused on its own line, naming both ways
out, and `serial.iyi` compiles. It runs `iyi check` through the `iyi` on
the `PATH`, or the one `IYI` names.

## License

iyi-web is released under the [MIT License](LICENSE).
