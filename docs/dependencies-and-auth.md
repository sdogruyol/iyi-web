# Dependencies and auth

## Providers

A provider is what a route needs before it can run - the signed-in user, a
database handle, a checked API key - written once and named on every route
that needs it. FastAPI calls it `Depends`; here it is a `Dep`:

```iyi
import web/iyi_web/dsl::*
import web/iyi_web/context::{Context}
import web/iyi_web/deps::{Dep}
import web/iyi_web/auth::*

def current_user(env : Context) : User | AuthError
  token = bearer_token(env)!
  find_user_by_token(token) || AuthError.new(401, "unknown token")
end

CURRENT_USER = Dep.new { |env| current_user(env) }

get "/me", deps: CURRENT_USER do |env, user|
  user.name
end
```

The block gets the provider's value with its errors taken out: `user` is a
`User`, not a `User | AuthError`. A provider that answers an error ends the
request with that error's status before the route runs, so a 401 or a 403 is
decided in one place:

```sh
curl localhost:3000/me                                # 401 missing bearer token
curl localhost:3000/me -H 'Authorization: Bearer ok'  # 200 ada
```

A provider is usually a `def` and a constant. In the `def`, `!` hands an
error on, so providers compose: one may use another with `resolve`.

```iyi
def admin(env : Context) : User | AuthError
  user = CURRENT_USER.resolve(env)!               # its 401 stays a 401
  user.admin ? user : AuthError.new(403, "admins only")
end

ADMIN = Dep.new { |env| admin(env) }

delete "/notes/:id", path: Int32, deps: ADMIN, status: 204 do |env, id, admin|
  remove_note(id)
  nil
end
```

Write the error types out, `User | AuthError` or `User | AuthError |
DbError`: a trait such as `HttpError` in a union is not an error member, so
`!` would not see it. Any type that implements `Error` works; one that
implements `HttpError` brings its own status, any other is a 500.

**Once per request.** A provider runs at most once per request, however
many providers ask for it: `ADMIN` above calls `CURRENT_USER`, and a route
that depends on both looks the user up once. The answer, error or value, is
kept on the context for the rest of the request.

**Before everything else.** Providers run before `path:`, `query:`,
`headers:` and `body:` are read, so a request without its token gets `401`
even when its body is also wrong ([Typed routes](typed-routes.md)). They are
the last value the block gets.

**On every core.** A provider runs on whichever worker serves the request,
several at once, so `Dep.new` checks its block where it is written, as a
route's is: state it shares goes behind a `Mutex` or in an `Atomic`. A
`Dep` is `Share` and may be a constant.

### Several providers

`Dep.all` makes one provider of several. Its value is a named tuple of
theirs, each typed as its provider answers it; they run in the order
written and the first error ends the request:

```iyi
get "/notes", deps: Dep.all(user: CURRENT_USER, db: DB) do |env, deps|
  deps[:db].notes_of(deps[:user])
end
```

`deps: {user: CURRENT_USER, db: DB}` is not accepted: a route's block is
typed from the arguments beside it when it is registered, a provider carries
the type of its value, and the named tuple of values a named tuple of
providers would give is a type no signature can spell. `Dep.all` builds that
type once, as a provider of its own.

### Providers in the OpenAPI document

`Dep.new(security: ...)` names the security scheme a provider checks. Every
route that depends on it lists the scheme under `security`, and the
document lists it under `components.securitySchemes`
([OpenAPI](openapi.md)). A provider built on another passes the other's on:

```iyi
CURRENT_USER = Dep.new(security: TOKEN.security) { |env| current_user(env) }
```

| Scheme | Made with |
|---|---|
| Bearer token | `SecurityScheme.bearer(name = "bearerAuth", format: "JWT")` |
| HTTP Basic | `SecurityScheme.basic(name = "basicAuth")` |
| API key | `SecurityScheme.api_key("X-API-Key", KeyLocation::Header, name = "apiKeyAuth")` |
| OAuth2 password flow | `SecurityScheme.oauth2_password("/token", {"notes" => "Read and write notes"})` |

The providers below come with theirs.

## Auth providers

`web/iyi_web/auth` reads credentials the way the HTTP and OAuth2
specifications say, as providers and as plain functions.

| Provider | Value | Scheme in the document |
|---|---|---|
| `bearer_auth` | the token of `Authorization: Bearer <token>` | `bearerAuth`, http bearer |
| `api_key_auth("X-API-Key")` | the key; `KeyLocation::Query` or `::Cookie` for the other places | `apiKeyAuth`, apiKey |
| `jwt_auth(secret)` | the token's `Claims`, verified | `bearerAuth`, http bearer, `bearerFormat: JWT` |
| `jwt_auth(secret, MyClaims)` | the payload read into `MyClaims` | the same |
| `oauth2_password_bearer("/token")` | the bearer token | `OAuth2PasswordBearer`, oauth2 password flow |

Each refuses a missing credential with `401`. A bearer token's refusal
carries `WWW-Authenticate: Bearer realm="api"`; a JWT that was sent and
refused, `Bearer realm="api", error="invalid_token", error_description="token
has expired"` (RFC 6750 §3.1). A value is only what was sent: whether a key
or a token's subject means anyone is the application's to decide, in a
provider of its own:

