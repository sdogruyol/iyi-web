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
- WebSockets, with an `Origin` check and sends from any fiber
- Static files with `ETag`, `304 Not Modified`, gzip and byte ranges, streamed
  from disk
- File downloads, cookies, redirects and early responses with `halt`
- Response compression, CORS and HTML form method override
- Templates with layouts, compiled into the program
- Command-line flags for host and port
- Persistent connections, each served by its own fiber
- Graceful shutdown on `INT` and `TERM`, and timeouts for slow and idle clients
- IPv4, IPv6 and unix-socket listeners

## Requirements

[iyi](https://iyi-lang.com) 0.15.0 or later: `iyi get`, the `as` short name on
an `iyi.mod` requirement, and `import X::{...}` - one line for a module and the
names it brings into scope - arrived in 0.15.0.

## Installation

iyi-web is an iyi module. Add it to your project's `iyi.mod`:

```sh
iyi get github.com/sdogruyol/iyi-web
```

This fetches the latest release, records it in `iyi.sum` and writes one line to
`iyi.mod`:

```
require github.com/sdogruyol/iyi-web v0.1.1
```

Files then name iyi-web's modules by their full path. One `import` line loads
a module and brings its names into scope:

```iyi
import github.com/sdogruyol/iyi-web/iyi_web/dsl::*
```

### A short name

The examples in this README write the path once, in `iyi.mod`, under the short
name `web`. Pass `--as web` when adding iyi-web, or run the same command in a
project that already requires it:

```sh
iyi get github.com/sdogruyol/iyi-web --as web
```

or add ` as web` to the `require` line by hand:

```
require github.com/sdogruyol/iyi-web v0.1.1 as web
```

`web/iyi_web/...` then means `github.com/sdogruyol/iyi-web/iyi_web/...`:

```iyi
import web/iyi_web/dsl::*
import web/iyi_web/router::{Router}
```

### Versions

`iyi get -u` moves to the latest release and
`iyi get github.com/sdogruyol/iyi-web@v0.1.1` to a given one; both keep the
short name. `iyi get -u --check` says whether a newer release exists without
changing anything.

iyi reads `iyi.mod` from the directory of the file being built, so keep the
entry file, and every `*_test.iyi` that uses iyi-web, beside it. Modules of
your own can live in subdirectories.

## Quick start

Start a project, add iyi-web, and save the program at the top of this page as
`app.iyi`:

```sh
mkdir app && cd app
iyi init app
iyi get github.com/sdogruyol/iyi-web --as web
iyi run app.iyi
```

`iyi init` writes `iyi.mod` together with a starter `main.iyi`, `greet.iyi`
and `main_test.iyi`, which can be deleted.

The server listens on http://localhost:3000. Pass `-p 8080` or set `PORT` to
use another port.

The examples below extend this program. Each goes between the `import` line and
`run`, and any `import` lines it shows go at the top of the file.

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
import web/iyi_web/body::{IntoBody}

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

A name sent more than once keeps its last value in the tables.
`env.params.query_all("tag")` and `env.params.body_all("tag")` return every
value, in the order sent, and an empty array when there is none; `body_all`
covers form and multipart text fields alike. A name is matched as sent, so
`?tag[]=a&tag[]=b` is `query_all("tag[]")`:

```iyi
get "/posts" do |env|
  tags = env.params.query_all("tag")   # ?tag=iyi&tag=web => ["iyi", "web"]
  "Tagged " + tags.join(", ")
end
```

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

Each uploaded file is written to a temporary file, in a new directory only
the server's account can open: `upload.path`, `upload.filename`,
`upload.content_type`, `upload.size`, `upload.headers` and `upload.read`
describe it, and the file is deleted once the response has been
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
import std/json::{JSON}

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

get "/download/note" do |env|
  env.send_data("Generated for you\n", filename: "note.txt")
end
```

The content type follows the file extension unless `mime_type:` is given.
`filename:` marks the response as a download; `disposition: "inline"` shows
it instead. Non-ASCII names are encoded for every browser. A `Range` request
gets `206 Partial Content` or `416`. A missing file responds with `404`.
`send_data` sends bytes held in memory the same way, typed by `filename:`.

`send_file` reads the file as it sends it. A file or range larger than 64 KiB
(`FILE_CHUNK_SIZE`) goes out in 64 KiB chunks behind its exact
`Content-Length`, so a download costs 64 KiB of memory whatever its size;
headers set after `send_file` are not sent for it. A `HEAD` request is
answered from the file's size without reading it. A file cut short while it
is being sent ends the connection, so the client sees the body as incomplete.

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

### WebSockets

```iyi
import web/iyi_web/dsl::*
import web/iyi_web/websocket::{WebSocket}

class Room
  @members : Array(WebSocket)

  def initialize
    @members = [] of WebSocket
  end

  def join(socket : WebSocket) : Nil
    @members << socket
  end

  def leave(socket : WebSocket) : Nil
    @members.delete(socket)
  end

  def broadcast(text : String) : Nil
    @members.each { |member| member.send(text) }
  end
end

ROOM = Room.new

ws "/chat/:name" do |socket, env|
  name = env.params.url["name"]
  ROOM.join(socket)
  socket.on_message { |text| ROOM.broadcast(name + ": " + text) }
  socket.on_close { |code, reason| ROOM.leave(socket) }
end
```

`ws` registers a WebSocket endpoint (RFC 6455); `Router#ws` does the same on a
router. A `GET` with `Upgrade: websocket` runs the `before` filters for `GET`,
then gets `101 Switching Protocols`. The block then receives the socket and the
context and sets the callbacks, and the connection's fiber reads frames until
the socket closes. The connection carries no more HTTP requests and has no read
timeout.

- Callbacks: `on_message` (text), `on_binary` (the bytes as a `String`),
  `on_ping`, `on_pong` and `on_close(code, reason)`.
- Sending: `send(text)`, `send_binary(bytes)`, `ping`, `pong` and
  `close(code = 1000, reason = "")`. Each returns `false` once the socket is
  closed or its client has gone, and affects nothing else. Any fiber may send,
  as a broadcast from another connection does; frames never interleave.
- A ping is answered with a pong, and fragments arrive as one message. Text that
  is not UTF-8 closes the connection with `1007`, an unmasked or malformed frame
  with `1002`, a message over `websocket_max_message_size` with `1009`, and a
  callback that panics with `1011`. `on_close` gets `1006` when the client left
  without a close frame.
- Another method gets `405` unless an HTTP route serves it. A missing
  `Connection: Upgrade`, HTTP/1.0 or a bad `Sec-WebSocket-Key` gets `400`, an
  `Origin` that is not allowed `403`, and a `Sec-WebSocket-Version` other than
  13 gets `426` with `Sec-WebSocket-Version: 13`. A refused handshake closes
  the connection.
- A `GET` without `Upgrade: websocket` goes to the HTTP route on the same path,
  or gets `426 Upgrade Required` when there is none.

`Origin` is checked against `websocket_allowed_origins`. Empty, the default,
means same-origin: the `Origin` has to name the request's `Host`. A request
without `Origin`, which most clients outside a browser send, is refused unless
the list holds `"*"`. A browser connects with
`new WebSocket("ws://localhost:3000/chat/ada")`.

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
import web/iyi_web/router::{Router}

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

import web/iyi_web/router::{Router}

pub def health_routes : Router
  router = Router.new
  router.get "/health" do |env|
    "ok"
  end
  router
end
```

```iyi
import routes/health::*

mount health_routes
```

## Middleware

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
| `LogHandler` | `web/iyi_web/log` | Writes one line per request to `config.logger`. Added by default; `logging false` removes it. |
| `StaticHandler` | `web/iyi_web/static` | Serves the public folder. Added by default; `serve_static false` removes it. |

To write your own, subclass `Handler`, override `call`, and pass the request
on with `call_next`. A handler that does not call `call_next` ends the chain.
`only` and `exclude` record which paths and methods a handler is for, using
the filter path syntax; `only_match?` and `exclude_match?` answer for the
current request:

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

## Static files

Files under `./public` are served for `GET` and `HEAD` requests before
routing, so a file takes precedence over a route with the same path:

- The content type follows the extension. `ETag` and `Last-Modified` are
  sent, and a matching `If-None-Match` or `If-Modified-Since` gets
  `304 Not Modified`.
- A textual file of 860 bytes to 1 MiB is sent gzip- or deflate-compressed to
  a client that accepts it. Any other file is read from disk as it is sent,
  like `send_file`, and a `Range` request gets `206` or `416`.
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
import std/html::{HTML}

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
import web/iyi_web/config::*

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
| `logger` | `StdoutLogger.new` | `logger MyLogger.new` |
| `powered_by_header` | `false` | `powered_by true` |
| `show_exceptions?` | `true` in development | `config.show_exceptions = false` |
| `keepalive` | `true` | |
| `max_keepalive_requests` | `100` | |
| `max_request_body_size` | `8 * 1024 * 1024` | |
| `max_file_uploads` | `128` | |
| `max_multipart_form_field_size` | `8 * 1024 * 1024` | |
| `max_ranges` | `16` | |
| `shutdown_timeout` | `30` | |
| `shutdown_message` | `true` | |
| `read_timeout` | `60` | |
| `write_timeout` | `60` | |
| `idle_timeout` | `75` | |
| `unix_socket` | `nil` | |
| `websocket_allowed_origins` | `[] of String` (same-origin) | |
| `websocket_max_message_size` | `8 * 1024 * 1024` | |
| `app_name` | `"iyi-web"` | |

- `max_keepalive_requests` caps the requests served on one connection before
  it is closed.
- A request whose body is larger than `max_request_body_size` bytes gets
  `413 Content Too Large`, as soon as its `Content-Length` is read, and its
  connection is closed.
- `max_ranges` is the most ranges one `Range` header may ask for; `0` turns
  range requests off.
- `websocket_allowed_origins` lists origins such as `"https://example.com"`;
  `"*"` admits every request and `"null"` a sandboxed page.
- `websocket_max_message_size` counts a fragmented message whole.
- `app_name` and `env` appear in the line printed at startup. With `env` set
  to `test`, `run` binds the port without serving requests.
- `powered_by true` adds `X-Powered-By: iyi-web` to every response.
- `unix_socket` is a path to listen at instead of `host` and `port`, for a
  proxy on the same machine: `config.unix_socket = "/run/app.sock"`. The file
  must not exist yet; it is removed when the server stops.
- Timeouts are in seconds, and `nil` or `0` turns one off. A client has
  `read_timeout` to send a whole request, headers and body, counted from its
  first byte (from the connection, for its first request); a request cut
  short gets `408 Request Timeout` and its connection is closed, and a
  connection that sent nothing is closed. `idle_timeout` is how long a
  keep-alive connection waits for its next request. `write_timeout` is how
  long one write waits for the client to take bytes; one that runs out ends
  the connection, so a stream lasts as long as its client keeps reading.

### Logging

Each request is logged as one line, `GET /users 200 1.234ms`, after its
response has been built; a request whose handler panicked is logged with its
`500`. `log "message"` writes a line of the application's own. Both go to
`config.logger`, standard output by default, and `logging false` silences
both.

A logger is a subclass of `Logger` from `web/iyi_web/log` with
`write(message)`; override `request(ctx, elapsed)` as well to choose what a
request line holds:

```iyi
import std/time::{Span}
import web/iyi_web/log::{Logger}
import web/iyi_web/context::{Context}

class JSONLogger < Logger
  pub def request(ctx : Context, elapsed : Span) : Nil
    write(%({"method":"#{ctx.request.method}","path":"#{ctx.request.path}","status":#{ctx.response.status_code}}))
  end

  pub def write(message : String) : Nil
    STDERR.puts message
  end
end

logger JSONLogger.new
```

### Command line

`run` reads the program's arguments:

```sh
./app -b 127.0.0.1 -p 8080
./app --help
```

`-b HOST` (`--bind`) and `-p PORT` (`--port`) set the host and port;
`run 8080` still wins over `-p`. The host may be an IPv6 address, bare or
bracketed (`-b ::1`, `-b '[::1]'`); `::` takes IPv6 connections only. An
unknown flag or an invalid port stops the program with the reason and the
list of flags. `extra_options` adds your own:

```iyi
extra_options do |parser|
  parser.on("--public DIR", "Folder to serve static files from") { |dir| public_folder(dir) }
end
```

`run(args: nil)` ignores the command line.

### Stopping

`INT` (Ctrl-C) or `TERM` stops the server as `stop` does: it takes no new
connections, closes the idle ones, and lets each request in flight finish,
closing its connection after the response. `run` returns once they have, or
after `shutdown_timeout` seconds, when the rest are cut off: their fibers are
cancelled and their connections closed. A second signal cuts them off at
once. A server-sent-events stream is in flight for as long as it is open.

With `shutdown_message` on, the stop prints
`[production] storefront is going to take a rest!`. Code after `run` runs.

## Deployment

```sh
iyi build --release app.iyi -o app
IYI_WEB_ENV=production ./app -p 8080
```

- iyi-web speaks plain HTTP/1.1. Terminate TLS at a reverse proxy such as
  nginx, Caddy or HAProxy; it can reach the server over a unix socket
  (`unix_socket`). Keep `idle_timeout` above the proxy's own keep-alive
  timeout, so that the proxy is the one to close an idle connection.
- A client that disconnects while its response is being written ends that
  request only; iyi's socket layer reports it as a panic line on standard
  error.

## Testing

`web/iyi_web/harness` sends requests through a router in-process, without a
socket:

```iyi
# health_test.iyi
module health_test

import web/iyi_web/router::{RouteHandler}
import web/iyi_web/harness::*
import routes/health::*

handler = RouteHandler.new(health_routes)
response = dispatch(handler, "GET", "/health").response

assert response.status_code == 200
assert response.body == "ok"
```

```sh
iyi test
```

A test is a `*_test.iyi` program that exits non-zero on failure, and
`iyi test` runs every one in the project. A test that uses iyi-web sits beside
`iyi.mod`, like the entry file. `http_request` and `form_request` build
requests with a query string, a body or a content type. `handler_chain` from
`web/iyi_web/dsl` is the whole application as `run` serves it (logging, static
files, middleware and routes), for tests that need more than one router.

## Modules

Paths as written with the short name `web`. Without a short name, a module is
written with the whole path: `github.com/sdogruyol/iyi-web/iyi_web/dsl`.

| Module | Provides |
|---|---|
| `web/iyi_web/dsl` | Routes, filters, `error`, `mount`, `use`, `sse`, `ws`, `render`, `run` and the setting shorthands |
| `web/iyi_web/router` | `Router`, `RouteHandler` |
| `web/iyi_web/context` | `Context` |
| `web/iyi_web/request` | `Request` |
| `web/iyi_web/response` | `Response` |
| `web/iyi_web/params` | `Params` |
| `web/iyi_web/multipart` | `FileUpload` and the `multipart/form-data` parser |
| `web/iyi_web/cookies` | `CookieJar` |
| `web/iyi_web/headers` | `Headers` |
| `web/iyi_web/body` | `IntoBody` |
| `web/iyi_web/handler` | `Handler`, `chain` |
| `web/iyi_web/config` | `Config`, `config` |
| `web/iyi_web/cli` | `CLIParser` |
| `web/iyi_web/event_stream` | `EventStream` |
| `web/iyi_web/websocket` | `WebSocket`, `Frame`, `FrameError` |
| `web/iyi_web/templates` | `render`, `content_for`, `yield_content` |
| `web/iyi_web/compress` | `CompressHandler` and the `Accept-Encoding` helpers |
| `web/iyi_web/range` | `Range` header parsing and `206` responses |
| `web/iyi_web/file_body` | `respond_file`, `FILE_CHUNK_SIZE`: a file sent from disk, whole or by range |
| `web/iyi_web/cors` | `CORSHandler` |
| `web/iyi_web/override` | `OverrideMethodHandler` |
| `web/iyi_web/static` | `StaticHandler` |
| `web/iyi_web/log` | `LogHandler`, `Logger`, `StdoutLogger` |
| `web/iyi_web/harness` | `http_request`, `form_request`, `dispatch`, `routes` |

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
| `hello.iyi` | The smallest application |
| `json_api.iyi` | CRUD over an in-memory store with `env.json`, `env.params.json`, status codes and `404` via `halt` |
| `forms_and_uploads.iyi` | Form fields, multipart uploads with limits, and `_method` override |
| `templates.iyi` | Views in `examples/views/` with a layout, `content_for` and a partial |
| `routers.iyi` | `Router`, `mount`, `namespace`, router filters and error pages |
| `middleware.iyi` | A custom `Handler` with `only` and `exclude`, CORS, gzip and static files from `examples/public/` |
| `streaming_and_sse.iyi` | `flush`, chunked responses and server-sent events |
| `websocket_chat.iyi` | A chat room over `ws`, broadcasting to every member |
| `cookies_and_context.iyi` | Cookies, redirects and `env.set` / `env.get` |
| `testing.iyi` | Routes in their own module, tested in-process by `testing_test.iyi` |

Each file's opening comment lists `curl` commands to try. `iyi test examples`
runs the example test.

## Development

```sh
iyi test iyi_web
iyi run examples/hello.iyi
```

## License

iyi-web is released under the [MIT License](LICENSE).
