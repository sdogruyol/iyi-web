# Changelog

All notable changes to iyi-web are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- WebSockets: `ws "/path" do |socket, env|` and `Router#ws`, matched like
  routes with `:name` and `*name`. The handshake runs the `GET` before
  filters and answers `101`, or `405`, `400`, `403` (`Origin`) or `426`
  (`Sec-WebSocket-Version: 13`) and closes the connection. A plain `GET` on a
  path only `ws` serves gets `426 Upgrade Required`.
- `WebSocket`: `on_message`, `on_binary`, `on_ping`, `on_pong`,
  `on_close(code, reason)`, `send`, `send_binary`, `ping`, `pong`,
  `close(code, reason)` and `closed?`. Pings are answered, fragments put
  back together, text checked for UTF-8. Protocol violations close with
  `1002`, `1007` or `1009`, and a panicking callback with `1011`. Any fiber
  may send, frames never interleave, and a send to a closed socket returns
  `false`. `websocket_allowed_origins` (same-origin by default, `"*"` for
  any) and `websocket_max_message_size` (8 MiB) configure it, and
  `Response#upgrade` hands the connection to a block once a `101` is out.
- Graceful shutdown: `INT` or `TERM` stops `run` taking connections, closes
  the idle ones and lets the requests in flight finish, each connection
  closing after its response; `run` returns when they have, or after
  `shutdown_timeout` seconds (default 30), when the rest are cut off. A
  second signal cuts them off at once. `Server#shutdown(timeout)` does the
  same without a signal. `shutdown_message` prints
  `[env] app_name is going to take a rest!` when a stop begins.
- `read_timeout` (60 s), `write_timeout` (60 s) and `idle_timeout` (75 s): a
  request that does not arrive whole in `read_timeout` gets
  `408 Request Timeout`, however slowly it trickles; a keep-alive connection
  idle for `idle_timeout` is closed; a write the client does not take for
  `write_timeout` ends the connection. `nil` or `0` turns one off.
- `-b` and `host` take IPv6 addresses, bare or bracketed, and the startup
  line brackets them. `unix_socket` (and `Server#bind_unix`) listens on a
  unix socket instead; the socket file is removed when the server stops.
