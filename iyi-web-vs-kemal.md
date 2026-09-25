# iyi-web compared with Kemal

Versions compared: iyi-web `main` (on iyi 0.14.0) and Kemal 1.14.0.
Kemal sources: `src/kemal/*.cr`. Facts about iyi were read from the installed
toolchain (`iyi` 0.14.0, `~/.local/share/iyi`).

## Summary

The routing, DSL and middleware core is largely the same. The gaps fall into
two groups:

1. Six cases where iyi-web behaved differently from Kemal, and wrongly. Each
   was reproduced.
2. Missing features. Some of them first need changes in iyi itself.

Sections 1–4 describe the state at the start; section 5 records what has been
done and what remains.

## 1. Verified defects

| Case | iyi-web | Kemal |
|---|---|---|
| Panic in a handler | The connection closes without a response, and **every other connection** open at that moment closes too | Answers 500 and leaves other requests alone (`exception_handler.cr`) |
| Client disconnects while the response is being written | `panic: cannot write to socket`; other connections close too | Only that request is affected |
| CR/LF in a header (`%0d%0a` through `env.redirect(query)`) | A forged `Set-Cookie: injected=1` header is added to the response: header injection | `HTTP::Headers` rejects the invalid character |
| `/users/:id` together with `/users/:user_id/posts` | The second route gets the parameter as `id`; `user_id` is empty | `Radix::Tree::SharedKeyError` at registration |
| The same route twice | The second silently replaces the first | `Radix::Tree::DuplicateError` at registration |
| A request for `/about/` | 404 | Matches `/about` (the radix tree tolerates a trailing `/`) |

**Causes:**
- **Panic and disconnecting client:** Every connection runs in the same
  `group`, and iyi's group rule cancels all sibling tasks on the first failure
  (`concurrency.iyi`, `child_finished`). The panicked task stays in the group's
  list and is raised again as `a task panicked` when the server stops.
- **A second panic during cancellation:** The iyi runtime also reported
  `panic: two fibers waiting on one fd`.
- **Header injection:** iyi-web's `Headers` type wrote values without checking
  them.
- **Parameter name:** The parameter name was stored on the tree node rather
  than on the route, so the first name defined won.
- **Trailing `/`:** When the path was split into segments, the empty piece
  after the trailing slash counted as a segment.

## 2. Missing features

Size: S small, M medium, L large.

