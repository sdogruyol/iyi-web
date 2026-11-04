// Express's side of bench/compare: the three endpoints, served by one
// worker process per core through node:cluster, Express's own answer to
// using every core. bench/compare/run.iyi runs `npm install` here, then
// `node app.js` with PORT set.
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

  app.listen(Number(process.env.PORT) || 3000);
}
