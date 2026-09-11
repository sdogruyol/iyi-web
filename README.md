# iyi-web

[Kemal](https://kemalcr.com), rewritten for [iyi](https://iyi-lang.com). Same
Sinatra-shaped DSL. Different compilation model: modules, `using`, traits, no
open classes.

The package name is `iyi-web`. Module paths are snake_case (`iyi_web/dsl`)
because iyi's in-package grammar does not admit a hyphen (SPEC.md IV.6).

Crystal Kemal injects `get` into your program when you `require "kemal"`, and
it reopens `HTTP::Server::Context`. iyi forbids both. The library exports
names; the program writes `using iyi_web/dsl`. A handler may return anything
that implements `IntoBody` — checked at the line you write the route, not
silently emptied on every request.

## Run

iyi binary: `/home/uzumaki/playground/iyi/bin/iyi` (or `iyi` if it is on
`PATH`).

```sh
iyi run examples/hello.iyi
# http://localhost:3000/
```

`PORT=4000 iyi run examples/hello.iyi` moves it. `IYI_WEB_ENV=production`
turns the banner.

```iyi
module examples/hello

import iyi_web/dsl
using iyi_web/dsl

get "/" do |env|
  "Hello World!"
end

run
```

## What is here

| | |
|---|---|
| `get` / `post` / `put` / `patch` / `delete` / `options` / `head` / `query` | routes |
| `/users/:id` and `/files/*path` | params |
| `before_all` / `after_all` / `before_get` / … | filters |
| `error 404` | status handlers |
| `env.params.url` / `.query` / `.body` | params |
| `env.halt`, `env.redirect` | short-circuit |
| `env.response.content_type =` | headers |
| `mount` / `namespace` / `Router` | modular routing |
| `use` | middleware (`Handler` subclass) |
| `./public` | static files |
| HTTP/1.1 keep-alive | leftover bytes stay on the connection |
| `env.cookies` / `env.set_cookie` | Cookie / Set-Cookie |
| `env.send_file` | whole-file response |
| `_method` | `use OverrideMethodHandler.new` |
| `use "/api", handler` | path-scoped middleware |
| `use CORSHandler.new` | CORS + preflight 204 |
| `env.text` / `html` / `xml` / `json` | content-type + body |
| `Date` | RFC 9110 IMF-fixdate |

iyi's own prelude has no `HTTP::Server` and no TLS. The server is
`std/socket` plus the cooperative scheduler (`wait_readable`, `group` /
`spawn`). HTTPS, WebSocket, SSE, multipart uploads and ECR are not ported
yet.

## Modules

```
iyi_web/dsl        get, post, run, error, mount, use
iyi_web/router     Router, RouteHandler, namespace
iyi_web/context    Context (request, response, params, halt)
iyi_web/body       IntoBody — String, Nil, Int32, Int64, Bool
iyi_web/handler    Handler, chain
iyi_web/server     HTTP/1.1 keep-alive on IyiSocket
iyi_web/config     port, env, public_folder, logging, keepalive
iyi_web/cookies    Cookie header table
iyi_web/override   POST `_method` → PUT/PATCH/DELETE
iyi_web/path       prefix-scoped middleware
iyi_web/cors       CORS + preflight
iyi_web/http_date  RFC 9110 Date
```

A program that only wants a sub-router imports `iyi_web/router` and never
`using`s the DSL.

`namespace` takes the sub-router as a block parameter (`|admin|`), not as
`self`. Crystal Kemal used `with sub_router yield`; iyi has nowhere to write
that a block's `self` changes (SPEC.md IV.2).

```iyi
import iyi_web/router
using iyi_web/router::{Router}

users = Router.new
users.namespace "/admin" do |admin|
  admin.get "/dashboard" do |env|
    "dashboard"
  end
end
```

## Tests

A test is a `*_test.iyi` program that exits non-zero on failure.

```sh
iyi test iyi_web
```

## Crystal Kemal

The original lives at `/home/uzumaki/playground/kemal`. This repository is
not a drop-in `require "kemal"` replacement under `--crystal`. It is Kemal
as an iyi library, compiled against iyi's own prelude.