| Area | Kemal has | Size | Needed on the iyi side first |
|---|---|---|---|
| Error pages | `error 500`; a detailed error page in development and a plain one in production (`show_exceptions`); `error 404 do \|env, ex\|`; `error HTTP::Status`; `error MyException`; 413 for an oversized body | M | The panic message can be read through `Panicked#text`; `error` per exception class has no direct equivalent in iyi |
| JSON parameters | `env.params.json`: `application/json` and `application/*+json`; an array under the `_json` key; 400 for malformed JSON | S | None; `JSON.parse?` is available |
| File uploads | `params.files`, `all_files` (`name[]`), `FileUpload` (path, filename, headers, size); writing to a temporary file and deleting it when the request ends; `max_file_uploads` (128), `max_multipart_form_field_size` (8 MiB), 413 | M | std has no multipart parser; `File.tempfile` exists |
| Parameter details | Several values for one key (`fetch_all`), `raw_body`, parsing on demand | S | `std/uri` Params panics on a malformed `%`, so it cannot be used directly |
| Incremental responses | `response.flush`, `headers_sent?`, `discard_unsent_body` | M | None. iyi-web writes the whole response as one String |
| SSE | `sse "/x" do \|stream, env\|`; `send(data, event:, id:, retry:)`, `comment`, `flush`, `close`; a HEAD short-circuit; CR/LF rejected in `event`/`id` | S (once responses stream) | Incremental responses |
| WebSocket | `ws` DSL and `Router#ws`; handshake (101/400/426); GET only (405); Origin check (`websocket_allowed_origins`, 403); `on_message`, `on_binary`, `on_ping`, `on_pong`, `on_close`, `send`, `ping`, `close` | L | **Two fibers cannot wait on the same socket at once** (`two fibers waiting on one fd`): a fiber writing to a socket (a broadcast) while another waits to read from it panics. The runtime needs separate read and write waits. SHA-1 and base64 are available |
| Static files | gzip (`Accept-Encoding` negotiation, `Vary`), precompressed `.gz`, 304 via ETag/Last-Modified, Range (206/416/multipart), `dir_listing`, `dir_index`, a trailing-`/` redirect for directories, a `static_headers` hook, `nosniff` and `Accept-Ranges`, the system MIME table | M | gzip compresses in one pass and cannot stream; files have no `seek` |
| `send_file` | Range, gzip, `disposition:`, RFC 6266/8187 filename encoding, `Slice` data, HEAD without reading the file | S–M | iyi-web writes the filename unescaped: a header injection risk |
| Templates | `render "v"`, `render "v", "layout"` and `content`, `content_for`/`yield_content` | S–M | Nested `Eiy.render` calls collide on the fixed name `__buf__` |
| Context | Typed storage with `env.set/get/get?` (Nil, String, Int32, Int64, Float64, Bool), `add_context_storage_type`, `env.route`, `route_found?` | S | None |
| Helpers | `redirect(url, status, body:, close:)`, `status(HTTP::Status)`, `json(data)` for any type, a `content_type:` parameter, `halt env, status_code:, response:`, `headers(env, hash)`, `gzip true` | S | None |
| Middleware | `only`/`exclude` with `only_match?`/`exclude_match?`, `use(handler, position)`, `use(path, [handlers])` | S | None |
| Filters | `before_all` also runs on 404/405; `:id` and `*` patterns in paths; several paths for one filter; error pages after before filters | S | None |
| Cookies | `HTTP::Cookie`: `Domain`, `Expires`, deletion with a past date | S | None |
| Logging | `200 GET / 1.2ms` through Crystal's `Log`; a swappable logger | S | `std/log` is available |
| Shutdown | Trapping SIGINT/SIGTERM, a shutdown message, finishing in-flight requests for up to `shutdown_timeout` (30 s) | M | **std has no signal trapping**. iyi-web has a `shutdown_message` setting that nothing uses; the `in_flight` counter is not decremented after a panic |
| Command line | `-b`, `-p`, `-s`, `--ssl-key-file`, `--ssl-cert-file`, `-h`, `extra_options` | S | `std/option_parser` exists but panics on errors |
| TLS | `config.ssl`, `bind_tls` | L | iyi's own library has no TLS, and it cannot be combined with `--crystal` mode. It needs an OpenSSL binding or a reverse proxy |
| Listening options | `reuse_port` and unix sockets through `Kemal.run do \|config\|` | M | std/socket has no SO_REUSEPORT, unix sockets or IPv6 |

Not in Kemal's core, but seen in its examples:
- **JSON models:** Reading user types from JSON (like `JSON::Serializable`) is
  not in `std/json`; it could be written with iyi's `derive`.
- **Examples:** Kemal ships with 16 examples; iyi-web has only `hello`.
- **Sessions and basic auth:** Separate libraries in Kemal too (kemal-session,
  kemal-basic-auth).
- **Route cache:** Kemal's LRU route cache is a performance feature; iyi-web
  does not need one because its route lookup is already cheap.

## 3. In iyi-web but not in Kemal

- `head` route definitions.
- A built-in `CORSHandler`.
- `env.params["x"]`, which searches every source in turn.
- The `PORT` environment variable and keep-alive settings (`keepalive`,
  `max_keepalive_requests`).
- Route return types checked at compile time (`IntoBody`). Kemal silently
  turns any return value other than a String into `""`.
- `iyi_web/harness` for testing requests without a socket.

## 4. Roadmap

1. **Security and robustness:** blocking CR/LF in headers; running each
   connection separately and answering a panic with 500; an error for a
   repeated route; different parameter names at the same position; trailing
   `/` support.
2. **Easy parity:** `params.json`, 413, helper method signatures, typed
   storage, `only`/`exclude`, the position and list forms of `use`, gzip
   middleware, filter behaviour, cookie attributes, ETag and 304 for static
   files, `render` with layouts.
