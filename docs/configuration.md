# Configuration

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
| `reject_unreadable_body` | `true` | |
| `route_on_raw_path` | `false` | |
| `shutdown_timeout` | `30` | |
| `shutdown_message` | `true` | |
| `read_timeout` | `60` | |
| `write_timeout` | `60` | |
| `idle_timeout` | `75` | |
| `unix_socket` | `nil` | |
| `ssl` | `nil` (plain HTTP) | `-s --ssl-key-file FILE --ssl-cert-file FILE`, `--ssl-min-version 1.2`, `--ssl-client-ca FILE` |
| `autocert` | `nil` | |
| `stream_bodies` | `false` | |
| `compress` | `false` | |
| `websocket_allowed_origins` | `[] of String` (same-origin) | |
| `websocket_max_message_size` | `8 * 1024 * 1024` | |
| `app_name` | `"iyi-web"` | |

- `max_keepalive_requests` caps the requests served on one connection before
  it is closed.
- A request whose body is larger than `max_request_body_size` bytes gets
  `413 Content Too Large`, as soon as its `Content-Length` is read, and its
  connection is closed. std/http refuses any body past 64 MiB whatever this
  says, so a limit above that has no effect.
- `autocert`, `stream_bodies` and `compress` (Let's Encrypt certificates,
  bodies read as they arrive, zstd or gzip answers) are described in
  [Transport](transport.md).
- A request line longer than 8 KiB gets `414 URI Too Long`, and header
  fields past 16 KiB `431 Request Header Fields Too Large`, the bounds
  Crystal's server holds Kemal to. Neither is a setting.
- `max_ranges` is the most ranges one `Range` header may ask for; `0` turns
  range requests off.
- `reject_unreadable_body` answers a JSON body that does not parse with `400`,
  and a malformed multipart one or one past the upload limits with `400` or
  `413`, before the route runs. Off, the route runs, as Kemal ran it, and
  reads what went wrong from `params.json_valid?`, `params.json_error` and
  `params.body_error`: an authentication check in the route then answers
  first.
- `route_on_raw_path` matches routes, filters, handlers' `only`/`exclude` and
  `use "/prefix"` against the path as sent, percent-encoded, and decodes each
  captured segment afterwards, as Kemal does: `/files/a%2Fb` reaches
  `/files/:name` with `name` = `a/b`. Off, the path is decoded first, so the
  same request is `/files/a/b`. Every handler and the router see the same
  path either way, so a rule cannot exempt a request the router routes
  elsewhere. Static files are looked up by the decoded path. The path as sent
  is `env.request.raw_path`.
- `websocket_allowed_origins` lists origins such as `"https://example.com"`;
  `"*"` admits every request and `"null"` a sandboxed page.
- `websocket_max_message_size` counts a fragmented message whole.
- `app_name` and `env` appear in the line printed at startup. With `env` set
  to `test`, `run` binds the port without serving requests.
- `powered_by true` adds `X-Powered-By: iyi-web` to every response.
- `unix_socket` is a path to listen at instead of `host` and `port`, for a
  proxy on the same machine: `config.unix_socket = "/run/app.sock"`. The file
  must not exist yet; it is removed when the server stops.
- `ssl` is a `TlsServerConfig` from `std/tls`; set, every connection is TLS
  1.3 and the startup line reads `https://`. See [HTTPS](#https).
- Timeouts are in seconds, and `nil` or `0` turns one off. A client has
  `read_timeout` to send a whole request, headers and body, counted from its
  first byte (from the connection, for its first request); a request cut
  short gets `408 Request Timeout` and its connection is closed, and a
  connection that sent nothing is closed. `idle_timeout` is how long a
  keep-alive connection waits for its next request. `write_timeout` is how
  long one write waits for the client to take bytes; one that runs out ends
  the connection, so a stream lasts as long as its client keeps reading.

## Logging

Each request is logged as one line, `GET /users 200 1.234ms`, after its
response has been built, with the request's id after it when
`RequestIdHandler` runs; a request whose handler panicked is logged with its
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

## Command line

`run` reads the program's arguments:

```sh
./app -b 127.0.0.1 -p 8080
./app --help
```

`-b HOST` (`--bind`) and `-p PORT` (`--port`) set the host and port;
`run 8080` still wins over `-p`. The host may be an IPv6 address, bare or
bracketed (`-b ::1`, `-b '[::1]'`); `::` takes IPv6 connections only. An
unknown flag or an invalid port stops the program with the reason and the
list of flags. `-s` (`--ssl`) serves HTTPS with the PEM files `--ssl-key-file`
and `--ssl-cert-file` name; `--ssl-min-version 1.2` takes TLS 1.2 clients as
well as 1.3's, and `--ssl-client-ca FILE` asks every client for a
certificate those roots issued (mutual TLS). A missing or unreadable file,
or a key TLS refuses, stops the program with the reason. `extra_options`
adds your own:

```iyi
extra_options do |parser|
  parser.on("--public DIR", "Folder to serve static files from") { |dir| public_folder(dir) }
end
```

`run(args: nil)` ignores the command line.

## Stopping

`INT` (Ctrl-C) or `TERM` stops the server as `stop` does: it takes no new
connections, closes the idle ones, and lets each request in flight finish,
closing its connection after the response. `run` returns once they have, or
after `shutdown_timeout` seconds, when the rest are cut off: their fibers are
cancelled and their connections closed. A second signal cuts them off at
once. A server-sent-events stream is in flight for as long as it is open.

With `shutdown_message` on, the stop prints
`[production] storefront is going to take a rest!`. Code after `run` runs.

## HTTPS

```sh
./app -s --ssl-cert-file chain.pem --ssl-key-file key.pem
```

or in code, as Kemal's `config.ssl`:

```iyi
import std/file::{File}
import std/tls::{TlsServerConfig}

tls = TlsServerConfig.from_pem(File.read("chain.pem"), File.read("key.pem")).or_panic
config.ssl = tls
```

TLS is `std/tls`, iyi's own: TLS 1.3, and TLS 1.2 as well when
`tls.min_version = TlsVersion::TLS12` (or `--ssl-min-version 1.2`). A
config that names no ALPN protocol is offered `["h2", "http/1.1"]`, so
browsers get HTTP/2; set `tls.alpn = ["http/1.1"]` to keep to HTTP/1.1.
The certificate chain comes leaf first; the key is PKCS #8, Ed25519, P-256
or RSA of 2048 bits or more. Each connection's handshake runs in its own
fiber within `read_timeout`, and one that fails closes that connection
only. Streaming, server-sent events, WebSockets (`wss://`) and the unix
socket listener work over TLS. `Server#bind_tls(host, port, tls)` does the
same without the DSL. Mutual TLS, TLS 1.2's requirements and certificates
from Let's Encrypt (`config.autocert`) are in
[Transport](transport.md#tls-13-and-12-mutual-tls). `std/tls` has not been
audited yet; until it is, a reverse proxy remains the conservative choice
in front of a public site.
