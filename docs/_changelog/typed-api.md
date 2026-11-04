### Added

- Typed parameter lookups: `env.params.int("id")`, `int64`, `float`,
  `bool` and `string` answer the value or a `ParamError` (422, naming the
  parameter), with `from: :url | :query | :body` and `default:`. Reading
  is strict: `"12abc"`, `" 12"` and `""` are not integers, `nan` and
  `inf` are not numbers (`iyi_web/coerce`, `iyi_web/params`).
- Typed routes: `path:`, `query:`, `headers:`, `body:` and `deps:` on
  every route method, in the DSL and on `Router`. The block gets each
  value after `env`, typed from the options given; what cannot be read is
  answered before the block runs - a `ParamError` (422) naming every wrong
  parameter, or the body's `BodyError` (400, 415, 422). Parameter structs
  use `derive serializable`: defaults and nilable fields are optional,
  enums take their names, `Array(T)` takes a repeated query key, and
  `Validate` runs once they read. `path: Int32` reads a route's one
  capture (`iyi_web/typed`, `iyi_web/router`, `iyi_web/dsl`).
- `response: T` writes the block's answer as JSON and checks its type
  when the program is compiled; `status:` is the status a route answers
  with unless its block sets another, on plain routes too.
- OpenAPI 3.1: `openapi(title, version)` (and `Router#openapi`) serves
  `/openapi.json`, made from every route, mount and namespace, with
  parameters, request and response schemas derived from the types at
  compile time (`required`, nested structs as `components.schemas`,
  arrays, enums, nullable, `JSON::Field` keys and ignores), `summary:`,
  `description:`, `tags:` and security; and `/docs`, Swagger UI 5 loaded
  from the jsDelivr CDN (`iyi_web/openapi`). The document of
  `examples/openapi_auth.iyi` passes openapi-spec-validator.
- Dependencies: `Dep.new { |env| ... }` providers whose error ends the
  request with its status before the route runs, composed with
  `resolve(env)!`, run once per request, and combined with `Dep.all(...)`
  into a named tuple (`iyi_web/deps`).
- Auth providers: `bearer_auth`, `api_key_auth` (header, query or
  cookie), `jwt_auth` and `oauth2_password_bearer`, with `bearer_token`,
  `api_key`, `password_grant`, `token_response`, `AuthError` and
  `OAuthError`; each provider's scheme is listed under
  `components.securitySchemes` and on its routes (`iyi_web/auth`).
- `JWT.sign` and `JWT.verify` for HS256 tokens: `alg` must be `HS256`
  (`none` and the rest refused), constant-time signature check, `exp`,
  `nbf` and `iat` with `leeway:`, optional `issuer:` and `audience:`,
  `Claims` or a payload type of the application's own; secrets under 32
  bytes are refused (`iyi_web/jwt`).
- `Params#query_pairs`, `json_errors(root, T)` and `enum_name` in
  `iyi_web/validation`, used by the above.
- `examples/openapi_auth.iyi`: a notes API with an OAuth2 password flow
  issuing JWTs, user and admin providers, an API-key client and the docs
  page.

### Changed

- `examples/typed_json.iyi` and `examples/json_api.iyi` are typed routes:
  no route parses a parameter or matches on `BodyError` by hand, and
  `json_api` serves its OpenAPI document.
- Each route method of `Router` and the DSL is now a set of overloads, one
  per combination of the typed options, and takes `response:`, `status:`,
  `summary:`, `description:` and `tags:`. `get "/" do |env| ... end`
  keeps working unchanged.
