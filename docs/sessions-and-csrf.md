# Sessions and CSRF

`SessionHandler` keeps the session in a cookie, as kemal-session's cookie
engine and `Rack::Session::Cookie` do: the server stores nothing. The cookie
is encrypted with AES-256-GCM under a key derived from your secret, so the
client can neither read nor alter what it holds, and it carries its issue and
expiry times, so a copied cookie stops working on the server when it lapses.

```iyi
import web/iyi_web/session::{SessionHandler, session}

use SessionHandler.new(Program.env("SESSION_SECRET") || raise "SESSION_SECRET is not set")

post "/sign-in" do |env|
  session(env).regenerate
  session(env)["user"] = env.params.body["name"]? || ""
  env.redirect("/", 303)
end

get "/" do |env|
  user = session(env)["user"]?
  user ? "Signed in as " + user : "Signed out"
end

post "/sign-out" do |env|
  session(env).clear
  env.redirect("/", 303)
end
```

The secret must be at least 32 bytes; a shorter one stops the program when
the handler is made. `SessionHandler.new` also takes:

| Option | Default | |
|---|---|---|
| `old_secrets` | `[] of String` | Secrets being retired. A cookie sealed under one is read, and sent back sealed under the current secret, so a secret can be replaced without signing anyone out. |
| `cookie_name` | `"iyi_web.session"` | |
| `max_age` | `14 * 86400` | Seconds. The cookie's `Max-Age`, and the server's own limit on a cookie's age. |
| `path`, `domain` | `"/"`, `""` | |
| `secure` | `false` | Set it behind HTTPS. |
| `http_only` | `true` | |
| `same_site` | `"Lax"` | `"None"` needs `secure: true`. |

`session(env)` answers the request's `Session`: `[]`, `[]?` and `[]=` for
strings, `set(key, value)` for anything `JSON.to_json` writes (read back as
`JSON::Any` with `json?(key)`), `delete`, `has_key?`, `keys`, `clear`, and
`id`, a random id for anything kept about the session elsewhere.
`regenerate` gives the session a new id and keeps its values: call it at
sign-in. A cookie that was altered, has lapsed, or was sealed under a secret
that is no longer listed is an empty session.

The response sets the cookie only when the session changed, and deletes it
when the session was cleared. A cookie larger than the 4096 bytes browsers
keep is refused with a `500`: keep an id in the session and the data on the
server. The cookie is written after the route returns, so a route that
streams calls `save_session(env)` before its first `env.response.flush`; a
change made after the headers went out cannot reach the client, and is
reported on the error stream.

## CSRF

`CSRFHandler`, kemal-csrf's equivalent, keeps a random token in the session
and refuses with `403` every `POST`, `PUT`, `PATCH`, `DELETE` and other
unsafe request that does not send it back in the `authenticity_token` form
field or the `X-CSRF-Token` header. `GET`, `HEAD`, `OPTIONS`, `TRACE` and
`QUERY` pass. It needs a `SessionHandler` before it.

```iyi
import web/iyi_web/session::{SessionHandler}
import web/iyi_web/csrf::{CSRFHandler, csrf_tag}

use SessionHandler.new(secret)
csrf = CSRFHandler.new
csrf.exclude ["/api/*"], "*"
use csrf

get "/note" do |env|
  "<form method='post'>" + csrf_tag(env) + "<input name='note'><button>Save</button></form>"
end
```

`csrf_tag(env)` is a hidden input holding the token; `csrf_token(env)` is the
token alone, for a script to send in the header. Each call masks the token
with fresh random bytes, so no two pages carry the same string and a
compressed response does not give it away. `CSRFHandler.new` takes `field`,
`header` and the refusal's `message` (default `"Forbidden (CSRF)"`). `only`
and `exclude` choose the requests it checks; their method defaults to `GET`,
which is never checked, so name the method or `"*"`.
