# iyi-web

The web framework for [iyi](https://iyi-lang.com).

```iyi
module app

import iyi_web/dsl
using iyi_web/dsl

get "/" do |env|
  "Hello, world!"
end

run
```

iyi-web serves HTTP/1.1 from native iyi programs. Routes are blocks,
middleware is a class, and settings live in a single `config` value. The type
a route returns is checked when the program compiles.

## Features

- Routes for `GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `OPTIONS`, `HEAD` and
  `QUERY`, with named and wildcard path segments
- URL, query-string and form parameters
- Before and after filters for every route, a path prefix or a single method
- Custom error pages per status code, automatic `404` and `405` responses, and
  `HEAD` for every `GET` route
- Composable routers with `mount` and `namespace`
- Middleware for every request or for a path prefix
- Static files, file downloads, cookies, redirects and early responses with
  `halt`
- CORS and HTML form method override
- Server-side templates compiled into the program with `std/eiy`
- Persistent connections, each served by its own fiber

## Requirements

[iyi](https://iyi-lang.com) 0.14.0 or later.

## Installation

iyi-web is distributed as source. Copy the `iyi_web` directory of a release
into your project's `lib/` directory:

```sh
git clone --depth 1 --branch v0.1.0 https://github.com/sdogruyol/iyi-web.git
mkdir -p lib
cp -R iyi-web/iyi_web lib/
rm -rf iyi-web
```

iyi resolves imports from `lib/` relative to the working directory, so run
`iyi` from the project root. To upgrade, replace `lib/iyi_web` with the
directory from the new release.

## Quick start

Save the program at the top of this page as `app.iyi` and run it:

```sh
iyi run app.iyi
```

The server listens on http://localhost:3000. Set `PORT` to use another port.

The examples below extend this program. Each goes between the `using` line and
`run`, and any `import` or `using` lines it shows go at the top of the file.

## Routing

```iyi
get "/articles" do |env|
  "All articles"
end

post "/articles" do |env|
  env.response.status_code = 201
  "Created"
end

get "/articles/:id" do |env|
  "Article " + env.params.url["id"]
end

delete "/articles/:id" do |env|
  env.response.status_code = 204
  nil
end

get "/assets/*path" do |env|
  "Asset " + env.params.url["path"]
end
```

`put`, `patch`, `options`, `head` and `query` work the same way. Paths start
with `/`.

- `:name` matches one path segment: `/articles/42` sets `id` to `42`.
- `*name` matches the rest of the path: `/assets/css/site.css` sets `path` to
  `css/site.css`.

A request that matches no route gets `404 Not Found`. A path that exists only
for other methods gets `405 Method Not Allowed` with an `Allow` header. Every
`GET` route also answers `HEAD`, without a body.

### Return values

The value a route returns is the response body. A route may return any type
that implements `IntoBody`; `String`, `Nil` (an empty body), `Int32`, `Int64`
and `Bool` do. The check happens at compile time, on the route. Implement
`IntoBody` to return your own types:

```iyi
import iyi_web/body
using iyi_web/body::{IntoBody}

struct Temperature
  def initialize(@celsius : Int32)
  end

  def celsius : Int32
    @celsius
  end
end

impl IntoBody for Temperature
  def into_body : String
    celsius.to_s + " °C"
  end
end

get "/temperature" do |env|
  Temperature.new(21)
end
```

## Parameters

```iyi
get "/search" do |env|
  term = env.params.query["q"]? || ""
  "Results for " + term
end

post "/subscribe" do |env|
  email = env.params.body["email"]? || ""
  "Subscribed " + email
end
```

| Source | Access |
|---|---|
| Route segments (`:id`, `*path`) | `env.params.url` |
| Query string | `env.params.query` |
| `application/x-www-form-urlencoded` body | `env.params.body` |

Each is a `Hash(String, String)` of percent-decoded values.
`env.params["name"]?` searches all three, in the order above. Indexing without
`?` panics when the key is missing, so use `[]?` for optional values. Other
request bodies, such as JSON, are available unparsed as `env.request.body`.

## Requests

`env.request` exposes `method`, `path`, `query_string`, `headers`, `body`,
`content_type`, `content_length`, `host` and `version`. Header lookups ignore
case:

```iyi
get "/agent" do |env|
  env.request.headers["User-Agent"]? || "unknown"
end
```

## Responses

Set the status, headers and content type on `env.response`:

```iyi
get "/report.csv" do |env|
  env.response.content_type = "text/csv; charset=utf-8"
  env.response.headers["Cache-Control"] = "no-store"
  "id,total\n1,42\n"
end
```

Responses default to `200` and `text/html; charset=utf-8`. The server sets
`Content-Length`, `Date` and `Connection`. `env.response.headers.add` appends
a header instead of replacing it.

These helpers set the content type and the body in one call:

| Helper | Content-Type |
|---|---|
| `env.text(body)` | `text/plain; charset=utf-8` |
| `env.html(body)` | `text/html; charset=utf-8` |
| `env.json(body)` | `application/json; charset=utf-8` |
| `env.xml(body)` | `application/xml; charset=utf-8` |

`env.status(code)` sets the status and returns `env`, so the two combine:

```iyi
post "/api/items" do |env|
  env.status(201).json(%({"created":true}))
end
```

### JSON

`std/json` parses documents with `JSON.parse?` and writes them with
`JSON.build` or `JSON.to_json`:

```iyi
import std/json
using std/json::{JSON}

get "/api/items/:id" do |env|
  item = JSON.build do |json|
    json.object do
      json.field("id", env.params.url["id"])
      json.field("status", "active")
    end
  end
  env.json(item)
end

post "/api/echo" do |env|
  payload = JSON.parse?(env.request.body)
  if payload
    env.json(JSON.to_json(payload))
  else
    env.halt(400, "Invalid JSON")
  end
end
```

### Redirects and halting

```iyi
get "/home" do |env|
  env.redirect("/")
end

get "/legacy" do |env|
  env.redirect("/articles", 301)
end

get "/private" do |env|
  env.halt(403, "Forbidden")
end
```

`redirect` responds with `302` unless given a status. After `redirect` or
`halt`, the rest of the chain is skipped: remaining filters and the route do
not run, the route's return value is discarded, and error pages are not
applied.

### Cookies

```iyi
post "/sign-in" do |env|
  env.set_cookie("session", "3f9a1c", http_only: true, secure: true, max_age: 86400, same_site: "Lax")
  env.redirect("/account")
end

get "/account" do |env|
  session = env.cookies["session"]?
  session ? "Signed in" : "Signed out"
end
```

`set_cookie` also takes `path`, which defaults to `/`. A `max_age` of `0`, the
default, makes a session cookie. Cookie values are read back percent-decoded,
so percent-encode values that may contain `%`, `+`, `;`, `,` or spaces.

### Files

```iyi
get "/download/report" do |env|
  env.send_file("reports/latest.pdf", filename: "report.pdf")
end
```

The content type follows the file extension unless `mime_type:` is given, and
`filename:` marks the response as a download. A missing file responds with
`404`. The file is read into memory in full.

## Filters

```iyi
before_all do |env|
  env.response.headers["X-Content-Type-Options"] = "nosniff"
end

before_all "/admin" do |env|
  env.halt(401, "Unauthorized") unless env.cookies.has_key?("session")
end

after_get "/api/*" do |env|
  env.response.headers["Cache-Control"] = "no-store"
end
```

- `before_all` and `after_all` run for every method. `before_get`,
  `after_post` and their siblings run for one method: `get`, `post`, `put`,
  `patch`, `delete`, `options` or `query`.
- The path defaults to `*`, every route. `/admin` and `/admin/*` both match
  `/admin` and every path under it.
- Filters run in declaration order, and only for requests that match a route.
- A before filter that calls `halt` or `redirect` stops the request before the
  route runs.
- A filter's return value is discarded, but like a route's it must implement
  `IntoBody`.

Filters, middleware and routes can pass strings along a request with
`env["key"] = value` and read them with `env["key"]?`:

```iyi
before_all do |env|
  env["locale"] = env.request.headers["Accept-Language"]? || "en"
end

get "/locale" do |env|
  "Locale: " + env["locale"]
end
```

## Error pages

```iyi
error 404 do |env|
  "<h1>Page not found</h1>"
end

error 422 do |env|
  "<h1>Please check the form and try again</h1>"
end

post "/signup" do |env|
  email = env.params.body["email"]? || ""
  env.response.status_code = 422 if email.empty?
  "Welcome"
end
```

An error page replaces the body of `404` and `405` responses from the router,
and of any response a route finishes with a status of `400` or above. The
status code is kept. Responses ended with `halt` are sent unchanged.

A panic in a handler is contained to its connection: the connection closes
without a response, the panic is logged, and the server keeps serving. Report
failures by setting a status, not by panicking.

## Routers

```iyi
import iyi_web/router
using iyi_web/router::{Router}

admin = Router.new

admin.get "/" do |env|
  "Dashboard"
end

admin.namespace "/reports" do |reports|
  reports.get "/daily" do |env|
    "Daily report"
  end
end

mount "/admin", admin
```

This serves `/admin` and `/admin/reports/daily`. A `Router` has the same route,
filter (`before`, `after`, `before_get`, …) and `error` methods as the
program. `mount` without a path mounts a router at the root, and `namespace`
passes the nested router to its block.

Larger applications keep routers in their own modules. A module does not need
the DSL to define one:

```iyi
# routes/health.iyi
module routes/health

import iyi_web/router
using iyi_web/router::{Router}

pub def health_routes : Router
  router = Router.new
  router.get "/health" do |env|
    "ok"
  end
  router
end
```

```iyi
import routes/health
using routes/health

mount health_routes
```

## Middleware

Requests pass through request logging, static files, the middleware added with
`use` in the order it was added, and then the router.

```iyi
import iyi_web/cors
import iyi_web/override
using iyi_web/cors::{CORSHandler}
using iyi_web/override::{OverrideMethodHandler}

use OverrideMethodHandler.new
use "/api", CORSHandler.new(origin: "https://app.example.com")
```

`use handler` runs a handler for every request; `use "/api", handler` runs it
for `/api` and every path under it.

| Handler | Module | Purpose |
|---|---|---|
| `CORSHandler` | `iyi_web/cors` | Sets `Access-Control-Allow-Origin` and answers preflight requests with `204`. Takes `origin` (default `*`), `methods`, `headers` (default `*`) and `max_age` (seconds as a string, default `"86400"`). |
| `OverrideMethodHandler` | `iyi_web/override` | Treats a form `POST` with `_method` set to `PUT`, `PATCH` or `DELETE` as that method. |
| `LogHandler` | `iyi_web/log` | Prints one line per request. Added by default; `logging false` removes it. |
| `StaticHandler` | `iyi_web/static` | Serves the public folder. Added by default; `serve_static false` removes it. |

To write your own, subclass `Handler`, override `call`, and pass the request
on with `call_next`. A handler that does not call `call_next` ends the chain.

```iyi
import iyi_web/handler
import iyi_web/context
using iyi_web/handler::{Handler}
using iyi_web/context::{Context}

class RequireToken < Handler
  @token : String

  def initialize(@token : String)
    super()
  end

  pub def call(ctx : Context) : Nil
    if ctx.request.headers["Authorization"]? == "Bearer " + @token
      call_next(ctx)
    else
      ctx.halt(401, "Unauthorized")
    end
  end
end

token = Program.env("API_TOKEN") || raise "API_TOKEN is not set"
use "/api", RequireToken.new(token)
```

## Static files

Files under `./public` are served for `GET` and `HEAD` requests before
routing, so a file takes precedence over a route with the same path. The
content type follows the extension, a directory serves its `index.html`, and
paths containing `..` are never served. `public_folder "/srv/app/public"`
changes the folder, resolving relative paths against the working directory, and
`serve_static false` turns static files off.

## Templates

```iyi
import std/eiy
import std/html
using std/eiy::{Eiy}
using std/html::{HTML}

class ProfilePage
  getter name : String

  def initialize(@name : String)
  end

  def h(text : String) : String
    HTML.escape(text)
  end

  Eiy.def_to_s("views/profile.eiy")
end

get "/profile/:name" do |env|
  ProfilePage.new(env.params.url["name"]).to_s
end
```

`views/profile.eiy`:

```erb
<h1>Hello, <%= h(name) %></h1>
```

`std/eiy` compiles templates into the program: `<%= expr %>` prints a value
and `<% code %>` runs iyi code. A template path is relative to the file that
names it. Output is not escaped automatically; escape untrusted text with
`HTML.escape`.

## Configuration

```iyi
import iyi_web/config
using iyi_web/config

config.app_name = "storefront"
config.max_request_body_size = 1024 * 1024
```

| Setting | Default | Shorthand |
|---|---|---|
| `host` | `"0.0.0.0"` | `host "127.0.0.1"` |
| `port` | `PORT`, else `3000` | `run 8080` |
| `env` | `IYI_WEB_ENV`, else `"development"` | |
| `public_folder` | `"./public"` | `public_folder "assets"` |
| `serve_static` | `true` | `serve_static false` |
| `logging` | `true` | `logging false` |
| `powered_by_header` | `false` | `powered_by true` |
| `keepalive` | `true` | |
| `max_keepalive_requests` | `100` | |
| `max_request_body_size` | `8 * 1024 * 1024` | |
| `app_name` | `"iyi-web"` | |

- `max_keepalive_requests` caps the requests served on one connection before
  it is closed.
- A request whose body is larger than `max_request_body_size` bytes is answered
  with `400 Bad Request`, and its connection is closed.
- `app_name` and `env` appear in the line printed at startup. With `env` set
  to `test`, `run` binds the port without serving requests.
- `powered_by true` adds `X-Powered-By: iyi-web` to every response.

## Deployment

```sh
iyi build --release app.iyi -o app
IYI_WEB_ENV=production PORT=8080 ./app
```

- iyi-web speaks plain HTTP/1.1. Terminate TLS at a reverse proxy such as
  nginx, Caddy or HAProxy, and let the proxy enforce connection timeouts: the
  server does not time out idle or slow clients.
- Static files and `send_file` read whole files into memory. Serve large files
  from the proxy or a CDN.

## Testing

`iyi_web/harness` sends requests through a router in-process, without a
socket:

```iyi
# test/health_test.iyi
module test/health_test

import iyi_web/router
import iyi_web/harness
import routes/health
using iyi_web/router::{RouteHandler}
using iyi_web/harness
using routes/health

handler = RouteHandler.new(health_routes)
response = dispatch(handler, "GET", "/health").response

assert response.status_code == 200
assert response.body == "ok"
```

```sh
iyi test test
```

A test is a `*_test.iyi` program that exits non-zero on failure, and
`iyi test test` runs every one under `test/`. `http_request` and
`form_request` build requests with a query string, a body or a content type.

## Modules

| Module | Provides |
|---|---|
| `iyi_web/dsl` | Routes, filters, `error`, `mount`, `use`, `run` and the setting shorthands |
| `iyi_web/router` | `Router`, `RouteHandler` |
| `iyi_web/context` | `Context` |
| `iyi_web/request` | `Request` |
| `iyi_web/response` | `Response` |
| `iyi_web/params` | `Params` |
| `iyi_web/cookies` | `CookieJar` |
| `iyi_web/headers` | `Headers` |
| `iyi_web/body` | `IntoBody` |
| `iyi_web/handler` | `Handler`, `chain` |
| `iyi_web/config` | `Config`, `config` |
| `iyi_web/cors` | `CORSHandler` |
| `iyi_web/override` | `OverrideMethodHandler` |
| `iyi_web/static` | `StaticHandler` |
| `iyi_web/log` | `LogHandler` |
| `iyi_web/harness` | `http_request`, `form_request`, `dispatch`, `routes` |

## Development

```sh
iyi test iyi_web
iyi run examples/hello.iyi
```

## License

iyi-web is released under the [MIT License](LICENSE).
