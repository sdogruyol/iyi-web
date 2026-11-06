// Express's side of bench/compare: the endpoints, served by one worker
// process per core through node:cluster, Express's own answer to using
// every core. bench/compare/run.iyi runs `npm install` here, then
// `node app.js` with PORT set.
//
// `/db` is there when DATABASE_URL is: a `pg` Pool per worker process,
// DB_POOL_SIZE connections each (default 4).
const cluster = require("node:cluster");
const os = require("node:os");

const workers = Number(process.env.WORKERS) || os.availableParallelism();

if (cluster.isPrimary) {
  for (let i = 0; i < workers; i++) cluster.fork();
  cluster.on("exit", (worker, code) => {
    if (code !== 0) console.error(`worker ${worker.process.pid} exited with ${code}`);
  });
} else {
  const express = require("express");
  const app = express();
  app.disable("x-powered-by");
  app.disable("etag");

  app.get("/plaintext", (req, res) => {
    res.type("text/plain").send("Hello, World!");
  });

  app.get("/json", (req, res) => {
    res.json({ message: "Hello, World!" });
  });

  app.get("/users/:id", (req, res) => {
    if (!/^-?\d+$/.test(req.params.id)) return res.status(404).send("Not Found");
    const id = Number(req.params.id);
    res.json({ id, name: `user-${id}`, fields: req.query.fields ?? "" });
  });

  if (process.env.DATABASE_URL) {
    const { Pool } = require("pg");
    const pool = new Pool({
      connectionString: process.env.DATABASE_URL,
      max: Number(process.env.DB_POOL_SIZE) || 4,
    });

    app.get("/db", async (req, res) => {
      try {
        const id = 1 + Math.floor(Math.random() * 10000);
        const { rows } = await pool.query("SELECT id, randomnumber FROM world WHERE id = $1", [id]);
        res.json({ id: rows[0].id, randomNumber: rows[0].randomnumber });
      } catch (err) {
        res.status(503).send("database unavailable");
      }
    });
  }

  app.listen(Number(process.env.PORT) || 3000);
}
