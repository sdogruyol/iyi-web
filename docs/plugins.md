# Writing and publishing a plugin

A plugin for iyi-web is an iyi package that exports one or more handlers - a
class with a `call` method that `use` puts in the chain - and, when it needs
them, its own metrics, hooks and background work. Nothing registers it but
the application's own `use` line: there is no global plugin list, and a
plugin is imported by name like any other module.

This guide builds one, `TimingHandler`: it times each request, adds a
`Server-Timing` header and counts slow requests.

## The handler

```iyi
# iyi_web_timing/timing.iyi
module iyi_web_timing/timing

import std/time::{Time}
import web/iyi_web/handler::{Handler}
import web/iyi_web/context::{Context}
import web/iyi_web/headers::{Headers}

pub class TimingHandler < Handler
  @header : String
  @slow_ms : Float64
  @slow : Atomic(Int32)

  def initialize(@header : String = "Server-Timing", @slow_ms : Float64 = 500.0)
    super()
    raise "TimingHandler: invalid header name #{@header.inspect}" unless Headers.valid_name?(@header)
    raise "TimingHandler: slow_ms must be positive" unless @slow_ms > 0
    @slow = Atomic(Int32).new(0)
  end

  pub def slow_requests : Int32
    @slow.get
  end

  pub def call(ctx : Context) : Nil
    return call_next(ctx) unless applies?(ctx)
    started = Time.monotonic
    call_next(ctx)
    took = (Time.monotonic - started).total_milliseconds
    @slow.add(1) if took >= @slow_ms
    ctx.set("timing.ms", took)
    ctx.response.headers[@header] = "app;dur=" + took.round(3).to_s
  end
end
```

The application:

```iyi
import web/iyi_web/dsl::*
import timing/iyi_web_timing/timing::{TimingHandler}

timing = TimingHandler.new(slow_ms: 250.0)
timing.exclude ["/health"]
use timing, 0
```

### The handler API

| Member | What it is for |
|---|---|
| `call(ctx)` | Runs for every request that reaches the handler's place in the chain. |
| `call_next(ctx)` | Runs the rest of the chain - later handlers, then the router - and returns when the response is ready. Code after it sees the status, headers and body. Not calling it ends the chain: answer with `ctx.halt(status, body)` or by setting the response. |
| `only(paths, method = "GET")`, `exclude(paths, method = "GET")` | Record which requests the handler is for, in the filter path syntax (exact, `:name`, `/*` prefix); `"*"` for every method. The application calls them on your handler; you may call them in `initialize` for a default. |
| `applies?(ctx)` | Whether this request is one the handler is for: no `only` rule or one that matches, and no `exclude` rule that matches. Start `call` with `return call_next(ctx) unless applies?(ctx)`, as every built-in handler does, so `only` and `exclude` mean the same on yours. |
| `ctx.set(key, value)`, `ctx.get?(key)`, `ctx.get?(key, Type)` | Per-request values for later handlers and the route. Prefix keys with the plugin's name (`"timing.ms"`) so two plugins never share one. Any type can be stored and read back by type. |
| `ctx.route_pattern` | After `call_next`, the route that matched as it was declared (`/users/:id`), or nil. Label metrics and spans with it, never with the raw path. |

Where it sits matters. `use handler` puts it after request logging and
static files; `use handler, 0` first, so it sees static files and the
requests other handlers answer themselves; `use "/api", handler` only under
a prefix. Say in your README where yours belongs.

## The Share rule

A server with more than one worker calls one handler object from every core
at once. So a handler `use` takes must be `Share`, and the compiler checks
it at the application's `use` line:

- **No field assigned after `initialize`.** A field is set once, in the
  constructor, and only read afterwards. `property`, `setter` or an
  `@count += 1` in `call` makes the handler not `Share`, and the refusal
  names the field.
- **Every field's type `Share` itself.** Strings, numbers, `Bool`, structs
  of those, `std/list`'s `List` for a table nothing writes, `Atomic(T)` for
  a count, `std/mutex`'s `Mutex(T)` or iyi-web's `Store(T)`
  ([state](state.md)) for anything that changes, `SharedProc` for a
  callback. An `Array` or a `Hash` field is refused even if nothing writes
  it: copy it into a `List` in `initialize`.
- **Callbacks are checked where they are written.** A def that keeps a
  block the application gives it is marked `@[Share]`, and keeps it as a
  `SharedProc`, so the application's block is checked at its own line:

```iyi
import std/shared_proc::{SharedProc}

pub class Gate < Handler
  @allow : SharedProc(Context, Bool)

  def initialize(@allow : SharedProc(Context, Bool))
    super()
  end

  @[Share]
  def self.new(&block : Context -> Bool) : Gate
    new(SharedProc(Context, Bool).of { |ctx| block.call(ctx) })
  end

  pub def call(ctx : Context) : Nil
    return call_next(ctx) unless applies?(ctx)
    @allow.call(ctx) ? call_next(ctx) : ctx.halt(403, "Forbidden")
  end
end

use Gate.new { |ctx| ctx.request.headers["X-Role"]? == "admin" }
```