```iyi
STATS_KEY = api_key_auth("X-API-Key")

def stats_client(env : Context) : String | AuthError
  key = STATS_KEY.resolve(env)!
  Subtle.constant_time_compare(key, EXPECTED_STATS_KEY) ? "stats" : AuthError.new(401, "unknown API key")
end

STATS = Dep.new(security: STATS_KEY.security) { |env| stats_client(env) }
```

Compare a secret with `Subtle.constant_time_compare` (`std/crypto`), never
`==`, which stops at the first byte that differs.

The functions under the providers are there for a filter or a route of your
own: `bearer_token(env) : String | AuthError` and
`api_key(env, "X-API-Key", KeyLocation::Header) : String | AuthError`.
`AuthError.new(403, "admins only")` is the error for a credential that is
valid but not enough.

## JWT

`web/iyi_web/jwt` signs and checks JSON Web Tokens with HMAC-SHA256
(`HS256`), the one algorithm a server that issues and checks its own tokens
needs:

```iyi
import std/time::{Span}
import web/iyi_web/jwt::{JWT, Claims, JWTError}

token = JWT.sign(Claims.new(sub: "ada", expires_in: Span.new(hours: 1), scope: "notes"), SECRET)

case claims = JWT.verify(token, SECRET)
in Claims   then claims.sub        # "ada"
in JWTError then claims.message    # "token has expired", ...
end
```

`verify` accepts a token only when every check passes, and says which one
failed:

| Check | Refusal |
|---|---|
| three base64url parts, none empty (an unsigned `alg: none` token has an empty one) | `malformed token` |
| a header that is a JSON object | `malformed token header` |
| `alg` exactly `HS256`; `none`, `HS512`, `RS256`, `hs256` are refused before the signature is read | `unsupported token algorithm: only HS256 is accepted` |
| no `crit` header | `unsupported token header: crit` |
| the signature, compared in constant time | `invalid token signature` |
| a payload that is a JSON object | `malformed token payload` |
| `exp` still ahead | `token has expired` |
| `nbf` passed | `token is not valid yet` |
| `iat` not in the future | `token was issued in the future` |
| `iss` / `aud`, when `issuer:` / `audience:` are given | `token issuer is not accepted`, `token audience is not accepted` |
| the payload reads into the type asked for | `invalid token claims: ...` |

`exp`, `nbf` and `iat` are optional, and checked when present, each give or
take `leeway:` seconds (default `0`). `JWTError` is an `HttpError` with
status 401.

`Claims` holds the registered claims (`sub`, `iss`, `aud`, `exp`, `nbf`,
`iat`, `jti`) and OAuth's `scope`; `claims.scopes` splits it,
`claims.audiences` reads `aud` whether it is one string or several.
`Claims.new(sub:, expires_in:, iss:, aud:, scope:, jti:)` sets `iat` to now.
Any type that `JSON.to_json` writes can be signed, and `verify(token,
secret, MyClaims)` reads the payload into a type of your own with the same
checks a JSON body gets.

The secret must be at least 32 bytes, as RFC 7518 §3.2 requires of an HS256
key; a shorter one panics where it is used (`JWT.sign`, `JWT.verify`,
`jwt_auth`). Keep it out of the source: whoever knows it can sign a token for
anyone.

## OAuth2 password flow

The flow FastAPI's tutorial uses, and the one Swagger UI's "Authorize"
dialog speaks: a client posts a username and a password as a form to a
token route, and sends the token it gets as a bearer token.

```iyi
import std/password::{Bcrypt}

TOKEN = jwt_auth(SECRET, security: SecurityScheme.oauth2_password("/token"))

post "/token" do |env|
  grant = password_grant(env)
  next grant if grant.is_a?(OAuthError)
  account = find_account(grant.username)
  if account && Bcrypt.verify(grant.password, account.password_hash)
    token = JWT.sign(Claims.new(sub: account.name, expires_in: Span.new(hours: 1)), SECRET)
    token_response(env, token, Span.new(hours: 1))
    nil
  else
    OAuthError.new("invalid_grant")
  end
end

get "/me", deps: TOKEN do |env, claims|
  claims.sub || ""
end
```

`password_grant(env)` reads RFC 6749 §4.3.2's form - an
`application/x-www-form-urlencoded` body with `grant_type=password`, a
`username`, a `password`, and maybe `scope`, `client_id` and
`client_secret` - into a `PasswordGrant`, or answers an `OAuthError`:
`invalid_request` for a missing field or another body type,
`unsupported_grant_type` for another grant. A wrong password is the route's
to refuse, with `OAuthError.new("invalid_grant")`. An `OAuthError` is a 400
(401 for `invalid_client`) whose message is the RFC's error code, so a
client that accepts JSON gets `{"error": "invalid_grant"}`, as §5.2 has it.

`token_response(env, token, expires_in, scope)` writes §5.1's answer,
`{"access_token": ..., "token_type": "bearer", "expires_in": 3600}`, with
`Cache-Control: no-store`.

`examples/openapi_auth.iyi` puts all of it together: accounts with bcrypt
hashes, the token route, a user provider and an admin provider built on the
JWT one, an API-key provider for a machine client, and the docs page whose
"Authorize" signs in.
