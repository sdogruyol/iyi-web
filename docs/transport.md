# Transport: HTTP/2, TLS, streaming bodies, compression

iyi-web speaks HTTP through `std/http`'s server. Every connection the
server accepts is handed to `Server.handle` (the connection half of
`Server.serve`), so what std/http speaks, your app speaks — with nothing
to change in your routes:

```iyi
get "/" do |env|
  "hi"   # HTTP/1.1, HTTP/1.0, h2c and h2 over TLS alike
end
```

## HTTP/2

- **In the clear (h2c, prior knowledge):** a connection that opens with
  HTTP/2's preface is served HTTP/2 on the same port as HTTP/1.1.

  ```sh
  curl --http2-prior-knowledge http://localhost:3000/
  ```

- **Over TLS (ALPN):** a TLS config that offers no protocol is given
  `["h2", "http/1.1"]` when the server binds it, and `-s` does the same,
  so browsers get HTTP/2.

  ```sh
  curl -k --http2 https://localhost:3000/
  ```

`env.request.version` is `"HTTP/2"` for such a request. WebSockets stay on
HTTP/1.1 (RFC 8441 is not in std/http); browsers open them on a connection
of their own.

## TLS 1.3 and 1.2, mutual TLS

`config.ssl` is std/tls's `TlsServerConfig`, so its options are yours:

```iyi
tls = TlsServerConfig.from_pem(File.read("cert.pem"), File.read("key.pem")).or_panic
tls.min_version = TlsVersion::TLS12                                   # take 1.2 clients too
tls.client_roots = Certificate.from_pem(File.read("clients.pem")).or_panic  # mutual TLS
config.ssl = tls

get "/whoami" do |env|
  certs = env.request.peer_certificates   # the client's chain, leaf first
  certs.empty? ? "anonymous" : certs[0].subject_name
end
```

On the command line:

```sh
./app -s --ssl-key-file key.pem --ssl-cert-file cert.pem \
      --ssl-client-ca clients.pem --ssl-min-version 1.2
```

std/tls requires the extended master secret (RFC 7627) on TLS 1.2, so a
1.2-only client without it (LibreSSL's) is refused; OpenSSL clients work.

## Certificates from Let's Encrypt (autocert)

```iyi
cache = AutocertDirCache.new("/var/lib/app/certs")
manager = AutocertManager.new(LETS_ENCRYPT, cache, ["example.com"])
manager.accept_terms = true
manager.email = "admin@example.com"
config.autocert = manager
run 443
```

The server serves TLS under the manager's config (HTTP/2 offered), answers
the CA's `tls-alpn-01` challenge on that same port, and runs the renewals
beside its accept loop until it stops. `LETS_ENCRYPT_STAGING` is there to
try a setup against. `config.ssl`, when set too, wins.

## Request bodies

By default a body is read whole before the chain runs, up to
`max_request_body_size`: past it the answer is `413`, too slow `408`,
broken `400` — before any handler sees the request. A `Content-Length`
over the limit is refused before a byte of the body is read (a client
waiting for `100 Continue` is never told to send it).

**`multipart/form-data` uploads always stream to disk:** each file part is
written to its temporary file a read at a time, when the fields are first
asked for (the router asks before the route runs), so an upload costs a
read's worth of memory, not its size. `params.raw_body` is empty for such a
request.

**`config.stream_bodies = true`** leaves every body on the connection for
the route to read as it arrives:

```iyi
config.stream_bodies = true

post "/upload" do |env|
  body = env.request.body_io
  File.open("/tmp/upload.bin", "w") do |file|
    while (piece = body.read).is_a?(String) && !piece.empty?
      file.write(piece)
    end
  end
  (failed = env.request.body_failure) ? "failed: #{failed.status}" : "stored"
end
```

`env.request.body` still reads it whole the first time it is asked for. A
body nobody reads is read past after the answer (std/http drains up to a
megabyte, else closes the connection). A JSON, form or multipart body that
cannot be read is still answered by the router before the route
(`params.body_error` says why: 413, 408, 400).

std/http refuses any body past 64 MiB (`Server::MAX_BODY`) whatever
`max_request_body_size` says.

## Compression: zstd and gzip

```iyi
config.compress = true
```

An answer whose type is worth compressing goes `zstd` to a client that
takes it at least as gladly as gzip, `gzip` otherwise, and gzip for a
streamed one, with `Vary: Accept-Encoding`. An answer that already has a
`Content-Encoding` (`CompressHandler`, a precompressed static file) is left
alone. Off by default.

## Limits iyi-web keeps on top of std/http

| What | Default | Answer |
| --- | --- | --- |
| request line | 8 KiB | `414` |
| header fields | 16 KiB | `431` |
| body | `max_request_body_size` (8 MiB) | `413` |
| whole request, from its first byte | `read_timeout` (60 s) | `408` |
| next request on a kept connection | `idle_timeout` (75 s) | closed |
| each write | `write_timeout` (60 s) | connection ends |
| requests per connection | `max_keepalive_requests` (100) | `Connection: close` |

A head that misses `read_timeout` gets its `408` over HTTP/1 in the clear;
under TLS or HTTP/2 the connection is closed (close_notify or GOAWAY),
since the bytes on the wire there are not plain HTTP/1.

## Stopping

`stop`, INT or TERM drain as before: the listener closes, connections
waiting for a request (or for the rest of a head, or in a TLS handshake)
are closed, requests in flight finish with `Connection: close`, and what
is still running after `shutdown_timeout` is cut off — a streamed answer
then ends without its last chunk, so no client takes it for a whole body.
A second signal cuts off at once.

## Not available

- `reuse_port`: std/socket sets `SO_REUSEADDR` only; there is no knob for
  `SO_REUSEPORT`.