An application whose handler cannot be `Share` passes `use handler,
workers: 1`, which keeps it unchecked and serves the whole application on
one thread - say in your README if yours needs that, and why.

## Configuration

Take settings as constructor arguments with defaults, named so the
application's line reads well (`TimingHandler.new(slow_ms: 250.0)`), and
check them there: a bad value is a bug in the application, so `raise` with
the plugin's name and the value. It panics at start-up, on the `use` line,
before any request. For a value from the environment, let the application
read it and pass it in; a plugin that reads `Program.env` itself surprises
its tests.

What a plugin needs from the application's settings, `web/iyi_web/config`'s
`config` has, read in `initialize`: `config.env`, `config.app_name`. A
server on more than one worker copies its settings when it starts, so read
them once, not per request.

## Metrics, hooks and background work

A plugin may use the rest of iyi-web the way an application does:

- **Metrics.** Register families in `initialize`, on a registry the
  application may pass (`registry : MetricsRegistry = METRICS`), named with
  the plugin's prefix (`timing_slow_requests_total`). Registering the same
  name twice with the same kind and labels answers the family already
  there, so two instances share it. See [observability](observability.md).
- **Work after the response.** `ctx.background { }` sends a block to the
  background runner; see [lifecycle and background](lifecycle-and-background.md).
  A plugin that buffers - an exporter, an audit log - drains its buffer
  from a background task, which the server's stop waits for.
- **Start and stop.** A plugin should not register hooks behind the
  application's back. Give it a method (`flush`, `close`) and show the
  application the line: `on_stop { audit.flush }`.

## Testing with the harness

`web/iyi_web/harness` runs requests through a chain in-process, without a
socket: build the chain with your handler in front of a router, dispatch,
and read the context.

```iyi
# iyi_web_timing/timing_test.iyi
module iyi_web_timing/timing_test

import web/iyi_web/handler::{chain}
import web/iyi_web/harness::*
import web/iyi_web/spec::*
import iyi_web_timing/timing::{TimingHandler}

describe "TimingHandler" do
  it "times the request and counts the slow ones" do
    timing = TimingHandler.new(slow_ms: 100.0)
    timing.exclude ["/health"]
    app = chain([timing, routes { |r|
      r.get "/slow" do |env|
        sleep(150)
        "done"
      end
      r.get "/health" do |env|
        "ok"
      end
    }])
    ctx = dispatch(app, "GET", "/slow")
    assert ctx.response.headers["Server-Timing"].starts_with?("app;dur=")
    assert_eq 1, timing.slow_requests
    assert !dispatch(app, "GET", "/health").response.headers.has_key?("Server-Timing")
  end

  it "refuses a header name no response can carry" do
    assert panics? { TimingHandler.new(header: "Server Timing") }
  end
end
```

`http_request(method, path, query, body, content_type)` builds a request
with a body or headers to set; `dispatch(handler, request)` sends it.
Test what the handler decides - boundaries, the requests it leaves alone,
the configuration it refuses - not that `call_next` was called.

Check the Share rule too: write the line an application would,
`use TimingHandler.new` with the DSL imported, in a program of its own and
`iyi check` it with no warning. iyi-web's own `iyi_web/refused_test.iyi`
does this with `iyi check -f json` for the programs it expects refused.

## Packaging

A plugin is an iyi package: a git repository with an `iyi.mod` at its root
and `vX.Y.Z` tags.

```
iyi-web-timing/
  iyi.mod
  iyi_web_timing/
    timing.iyi
    timing_test.iyi
  README.md
```

```
module github.com/you/iyi-web-timing
require github.com/sdogruyol/iyi-web v0.5.1 as web
```

- **The module path is the repository.** `iyi get` clones
  `https://github.com/you/iyi-web-timing.git` at the tag it chose. A
  package's modules live under its last path segment with `-` as `_`, so
  keep them in `iyi_web_timing/`, as iyi-web keeps its own in `iyi_web/`.
- **Require iyi-web**, with the lowest version your plugin needs: iyi
  resolves versions by minimal version selection, so an application on a
  newer iyi-web uses its own and yours still builds against it. `as web`
  gives your files the short `web/iyi_web/...` paths the examples here use.
- **Export with `pub`.** Only what a module marks `pub` can be imported;
  keep helpers private.
- **Tag releases** `v0.1.0`, `v0.2.0`, ...: `iyi get` picks the highest
  release tag, and a breaking change is a new minor version before 1.0.
- **Document the `use` line**, where it belongs in the chain, its
  arguments, and whether it needs `workers: 1`.

An application then adds it with one command and imports it by name:

```sh
iyi get github.com/you/iyi-web-timing --as timing
```

```iyi
import timing/iyi_web_timing/timing::{TimingHandler}
```

The application imports iyi-web itself too: a dependency's imports are its
own, and never bring names into the application.
