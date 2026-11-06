# Modules

Paths as written with the short name `web`. Without a short name, a module is
written with the whole path: `github.com/sdogruyol/iyi-web/iyi_web/dsl`.

| Module | Provides |
|---|---|
| `web/iyi_web/dsl` | Routes, filters, `error`, `mount`, `use`, `sse`, `ws`, `render`, `run` and the setting shorthands |
| `web/iyi_web/router` | `Router`, `RouteHandler` |
| `web/iyi_web/app` | `build_server`: the server `run` builds, for a test or a program of its own |
| `web/iyi_web/context` | `Context` |
| `web/iyi_web/request` | `Request` (with `remote_address` and `tls?`) |
| `web/iyi_web/response` | `Response` |
| `web/iyi_web/params` | `Params`, `json_as` |
| `web/iyi_web/validation` | `BodyError`, `Validate`, `Validator`, `read_json`: typed JSON bodies and their checks |
| `web/iyi_web/coerce` | `ParamError`, `decode_param`: parameters read as `Int32`, `Int64`, `Float64`, `Bool`, enums ([Typed routes](typed-routes.md)) |
| `web/iyi_web/typed` | What a typed route reads before its block runs (`path:`, `query:`, `headers:`, `body:`) and how it answers (`response:`) |
| `web/iyi_web/openapi` | `OpenAPIInfo`, `SecurityScheme`, `KeyLocation`, `openapi_document`, `docs_page` ([OpenAPI](openapi.md)) |
| `web/iyi_web/deps` | `Dep`: providers a route names with `deps:` ([Dependencies and auth](dependencies-and-auth.md)) |
| `web/iyi_web/auth` | `bearer_auth`, `api_key_auth`, `jwt_auth`, `password_grant`, `token_response`, `AuthError`, `OAuthError` |
| `web/iyi_web/jwt` | `JWT`, `Claims`, `JWTError`: HS256 JSON Web Tokens |
| `web/iyi_web/multipart` | `FileUpload` and the `multipart/form-data` parser |
| `web/iyi_web/cookies` | `CookieJar` |
| `web/iyi_web/headers` | `Headers` |
| `web/iyi_web/body` | `IntoBody` |
| `web/iyi_web/handler` | `Handler`, `chain` |
| `web/iyi_web/config` | `Config`, `config` |
| `web/iyi_web/cli` | `CLIParser` |
| `web/iyi_web/event_stream` | `EventStream` |
| `web/iyi_web/websocket` | `WebSocket`, `Frame`, `FrameError` |
| `web/iyi_web/templates` | `render`, `content_for`, `yield_content`, `raw`, `SafeHTML` ([Templates](templates.md)) |
| `web/iyi_web/compress` | `CompressHandler` |
| `web/iyi_web/content_coding` | `Accept-Encoding` negotiation, `Vary` and `ETag` helpers, `COMPRESS_MIN_SIZE` |
| `web/iyi_web/failure` | `StatusError`, the built-in error pages |
| `web/iyi_web/status` | `HttpError`, `phrase` |
| `web/iyi_web/range` | `Range` header parsing and `206` responses |
| `web/iyi_web/file_body` | `respond_file`, `respond_file_encoded`, `FILE_CHUNK_SIZE`: a file sent from disk, whole, by range or compressed |
| `web/iyi_web/cors` | `CORSHandler` |
| `web/iyi_web/override` | `OverrideMethodHandler` |
| `web/iyi_web/static` | `StaticHandler` |
| `web/iyi_web/log` | `LogHandler`, `Logger`, `StdoutLogger` |
| `web/iyi_web/basic_auth` | `BasicAuthHandler`, `basic_credentials` |
| `web/iyi_web/security_headers` | `SecurityHeadersHandler` |
| `web/iyi_web/request_id` | `RequestIdHandler`, `acceptable_id?` |
| `web/iyi_web/rate_limit` | `RateLimitHandler`, `monotonic_ms` |
| `web/iyi_web/harness` | `http_request`, `form_request`, `dispatch`, `routes` |
| `web/iyi_web/session` | `SessionHandler`, `Session`, `session`, `save_session` |
| `web/iyi_web/csrf` | `CSRFHandler`, `csrf_token`, `csrf_tag` |
| `web/iyi_web/store` | `Store`, `HashStore`, `ArrayStore`: state every worker shares, behind one lock ([Store](state.md)) |
| `web/iyi_web/lifecycle` | `Lifecycle`, `lifecycle_hook`: `on_start` and `on_stop` ([Lifecycle](lifecycle-and-background.md)) |
| `web/iyi_web/background` | `Background`, `background_runner`: `env.background { }`, work done after the response |
| `web/iyi_web/metrics` | `MetricsHandler`, `METRICS`, `Counter`, `Gauge`, `Histogram`: Prometheus metrics ([Observability](observability.md)) |
| `web/iyi_web/tracing` | `TraceHandler`, `OtlpHttpExporter`, `JsonLinesExporter`, `current_span`: W3C trace context tracing |
| `web/iyi_web/spec` | `describe`, `it`, `context`, `panics?`: grouping for `*_test.iyi` programs |
| `web/iyi_web/token` | `random_hex`, `random_bytes`, `encode_base64url`, `decode_base64url?`: random tokens nobody can guess, and base64url for carrying them |
