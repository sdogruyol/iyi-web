# Kemal for iyi

[Kemal](https://kemalcr.com), rewritten for [iyi](https://iyi-lang.com). Same
Sinatra-shaped DSL. Different compilation model: modules, `using`, traits, no
open classes.

Crystal Kemal injects `get` into your program when you `require "kemal"`, and
it reopens `HTTP::Server::Context`. iyi forbids both. The library exports
names; the program writes `using kemal/dsl`. A handler may return anything
that implements `IntoBody` — checked at the line you write the route, not
silently emptied on every request.

## Run

iyi binary: `/home/uzumaki/playground/iyi/bin/iyi` (or `iyi` if it is on
`PATH`).

```sh
iyi run examples/hello.iyi
# http://localhost:3000/
```

`PORT=4000 iyi run examples/hello.iyi` moves it. `KEMAL_ENV=production` turns
the banner.

```iyi
module examples/hello

import kemal/dsl
using kemal/dsl

get "/" do |env|
  "Hello iyi!"
end

get "/hello/:name" do |env|
  "Hello, #{env.params.url["name"]}!"
end

get "/count" do |env|
  42
end

post "/echo" do |env|
  env.request.body
end

error 404 do |env|
  "no such route"
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
| one request per connection | HTTP/1.1, no TLS yet |

iyi's own prelude has no `HTTP::Server` and no TLS. The server is
`std/socket` plus the cooperative scheduler (`wait_readable`, `group` /
`spawn`). HTTPS, WebSocket, SSE, multipart uploads and ECR are not ported
yet.

## Modules

```
kemal/dsl        get, post, run, error, mount, use
kemal/router     Router, RouteHandler, namespace
kemal/context    Context (request, response, params, halt)
kemal/body       IntoBody — String, Nil, Int32, Int64, Bool
kemal/handler    Handler, chain
kemal/server     HTTP/1.1 on IyiSocket
kemal/config     port, env, public_folder, logging
```

A program that only wants a sub-router imports `kemal/router` and never
`using`s the DSL.

`namespace` takes the sub-router as a block parameter (`|admin|`), not as
`self`. Crystal Kemal used `with sub_router yield`; iyi has nowhere to write
that a block's `self` changes (SPEC.md IV.2).

```iyi
import kemal/router
using kemal/router::{Router}

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
iyi test kemal
```

## Crystal Kemal

The original lives at `/home/uzumaki/playground/kemal`. This repository is
not a drop-in `require "kemal"` replacement under `--crystal`. It is Kemal
as an iyi library, compiled against iyi's own prelude.
