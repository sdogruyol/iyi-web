# Every core

`run` serves each connection as a parallel task on a pool of worker
threads (iyi's `spawn_parallel`, SPEC.md III.4.13): whichever worker is
free takes it, so a CPU-bound route - a bcrypt check, a template - uses
the machine rather than one thread. The pool has one worker per core the
process may run on; `IYI_WORKERS`, `workers 4`, `config.workers = 4` or
`-w 4` set it, and `workers 1` serves every connection on the thread that
accepts them, as iyi-web did before.

Because a route may run on several cores at once, the compiler checks
every block you register where you write it, as it checks a parallel
task's (SPEC.md III.4.4). A route that captures a bare `Array` or `Hash`,
or assigns a local it captured, does not compile:

```iyi
seen = [] of String

get "/" do |env|
  seen << env.request.path   # refused
  seen.size.to_s
end
```

```
Error: the block Dsl.get keeps, which may run on other threads captures
`seen : Array(String)`, which is not Share: Array(String)'s field @size is
assigned in `append`. Put it behind a lock, a `Mutex(Array(String))`
(std/mutex), or pass `workers: 1` so the block runs on one thread (SPEC.md
III.4.4)
```

Those are the two ways out. Keep the state behind a lock or in an atomic:
a [store](state.md) for a table every worker changes
(`SEEN = ArrayStore(String).new` with
`SEEN.update { |list| list << path; nil }`), `Atomic(Int32)` for a count, a
`List` for a table nothing writes, or a `Mutex` from `std/mutex`, which the
stores are built on (`examples/json_api.iyi`). Or register the block with
`workers: 1`: it is kept unchecked, and the application is served on one
thread, saying so when it starts (`examples/websocket_chat.iyi`):

```iyi
get "/", workers: 1 do |env|
  seen << env.request.path
  seen.size.to_s
end
```

The same holds for filters, `error` pages, `ws`, `sse` and
`static_headers`. A handler given to `use`, and a logger, are called by
every worker, so they must be `Share` - no field assigned after
`initialize` - and one that is not is refused at the `use` or `logger`
line, at the value given, naming the field and the same two ways out;
`use handler, workers: 1` and `logger value, workers: 1` keep them
unchecked. `use path, [a, b]` checks each handler inside iyi-web, since an
`Array` is never `Share`; give a handler that must stay on one thread
alone. `config.logger = value` has no `workers:`, and its refusal says to
use `logger value, workers: 1`.

A constant the block names is checked as a capture is. One it reaches
through the functions it calls is warned about, with the path (iyi's
reach warning, #148): make it a `List` if it is only read, put it behind
a `Mutex`, or say why every worker may reach it with `@[SafeReach("...")]`
on the constant. iyi-web's own programs, tests and examples compile with
no such warning.

Settings are copied when a server on more than one worker starts
(`Settings`); one changed on `config` afterwards does not reach it.
