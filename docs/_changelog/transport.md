### Added

- HTTP/2: h2c with prior knowledge beside HTTP/1.1 on the same port, and h2 over TLS by ALPN (`["h2", "http/1.1"]` is offered when a TLS config names nothing; `-s` offers it too).
- TLS 1.2 (`config.ssl.min_version`, `--ssl-min-version 1.2`) and mutual TLS (`config.ssl.client_roots`, `--ssl-client-ca FILE`); `env.request.peer_certificates`.
- `config.autocert` (std/autocert, Let's Encrypt; tls-alpn-01 on the TLS port, renewals beside the accept loop), `LETS_ENCRYPT`, `LETS_ENCRYPT_STAGING`, `Config#tls_config`, `Server#autocert=`.
- `config.stream_bodies`: bodies left on the connection; `env.request.body_io` (`RequestBody#read`), `env.request.body_failure` (`BodyFailure`), `body_pending?`.
- `config.compress`: zstd or gzip negotiated by std/http.
- `multipart/form-data` uploads stream to disk as they arrive (`parse_multipart(RequestBody, ...)`).
- `params.body_error` reports a body that could not be read (413/408/400).

### Changed

- The transport is std/http's `Server.handle`; iyi-web keeps its accept loop, drain, timeouts, 408, head bounds (414/431) and body limit (413) in a thin layer.
- **Breaking:** `Response#attach(sink, head)` replaces `attach(sink, version, keepalive, head)`; the sink gets unframed body pieces (framing is std/http's). `Response#reusable?` is gone; `Response#no_entity?` is public.
- HTTP/1.0 requests are answered with an `HTTP/1.1` status line (std/http's, as RFC 9110 allows).
- A drain also closes a connection whose next head was still arriving or that was in its TLS handshake.
- A head that misses `read_timeout` under TLS or HTTP/2 is closed rather than answered 408.
- `params.raw_body` is empty for a multipart request (its body streamed to its files).
- std/http caps every body at 64 MiB, whatever `max_request_body_size` says.
- bench/micro: `intake.get` / `intake.post_form` became `wire.get` / `wire.post_form`.

### Removed

- `iyi_web/intake` (`Intake`, `TooLarge`, `HeadTooLarge`), and `Closed` / `TimedOut` from `iyi_web/server`.
