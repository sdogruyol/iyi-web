# Kemal's side of bench/compare: the endpoints, with request logging off.
# Built by bench/compare/run.iyi with `crystal build --release`.
#
# Crystal 1.22's default execution context is parallel but starts with one
# thread; it is resized to the core count (or CRYSTAL_WORKERS) before the
# server starts, so Kemal serves on every core as the others do.
#
# `/db` is there when DATABASE_URL is: one crystal-db pool (driver
# crystal-pg) shared by every thread, at most DB_POOL_SIZE connections
# (default 48), all of them kept open between bursts.
require "json"
require "kemal"
require "db"
require "pg"

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

if url = ENV["DATABASE_URL"]?
  pool_size = ENV["DB_POOL_SIZE"]? || "48"
  database = DB.open(url + (url.includes?('?') ? "&" : "?") + "max_pool_size=#{pool_size}&max_idle_pool_size=#{pool_size}")

  get "/db" do |env|
    id, random_number = database.query_one("SELECT id, randomnumber FROM world WHERE id = $1", rand(1..10_000), as: {Int32, Int32})
    env.response.content_type = "application/json"
    {id: id, randomNumber: random_number}.to_json
  end
end

Fiber::ExecutionContext.default.resize(Fiber::ExecutionContext.default_workers_count)

Kemal.config.logging = false
Kemal.config.env = "production"
Kemal.config.port = (ENV["PORT"]? || "3000").to_i
Kemal.run
