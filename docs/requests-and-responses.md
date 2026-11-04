# Requests and responses

## Requests

`env.request` exposes `method`, `path`, `query_string`, `headers`, `body`,
`content_type`, `content_length`, `host` and `version`, plus `remote_address`,
the client's IP address as the connection saw it (nil over a unix socket, and
the proxy's address behind a reverse proxy), and `tls?`, whether the request
came over TLS to this server. Header lookups ignore case:

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

A type with `derive serializable` writes itself, so `env.json` takes it, alone
or in an `Array`, the same type `env.params.json_as` reads
([Typed JSON bodies](parameters.md#typed-json-bodies)):

```iyi
import std/json::{serializable}

struct Note
  getter id : Int32
  getter title : String
  derive serializable

  def initialize(@id : Int32, @title : String)
  end
end

get "/api/notes/:id", path: Int32 do |env, id|
  env.json(Note.new(id, "Groceries"))   # {"id":1,"title":"Groceries"}
end
```

A [typed route](typed-routes.md) says the same with `response: Note` and
returns the `Note`, which also puts its schema in the
[OpenAPI document](openapi.md).

`JSON.to_json` refuses, when the program is compiled, a `Hash` whose values
are of more than one type: `{"count" => 2, "notes" => notes}` is a
`Hash(String, Int32 | Array(Note))`, and a union has no `to_json` of its own.
Write such a document as a `derive serializable` struct with a field per key,
or with `JSON.build`.

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
`path` and `domain` the cookie was set with. To keep values between requests
without a store of your own, use a [session](sessions-and-csrf.md).

### Files

```iyi
get "/download/report" do |env|
  env.send_file("reports/latest.pdf", filename: "report.pdf")
end

get "/download/note" do |env|
  env.send_data("Generated for you\n", filename: "note.txt")
end
```

The content type follows the file extension (`std/mime`'s table) unless
`mime_type:` is given.
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

With static files' `gzip` option on (`serve_static({"gzip" => true})`), a
textual file of 860 bytes or more goes out gzip- or deflate-compressed to a
client that accepts it, as Kemal does: compressed 64 KiB at a time as it is
read, sent chunked and without a `Content-Length`, with
`Vary: Accept-Encoding`. A `Range` request gets the file uncompressed, and an
`ETag` set before the call gets the coding as a suffix.

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
