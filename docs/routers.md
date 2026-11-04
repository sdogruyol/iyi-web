# Routers

```iyi
import web/iyi_web/router::{Router}

admin = Router.new

admin.get "/" do |env|
  "Dashboard"
end

admin.namespace "/reports" do |reports|
  reports.get "/daily" do |env|
    "Daily report"
  end
end

mount "/admin", admin
```

This serves `/admin` and `/admin/reports/daily`. A `Router` has the same
route, `sse`, filter (`before`, `after`, `before_get`, …) and `error`
methods as the program. `mount` without a path mounts a router at the root,
and `namespace` passes the nested router to its block.

Larger applications keep routers in their own modules. A module does not need
the DSL to define one:

```iyi
# routes/health.iyi
module routes/health

import web/iyi_web/router::{Router}

pub def health_routes : Router
  router = Router.new
  router.get "/health" do |env|
    "ok"
  end
  router
end
```

```iyi
import routes/health::*

mount health_routes
```
