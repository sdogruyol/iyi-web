# Error pages

```iyi
error 404 do |env|
  "<h1>Page not found</h1>"
end

error 422 do |env|
  "<h1>Please check the form and try again</h1>"
end

error 500 do |env, err|
  "<h1>Something went wrong</h1><!-- " + err.message + " -->"
end

post "/signup" do |env|
  email = env.params.body["email"]? || ""
  env.response.status_code = 422 if email.empty?
  "Welcome"
end
```

An error page replaces the body of `404` and `405` responses from the router,
and of any response a route finishes with a status of `400` or above. The
status code is kept. Responses ended with `halt` are sent unchanged.

A page may take a second argument, `err`, what caused it, as Kemal's
`error 404 do |env, ex|` does. iyi has no exceptions; `err` is a value of the
prelude's `Error` trait: the `Panicked` a route's panic was caught as, the
error a route returned, or a `StatusError` (`web/iyi_web/failure`) with the
status and a message such as `404 Not Found`.

## Errors by type

Where Kemal has `error MyException do |env, ex|`, iyi-web has a page per error
type. A route returns the error as part of its value, and the page for its
type answers it:

```iyi
struct Gone
  getter what : String

  def initialize(@what : String)
  end
end

impl Error for Gone
  def message : String
    what + " is gone"
  end
end

get "/posts/:id" do |env|
  id = env.params.url["id"]
  id == "1" ? "First post" : Gone.new("post " + id)
end

error Gone do |env, err|
  env.response.status_code = 410
  "<h1>" + err.message + "</h1>"
end
```

- `err` has the page's type. Pages are tried in the order they were
  registered, and a page for a type also takes its subclasses; `error Error`
  takes every error.
- The response is a `500`, or the status of an
  [error that carries one](#errors-that-carry-a-status), unless the page sets
  another. The route's headers are kept, its body is dropped, and after
  filters do not run.
- An error no page takes goes to the `error` page for that status (`error
  500` for a plain error) with it as `err`, then to the built-in page.
- A panic is offered to the type pages too, as a `Panicked`: `error Panicked`
  or `error Error` catches it before `error 500` does.

A route that panics gets `500 Internal Server Error` and its connection is
closed; other connections are not affected, and the panic is logged. The
first page that takes it is used. Otherwise the built-in page shows the panic
message in development and hides it in every other environment;
`config.show_exceptions = true` or `false` overrides that. An error a route
returned that no page takes is shown the same way.

## Errors that carry a status

An error type that also implements `HttpError` (`web/iyi_web/status`) is
answered with its own status instead of `500`, which is what Kemal's
`CustomException` subclasses are for:

```iyi
import web/iyi_web/status::{HttpError}

struct Conflict
end

impl Error for Conflict
  def message : String
    "that title is taken"
  end
end

impl HttpError for Conflict
  def status : Int32
    409
  end
end

post "/notes" do |env|
  title_taken?(env) ? Conflict.new : "created"
end
```

The page for its type comes first, then the page for its status (`error
409`), then the built-in page. Below `500` the error is the client's, so the
built-in page shows its `message`, and its `fields` (a `Hash(String,
String)`, empty unless the type defines it): `{"error": message, "fields":
{...}}` for a request that sent JSON or whose `Accept` asks for it, the
message as plain text otherwise; write those for the client. From `500` up,
the message is shown only under `show_exceptions`, as above.

`BodyError` ([Typed JSON bodies](parameters.md#typed-json-bodies)) and `StatusError`
(`web/iyi_web/failure`) are `HttpError`s: a route may return
`StatusError.new(404)` and get the `error 404` page. A JSON body that does not
parse is answered as the `BodyError` `json_as` would have returned, so
`error BodyError` and `error 400` both take it.
