# Routing

```iyi
get "/articles" do |env|
  "All articles"
end

post "/articles" do |env|
  env.response.status_code = 201
  "Created"
end

get "/articles/:id" do |env|
  "Article " + env.params.url["id"]
end

delete "/articles/:id" do |env|
  env.response.status_code = 204
  nil
end

get "/assets/*path" do |env|
  "Asset " + env.params.url["path"]
end
```

`put`, `patch`, `options`, `head` and `query` work the same way. Paths start
with `/`.

- `:name` matches one path segment: `/articles/42` sets `id` to `42`.
- `*name` matches the rest of the path: `/assets/css/site.css` sets `path` to
  `css/site.css`.
- A trailing slash does not matter: `/articles/` is `/articles`.
- Two routes may name the same segment differently: `/users/:id` and
  `/users/:user_id/posts` each read their own name.
- Defining the same method and path twice stops the program at startup.

A request that matches no route gets `404 Not Found`. A path that exists only
for other methods gets `405 Method Not Allowed` with an `Allow` header. Every
`GET` route also answers `HEAD`, without a body.

A route can also say what it reads and what it answers - `get
"/articles/:id", path: Int32, response: Article do |env, id|` - and have
the capture, the query string, headers and JSON body read into types before
its block runs: see [Typed routes](typed-routes.md).

## Return values

The value a route returns is the response body. A route may return any type
that implements `IntoBody`; `String`, `Nil` (an empty body), `Int32`, `Int64`
and `Bool` do. The check happens at compile time. A route may also return an
error value beside its body, such as `String | NotFound`; the error goes to the
`error` page for its type (see [Error pages](errors.md)). Implement
`IntoBody` to return your own types:

```iyi
import web/iyi_web/body::{IntoBody}

struct Temperature
  def initialize(@celsius : Int32)
  end

  def celsius : Int32
    @celsius
  end
end

impl IntoBody for Temperature
  def into_body : String
    celsius.to_s + " °C"
  end
end

get "/temperature" do |env|
  Temperature.new(21)
end
```

## Filters

```iyi
before_all do |env|
  env.response.headers["X-Content-Type-Options"] = "nosniff"
end

before_all "/admin/*" do |env|
  env.halt(401, "Unauthorized") unless env.cookies.has_key?("session")
end

after_get ["/api/*", "/reports/*"] do |env|
  env.response.headers["Cache-Control"] = "no-store"
end
```

- `before_all` and `after_all` run for every method. `before_get`,
  `after_post` and their siblings run for one method: `get`, `post`, `put`,
  `patch`, `delete`, `options` or `query`.
- The path defaults to `*`, every path. `/admin/*` matches `/admin` and every
  path under it; `/users/:id` matches one segment in place of `:id`; any other
  path matches exactly. A list registers the same block for each path.
- Filters run in declaration order. `before_all` filters also run for a
  request no route matched, before its `404` or `405`; the others run only
  for a matched route.
- A before filter that calls `halt` or `redirect` stops the request before the
  route runs. One that sets an error status with an error page gets that page
  instead of the route.
- A filter's return value is discarded, but like a route's it must implement
  `IntoBody`.

Filters, middleware and routes pass values along a request with `env.set`,
`env.get` and `env.get?`. A `String`, `Int32`, `Int64`, `Float64`, `Bool` or
`nil` reads back with `env.get(name)`. A value of any other type, such as
your own class, reads back by its type: `env.get(name, User)` panics when
nothing or something else is stored there, and `env.get?(name, User)`
answers nil instead. Kemal needs `add_context_storage_type(User)` and
`env.get(name).as(User)` for the same; iyi-web needs no registration.
`env["key"]` reads and writes strings only:

```iyi
before_all "/account/*" do |env|
  env.set("user_id", 42)
  env.set("user", User.new("ada"))
end

get "/account/orders" do |env|
  "Orders for " + env.get("user", User).name + ", user " + env.get("user_id").to_s
end
```
