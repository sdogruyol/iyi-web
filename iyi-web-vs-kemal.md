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

iyi-web `main`, iyi 0.14.0. `iyi test iyi_web` passes in all 27 test files.
The README examples were built into a single program, run, and exercised with
curl.

### Fixed defects

All six cases from section 1:

- **Panic in a handler:** Each connection runs in its own `group`. A request
  that panics gets the `error 500` page, or the built-in page when there is
  none; the panic message is shown only in development (`show_exceptions`).
  Only that connection closes; the others are not affected.
- **Disconnecting client:** Only that request ends. iyi's socket layer still
  writes a panic line to stderr (see Remaining).
- **Header injection:** A control character in a header name or value is
  refused with a panic. `send_file` encodes the filename per RFC 6266/8187.
- **Parameter names:** Each route reads its own names. `/users/:id` and
  `/users/:user_id/posts` work together; Kemal raises an error here.
- **The same route twice:** The program stops with an error at startup.
- **Trailing `/`:** A request for `/about/` goes to the `/about` route.

### Closed gaps

| Area | Done |
|---|---|
| Error pages | `error 500`, `show_exceptions`, 413. An error status set by a before filter also gets its error page |
| JSON parameters | `env.params.json`, `_json`, 400 for malformed JSON |
| File uploads | `params.files`, `all_files`, `FileUpload`, both limits and 413. Each file is written into a directory of its own, with an unguessable name and mode 0700, and deleted after the response |
| Parameter details | `raw_body`. JSON and multipart bodies are parsed on first use |
| Incremental responses | `flush`, `headers_sent?`, a chunked body on HTTP/1.1. A panic discards the unsent body |
| SSE | `sse`, `Router#sse`, `EventStream` (`send`, `comment`, `close`); a HEAD short-circuit; line breaks rejected in `event`/`id` |
| Static files | gzip and deflate (`Vary`), 304 via ETag/Last-Modified, Range (206, 416, `multipart/byteranges`), `dir_index`, `dir_listing`, a trailing-`/` redirect for directories, `static_headers`, `nosniff`, `Accept-Ranges` |
| `send_file` | Range, `disposition:`, filename encoding |
| Templates | `render` (with a layout), `content_for`, `yield_content`; nested `render` works |
| Context | `set`/`get`/`get?`, `route_pattern`, `route_found?` |
| Helpers | Everything in the row; `status` takes the code as an `Int32` rather than an `HTTP::Status` |
| Middleware | `only`/`exclude`, `use(handler, position)`, `use(path, [handlers])`, `CompressHandler` |
| Filters | Everything in the row |
| Cookies | `domain`, `expires`, `delete_cookie`; values are encoded and decoded |
| Command line | `-b`, `-p`, `-h`, `extra_options`. `-s` and `--ssl-*` stop the program with a message that TLS is not supported |
| Installation | `iyi get github.com/sdogruyol/iyi-web --as web` writes `require github.com/sdogruyol/iyi-web v0.1.0 as web` to `iyi.mod`; files write `using web/iyi_web/dsl` (iyi after 0.14.1) |

### Remaining

Possible within iyi-web:

- The `error 404 do |env, ex|` form and `error` per exception class. The panic
  text can be read with `Panicked#text`; exception classes have no direct
  equivalent in iyi.
- Several values for one key (`fetch_all`). The query and form tables keep the
  last value.
- A swappable logger. `LogHandler` writes to stdout in a fixed format.
- `send_file`: gzip, sending data held in memory, answering HEAD without
  reading the file.
- Static files: precompressed `.gz` files, the system MIME table.
- `add_context_storage_type`. The types that can be stored are fixed
  (`StoreValue`).
- Examples: there is only `examples/hello.iyi`.

Needing changes in iyi first:

| Missing in iyi | iyi-web feature waiting on it |
|---|---|
| Separate read and write waits on the same fd (`two fibers waiting on one fd`) | WebSocket (`ws`) |
| Socket errors returned as values instead of panics (`panic: cannot write to socket`) | No panic on stderr when a client disconnects; noticing during a stream that the client has gone; closing WebSockets |
| Signal trapping (SIGINT, SIGTERM) | Graceful shutdown, `shutdown_message`, finishing in-flight requests |
| TLS | `-s`, `--ssl-key-file`, `--ssl-cert-file`, `bind_tls` |
| SO_REUSEPORT, unix sockets, IPv6, and read and write timeouts in std/socket | `reuse_port`, listening on a unix socket, timeouts for slow clients |
| `seek` in std/file | Sending large files and ranges without reading them into memory |

Problems found in iyi and worked around in iyi-web:

- `File.tempfile` derives a predictable name from the pid and a counter, then
  checks whether the path exists before writing to it. A symlink planted there
  beforehand in a shared temporary directory had an upload written wherever
  the attacker chose (reproduced). iyi-web now creates a randomly named
  directory with mode 0700 through `mkdir` for each upload.
- `std/uri` `Params.parse` panics on a malformed `%`. iyi-web uses its own
  decoder (`codec.iyi`).
- `std/option_parser` panics on invalid input. iyi-web uses its own
  `CLIParser`.
- In a program that imports `std/file`, an unseeded `Random.new` does not
  compile (`undefined method 'open' for Std::File:Module`). iyi-web supplies
  the seed itself (`token.iyi`).
- Compiler: a block that refers to a top-level constant defined further down
  the file fails with `BUG: __iyi_once is not defined` (for example, an
  `extra_options` block that uses an array defined below it). Moving the
  constant above the block is enough.
