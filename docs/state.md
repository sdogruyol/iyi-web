# Shared state with `Store`

A route may run on every core at once, so state it changes has to be behind
a lock, and the compiler refuses a route that captures a bare `Array` or
`Hash` (see "Every core" in the README). `std/mutex`'s `Mutex` is the lock,
and it asks three things of every caller: a `.or_panic` for the `Cancelled`
a wait may answer, an answer that is `Share` because it leaves the lock, and
so a `List.new(todos.values)` where the route wanted `todos.values`.

`Store(T)` from `web/iyi_web/store` pays that once:

```iyi
import std/json::{serializable}
import web/iyi_web/dsl::*
import web/iyi_web/store::{Store}

struct Todo
  getter id : Int32
  getter title : String

  def initialize(@id : Int32, @title : String)
  end

  derive serializable
end

TODOS = Store.new { {} of Int32 => Todo }

get "/todos" do |env|
  env.json(TODOS.values)                # a copy, taken under the lock
end

get "/todos/:id" do |env|
  todo = TODOS[env.params.url["id"].to_i? || 0]?
  todo ? env.json(todo) : env.status(404).text("not found")
end

post "/todos" do |env|
  title = env.params.body["title"]? || "untitled"
  todo = TODOS.update { |todos| made = Todo.new(todos.size + 1, title); todos[made.id] = made; made }
  env.status(201).json(todo)
end

run
```

It serves on every core: a `Store` is `Share` (a `Mutex` is its only field),
so routes, handlers and background tasks capture one as it is.

## Reading and changing

| Call | What it does |
|---|---|
| `Store.new { value }` | Makes the value inside the store; nothing outside holds it. The block is checked as `Mutex.new`'s is. |
| `read { \|v\| ... }` | The block's answer, worked out with the lock held. |
| `update { \|v\| ... }` | Changes a `Hash` or an `Array` in place with the lock held; answers the block's answer (an id handed out, a count, nil). |
| `replace { \|v\| new }` | Replaces the value with the block's answer: for a number or a struct, which a block cannot change in place. |
| `get` / `set(value)` | The value itself, or a new one, for a `Share` value: `HITS.get`, `NAME.set("x")`. |
| `values`, `keys` | A `Hash`'s values or keys, copied out as an `Array`, in insertion order. |
| `to_a` | An `Array`'s elements, or a `Hash`'s key-value pairs, copied out. |
| `to_h` | A copy of a `Hash`. |
| `[]?(key)` | The entry under a key (or the element at an index), or nil. |
| `size` | How many entries. |

The copies are the caller's: nothing another worker does afterwards reaches
them. What `read` and `update` answer still has to be `Share` - a number, a
string, a struct of those, a `List`, a tuple of them - and a block that
answers an `Array` or a `Hash` is refused where it is written, as `Mutex#get`
refuses it. The snapshot helpers are there so that is rarely in the way.

A value whose elements are not `Share` themselves - a struct holding an
`Array(String)` - cannot leave the lock in any form. Work out the response
inside the block instead:

```iyi
NOTES = Store.new { [] of Note }        # Note has tags : Array(String)

get "/notes" do |env|
  env.json(NOTES.read { |notes| JSON.to_json(notes) })   # a String leaves the lock
end
```

## One critical section per call

Each call takes the lock once. A `read` followed by an `update` is two
critical sections, and another worker may come between them:

```iyi
# Racy: two requests can read the same size and hand out the same id.
id = ITEMS.size + 1
ITEMS.update { |items| items[id] = Item.new(id) }

# One section: the size read and the insert happen under one lock.
id = ITEMS.update { |items| id = items.size + 1; items[id] = Item.new(id); id }
```

## Cancellation

A task cancelled while it waits for a store's lock - a request being cut off
at the end of a stop's `shutdown_timeout`, a background task past its drain
- panics with `Store: cancelled while waiting for the lock`, as `.or_panic`
would. It is being cut off and has nothing to give its caller; the panic
ends it at its task boundary and nothing else.

## Counters

For a single number a `Store` works (`Store.new { 0 }` with
`replace { |n| n + 1 }`), but `Atomic(Int32)` is lock-free and is the better
choice for a counter or a gauge. For numbers a monitoring system should
scrape, use the metrics registry in [observability](observability.md).
