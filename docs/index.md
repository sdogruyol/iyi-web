# iyi-web

The web framework for [iyi](https://iyi-lang.com).

```iyi
module app

import web/iyi_web/dsl::*

get "/" do |env|
  "Hello, world!"
end

run
```

iyi-web serves HTTP/1.1, HTTP/2 and HTTPS from native iyi programs, on
every core. Routes are blocks, middleware is a class, and settings live in
a single `config` value. Its DSL follows [Kemal](https://kemalcr.com)'s,
and what the type of a route returns, what it reads and what it shares
between threads are all checked when the program compiles.

## Where to start

- [Installation](installation.md): requirements, adding iyi-web to a
  project, and a first program.
- [Tutorial](tutorial.md): a typed JSON API from `iyi-web new` to a release
  build - typed routes, validation, `Store`, OpenAPI, JWT sign-in, tests and
  metrics.
- [The `iyi-web` command](cli.md): `iyi-web new` and `iyi-web dev`.

## The guide

| Topic | Pages |
|---|---|
| Routes and input | [Routing](routing.md), [Parameters](parameters.md), [Typed routes](typed-routes.md), [Requests and responses](requests-and-responses.md), [Errors](errors.md), [Routers](routers.md) |
| Pages | [Templates](templates.md), [Static files](static-files.md), [Sessions and CSRF](sessions-and-csrf.md) |
| Real time | [WebSockets and server-sent events](websockets-and-sse.md) |
| APIs | [OpenAPI](openapi.md), [Dependencies and auth](dependencies-and-auth.md), [Databases](database.md) |
| Around requests | [Middleware](middleware.md), [Security](security.md), [Lifecycle and background tasks](lifecycle-and-background.md), [Observability](observability.md), [Plugins](plugins.md) |
| Concurrency | [Every core](every-core.md), [Shared state with `Store`](state.md) |
| Running it | [Transport](transport.md), [Configuration](configuration.md), [Testing](testing.md), [Deployment](deployment.md) |

[Modules](modules.md) lists every module and what it provides, and
[Benchmarks](benchmarks.md) times iyi-web against itself.
