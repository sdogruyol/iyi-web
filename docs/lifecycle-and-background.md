# Lifecycle hooks

Some work happens around requests rather than inside them: what an
application does once when it starts and once when it stops.

## Start and stop hooks

```iyi
import web/iyi_web/dsl::*

on_start do
  DB.connect(Program.env("DATABASE_URL") || "postgres://localhost/app")
end

on_stop do
  DB.close
end

get "/" do |env|
  "hello"
end

run
```

`on_start` hooks run when `run` starts, in the order they were written,
before the server is bound: nothing is accepted until every one of them has
returned. A hook whose block answers an error value (any type implementing
`Error`) or panics stops the start. The hooks after it do not run, the server
never says it is ready, and the program exits with status 1, naming the hook
by file and line:

```
[development] iyi-web could not start: on_start (app.iyi:3) failed: database unreachable
[development] iyi-web could not start: on_start (app.iyi:3) panicked: config file missing
```

A server that cannot reach its database says so before it takes traffic,
not on the first request.

`on_stop` hooks run once the server has stopped, whether by `stop` or by the
first INT or TERM (Ctrl-C or Ctrl-Break on Windows):

1. the listener closes and the requests in flight finish, for up to
   `shutdown_timeout` seconds;
2. the `on_stop` hooks run, the last written first, so what was opened last
   is closed first.

A stop hook that fails, by an error value or a panic, is reported on
standard output and the others still run:

```
[development] iyi-web: on_stop (app.iyi:9) panicked: flush failed
```

With `IYI_WEB_ENV=test`, `run` binds the server and returns without serving,
and no hook runs.

### What a hook may capture

A hook's block is checked where it is written, as a route's is: it usually
touches the state the routes use, and those run on every worker. A hook that
captures a bare `Array` is refused, naming the variable and the two ways
out:

```
Error: the block Dsl.on_start keeps, which may run on other threads captures
`names : Array(String)`, which is not Share: ... Put it behind a lock, a
`Mutex(Array(String))` (std/mutex), or pass `workers: 1` so the block runs
on one thread (SPEC.md III.4.4)
```

`on_start workers: 1 do ... end` keeps the block unchecked. Unlike a route
registered that way, it does not put the server on one thread: a hook runs
once, on the thread that calls `run`, while no request is being served.

### Hooks in a test

`web/iyi_web/lifecycle` is the same machinery as a value. A `Lifecycle`
holds hooks and runs them, answering what failed instead of exiting, so a
test can check a hook without starting a server:

```iyi
import web/iyi_web/lifecycle::{Lifecycle, lifecycle_hook}

hooks = Lifecycle.new
hooks.add_start(lifecycle_hook { Migrations.check }, "app.iyi:3")
assert hooks.run_start.nil?         # or "on_start (app.iyi:3) failed: ..."
assert hooks.run_stop.empty?        # the messages of the stop hooks that failed
```

`lifecycle` (or `LIFECYCLE`) is the application's own, the one `on_start`
and `on_stop` add to.
