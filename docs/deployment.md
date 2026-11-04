# Deployment

```sh
iyi build --release app.iyi -o app
IYI_WEB_ENV=production ./app -p 8080
```

- iyi-web serves HTTP/1.1 and HTTP/2, and HTTPS itself with `-s` (see
  [HTTPS](configuration.md#https)), with certificates from Let's Encrypt if
  you set `config.autocert` ([Transport](transport.md)). Behind a reverse
  proxy such as nginx, Caddy or HAProxy, the proxy can reach the server over
  a unix socket (`unix_socket`). Keep `idle_timeout` above the proxy's own
  keep-alive timeout, so that the proxy is the one to close an idle
  connection.
- One process listens per port: `reuse_port` is not available (std/socket
  sets `SO_REUSEADDR` only), so run several processes behind a proxy rather
  than on one port.
- Request bodies stop at 64 MiB whatever `max_request_body_size` says (a
  std/http limit); larger uploads need another route in, such as direct
  uploads to object storage.
- A client that disconnects while its response is being written ends that
  request only; iyi's runtime reports it as a panic line on standard error.
- The program serves on every core it may run on; `-w 4`, `IYI_WORKERS=4`
  or `workers 4` set how many ([Every core](every-core.md)).
- `IYI_WEB_ENV=production` hides panic messages from the built-in error
  pages ([Errors](errors.md)), and is the `env` shown in the startup line.
- `INT` and `TERM` stop the server gracefully, within `shutdown_timeout`
  ([Stopping](configuration.md#stopping)); `on_start` and `on_stop` open and
  close what the program holds, such as a database pool
  ([Lifecycle](lifecycle-and-background.md), [Databases](database.md)).
- Point Prometheus at `/metrics` and a collector at the tracer
  ([Observability](observability.md)).
