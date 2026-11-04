# Testing

`web/iyi_web/harness` sends requests through a router in-process, without a
socket:

```iyi
# health_test.iyi
module health_test

import web/iyi_web/router::{RouteHandler}
import web/iyi_web/harness::*
import routes/health::*

handler = RouteHandler.new(health_routes)
response = dispatch(handler, "GET", "/health").response

assert response.status_code == 200
assert response.body == "ok"
```

```sh
iyi test
```

A test is a `*_test.iyi` program that exits non-zero on failure, and
`iyi test` runs every one in the project. A test that uses iyi-web sits beside
`iyi.mod`, like the entry file. `http_request` and `form_request` build
requests with a query string, a body or a content type. `dispatch` gives the
request the process `config`'s per-request settings, as the server does
(`dispatch(handler, request, settings)` takes another `Config`).
`handler_chain` from `web/iyi_web/dsl` is the whole application as `run`
serves it (logging, static files, middleware and routes), for tests that need
more than one router.

A project made by `iyi-web new` ([The `iyi-web` command](cli.md)) has this
shape from the start, and the [tutorial](tutorial.md#7-tests) tests typed
routes behind a JWT this way. `on_start` and `on_stop` hooks are tested as
a value ([Hooks in a test](lifecycle-and-background.md#hooks-in-a-test)).
