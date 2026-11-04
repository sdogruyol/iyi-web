# WebSockets and server-sent events

## Server-sent events

```iyi
sse "/clock" do |stream, env|
  3.times do |tick|
    stream.send("tick " + tick.to_s, event: "tick", id: tick)
    sleep(1000)
  end
end
```

`sse` registers a `GET` route answering `text/event-stream`. `send` takes
`event:`, `id:` and `retry:` (a `Span`), splits multi-line data into `data:`
lines and flushes; `comment` sends a keep-alive line clients ignore. An event
name or id containing a line break panics. The stream ends when the block
returns. A browser reads it with `new EventSource("/clock")`.

## WebSockets

```iyi
import web/iyi_web/dsl::*
import web/iyi_web/websocket::{WebSocket}

class Room
  @members : Array(WebSocket)

  def initialize
    @members = [] of WebSocket
  end

  def join(socket : WebSocket) : Nil
    @members << socket
  end

  def leave(socket : WebSocket) : Nil
    @members.delete(socket)
  end

  def broadcast(text : String) : Nil
    @members.each { |member| member.send(text) }
  end
end

ROOM = Room.new

ws "/chat/:name", workers: 1 do |socket, env|
  name = env.params.url["name"]
  ROOM.join(socket)
  socket.on_message { |text| ROOM.broadcast(name + ": " + text) }
  socket.on_close { |code, reason| ROOM.leave(socket) }
end
```

The room is an `Array` of sockets, which no two workers may share, so this
endpoint is registered with `workers: 1` and the application is served on
one thread ([Every core](every-core.md)), as `examples/websocket_chat.iyi`
is.

`ws` registers a WebSocket endpoint (RFC 6455); `Router#ws` does the same on a
router. A `GET` with `Upgrade: websocket` runs the `before` filters for `GET`,
then gets `101 Switching Protocols`. The block then receives the socket and the
context and sets the callbacks, and the connection's fiber reads frames until
the socket closes. The connection carries no more HTTP requests and has no read
timeout.

- Callbacks: `on_message` (text), `on_binary` (the bytes as a `String`),
  `on_ping`, `on_pong` and `on_close(code, reason)`.
- Sending: `send(text)`, `send_binary(bytes)`, `ping`, `pong` and
  `close(code = 1000, reason = "")`. Each returns `false` once the socket is
  closed or its client has gone, and affects nothing else. Any fiber may send,
  as a broadcast from another connection does; frames never interleave.
- A ping is answered with a pong, and fragments arrive as one message. Text that
  is not UTF-8 closes the connection with `1007`, an unmasked or malformed frame
  with `1002`, a message over `websocket_max_message_size` with `1009`, and a
  callback that panics with `1011`. `on_close` gets `1006` when the client left
  without a close frame.
- Another method gets `405` unless an HTTP route serves it. A missing
  `Connection: Upgrade`, HTTP/1.0 or a bad `Sec-WebSocket-Key` gets `400`, an
  `Origin` that is not allowed `403`, and a `Sec-WebSocket-Version` other than
  13 gets `426` with `Sec-WebSocket-Version: 13`. A refused handshake closes
  the connection.
- A `GET` without `Upgrade: websocket` goes to the HTTP route on the same path,
  or gets `426 Upgrade Required` when there is none.

`Origin` is checked against `websocket_allowed_origins`. Empty, the default,
means same-origin: the `Origin` has to name the request's `Host`. A request
without `Origin`, which most clients outside a browser send, is refused unless
the list holds `"*"`. A browser connects with
`new WebSocket("ws://localhost:3000/chat/ada")`, or `wss://` when the server
runs with TLS.
