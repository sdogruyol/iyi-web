# Changelog

All notable changes to iyi-web are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Requires iyi 0.21.0 or later. iyi 0.21.0 made `spawn` one verb (SPEC.md
III.4.16/18) and removed `spawn_parallel`, and it refuses raw memory in a
module that is not marked `@[Unsafe("why")]` (SPEC.md III.13); 0.20.x
refuses both new spellings, so no source of this library compiles on both.

### Changed

- A connection on the pool, and a background job, is started with
  `spawn(unit: :new)`, 0.21.0's spelling of `spawn_parallel`; nothing
  else about either changed.
- A server with `workers 1` starts each connection with
  `spawn(unit: :same)`. On 0.21.0 a plain `spawn` is placed by the
  compiler and runs on the pool where it can prove that safe, so the
  promise that `workers 1` serves on the accepting thread is now said
  at the spawn rather than left to what its block happens to capture.
- The eighteen modules that read or write a string's bytes through its
  buffer (`auth`, `basic_auth`, `codec`, `context`, `cookies`, `csrf`,
  `headers`, `http_date`, `metrics`, `multipart`, `range`, `request_id`,
  `server`, `token`, `tracing`, `validation`, `websocket` and the
  template generator `templates/process`) are marked `@[Unsafe("why")]`
  above their `module` header, each saying what it does with the raw
  memory.
- `coerce` reads a parameter's first and last byte with `byte_at`, and
  `jwt` makes its HMAC's string with `String.new(Array(UInt8))`, so
  neither handles raw memory and both stay checked. `websocket_test` and
  `jwt_test` do the same.

## [0.6.0] - 2026-11-06

Requires iyi 0.20.1 or later.

The release that turns the roadmap (`ROADMAP.md`) into code. A route can
name the types it reads and answers, and the framework reads, validates
and documents them: typed routes, an OpenAPI 3.1 document with Swagger UI,
dependencies and auth providers with HS256 JWTs. Every connection is
served through std/http, which brings HTTP/2, TLS 1.2 beside 1.3, mutual
TLS, Let's Encrypt and streamed request bodies. Templates escape by
default. Around the framework: an `iyi-web` command that scaffolds a
project and rebuilds it on save, shared-state stores, background tasks,
Prometheus metrics, OpenTelemetry tracing, a PostgreSQL example, a docs
site with a tutorial, and a benchmark against FastAPI, Express, Kemal and
Go. `get "/" do |env| ... end` works exactly as before; everything new is
opt-in.

### Upgrading from 0.5

- **Templates escape `<%= %>`.** Drop `HTML.escape(...)` inside `<%= %>`
  (it would escape twice), and wrap every `<%= %>` that prints markup on
  purpose in `raw(...)`: HTML the program built, `csrf_tag(env)`, or a
  page a helper rendered in iyi code. A layout's `content` and
  `yield_content` are `SafeHTML` now; String methods on them need `.to_s`
  first. See `docs/templates.md`.
- **`std/eiy` is no longer re-exported** by `iyi_web/templates` or
  `iyi_web/dsl`: a program that names `Eiy` imports `std/eiy` itself.
- **Request bodies stop at 64 MiB.** std/http refuses anything larger,
  whatever `max_request_body_size` says (the default stays 8 MiB).
- **Only code that touched the transport** needs changes beyond these:
  `Response#attach(sink, head)` replaces the four-argument form,
  `Response#reusable?` and `iyi_web/intake` are gone, and
  `params.raw_body` is empty for multipart requests (the files are in
  `params.files`).

### Added

**Typed routes**

- `path:`, `query:`, `headers:` and `body:` on every route method, in
  the DSL and on `Router`. The block gets each value after `env`, typed;
  what cannot be read is answered before the block runs, with a
  `ParamError` (422) naming every wrong parameter or the body's
  `BodyError` (400, 415, 422). Parameter structs use
  `derive serializable`: defaults and nilable fields are optional, enums
  take their names, `Array(T)` takes a repeated query key, `JSON::Field`
  keys rename, and `Validate` runs once they are read. `path: Int32`
  reads a route's one capture (`iyi_web/typed`).
