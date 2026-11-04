# Typed routes

A route can name the types a request is read into, and get them as typed
values after `env`. What cannot be read is answered with a 4xx naming the
field before the block runs, so the block never parses or checks anything:

```iyi
import std/json::{serializable}
import web/iyi_web/dsl::*
import web/iyi_web/failure::{StatusError}

struct NoteFilter
  getter tag : String?
  getter limit : Int32 = 20
  derive serializable
end

get "/notes", query: NoteFilter, response: Array(Note) do |env, filter|
  find_notes(filter.tag, filter.limit)
end

get "/notes/:id", path: Int32, response: Note do |env, id|
  find_note(id) || StatusError.new(404)
end

post "/notes", body: NoteInput, response: Note, status: 201 do |env, input|
  save(input)
end
```

```sh
curl 'localhost:3000/notes?limit=many'
# 422 {"error":"invalid query parameters: limit must be an integer","fields":{"limit":"must be an integer"}}
curl localhost:3000/notes/abc
# 422 {"error":"invalid path parameters: id must be an integer","fields":{"id":"must be an integer"}}
```

The typed form is opt-in. `get "/" do |env| "hi" end` is unchanged, and a
plain route and a typed one sit side by side in the same router.

## One parameter at a time

Without changing a route's shape, `env.params` reads a single parameter as a
type. Each answers the value or a `ParamError` (422, naming the parameter):

```iyi
import web/iyi_web/coerce::{ParamError}

get "/notes/:id" do |env|
  id = env.params.int("id")
  next id if id.is_a?(ParamError)          # answered 422
  page = env.params.int("page", from: :query, default: 1)
  next page if page.is_a?(ParamError)
  "note #{id}, page #{page}"
end
```

| Method | Type | Accepts |
|---|---|---|
| `string(key)` | `String` | anything |
| `int(key)` | `Int32` | decimal digits with an optional sign |
| `int64(key)` | `Int64` | the same, in Int64's range |
| `float(key)` | `Float64` | a finite decimal or exponent number |
| `bool(key)` | `Bool` | `true`, `1`, `yes`, `on`, `false`, `0`, `no`, `off`, in any case |

Each takes `from:` (`:any`, the default, which searches url, then query,
then form body as `env.params["key"]?` does; or `:url`, `:query`, `:body`)
and `default:`. The default is used only when the parameter is missing: one
that was sent and is not the type is still a 422. Reading is strict: `" 12"`,
`"12abc"`, `"0x1f"` and `""` are not integers, and `"nan"` and `"inf"` are not
numbers, so nothing turns a client's mistake into a silent `0`.

A route's block is kept and called later, so `!` cannot leave it (the
compiler says so). `next` the error, as above, and the router answers it with
its status. Inside a `def`, `env.params.int("id")!` does the same.

## Options

| Option | The block gets | Read from |
|---|---|---|
| `path: T` | a `T` | the route's captures (`:id`, `*rest`) |
| `query: T` | a `T` | the query string |
| `headers: T` | a `T` | the request headers |
| `body: T` | a `T` | the JSON body, as `env.params.json_as(T)` reads it |
| `deps: D` | the provider's value | a provider ([Dependencies and auth](dependencies-and-auth.md)) |

The block gets `env` first, then one value for each option given, always in
the order of this table, whatever order the options are written in:

```iyi
put "/users/:user/notes/:id", path: NoteRef, query: Options, headers: Trace, body: NoteInput, deps: CURRENT_USER do |env, ref, options, trace, input, user|
  # ...
end
```

Every combination is its own overload, so the block's parameters are typed
from the options given: `id` above is a `NoteRef`, not a `String`. The same
options exist on every method (`get`, `post`, `put`, `patch`, `delete`,
`options`, `head`, `query`), in the DSL and on a `Router`, and on a mounted
or namespaced router.

## Parameter structs

`path:`, `query:` and `headers:` take a struct with `derive serializable`,
the same derive a JSON body uses. Each field the derive reads is a
parameter, named as the field, or by its `@[JSON::Field(key: "...")]`:

```iyi
enum Sort
  Newest
  MostLiked
end

struct Page
  getter page : Int32 = 1           # optional, defaults to 1
  getter q : String?                # optional, nil when absent
  getter sort : Sort = Sort::Newest # ?sort=most_liked
  getter tag : Array(String) = [] of String   # ?tag=a&tag=b
  @[JSON::Field(key: "per-page")]
  getter per_page : Int32 = 20      # ?per-page=50
  getter user_id : Int64            # required
  derive serializable
end
```

| Field | Rule |
|---|---|
| `String`, `Int32`, `Int64`, `Float64`, `Bool` | read strictly, as in the table above |
| an enum | a member's name as JSON writes it (`most_liked`), in any case |
| `Array(T)` of those | every value of a repeated key, in order; a wrong one is named `tag[1]` |
| `T?` | may be left out, and is nil then |
| with a default | may be left out, and keeps the default |
| neither | required: missing is `is required` |
| anything else (a struct, a hash) | refused when the program is compiled |

