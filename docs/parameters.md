# Parameters

```iyi
get "/search" do |env|
  term = env.params.query["q"]? || ""
  "Results for " + term
end

post "/subscribe" do |env|
  email = env.params.body["email"]? || ""
  "Subscribed " + email
end
```

| Source | Access |
|---|---|
| Route segments (`:id`, `*path`) | `env.params.url` |
| Query string | `env.params.query` |
| `application/x-www-form-urlencoded` or `multipart/form-data` fields | `env.params.body` |
| `application/json` and `application/*+json` bodies | `env.params.json`, or `env.params.json_as(T)` for a type of your own |
| Uploaded files | `env.params.files`, `env.params.all_files` |

`url`, `query` and `body` are `Hash(String, String)` tables of percent-decoded
values; `env.params["name"]?` searches them in that order. Indexing without
`?` panics when the key is missing, so use `[]?` for optional values.
`env.params.raw_body` is the body as it arrived (empty for a
`multipart/form-data` request, whose files [stream to disk](transport.md#request-bodies)).

These are strings. To read one as a number or a flag, with a `422` naming
it when it is not one, use `env.params.int("id")`, `int64`, `float`, `bool`
or `string` ([One parameter at a time](typed-routes.md#one-parameter-at-a-time)),
or declare the route's captures, query string and body as types with
[typed routes](typed-routes.md).

A name sent more than once keeps its last value in the tables.
`env.params.query_all("tag")` and `env.params.body_all("tag")` return every
value, in the order sent, and an empty array when there is none; `body_all`
covers form and multipart text fields alike. A name is matched as sent, so
`?tag[]=a&tag[]=b` is `query_all("tag[]")`:

```iyi
get "/posts" do |env|
  tags = env.params.query_all("tag")   # ?tag=iyi&tag=web => ["iyi", "web"]
  "Tagged " + tags.join(", ")
end
```

A JSON object's members are in `env.params.json`, a `Hash(String, JSON::Any)`;
a top-level array is under the key `"_json"`. A request that declares JSON
and sends something that does not parse gets `400 Bad Request` before the
route runs, with the line and column where the body stopped making sense
(see [Typed JSON bodies](#typed-json-bodies)).

## Typed JSON bodies

`env.params.json_as(T)` reads the body into a type with `derive serializable`
(or anything `JSON.from_json` reads, such as `Array(Note)`), and answers
`T | BodyError`. Return the error and the client gets its status:

```iyi
import std/json::{serializable}
import web/iyi_web/validation::{BodyError, Validate, Validator}

struct NoteInput
  getter title : String
  getter priority : Int32 = 3
  getter tags : Array(String) = [] of String
  derive serializable
end

post "/notes" do |env|
  case input = env.params.json_as(NoteInput)
  in BodyError
    input
  in NoteInput
    env.status(201).json(save(input))
  end
end
```

`json_as` never panics on what the client sent. Kemal's
`NoteInput.from_json(env.request.body)` raises on a body of the wrong shape;
iyi's `JSON.from_json` panics, so the parsed body is first checked against
the type the way `derive serializable` reads it, and every field it would
refuse is reported at once:

| Body | Status | `BodyError` |
|---|---|---|
| Not declared JSON (no `application/json` or `application/*+json`) | `415` | `expected a JSON body (...)` |
| Empty, or not JSON | `400` | `malformed JSON: trailing comma in object at line 1, column 21` |
| A required field missing or `null`, a value of the wrong kind, an integer out of range, an unknown enum member | `422` | `fields`: `{"title" => "is required", "tags[1]" => "must be a string"}` |
| Failed the type's `Validate` rules | `422` | `fields`: one message per field |

A field with a default may be left out, and keeps its default for a `null`; a
field whose type admits `nil` may be left out or `null`. Nested fields are
named by path: `author.name`, `tags[1]`, `[0].title` for an array body.

Unless an `error` page takes it, a `BodyError` is answered with
`{"error": message, "fields": {...}}` when the request sent JSON or its
`Accept` asks for it, and with the message as plain text otherwise (see
[Errors that carry a status](errors.md#errors-that-carry-a-status)). The messages are
written for the client and shown in every environment.

## Validation

A type that implements `Validate` (`web/iyi_web/validation`) is checked once
it has been read, and `json_as` answers `422` with every failing field:

```iyi
impl Validate for NoteInput
  def validate(v : Validator) : Nil
    v.required("title", title)
    v.length("title", title, max: 80)
    v.range("priority", priority, min: 1, max: 5)
    v.length("tags", tags, max: 5)
    v.add("title", "is taken") if title_taken?(title)
  end
end
```

| Rule | Fails when | Message |
|---|---|---|
| `required(field, value)` | `nil`, a blank string or an empty array | `is required` |
| `length(field, value, min:, max:)` | a string has fewer or more characters, an array fewer or more items | `must be at least 3 characters`, `must have at most 5 items` |
| `range(field, value, min:, max:)` | a number is outside the bounds, inclusive; the bounds are of the value's type | `must be between 1 and 5`, `must be at least 1` |
| `format(field, value, regex, message = "is invalid")` | the regex does not match; it matches anywhere unless anchored with `\A` and `\z` | `is invalid` |
| `one_of(field, value, choices)` | the value is not among the choices | `must be one of: free, pro` |
| `add(field, message)` | always: a rule of your own | your message |

Every rule but `required` passes over a `nil`, so an optional field is
checked only when it was sent. A field keeps the first message it gets, so a
blank title is `is required` and not also too short. `v.valid?`, `v.errors`
and `v.failed?(field)` read what has been collected. Only the value read is
validated: a type it holds is checked by the outer type's `validate`.
`read_json(text, T)` does the same for a string that did not come from the
request.

## File uploads

```iyi
post "/avatar" do |env|
  if upload = env.params.files["avatar"]?
    env.text("Received " + upload.filename + ", " + upload.size.to_s + " bytes")
  else
    env.halt(422, "No file")
  end
end
```

Each uploaded file is written to a temporary file, in a new directory only
the server's account can open: `upload.path`, `upload.filename`,
`upload.content_type`, `upload.size`, `upload.headers` and `upload.read`
describe it, and the file is deleted once the response has been
sent. Files sent under a name ending in `[]` are all kept, in
`env.params.all_files["photos[]"]`. The filename is the client's, unchanged:
never join it to a directory path without cleaning it first.

A malformed `multipart/form-data` body gets `400`. More file parts than
`max_file_uploads`, or a text field larger than
`max_multipart_form_field_size`, gets `413 Content Too Large`.
