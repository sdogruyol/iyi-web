# OpenAPI and the docs page

One line serves an OpenAPI 3.1 document of every route, and a page that
renders it:

```iyi
import web/iyi_web/dsl::*

openapi("Notes API", "1.0.0", description: "Notes with users and roles.")

get "/notes", query: NoteFilter, response: Array(Note), summary: "List notes", tags: ["notes"] do |env, filter|
  find_notes(filter)
end

run
```

```sh
curl localhost:3000/openapi.json     # the document
open http://localhost:3000/docs      # Swagger UI
```

The document is made from the routes themselves, mounts and namespaces
included, and from the types they declare ([Typed routes](typed-routes.md)):
there is nothing to keep in step by hand. Each type's schema is written by a
macro that walks the type's fields when the program is compiled, the same
walk that checks a JSON body, so the document says what the route reads,
field for field.

## Turning it on

```iyi
openapi("Notes API", "1.0.0")                                  # DSL
router.openapi("Notes API", "1.0.0")                           # a Router
openapi("Notes API", "1.0.0", path: "/api/spec.json", docs: "/api/docs")
openapi("Notes API", "1.0.0", docs: nil)                       # no page
```

| Option | Default | |
|---|---|---|
| `title`, `version` | | `info.title`, `info.version` |
| `description:` | none | `info.description` |
| `path:` | `/openapi.json` | where the document is served |
| `docs:` | `/docs` | where the page is served; `nil` for none |

On a `Router`, both paths are under the router's prefix, and the document
covers that router and everything mounted on it. The document is made once,
when the server is built (or a `RouteHandler` is made in a test), from the
routes registered by then, and is served as a string every worker shares.

## What a route contributes

| Route | In the document |
|---|---|
| its method and full path | `paths`, with `:id` and `*rest` written `{id}` and `{rest}` |
| every capture | a required `path` parameter, typed by `path:`, a `string` otherwise |
| `query:` | a `query` parameter per field, `required` unless it has a default or is nilable, its default when that is a literal |
| `headers:` | a `header` parameter per field, named as it is read (`x-request-id`) |
| `body:` | `requestBody`, `application/json`, required |
| `response:` | the schema of the `status:` response (default `200`) |
| `status:` | the success response's code; `204` has no content |
| `summary:`, `description:`, `tags:` | the operation's own |
| typed options | the errors the framework answers itself: `422` for parameters, `400`, `415` and `422` for a body, each with the `Error` schema |

Every route appears, typed or not: `get "/files/*path" do |env|` is listed
with its `path` parameter as a string and a plain `200`. `operationId` is
the method and the path's words, `get_notes_id`. Routes with the `QUERY`
method are left out: OpenAPI 3.1 has no operation for it. `ws` endpoints
are not HTTP operations and are not listed; an `sse` route is a `GET` and
is.

## Schemas

| Type | Schema |
|---|---|
| `String` | `{"type": "string"}` |
| `Int32`, `Int64` | `{"type": "integer", "format": "int32"}` / `"int64"` |
| `UInt8`, `UInt64` | `{"type": "integer", "minimum": 0, ...}` |
| `Float64` | `{"type": "number", "format": "double"}` |
| `Bool` | `{"type": "boolean"}` |
| `JSON::Any` | `{}`, any value |
| `Array(T)` | `{"type": "array", "items": T}` |
| `Hash(String, V)` | `{"type": "object", "additionalProperties": V}` |
| an enum | `{"type": "string", "enum": ["newest", "most_liked"]}`, the names JSON writes |
| `T?` | `{"anyOf": [T, {"type": "null"}]}` |
| a struct or class | `{"$ref": "#/components/schemas/Name"}`, its schema under `components.schemas` |

A struct's schema is an object with a property per field, named by the
field or its `JSON::Field` key. `required` lists the fields with neither a
default nor a nilable type. A field with `ignore: true` is left out, one
with `ignore_deserialize: true` is `readOnly` (it is written but never
read), one with `ignore_serialize: true` is `writeOnly`, and one with a
`converter:` is any value. A literal default (`= 3`, `= "draft"`,
`= false`) is the property's `default`. A struct inside a struct is a
schema of its own, referred to by `$ref`, and a type that holds itself is a
reference the second time.

A schema is named by the type's name without its module, generic arguments
joined with `_`: `App::Models::Page(App::Models::Note)` is `Page_Note`. Two
different types with the same name would be one schema, so building the
server raises, naming it: rename one.

A union of several types other than `nil` (`Int32 | String`) is any value;
its members are not the generator's to name.

## The docs page

`/docs` is one static HTML page that loads [Swagger UI](https://swagger.io/tools/swagger-ui/)
5 from the jsDelivr CDN (`https://cdn.jsdelivr.net/npm/swagger-ui-dist@5`)
and points it at the document. Nothing is bundled into the binary; a
browser that cannot reach the CDN shows an empty page while `/openapi.json`
keeps working. A `Content-Security-Policy` that allows only `'self'` (one
given to `SecurityHeadersHandler`'s `content_security_policy:`, say) must
also allow `cdn.jsdelivr.net` and the page's inline script on that path, or
serve the page with `docs: nil` and use another viewer.

## Checking the document

The document of `examples/json_api.iyi` passes
[openapi-spec-validator](https://github.com/python-openapi/openapi-spec-validator):

```sh
iyi run examples/json_api.iyi &
curl -s localhost:3000/openapi.json > openapi.json
python -m pip install openapi-spec-validator
python -m openapi_spec_validator openapi.json
# openapi.json: OK
```

The docs page is a client built from that same document: its "Try it out"
calls the running API.