3. **Structural:** incremental responses; SSE; file uploads; Range.
4. **Needed in iyi first:**
   - separate read and write waits per socket (WebSocket depends on this)
   - socket errors returned as values instead of panics
   - signal trapping
   - TLS
   - SO_REUSEPORT, unix sockets, IPv6

   Then: WebSocket, graceful shutdown, the `-s` flag.

## 5. Status

iyi-web `master`, iyi 0.15.0 (the released toolchain). `iyi test iyi_web`
passes in all 31 test files and `iyi test examples` in its one. Every example
was built, run and exercised with curl; WebSockets with Node's client.

iyi 0.14.1 lifted most of what section 4 listed as needed in iyi first:
`std/signal`, read and write timeouts, `SocketError` values instead of
panics, one reader and one writer per descriptor, IPv6, unix sockets and
`IO#seek`.

### Fixed defects

All six cases from section 1:

- **Panic in a handler:** Each connection runs in its own `group`. A request
  that panics gets the `error 500` page, or the built-in page when there is
  none; the panic message is shown only in development (`show_exceptions`).
  Only that connection closes; the others are not affected.
- **Disconnecting client:** Only that request ends. The runtime still writes
  a line to stderr for the caught panic (see Remaining).
- **Header injection:** A control character in a header name or value is
  refused with a panic. `send_file` encodes the filename per RFC 6266/8187.
- **Parameter names:** Each route reads its own names. `/users/:id` and
  `/users/:user_id/posts` work together; Kemal raises an error here.
- **The same route twice:** The program stops with an error at startup.
- **Trailing `/`:** A request for `/about/` goes to the `/about` route.

Found later and fixed:

- **Connections accepted together:** the accept loop's block captured one
  variable that every accept overwrote, so connections accepted at the same
  moment were served by one task; 40 parallel clients got 20 answers.
- **Request bodies:** the buffer grew by concatenation and was parsed again
  after every read, so a body cost the square of its size (64 MB: 19.3 s,
  now 0.24 s). `Expect: 100-continue` is answered.
- **Error pages written with a helper** (`env.json` in an `error` block) were
  sent empty.

### Closed gaps