- `response: T` writes the block's answer as JSON and checks its type
  when the program compiles; `status:` sets the status a route answers
  with, on plain routes too.
- One parameter at a time: `env.params.int("id")`, `int64`, `float`,
  `bool` and `string` answer the value or a `ParamError`, with
  `from: :url | :query | :body` and `default:`. Reading is strict:
  `"12abc"`, `" 12"` and `""` are not integers, `nan` and `inf` are not
  numbers (`iyi_web/coerce`).
- `Params#query_pairs`, and `json_errors` and `enum_name` in
  `iyi_web/validation`.

**OpenAPI**

- `openapi(title, version)` (and `Router#openapi`) serves
  `/openapi.json`, an OpenAPI 3.1 document of every route, mount and
  namespace, and `/docs`, Swagger UI. Schemas are derived from the types
  at compile time: `required`, nested structs as `components.schemas`,
  arrays, enums, nullable fields, `JSON::Field` keys and ignores. Routes
  take `summary:`, `description:` and `tags:`, and list the 4xx answers
  the framework gives for them (`iyi_web/openapi`).

**Dependencies and auth**

- `Dep.new(User) { |env| ... }`: a provider of the type it names, whose
  error ends the request with its status before the route runs. A route
  takes one with `deps:`; providers compose with `resolve(env)!`, run
  once per request, and combine with `Dep.all(user: A, db: B)` into a
  named tuple (`iyi_web/deps`).
- `bearer_auth`, `api_key_auth` (header, query or cookie), `jwt_auth` and
  `oauth2_password_bearer`, with `password_grant`, `token_response`,
  `AuthError` and `OAuthError`. Each provider's scheme appears under
  `components.securitySchemes` and on its routes (`iyi_web/auth`).
- `JWT.sign` and `JWT.verify` for HS256: `alg` must be `HS256`,
  signatures are compared in constant time, `exp`, `nbf` and `iat` are
  checked with `leeway:`, `issuer:` and `audience:` are optional, and
  secrets under 32 bytes are refused (`iyi_web/jwt`).

**Transport** (`docs/transport.md`)

- HTTP/2: h2c with prior knowledge beside HTTP/1.1 on the same port, and
  h2 over TLS by ALPN. A TLS config that names no protocol, and `-s`,
  offer `["h2", "http/1.1"]`.
- TLS 1.2 beside 1.3 (`config.ssl.min_version`, `--ssl-min-version 1.2`)
  and mutual TLS (`config.ssl.client_roots`, `--ssl-client-ca FILE`),
  with the client's chain in `env.request.peer_certificates`. std/tls
  requires the extended master secret on 1.2, so LibreSSL's 1.2 clients
  are refused.
- `config.autocert`: certificates from Let's Encrypt through std/autocert,
  `tls-alpn-01` answered on the TLS port and renewals run beside the
  accept loop (`LETS_ENCRYPT`, `LETS_ENCRYPT_STAGING`).
- `config.stream_bodies`: a route reads the body as it arrives with
  `env.request.body_io`; `env.request.body_failure` says why a read
  failed.
- `config.compress`: zstd or gzip, negotiated per client.
- `multipart/form-data` uploads stream to disk as they arrive, so an
  upload costs a read's worth of memory rather than its size;
  `params.body_error` reports a body that could not be read (413, 408,
  400).

**Running an application**

