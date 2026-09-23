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
- URL, query-string, form, JSON and `multipart/form-data` parameters, with
  file uploads
- Before and after filters for every route, a path pattern or a single method
- Error pages per status code, automatic `404` and `405` responses, and a
  `500` page for a route that panics
- Composable routers with `mount` and `namespace`
- Middleware for every request or for a path prefix
- Streaming responses and server-sent events
- Static files with `ETag`, `304 Not Modified`, gzip and byte ranges
- File downloads, cookies, redirects and early responses with `halt`
- Response compression, CORS and HTML form method override
- Templates with layouts, compiled into the program
- Command-line flags for host and port
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

The server listens on http://localhost:3000. Pass `-p 8080` or set `PORT` to
use another port.

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
- A trailing slash does not matter: `/articles/` is `/articles`.
- Two routes may name the same segment differently: `/users/:id` and
  `/users/:user_id/posts` each read their own name.
- Defining the same method and path twice stops the program at startup.

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
| `application/x-www-form-urlencoded` or `multipart/form-data` fields | `env.params.body` |
| `application/json` and `application/*+json` bodies | `env.params.json` |
| Uploaded files | `env.params.files`, `env.params.all_files` |

`url`, `query` and `body` are `Hash(String, String)` tables of percent-decoded
values; `env.params["name"]?` searches them in that order. Indexing without
`?` panics when the key is missing, so use `[]?` for optional values.
`env.params.raw_body` is the body as it arrived.

A JSON object's members are in `env.params.json`, a `Hash(String, JSON::Any)`;
a top-level array is under the key `"_json"`. A request that declares JSON
and sends something that does not parse gets `400 Bad Request` before the
route runs.

### File uploads

```iyi
post "/avatar" do |env|
  if upload = env.params.files["avatar"]?
    env.text("Received " + upload.filename + ", " + upload.size.to_s + " bytes")
  else
    env.halt(422, "No file")
  end
end
```

Each uploaded file is written to its own temporary file: `upload.path`,
`upload.filename`, `upload.content_type`, `upload.size`, `upload.headers` and
`upload.read` describe it, and the file is deleted once the response has been
sent. Files sent under a name ending in `[]` are all kept, in
`env.params.all_files["photos[]"]`. The filename is the client's, unchanged:
never join it to a directory path without cleaning it first.

A malformed `multipart/form-data` body gets `400`. More file parts than
`max_file_uploads`, or a text field larger than
`max_multipart_form_field_size`, gets `413 Content Too Large`.

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
a header instead of replacing it, and `headers env, {"X-A" => "1"}` sets
several at once. A header name or value containing a line break or another
control character is refused with a panic, so a value built from user input
cannot forge a second header.

These helpers set the content type and the body in one call; each also takes
a `content_type:` argument:

| Helper | Content-Type |
|---|---|
| `env.text(body)` | `text/plain; charset=utf-8` |
| `env.html(body)` | `text/html; charset=utf-8` |
| `env.json(body)` | `application/json; charset=utf-8` |
| `env.xml(body)` | `application/xml; charset=utf-8` |

`env.json` sends a `String` as it is and serialises anything else, such as a
`Hash`, an `Array` or a type that implements `ToJSON`. `env.status(code)` sets
the status and returns `env`, so the two combine:

```iyi
post "/api/items" do |env|
  env.status(201).json({"created" => true})
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
  env.json(env.params.json)
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
  halt env, status_code: 403, response: "Forbidden"
end
```

`redirect` responds with `302` unless given a status; `body:` adds a body and
`close: false` keeps the chain running. `env.halt(403, "Forbidden")` and
`halt env, status_code: 403, response: "Forbidden"` are the same. After a
redirect or a halt, the rest of the chain is skipped: remaining filters and
the route do not run, the route's return value is discarded, and error pages
are not applied.

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

post "/sign-out" do |env|
  env.delete_cookie("session")
  env.redirect("/")
end
```

`set_cookie` also takes `path` (default `/`), `domain` and `expires` (a
`Time`); with neither `max_age` nor `expires` it makes a session cookie.
Values are percent-encoded where cookies do not allow a character and
decoded when read, so any string round-trips. `delete_cookie` needs the same
`path` and `domain` the cookie was set with.

### Files

```iyi
get "/download/report" do |env|
  env.send_file("reports/latest.pdf", filename: "report.pdf")
end
```

The content type follows the file extension unless `mime_type:` is given.
`filename:` marks the response as a download; `disposition: "inline"` shows
it instead. Non-ASCII names are encoded for every browser. A `Range` request
gets `206 Partial Content` or `416`. A missing file responds with `404`. The
file is read into memory in full.

### Streaming

`env.response.flush` sends what the route has written so far and keeps the
response open; on HTTP/1.1 the body is sent chunked.

```iyi
get "/export.csv" do |env|
  env.response.content_type = "text/csv; charset=utf-8"
  env.response.print("id,total\n")
  env.response.flush
  (1..3).each { |id| env.response.print(id.to_s + "," + (id * 10).to_s + "\n") }
  nil
