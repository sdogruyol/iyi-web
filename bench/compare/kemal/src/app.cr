# Kemal's side of bench/compare: the three endpoints, with request logging
# off. Built by bench/compare/run.iyi with `crystal build --release`.
#
# Crystal 1.22's default execution context is parallel but starts with one
# thread; it is resized to the core count (or CRYSTAL_WORKERS) before the
# server starts, so Kemal serves on every core as the others do.
require "json"
require "kemal"

get "/plaintext" do |env|
  env.response.content_type = "text/plain"
  "Hello, World!"
end

get "/json" do |env|
  env.response.content_type = "application/json"
  {message: "Hello, World!"}.to_json
end

get "/users/:id" do |env|
  id = env.params.url["id"].to_i64?
  if id
    env.response.content_type = "application/json"
    {id: id, name: "user-#{id}", fields: env.params.query["fields"]? || ""}.to_json
  else
    halt env, status_code: 404, response: "Not Found"
  end
end

Fiber::ExecutionContext.default.resize(Fiber::ExecutionContext.default_workers_count)

Kemal.config.logging = false
Kemal.config.env = "production"
Kemal.config.port = (ENV["PORT"]? || "3000").to_i
Kemal.run
