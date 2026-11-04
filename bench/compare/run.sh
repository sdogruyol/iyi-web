#!/usr/bin/env bash
# Builds bench/compare/run.iyi and runs it: iyi-web, FastAPI, Express, Kemal
# and Go's net/http on the same endpoints (/plaintext, /json, /users/:id and
# /db, one PostgreSQL row through a pool), loaded with oha. Options go to the
# runner (--help lists them); results land in bench/compare/results.json and
# bench/compare/results.md.
#
#   bash bench/compare/run.sh
#   bash bench/compare/run.sh --duration 5 --only iyi-web,go
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "$here/.build"
iyi build --release "$here/run.iyi" -o "$here/.build/run"
exec "$here/.build/run" "$@"