- `on_start do ... end` and `on_stop do ... end` (FastAPI's `lifespan`).
  Start hooks run in order before the server binds; one that answers an
  `Error` or panics stops the start, and the program exits 1 naming the
  hook's file and line. Stop hooks run after the drain and the background
  tasks, last written first (`iyi_web/lifecycle`).
- Background tasks: `env.background { }` in a route and `background { }`
  anywhere run work off the request path on a free worker. A panic is
  caught, reported and counted; it never reaches the server. On stop,
  queued and running tasks get up to `shutdown_timeout`
  (`iyi_web/background`).
- Shared state without the `Mutex` showing: `HashStore(K, V)`,
  `ArrayStore(E)` and `Store(T)`, with `read`/`update` blocks under the
  lock and copies out (`values`, `keys`, `to_h`, `to_a`, `[]?`, `size`).
  They are `Share`, so routes on every core capture them
  (`iyi_web/store`).
- Prometheus metrics: `MetricsHandler` serves `/metrics` with
  `http_requests_total{method,route,status}`,
  `http_request_duration_seconds` and `http_requests_in_flight`, labelled
  by route pattern, never by raw path; `METRICS` makes counters, gauges
  and histograms of an application's own (`iyi_web/metrics`).
- OpenTelemetry tracing: `TraceHandler` records a span per request, the
  child of an incoming W3C `traceparent`, named by route and carrying
  OpenTelemetry's HTTP attributes; `current_span(env)` adds the route's
  own. Spans are batched to `OtlpHttpExporter` (OTLP/HTTP JSON) or
  `JsonLinesExporter`, and flushed on stop (`iyi_web/tracing`).

**Templates**

- `raw(value)`, `SafeHTML` and `HTMLBuffer` (`iyi_web/templates`):
  markup printed without escaping, and the buffer that escapes the rest.

**Tooling**

- The `iyi-web` command (`cmd/`; `iyi build --release cmd/iyi_web.iyi -o
  bin/iyi-web`):
  - `iyi-web new DIR [--api | --full]` writes a project that builds and
    passes its own test: `--api` a validated JSON API of typed routes
    over a `HashStore`, `--full` views in a layout and `public/`.
    `--web-path PATH` builds against a local checkout.
  - `iyi-web dev` builds and runs the app, rebuilds on save and restarts
    it on success; a failed build prints the compiler's error and keeps
    the previous build serving.
- `bench/compare/`: the same four endpoints (plain text, JSON, a
  parameter route and a pooled PostgreSQL query) in iyi-web, FastAPI,
  Express, Kemal and Go `net/http`, with a runner that checks every
  endpoint before timing it and writes `results.json` and `results.md`.

**Examples and docs**

- `examples/openapi_auth.iyi` (OAuth2 password flow issuing JWTs, user
  and admin providers, an API-key client, `/docs`),
  `examples/observability.iyi` (a store, metrics, tracing, background work
  and hooks) and `examples/postgres/` (iyilang/db + iyilang/pg, a pool,
  migrations at start, `503` on a database error).
- A documentation site: `mkdocs.yml` builds `docs/` (checked by CI's new
  `docs` job), with a step-by-step tutorial, the guide pages that used to
  be the README, and new guides to typed routes, OpenAPI, dependencies
  and auth, transport, templates, state, lifecycle and background tasks,
  observability, plugins, the CLI, databases and benchmarks.

### Changed

- **Breaking:** `<%= expr %>` in a template rendered with `render` prints
  `expr.to_s` HTML-escaped (`&`, `<`, `>`, `"`, `'`). The template's own
  text is printed as written; `render` written inside a template answers
  `SafeHTML`, so a partial is not escaped twice.
- **Breaking:** a layout's `content` and `yield_content` are `SafeHTML`
  instead of `String`.
- **Breaking:** std/http refuses any request body past 64 MiB
  (`Server::MAX_BODY`), whatever `max_request_body_size` says.
- **Breaking:** `Response#attach(sink, head)` replaces
  `attach(sink, version, keepalive, head)`; the sink gets unframed body
  pieces. `Response#no_entity?` is public.
- Every connection is served through std/http's `Server.handle`. iyi-web
  keeps its accept loop, worker pool, drain, timeouts, `408`, `413`,
  `414` and `431` in a thin layer over the socket. A request head is
  parsed once instead of twice: parsing a GET went from 5966 ns to
  3397 ns, a form POST from 2267 ns to 1688 ns.
- HTTP/1.0 requests are answered with an `HTTP/1.1` status line, as RFC
  9110 allows.
- A head that misses `read_timeout` under TLS or HTTP/2 is closed (close
  notify or GOAWAY) rather than answered `408`.
- A drain also closes a connection whose next head was still arriving or
  that was in its TLS handshake.
- `params.raw_body` is empty for a multipart request: its body went to
  its files.
- Templates are translated by iyi-web's own compile-time program,
  `iyi_web/templates/process.iyi`, instead of std/eiy's; tags, trimming,
  comments and error positions are unchanged.
- Each route method of `Router` and the DSL is a set of overloads, one
  per combination of typed options. Existing calls compile unchanged.
- `run` runs the background runner beside the listener and, after the
  drain, closes it and runs the `on_stop` hooks.
- `iyi_web/log`'s `STDOUT_LOCK` is exported, so other writers to standard
  output share the request log's lock.
- The examples are typed routes over stores and serve on every core:
  none parses a parameter by hand, and `typed_json` no longer needs
  `workers: 1`. A word where an example expects a number is a `422`.
- The README is an introduction that links the docs site, with badges and
  benchmark results; stale statements were fixed on the way.
- bench/micro's `intake.get` and `intake.post_form` are `wire.get` and
  `wire.post_form`.

### Removed

- **Breaking:** `iyi_web/templates` (and through it `iyi_web/dsl`) no
  longer re-exports `std/eiy`. `ContentBlocks#capture` yields an
  `HTMLBuffer`, not an `Eiy::Buffer`.
- **Breaking:** `iyi_web/intake` (`Intake`, `TooLarge`, `HeadTooLarge`),
  `Closed` and `TimedOut` from `iyi_web/server`, and
  `Response#reusable?`.

### Security

- Templates escape what `<%= %>` prints: a value a request sent can no
  longer inject markup or script into a page by default.
- `JWT.verify` accepts only `HS256` and compares signatures in constant
  time, so an `alg: none` or algorithm-confusion token is refused before
  its signature is read.

## [0.5.1] - 2026-11-04

Requires iyi 0.20.1 or later.

### Fixed

- A route whose block only raises runs its block again, through the
  same call as every other route: iyi 0.20.1 fixes the compiler crash
  that the private `answer_route` helper of 0.5.0 worked around, and
  the miscompile where such a route panicked "can't execute" without
  running its body. The helper is gone.

## [0.5.0] - 2026-11-02

Requires iyi 0.20.0 or later: `spawn_parallel` (SPEC.md III.4.13)
and the `@[Share(serial:, crossing:)]` mark. Exports changed (`iyi mod
release`): `Handler#next_handler` and `next_handler=` are gone,
`RouteHandler#lookup` answers a `Match(RouteEntry(...))`,
`SessionHandler#clock=` takes the Unix second to fix the clock at,
`RateLimitHandler`'s `clock:` is a `SharedProc(Nil, Int64)`,
`StaticHeadersHook` is a `SharedProc` and `Config#static_headers` a
`KeptStaticHeaders`, `Config`'s `custom_handlers`/`positioned_handlers`
hold kept steps, each `before`/`after` filter is one def taking a path or
an `Array` of them, and `select_content_coding`'s *available* is a
`List(String)`.

### Added

- A request is served on whichever core is free: `run` serves each
  connection as a parallel task on a pool of `workers` threads, the
  cores the process may run on by default (`IYI_WORKERS` overrides).
  `workers N` in the DSL, `config.workers`, or `-w`/`--workers` on the
  command line; `workers 1` serves every connection on the accepting
  thread, as before.
- Every block the application gives a route, a filter, an `error` page,
  `ws`, `sse`, `static_headers` and `BasicAuthHandler`/`RateLimitHandler`
  is checked by the compiler where it is written, as a parallel task's
  is: one that captures an `Array`, or assigns a local it captured, is
  refused naming the variable. A handler given to `use` or
  `add_handler`, and a logger given to `logger` or `config.logger =`,
  must be `Share`: one that is not is refused at the argument on the
  application's line, not inside iyi-web, naming the field.
- Each registration is marked `@[Share(serial: workers)]`, and `use` and
  `logger` `crossing:` too, so a refusal names both ways past it: a
  `Mutex` or an `Atomic` for the state, or `workers: 1`.
- `workers: 1` on a registration (`get "/x", workers: 1 do ...`, `use
  handler, workers: 1`, `logger value, workers: 1`, `static_headers
  workers: 1 do ...`) keeps its block unchecked; an application holding
  one is served on one thread and says so at start. Each registration is
  one def taking `workers:`, rather than a checked def and an unchecked
  one beside it.
- `iyi_web/refused_test.iyi` checks the refusals' text and place: the
  programs in `iyi_web/refused` go through `iyi check -f json`, and the
  one with `workers: 1` on everything must compile with no warning.
- `iyi_web/app`: `build_server(router, config)`, the server `run` builds,
  for a test or a program of its own.
- `bench/cores.sh`: one worker against every core under wrk, on bcrypt
  and on a light route, with the server's CPU from /proc.

### Changed

- A request's place in the chain is the request's (`Context#call_next`),
  not a field of the handler; `only`/`exclude` rules are behind a lock a
  request takes only when there are rules.
- Routes are read from a frozen copy of the tree (`Tree#frozen`), children
  sorted and binary-searched, so every worker reads one tree.
- `RateLimitHandler`'s table is behind a `Mutex`; `SessionHandler` keeps
  derived keys and expands an `AesGcm` per seal and open; `StdoutLogger`
  writes under one lock; the HTTP date cache is per connection.
- A stop asked for from a request on a worker is sent to the accepting
  thread, which drains; each connection's watcher closes or cuts off its
  own connection.
- The content codings iyi-web negotiates (`CONTENT_CODINGS`) are a
  `List`, which every worker may read: iyi master's reach warning (#148)
  named the `Array` they were in every program that served files or
  compressed. Every program here, tests and examples, now compiles with
  no reach warning.

## [0.4.0] - 2026-10-21

Requires iyi 0.18.0 or later. One export moved (`iyi mod release`):
`StatusError#status` is now `HttpError`'s, which `StatusError` implements;
a call to it is unchanged.

### Added

- `Request#raw_path`: the path as the request line sent it, before
  percent-decoding (`path` for a request built in-process).
- `config.route_on_raw_path` (off by default): routes, filters, `ws`
  routes, handlers' `only`/`exclude` rules and `use "/prefix"` match the
  raw path, and each captured segment is decoded after the match, as in
  Kemal, so `/files/a%2Fb` reaches `/files/:name` with `name` = `a/b`.
  `Context#routing_path` is the path they all match, so a rule never reads
  a request the router routes elsewhere: an `exclude ["/hooks/*"]` does not
  exempt `/hooks%2Fx/delete` from a CSRF check when it routes to
  `/:org/delete`.
- `config.reject_unreadable_body` (on by default): off, a route runs with
  a malformed JSON or multipart body, or one over the upload limits, and
  reads what went wrong from `params.json_valid?`, `params.json_error` and
  `params.body_error`, as Kemal ran the route and raised only when it read
  the body.
- Cookie sessions, kemal-session's cookie engine (new `iyi_web/session`):
  `use SessionHandler.new(secret)` and `session(env)["user"] = name`. The
  cookie is AES-256-GCM under a key HKDF derives from the secret (32 bytes
  or more, a shorter one refused), with a fresh `Random::Secure` nonce, and
  carries its issue and expiry times, checked on the server. An altered,
  lapsed or foreign cookie is an empty session. `old_secrets` rotates the
  secret: a cookie sealed under an old one is read and re-sealed under the
  new one with its first expiry. The cookie is set only when the session
  changed and deleted when it is cleared; one over 4096 bytes is refused.
  `regenerate` gives a new id, `set`/`json?` keep any JSON value, and
  `save_session(env)` writes the cookie before a streamed response flushes.
- CSRF protection, kemal-csrf (new `iyi_web/csrf`): `CSRFHandler` refuses
  unsafe requests without the session's token in the `authenticity_token`
  field or the `X-CSRF-Token` header with `403`, compared in constant time;
  `only`/`exclude` let an API opt out. `csrf_tag(env)` and `csrf_token(env)`
  hand the token out masked afresh on each call, against BREACH.
- `iyi_web/token`: `random_bytes`, `encode_base64url` and a
  `decode_base64url?` that answers nil, not a panic, for text a client sent.
- `examples/sessions_and_csrf.iyi`: sign-in and sign-out in a session, and
  forms guarded by `CSRFHandler`.
- Typed JSON bodies (new `iyi_web/validation`): `env.params.json_as(T)` reads
  the body into a `derive serializable` type and answers `T | BodyError`,
  never a panic: `415` for a body not declared JSON, `400` for one that does
  not parse, with the line and column, `422` naming every field that is
  missing, `null`, of the wrong kind or out of range (`title`,
  `author.name`, `tags[1]`). `read_json(text, T)` does the same for any
  string.
- Validation: a type that implements `Validate` gets `validate(v :
  Validator)` run after the read, with `required`, `length`, `range`,
  `format`, `one_of` and `add`; every failing field is answered in one
  `422`.
- `HttpError` (`iyi_web/status`): an `Error` that carries its status. A route
  that returns one gets that status, its type's page, then its status's
  page; below 500 the built-in page shows its message and `fields`, as
  `{"error": ..., "fields": {...}}` to a JSON client and plain text to any
  other. `BodyError` and `StatusError` implement it.
- `Params#json_error`: why a declared JSON body does not parse.
- `examples/typed_json.iyi`: notes read with `json_as`, validated, and
  written from `derive serializable` types.
- Benchmarks (`bench/`): `bench/micro.iyi` times route lookup over about a
  hundred routes, request-head parsing, query/form/JSON parameters, the
  header table and whole dispatches through `RouteHandler` and
  `handler_chain`; `bench/load.iyi` is a keep-alive load generator (no `wrk`,
  Linux and Windows) reporting req/s, p50/p99 latency and errors against
  `bench/server.iyi`. `bash bench/run.sh` builds both with `--release` and
  writes `bench/results.json`; `bench/compare.iyi` turns two sets of result
  files into a Markdown table of medians and exits 1 when a microbenchmark
  is more than 30% slower in every run. CI's new `bench` job compares a pull
  request with its base in the job summary, failing on such a regression,
  and keeps master's results as an artifact.
- `BasicAuthHandler` (new `iyi_web/basic_auth`), kemal-basic-auth: one fixed
  user compared in constant time, or a verifier block; `401` with
  `WWW-Authenticate: Basic realm="...", charset="UTF-8"` for missing,
  refused or malformed credentials (base64 that does not decode is a `401`,
  not a panic); the user name stored under `"basic_auth.username"`.
- `SecurityHeadersHandler` (new `iyi_web/security_headers`):
  `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy` and
  `Cross-Origin-Opener-Policy` by default, `Content-Security-Policy` and
  `Strict-Transport-Security` when given (HSTS only over TLS or behind
  `X-Forwarded-Proto: https`); each replaceable or left out with `nil`, set
  before the route so the route's own value wins.
- `RequestIdHandler` (new `iyi_web/request_id`): keeps an incoming
  `X-Request-Id` that is a short plain token, replaces any other with a
  UUID v4, echoes it, stores it under `"request_id"`, and the request log
  line ends with it.
- `RateLimitHandler` (new `iyi_web/rate_limit`): `limit` requests per
  `period` seconds per client address or per key a block chooses, in fixed
  windows; `RateLimit-Limit`/`-Remaining`/`-Reset` on every answer, `429`
  with `Retry-After` past the limit; at most `max_keys` windows held; an
  injectable millisecond clock.
- `Request#remote_address` (the client's IP, nil over a unix socket) and
  `Request#tls?`, filled in by the server.
- `Handler#applies?`: `only` and `exclude` together, an empty `only`
  meaning every request.
- `examples/security.iyi`: all four handlers in front of a page and an
  `/admin` area.

### Changed

- A route that returns a `StatusError` is answered with its status, not
  `500`.
- A declared JSON body that does not parse is answered as a `BodyError`:
  `error BodyError` and `error Error` pages now take it before `error 400`,
  and the built-in `400` says where the body broke, in JSON to a JSON
  client.
- `render_failure_page` takes the status to title the page with; it
  defaults to 500.
- `request_log_line` takes an optional request id, which `Logger#request`
  passes when `RequestIdHandler` stored one.
- `iyi_web/harness`'s `dispatch` gives the context the per-request
  settings the server gives it (`Config#prepare`: upload limits,
  `max_ranges`, `send_file`'s compression and the routing path), from the
  process `config` or a `Config` passed as its third argument, so a request
  driven in-process is handled as one over a socket.

### Fixed

- `render` in a method of a file that does not import `std/eiy` itself
  no longer fails to build: `iyi_web/templates` re-exports `std/eiy`, whose
  `Eiy.embed` the macro expands to in the caller's file.
- `examples/cookies_and_context.iyi` answered every sign-in with `500` on
  Windows, opening `/dev/urandom` itself; its tokens come from
  `iyi_web/token`'s `random_hex`, which draws from `Random::Secure`.

### Security

- `random_hex`, which names multipart boundaries and upload spool
  directories, draws from `Random::Secure` on every platform. Where there
  was no `/dev/urandom`, as on Windows, it drew from a PCG seeded once at
  start-up, whose later outputs a few earlier ones give away.

## [0.3.0] - 2026-10-19

Requires iyi 0.18.0 or later, for its TLS server, streaming compressor and
media-type table. 35 exports are gone (`iyi mod release`): `error` pages
and routes take new block types, `Response#upgrade` and `WebSocket.new`
take `IyiSocket | TlsStream`, `Server.new` takes pages with their cause,
`iyi_web/mime` is gone and the `Accept-Encoding` helpers moved from
`iyi_web/compress` to `iyi_web/content_coding`.

### Added

- HTTPS, Kemal's `config.ssl`: `config.ssl = TlsServerConfig`, or `-s` with
  `--ssl-key-file FILE` and `--ssl-cert-file FILE`, serves every connection
  over `std/tls` (TLS 1.3; Ed25519, P-256 or RSA keys in PKCS #8), and
  `Server#bind_tls(host, port, tls)` does it without the DSL. A missing key
  or certificate flag stops the program with Kemal's sentence, an unreadable
  or refused file with the reason. Each handshake runs in its connection's
  fiber within `read_timeout`; a failed one closes that connection only.
  Streaming, SSE, WebSockets (`wss://`) and unix sockets work over TLS, and
  the startup line reads `https://`.
- `error 404 do |env, err|`: a page may take what caused it, a value of the
  prelude's `Error`: the `Panicked` of a route's panic, the error a route
  returned, or a `StatusError` with the status (new `iyi_web/failure`).
- Error pages per error type, iyi's `error MyException`: a route may return
  an error beside its body (`String | Gone`), and `error Gone do |env, err|`
  answers it, as a `500` unless it sets another status. Pages are tried in
  registration order, take subclasses, and `error Error` takes every error;
  a panic is offered to them as a `Panicked` before `error 500`.
- `env.set(name, value)` for a value of any type, read back by type with
  `env.get(name, User)` and `env.get?(name, User)`: Kemal's
  `add_context_storage_type`, without the registration.
- Static files: a `<file>.gz` beside a file, no older than it, is sent as it
  is to a client that accepts gzip, with the original's content type.
- `send_file` compresses with gzip or deflate under Kemal's conditions: the
  static `gzip` option on, a compressible type of 860 bytes or more, no
  `Range`.

### Changed

- Static files and `send_file` compress as they read from disk, 64 KiB at a
  time with `std/compress`'s `Deflater`, whatever their size; static files
  were compressed up to 1 MiB, whole in memory. A compressed body gets a weak
  `ETag` naming its coding, and a `Range` request the uncompressed file.
- Content types come from `std/mime`: `.wasm`, `.mjs`, `.csv`, `.md`,
  `.avif`, `.mp4` and more are named, `.svg` and `.xml` carry
  `charset=utf-8`, and `.ico` is `image/vnd.microsoft.icon`.
- An object stored in the context is kept out of the untyped `env.get(name)`,
  which panics naming the typed read, and `env.get?(name)`, which answers nil.
- `Content-Length` is read with `std/http`'s `HTTP.content_length`; the copy
  kept for iyi 0.15.0 is gone.

### Removed

- `COMPRESS_MAX_SIZE`, `compressible_type?` (`MIME.compressible?` takes its
  place), `iyi_web/mime`'s `mime_type_of` and `codec`'s `extension_of`.
- The refusal of `-s` and `--ssl-*` as unsupported.

### Fixed

- Multipart boundaries and upload spool directories panicked on iyi 0.17.0
  and later where `/dev/urandom` is there but may not be read, as in a
  sandbox: `File.exists?` stopped opening the path in 0.17.0, so the check
  passed and the open after it failed. `File.readable?` is asked instead,
  and `std/random` used when it says no, as before.

## [0.2.0] - 2026-10-16

Requires iyi 0.15.0 or later. Five exports are gone (`iyi mod release`):
`parse_ranges`, `content_range` and `unsatisfied_range` take `Int64`, and
`TooLarge` moved from `iyi_web/server` to `iyi_web/intake`.

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
  example, on Linux with iyi 0.15.0 and the latest iyi, and on Windows with
  the latest.

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
- An `If-Modified-Since` naming a day its month does not have
  (`31 Feb`), an hour past 23 or a signed field panicked and was answered
  `500`; it is ignored, as RFC 9110 asks. A leap second (`:60`) is read
  as `:59`.
- A request led by empty lines (`\r\n`) was taken to end at them, then
  buffered whole, past `max_request_body_size`, and parsed again after
  every read. They are skipped, as `std/http` skips them, and
  `Content-Length: 5, 5` is read as one length, as `std/http` reads it
  from iyi 0.16.1 on (before, it refuses it with `400`), instead of
  buffering on. A request whose framing the two still read differently is
  refused with `400`.
- `render`, `content_for` and `yield_content` from `import iyi_web/dsl::*`
  did not build on iyi 0.17.0, which refuses `IyiWeb::Templates` in a file
  that does not import it. `iyi_web/dsl` re-exports `iyi_web/templates`
  with `pub import`.

### Security

- Two `Content-Length` headers that differ, or more than one
  `Transfer-Encoding`, are refused with `400` rather than read one way by
  iyi-web and another by a proxy. A chunked body over
  `max_request_body_size` gets `413` as soon as its chunks pass it.
- Static files on Windows: `\` (`%5C`) is a separator to the file system,
  so `GET /..%5C..%5Csecret.txt` walked out of the public folder and was
  served. A path with `\` or `:` (a drive, an alternate stream such as
  `a.txt::$DATA`) is not served on Windows.
- A request's head is held to 8 KiB of request line (`414`) and 16 KiB of
  fields (`431`), Crystal's bounds. It could be a megabyte, and the header
  table was built in time the square of the field count: one request of
  90,000 short fields kept the server busy for 4.7 s, and every other
  client waited. The table is built in linear time too.
- WebSockets: a fragmented message is held in one buffer counted against
  `websocket_max_message_size`, and a continuation frame is refused from
  its header when it would pass what the message has left. Empty
  continuation frames, which the limit never counted, grew the server's
  memory without bound.
- WebSockets: no data frame is written after the close frame. A send
  already waiting for the write lock could get it after `close` and write
  its frame behind the close frame (RFC 6455 §5.5.1); it now returns
  `false`.
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

[Unreleased]: https://github.com/sdogruyol/iyi-web/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/sdogruyol/iyi-web/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/sdogruyol/iyi-web/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/sdogruyol/iyi-web/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/sdogruyol/iyi-web/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/sdogruyol/iyi-web/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/sdogruyol/iyi-web/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/sdogruyol/iyi-web/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/sdogruyol/iyi-web/releases/tag/v0.1.0