| Area | Done |
|---|---|
| Error pages | `error 500`, `show_exceptions`, 413. An error status set by a before filter also gets its error page; a page may be written with `env.json` and the other helpers |
| JSON parameters | `env.params.json`, `_json`, 400 for malformed JSON |
| File uploads | `params.files`, `all_files`, `FileUpload`, both limits and 413. Each file is written into a directory of its own, with an unguessable name and mode 0700, and deleted after the response |
| Parameter details | `raw_body`, `query_all` / `body_all` (Kemal's `fetch_all`). JSON and multipart bodies are parsed on first use |
| Incremental responses | `flush`, `headers_sent?`, a chunked body on HTTP/1.1. A panic discards the unsent body |
| SSE | `sse`, `Router#sse`, `EventStream` (`send`, `comment`, `close`); a HEAD short-circuit; line breaks rejected in `event`/`id` |
| WebSocket | `ws`, `Router#ws`; handshake with 101, 400, 403 (`websocket_allowed_origins`), 405 and 426; `on_message`, `on_binary`, `on_ping`, `on_pong`, `on_close`, `send`, `send_binary`, `ping`, `pong`, `close`; sends from any fiber |
| Static files | gzip and deflate (`Vary`, up to 1 MiB), 304 via ETag/Last-Modified, Range (206, 416, `multipart/byteranges`), `dir_index`, `dir_listing`, a trailing-`/` redirect for directories, `static_headers`, `nosniff`, `Accept-Ranges`; files streamed from disk, HEAD without reading them |
| `send_file` | Range, `disposition:`, filename encoding, streamed from disk, HEAD without reading the file; `send_data` for bytes in memory |
| Templates | `render` (with a layout), `content_for`, `yield_content`; nested `render` works |
| Context | `set`/`get`/`get?`, `route_pattern`, `route_found?` |
| Helpers | Everything in the row; `status` takes the code as an `Int32` rather than an `HTTP::Status` |
| Middleware | `only`/`exclude`, `use(handler, position)`, `use(path, [handlers])`, `CompressHandler` |
| Filters | Everything in the row |
| Cookies | `domain`, `expires`, `delete_cookie`; values are encoded and decoded |
| Logging | `Logger` / `StdoutLogger`, `logger`, `log "message"`, `logging false` |
| Shutdown | INT and TERM drain: the listener closes, idle connections close, requests in flight finish within `shutdown_timeout` (30 s); a second signal cuts off at once; `shutdown_message` |
| Command line | `-b` (IPv4 or IPv6), `-p`, `-h`, `extra_options`. `-s` and `--ssl-*` stop the program with a message that TLS is not supported |
| Listening options | IPv6 and `unix_socket`; `read_timeout`, `write_timeout` and `idle_timeout` (not in Kemal) |
| Installation | `iyi get github.com/sdogruyol/iyi-web` writes `require github.com/sdogruyol/iyi-web v0.1.1` to `iyi.mod`, and files write `import github.com/sdogruyol/iyi-web/iyi_web/dsl::*`; with `--as web` the line ends `as web` and files write `import web/iyi_web/dsl::*` (iyi 0.15.0 and later) |
| Examples | Ten, from `hello` to a JSON API, uploads, templates, routers, middleware, SSE, a WebSocket chat room, cookies and in-process testing |

### Remaining

Possible within iyi-web:

- The `error 404 do |env, ex|` form and `error` per exception class. The panic
  text can be read with `Panicked#text`; exception classes have no direct
  equivalent in iyi.
- `send_file` with gzip. Static files are compressed up to 1 MiB only, since
  `std/compress` encodes a whole string at once.
- Headers set after a streamed file response has started (an after filter,
  `CompressHandler`) are not sent; Kemal behaves the same.
- Static files: precompressed `.gz` files, the system MIME table.
- `add_context_storage_type`. The types that can be stored are fixed
  (`StoreValue`).
- WebSocket subprotocols and `permessage-deflate` (Kemal has neither).
  WebSocket sessions are not closed with `1001` when the server drains; they
  are cut off at `shutdown_timeout`.
- A command-line flag for `unix_socket`.
- A 64 MB request body peaks at several times its size in memory: the bytes
  are copied into a string for `std/http`'s parser, which copies the body out
  again.

Needing changes in iyi first:

| Missing in iyi | iyi-web feature waiting on it |
|---|---|
| TLS | `-s`, `--ssl-key-file`, `--ssl-cert-file`, `bind_tls` |
| SO_REUSEPORT in std/socket | `reuse_port` |
| A caught panic that the runtime does not print | No `iyi: panic:` line on stderr when a client disconnects mid-response, or a write times out |
| A streaming `std/compress` | Compressing large static files and `send_file` |

Problems found in iyi and worked around in iyi-web. The first four are fixed
in iyi 0.14.1 or 0.15.0:

- `File.tempfile` derived a predictable name and wrote through a symlink
  planted there (fixed in 0.14.1). iyi-web still spools each upload into a
  randomly named directory with mode 0700.
- `std/uri` `Params.parse` panicked on a malformed `%` (fixed in 0.14.1: it
  is lenient now). iyi-web keeps its own decoder (`codec.iyi`).
- In a program that imports `std/file`, an unseeded `Random.new` did not
  compile (fixed). `token.iyi` now falls back to it where there is no
  `/dev/urandom`.
- A block referring to a top-level constant defined further down the file
  failed with `BUG: __iyi_once is not defined` (fixed).
- `std/option_parser` panics on invalid input unless `invalid_option` and
  `missing_option` handlers are set. iyi-web uses its own `CLIParser`.
- `File.exists?` answers false for a unix socket's file, because it opens the
  path for reading; `File.info?` reports it.
- A method a subclass inherits cannot call a top-level function of its
  module by its short name ("not brought into scope"); the full name works.
- An integer literal passed to an imported function taking `Int64` is not
  autocast, and the error says the function is not in scope.
- `JSON.to_json` refuses a hash whose values are a union, such as
  `{"version" => 1, "healthy" => true}`.
- A closure captures a variable rather than its value, and a `while` body is
  not a scope, so a task spawned in a loop sees the loop's last value. This
  is Crystal's rule too; it caused the accept-loop bug above.
