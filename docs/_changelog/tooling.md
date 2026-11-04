### Added

- The `iyi-web` command (`cmd/`, `iyi build --release cmd/iyi_web.iyi -o bin/iyi-web`):
  - `iyi-web new DIR [--api | --full] [--web-path PATH]` writes a project that builds and passes its own test: `iyi.mod` requiring iyi-web as `web`, `app.iyi`, routes in their own module, an in-process `app_test.iyi`, `.gitignore`; `--api` a validated JSON CRUD, `--full` views in a layout and `public/`. `--web-path` adds a `replace` line for a local checkout. A non-empty directory is refused before anything is written.
  - `iyi-web dev [ENTRY] [--watch DIR] [--interval MS] [-- ARGS]` builds and runs the app, rebuilds on a saved `*.iyi`/`*.eiy`/`*.ecr`/`iyi.mod` change and restarts it on success; a failed build prints the compiler's error and keeps the previous build serving. Changes under `public/` are reported without a rebuild. Ctrl-C/TERM stops the app, then dev. Same-second saves of the same size are caught by comparing text.
- `examples/postgres/`: a standalone project on iyilang/db + iyilang/pg with a pool from `DATABASE_URL`, migrations applied at start under an advisory lock, a JSON CRUD with validated bodies, `DBError` answered as `503`, and `smoke.sh`.
- `bench/compare/`: the same three endpoints in iyi-web, FastAPI, Express, Kemal and Go `net/http`, and a runner (`bash bench/compare/run.sh`) that builds, checks, warms up and measures each with oha, skips missing toolchains with the reason, and writes `results.json` and `results.md`.
- Docs: `docs/cli.md`, `docs/database.md`, `docs/benchmarks.md`.

### Changed

- `.gitignore` ignores `.iyi-web/` (dev builds), the postgres example's binary, and bench/compare's builds, results and fetched dependencies.

Note for the release: `WEB_VERSION` in `cmd/scaffold.iyi` (0.5.1) is the release new projects require; bump it with the release that ships the command.
