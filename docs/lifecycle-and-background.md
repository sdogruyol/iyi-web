# Lifecycle hooks and background tasks

Two things happen around requests rather than inside them: the work an
application does once when it starts and once when it stops, and the work a
request starts and does not wait for. `examples/observability.iyi` uses both.

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
2. the background tasks still queued or running finish, for up to
   `shutdown_timeout` seconds more, and what is still running then is
   cancelled;
3. the `on_stop` hooks run, the last written first, so what was opened last
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

## Background tasks

```iyi
post "/signup" do |env|
  email = env.params.body["email"]
  env.background { Mailer.welcome(email) }
  env.status(201).text("welcome")
end
```

`env.background { }` inside a route, or `background { }` anywhere, runs the
block off the request path: the call returns at once, the response goes
out, and the block runs on whichever worker is free. FastAPI's
`BackgroundTasks` runs its tasks after the response on the request's own
event loop; here they run in parallel with every request, on every core.

- **A panic stays in its task.** It is caught at the task's boundary,
  reported (`background task panicked: MESSAGE` on standard error, after
  the runtime's own panic line), counted, and the server goes on.
- **The stop waits for them.** Queued and running tasks get up to
  `shutdown_timeout` seconds after the requests have drained; then those
  still running are cancelled - a `sleep` or a socket wait answers
  `Cancelled` - and the `on_stop` hooks run. A task computing without ever
  waiting is not interrupted; the stop waits for it.
- **Outside a running server** - a test through `web/iyi_web/harness`, a
  script, an `on_start` hook, or once the stop has begun - nothing would
  ever take a queued task, so `background` runs the block at once, on the
  caller's task, still isolated: a panic is reported and the caller goes
  on. A harness test sees the work done when `dispatch` returns.

### What a background block may capture

The block runs on another worker, so it is checked as a route's block is,
and there is no `workers: 1` way past it. Copy what it needs from the
request into locals first - `env` itself is the request's, not `Share` - and
keep shared state in a [`Store`](state.md), an `Atomic` or behind a `Mutex`:

```iyi
SENT = Atomic(Int32).new(0)

post "/orders" do |env|
  id = env.params.body["id"]
  env.background do
    Receipts.send(id)
    SENT.add(1)
  end
  "queued"
end
```

### The runner as a value

`web/iyi_web/background` exports `Background`, the runner, and
`BACKGROUND`, the process's own, which `run` starts beside the listener. A
test or a program of its own can run one:

```iyi
import web/iyi_web/background::{Background}

pool = Background.new
pool.on_panic { |message| ERRORS.update { |e| e << message; nil } }
group do |g|
  g.spawn do
    pool.run                       # takes jobs until close
    0
  end
  g.spawn do
    pool.spawn { work }
    pool.close(Span.seconds(5))    # waits for the jobs, at most 5 s
    0
  end
end
pool.completed                     # jobs that ended, pool.panics those that panicked
```

`pending` is the number queued or running, `running?` whether a runner is
taking jobs, and `closing?` whether one is finishing: a job that waits on
purpose, such as a batch of spans held back for more to arrive, stops
waiting when it sees it.
