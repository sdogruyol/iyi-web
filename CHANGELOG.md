# Changelog

All notable changes to iyi-web are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- iyi-web is installed as an `iyi.mod` requirement instead of copying
  `iyi_web/` into `lib/`: `iyi get github.com/sdogruyol/iyi-web --as web`, then
  `using web/iyi_web/dsl`. The README's examples name modules this way, with one
  `using` line and no `import`. Requires iyi newer than 0.14.1.

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

[Unreleased]: https://github.com/sdogruyol/iyi-web/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/sdogruyol/iyi-web/releases/tag/v0.1.0