- `send_data` sends bytes held in memory as a download, with the same
  `filename:`, `disposition:`, `mime_type:` and byte ranges as `send_file`
  (Kemal's `send_file` with a `Slice`).
- `env.params.query_all(name)` and `env.params.body_all(name)`: every value
  of a repeated query or form name, in the order sent (multipart text fields
  included; `tag[]` is matched as written). The `query` and `body` tables
  still keep the last value.
- A swappable logger: `Logger` (`write(message)`, and optionally
  `request(ctx, elapsed)`) and the default `StdoutLogger` in `iyi_web/log`,
  set with `config.logger =` or `logger MyLogger.new`. `log "message"`
  writes an application line through it.
- A request with `Expect: 100-continue` gets `100 Continue` once its head is
  accepted. curl held back every body over a megabyte for a second waiting
  for it.
- Examples for a JSON API, forms and file uploads, templates, routers,
  middleware, streaming and server-sent events, a WebSocket chat room,
  cookies and the request store, and in-process testing, listed in the
  README's new Examples section.
- CI on GitHub Actions: the tests, the examples' test and a build of every
  example, on the released iyi 0.15.0.

### Changed

- The README installs iyi-web with `iyi get github.com/sdogruyol/iyi-web`,
  released in iyi 0.15.0, and imports it by its full path; `--as web` is the
  short name the README's examples use.
- `send_file` and static files read files from disk as they send them,
  rather than loading them whole. A file or range larger than 64 KiB is
  streamed in 64 KiB chunks behind an exact `Content-Length`, so serving a
  200 MB file peaks at about 7.5 MB instead of about 1 GB. A HEAD is
  answered from the file's size without reading it. Headers set after such
  a response has started (an after filter, `CompressHandler`) are not sent.
- Static files are compressed only up to 1 MiB (`COMPRESS_MAX_SIZE`);
  larger files are sent uncompressed, streamed, and without
  `Vary: Accept-Encoding`.
- Byte ranges use 64-bit positions (`parse_ranges`, `content_range` and
  `unsatisfied_range` take `Int64`), so files larger than 2 GiB can be served
  and ranged.
- `send_file` answers `404` for paths that are not regular readable files
  (FIFOs, devices), as it did for missing paths and directories.
- Request lines, including the `500` line for a request whose handler
  panicked, go through `config.logger` instead of straight to stdout; the
  default format is unchanged. `logging false` silences them and `log`.
- `stop` no longer leaves `run` waiting on idle keep-alive connections, and
  `INT` and `TERM` no longer end the process mid-response: code after `run`
  runs.

### Fixed

- Connections accepted at the same moment were served by one task: the
  accept loop's block captured a variable every accept overwrote. 40
  parallel clients got 20 answers, and the rest `two fibers reading one fd`
  panics; `wrk` with 100 connections logged one such panic per connection.
- Request bodies are read in linear time. The buffer grew by concatenation
  and was parsed again after every read: an 8 MB body took 0.41 s of the
  server's time and 64 MB 19.3 s; now 0.07 s and 0.24 s. A chunked body is
  decoded as it arrives.
- An error block that wrote its page with `env.text`, `env.json` or
  `env.html` sent an empty body, and so did the `error 500` page after a
  panic.
- A file cut short while it is being sent ends the connection, instead of
  sending fewer bytes than its `Content-Length`.

### Security

- Two `Content-Length` headers that differ, or more than one
  `Transfer-Encoding`, are refused with `400` rather than read one way by
  iyi-web and another by a proxy. A chunked body over
  `max_request_body_size` gets `413` as soon as its chunks pass it.
- Where there is no `/dev/urandom` (Windows), multipart boundaries and upload
  directory names come from `Random.new`, which reads `RtlGenRandom`, rather
  than from the clocks.

## [0.1.1] - 2026-09-25

Requires iyi 0.15.0 or later. The exported surface is v0.1.0's, line for
line (`iyi mod release` compared them).

### Changed

- Written in iyi 0.15.0's one keyword: `import X::{a}` and `import X::*`
  where `import X` + `using X` were, produced by `iyi fix .`. iyi 0.15.0
  refuses `using`, so v0.1.0 does not build on it.
- iyi-web is installed as an `iyi.mod` requirement instead of copying
  `iyi_web/` into `lib/`: `iyi get github.com/sdogruyol/iyi-web --as web`, then
  `import web/iyi_web/dsl::*`. The README's examples name modules this way.

## [0.1.0] - 2026-09-24

The first release. Requires iyi 0.14.1 or later.

### Added

- HTTP/1.1 server on iyi's parking sockets: persistent connections, each
  served by its own task, with `max_keepalive_requests` capping the requests
  on one connection.
- Connection isolation: a route that panics gets a `500` page, and neither it
  nor a client that disconnects mid-response closes other connections.
- Routes for `GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `OPTIONS`, `HEAD` and
  `QUERY`, with named and wildcard segments, matched with or without a
  trailing slash. Parameter names are kept per route; duplicate routes are
  rejected.
- Route return values through `IntoBody`, checked when the program compiles.
- URL, query-string, form, JSON (`params.json`) and `multipart/form-data`
  parameters. Uploads are spooled into private temporary directories and
  limited by `max_file_uploads` and `max_multipart_form_field_size`.
- `before_*` and `after_*` filters for every route, a path pattern or a single
  method; `before_all` also runs on `404` and `405`.
- Error pages per status code, automatic `404` and `405` responses.
- Composable routers with `mount` and `namespace`.
- Middleware with `Handler`, `use` for every request or a path prefix,
  placement by index, and `only` / `exclude` path matching.
- Built-in handlers: `LogHandler`, `StaticHandler`, `CompressHandler` (gzip and
  deflate, `gzip true`), `CORSHandler` and `OverrideMethodHandler`.
- Static files with `ETag`, `Last-Modified`, `304 Not Modified`, gzip or
  deflate compression, byte ranges and optional directory listings.
- Responses: redirects, `halt`, `send_file` with byte ranges and encoded file
  names, cookies with `domain`, `expires` and `delete_cookie`, and a typed
  context store.
- Streaming responses with `flush` and chunked encoding, and server-sent events
  with `sse` and `EventStream`.
- Compiled templates with layouts, `render` and `content_for`.
- `config` with the settings and DSL shorthands listed in the README;
  `-b`, `-p` and `-h` / `--help` on the command line, and `extra_options` for
  more.
- `iyi_web/harness` for in-process tests of routers and the whole handler
  chain.

### Security

- Header fields with control characters are rejected with `400`.
- A body over `max_request_body_size` is answered `413` as soon as its
  `Content-Length` is read, before the body is buffered.
- Static file paths with a `..` segment or a NUL byte are refused.

[Unreleased]: https://github.com/sdogruyol/iyi-web/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/sdogruyol/iyi-web/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/sdogruyol/iyi-web/releases/tag/v0.1.0