A scalar sent twice takes the last value, as `env.params.query` does. Once
every field reads, a struct that implements `Validate` is checked, and its
messages are part of the same 422:

```iyi
impl Validate for Page
  def validate(v : Validator) : Nil
    v.range("per-page", per_page, min: 1, max: 100)
  end
end
```

Every wrong field is named in one error, all of them rather than the first:

```json
{"error": "invalid query parameters: page must be an integer, sort must be one of: newest, most_liked, user_id is required",
 "fields": {"page": "must be an integer", "sort": "must be one of: newest, most_liked", "user_id": "is required"}}
```

### `path:`

A route that captures one segment may name a scalar: `path: Int32`,
`path: Int64`, `path: String`, `path: Bool`, `path: Float64` or an enum. It
reads that one capture:

```iyi
get "/notes/:id", path: Int32 do |env, id|
  "note #{id + 1}"
end
```

Registering a scalar `path:` on a route with no capture, or with several,
raises where the route is registered; give a struct with a field per capture
instead:

```iyi
struct NoteRef
  getter user : String
  getter id : Int64
  derive serializable
end

namespace "/users/:user" do |users|
  users.get "/notes/:id", path: NoteRef do |env, ref|
    "#{ref.user}/#{ref.id}"
  end
end
```

A field the route's full path does not capture (prefixes, namespaces and
mounts included) is refused when the server is built, naming the route and
the captures it has: such a route could only ever answer 422.

### `headers:`

A field matches the header named as the field with `_` as `-`, in any case:
`x_request_id` reads `X-Request-Id`. A missing or wrong header is named the
same way in the error, `x-request-id`.

```iyi
struct Trace
  getter x_request_id : String
  getter x_retry : Int32 = 0
  derive serializable
end

get "/trace", headers: Trace do |env, trace|
  trace.x_request_id
end
```

## `body:`

`body: T` reads the JSON body exactly as `env.params.json_as(T)` does, with
the same answers: `415` for a body that is not declared JSON, `400` for one
that does not parse (with line and column), `422` naming every field that is
missing, of the wrong kind or fails `Validate`. See
[Typed JSON bodies](parameters.md#typed-json-bodies) for the full table.

```iyi
post "/notes", body: NoteInput do |env, input|
  # input is a NoteInput that passed validate
end
```

## The order things are read in, and what answers

Providers (`deps:`) run first, then `path:`, `query:`, `headers:` and
`body:`. The first that fails answers the request and the rest are not read:
a request without its token gets `401` even when its body is also wrong.

| Failure | Status | Error | Message starts |
|---|---|---|---|
| a provider refused | the provider's | its own (`AuthError`, ...) | its own |
| a path capture | `422` | `ParamError` | `invalid path parameters:` |
| a query parameter | `422` | `ParamError` | `invalid query parameters:` |
| a header | `422` | `ParamError` | `invalid header parameters:` |
| the body | `400`, `415` or `422` | `BodyError` | `malformed JSON:`, `expected a JSON body`, `invalid body:` |

`ParamError` is an `HttpError` beside `BodyError`, answered the same way:
`{"error": ..., "fields": {...}}` to a client that sent or accepts JSON, the
message as text otherwise, and by your `error ParamError do |env, err|` or
`error 422` page when you register one.

## `response:` and `status:`

`response: T` declares what the block answers. The answer is written as
JSON (`env.json`), and the block's type is checked when the program is
compiled:

```iyi
get "/notes/:id", path: Int32, response: Note do |env, id|
  "not a note"
end
```

```
Error: the route answers String, which is not its response: Note (an error it answers is sent as an error)
```

Errors may be answered beside the type, as on any route: a block typed
`Note | StatusError` sends the note as JSON or the error with its status.
`Array(Note)`, `Hash(String, Note)` and anything else `JSON.to_json` writes
work as response types.

`status:` is the status the route answers with unless its block sets
another (`env.status(...)`), on a typed route or a plain one:

```iyi
post "/jobs", status: 202 do |env|
  enqueue(env.params.raw_body)
  "queued"
end
```

`response:`, `status:`, `summary:`, `description:` and `tags:` are also what
the [OpenAPI document](openapi.md) says about the route.

## Every core

A typed route's block is checked for data races where it is written, as a
plain route's is: a block that captures an `Array` or assigns a local it
captured is refused, naming the variable, and `workers: 1` keeps it
unchecked on one thread:

```iyi
NOTES = [] of Note

post "/notes", body: NoteInput, response: Note, status: 201, workers: 1 do |env, input|
  note = Note.new(NOTES.size + 1, input)
  NOTES << note
  note
end
```

That serves the whole application on one thread. To serve on every core,
keep the notes in a [`Store`](state.md) instead, as
`examples/typed_json.iyi` and `examples/openapi_auth.iyi` do;
`examples/json_api.iyi` keeps its store behind a `Mutex`.

## Examples

- `examples/typed_json.iyi`: `body:`, `query:` and `path:` with `response:`.
- `examples/json_api.iyi`: a CRUD API, every route typed, with `/openapi.json`.
- `examples/openapi_auth.iyi`: typed routes behind JWT, OAuth2 and API-key
  providers.