end
```

Headers changed after the first `flush` are not sent.

### Server-sent events

```iyi
sse "/clock" do |stream, env|
  3.times do |tick|
    stream.send("tick " + tick.to_s, event: "tick", id: tick)
    sleep(1000)
  end
end
```

`sse` registers a `GET` route answering `text/event-stream`. `send` takes
`event:`, `id:` and `retry:` (a `Span`), splits multi-line data into `data:`
lines and flushes; `comment` sends a keep-alive line clients ignore. An event
name or id containing a line break panics. The stream ends when the block
returns. A browser reads it with `new EventSource("/clock")`.

## Filters

```iyi
before_all do |env|
  env.response.headers["X-Content-Type-Options"] = "nosniff"
end

before_all "/admin/*" do |env|
  env.halt(401, "Unauthorized") unless env.cookies.has_key?("session")
end

after_get ["/api/*", "/reports/*"] do |env|
  env.response.headers["Cache-Control"] = "no-store"
end
```

- `before_all` and `after_all` run for every method. `before_get`,
  `after_post` and their siblings run for one method: `get`, `post`, `put`,
  `patch`, `delete`, `options` or `query`.
- The path defaults to `*`, every path. `/admin/*` matches `/admin` and every
  path under it; `/users/:id` matches one segment in place of `:id`; any other
  path matches exactly. A list registers the same block for each path.
- Filters run in declaration order. `before_all` filters also run for a
  request no route matched, before its `404` or `405`; the others run only
  for a matched route.
- A before filter that calls `halt` or `redirect` stops the request before the
  route runs. One that sets an error status with an error page gets that page
  instead of the route.
- A filter's return value is discarded, but like a route's it must implement
  `IntoBody`.

Filters, middleware and routes pass values along a request with `env.set`,
`env.get` and `env.get?`, which hold a `String`, `Int32`, `Int64`, `Float64`,
`Bool` or `nil`. `env["key"]` reads and writes strings only:

```iyi
before_all "/account/*" do |env|
  env.set("user_id", 42)
end

get "/account/orders" do |env|
  "Orders for user " + env.get("user_id").to_s
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

error 500 do |env|
  "<h1>Something went wrong</h1>"
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

A route that panics gets `500 Internal Server Error` and its connection is
closed; other connections are not affected, and the panic is logged. The
`error 500` page is used when there is one. Otherwise the built-in page shows
the panic message in development and hides it in every other environment;
`config.show_exceptions = true` or `false` overrides that.

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

This serves `/admin` and `/admin/reports/daily`. A `Router` has the same
route, `sse`, filter (`before`, `after`, `before_get`, …) and `error`
methods as the program. `mount` without a path mounts a router at the root,
and `namespace` passes the nested router to its block.

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
| `CompressHandler` | `iyi_web/compress` | Compresses textual responses of 860 bytes or more with gzip or deflate when `Accept-Encoding` allows it. `gzip true` adds it. |
| `CORSHandler` | `iyi_web/cors` | Sets `Access-Control-Allow-Origin` and answers preflight requests with `204`. Takes `origin` (default `*`), `methods`, `headers` (default `*`) and `max_age` (seconds as a string, default `"86400"`). |
| `OverrideMethodHandler` | `iyi_web/override` | Treats a form `POST` with `_method` set to `PUT`, `PATCH` or `DELETE` as that method. |
| `LogHandler` | `iyi_web/log` | Prints one line per request. Added by default; `logging false` removes it. |
| `StaticHandler` | `iyi_web/static` | Serves the public folder. Added by default; `serve_static false` removes it. |

To write your own, subclass `Handler`, override `call`, and pass the request
on with `call_next`. A handler that does not call `call_next` ends the chain.
`only` and `exclude` record which paths and methods a handler is for, using
the filter path syntax; `only_match?` and `exclude_match?` answer for the
current request:

```iyi
import iyi_web/handler
import iyi_web/context
using iyi_web/handler::{Handler}
using iyi_web/context::{Context}

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

## Static files

Files under `./public` are served for `GET` and `HEAD` requests before
routing, so a file takes precedence over a route with the same path:

- The content type follows the extension. `ETag` and `Last-Modified` are
  sent, and a matching `If-None-Match` or `If-Modified-Since` gets
  `304 Not Modified`.
- A textual file of 860 bytes or more is sent gzip- or deflate-compressed to
  a client that accepts it, and a `Range` request gets `206` or `416`.
- A directory serves its `index.html`, after redirecting to the path with a
  trailing slash. Paths containing `..` are never served.

`public_folder "/srv/app/public"` changes the folder, resolving relative
paths against the working directory, and `serve_static false` turns static
files off. `serve_static({"gzip" => true, "dir_listing" => true})` sets the
options; a key left out counts as false, and `dir_index` controls the
`index.html` lookup. `static_headers` runs for every served file:

```iyi
static_headers do |env, path, info|
  env.response.headers["Cache-Control"] = "public, max-age=3600"
end
```

## Templates

```iyi
import std/html
using std/html::{HTML}

get "/profile/:name" do |env|
  name = HTML.escape(env.params.url["name"])
  render "views/profile.eiy", "views/layout.eiy"
end
```

`views/profile.eiy`:

```erb
<% content_for "title" do %>Profile of <%= name %><% end -%>
<h1>Hello, <%= name %></h1>
```

`views/layout.eiy`:

```erb
<!DOCTYPE html>
<html>
<head><title><%= yield_content "title" %></title></head>
<body><%= content %></body>
</html>
```

Templates use iyi's `.eiy` format: `<%= expr %>` prints a value and
`<% code %>` runs iyi code. They are compiled into the program, and see the
local variables where `render` is written.

- `render "view.eiy"` returns the rendered text. `render "view.eiy",
  "layout.eiy"` renders the view, then the layout with the view as `content`.
- `content_for "key" do ... end` captures markup in the view, and
  `yield_content "key"` prints it in the layout; a key never captured prints
  nothing.
- A template path is relative to the file that calls `render`, or, for a
  template rendered inside another template, to that template.
- Output is not escaped automatically; escape untrusted text with
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
| `host` | `"0.0.0.0"` | `host "127.0.0.1"`, `-b 127.0.0.1` |
| `port` | `PORT`, else `3000` | `run 8080`, `-p 8080` |
| `env` | `IYI_WEB_ENV`, else `"development"` | |
| `public_folder` | `"./public"` | `public_folder "assets"` |
| `serve_static` | `true` | `serve_static false` |
| `logging` | `true` | `logging false` |
| `powered_by_header` | `false` | `powered_by true` |
| `show_exceptions?` | `true` in development | `config.show_exceptions = false` |
| `keepalive` | `true` | |
| `max_keepalive_requests` | `100` | |
| `max_request_body_size` | `8 * 1024 * 1024` | |
| `max_file_uploads` | `128` | |
| `max_multipart_form_field_size` | `8 * 1024 * 1024` | |
| `max_ranges` | `16` | |
| `app_name` | `"iyi-web"` | |

- `max_keepalive_requests` caps the requests served on one connection before
  it is closed.
- A request whose body is larger than `max_request_body_size` bytes gets
  `413 Content Too Large`, as soon as its `Content-Length` is read, and its
  connection is closed.
- `max_ranges` is the most ranges one `Range` header may ask for; `0` turns
  range requests off.
- `app_name` and `env` appear in the line printed at startup. With `env` set
  to `test`, `run` binds the port without serving requests.
- `powered_by true` adds `X-Powered-By: iyi-web` to every response.

### Command line

`run` reads the program's arguments:

```sh
./app -b 127.0.0.1 -p 8080
./app --help
```

`-b HOST` (`--bind`) and `-p PORT` (`--port`) set the host and port;
`run 8080` still wins over `-p`. An unknown flag or an invalid port stops the
program with the reason and the list of flags. `extra_options` adds your own:

```iyi
extra_options do |parser|
  parser.on("--public DIR", "Folder to serve static files from") { |dir| public_folder(dir) }
end
```

`run(args: nil)` ignores the command line.

## Deployment

```sh
iyi build --release app.iyi -o app
IYI_WEB_ENV=production ./app -p 8080
```

- iyi-web speaks plain HTTP/1.1. Terminate TLS at a reverse proxy such as
  nginx, Caddy or HAProxy, and let the proxy enforce connection timeouts: the
  server does not time out idle or slow clients.
- Static files and `send_file` read whole files into memory. Serve large files
  from the proxy or a CDN.
- A client that disconnects while its response is being written ends that
  request only; iyi's socket layer reports it as a panic line on standard
  error.

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
`handler_chain` from `iyi_web/dsl` is the whole application as `run` serves
it (logging, static files, middleware and routes), for tests that need more
than one router.

## Modules

| Module | Provides |
|---|---|
| `iyi_web/dsl` | Routes, filters, `error`, `mount`, `use`, `sse`, `render`, `run` and the setting shorthands |
| `iyi_web/router` | `Router`, `RouteHandler` |
| `iyi_web/context` | `Context` |
| `iyi_web/request` | `Request` |
| `iyi_web/response` | `Response` |
| `iyi_web/params` | `Params` |
| `iyi_web/multipart` | `FileUpload` and the `multipart/form-data` parser |
| `iyi_web/cookies` | `CookieJar` |
| `iyi_web/headers` | `Headers` |
| `iyi_web/body` | `IntoBody` |
| `iyi_web/handler` | `Handler`, `chain` |
| `iyi_web/config` | `Config`, `config` |
| `iyi_web/cli` | `CLIParser` |
| `iyi_web/event_stream` | `EventStream` |
| `iyi_web/templates` | `render`, `content_for`, `yield_content` |
| `iyi_web/compress` | `CompressHandler` and the `Accept-Encoding` helpers |
| `iyi_web/range` | `Range` header parsing and `206` responses |
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
