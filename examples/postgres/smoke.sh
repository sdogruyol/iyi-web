#!/usr/bin/env bash
# Drives a running examples/postgres server over HTTP with curl: create,
# read, update and delete a todo, and the refusals in between. Exits 1 at
# the first answer that is not the one expected, naming it.
#
#   iyi run app.iyi &          # with DATABASE_URL set
#   bash smoke.sh              # against http://localhost:3000
#   bash smoke.sh http://localhost:8080
set -euo pipefail

base=${1:-http://localhost:3000}
failures=0

# check NAME EXPECTED_STATUS METHOD PATH [JSON_BODY] [EXPECTED_BODY_PART]
check() {
  local name=$1 want=$2 method=$3 path=$4 body=${5:-} part=${6:-}
  local args=(-s -o /tmp/smoke-body.$$ -w '%{http_code}' -X "$method" "$base$path")
  [ -n "$body" ] && args+=(-H 'Content-Type: application/json' -d "$body")
  local got
  got=$(curl "${args[@]}")
  local text
  text=$(cat /tmp/smoke-body.$$)
  if [ "$got" != "$want" ] || { [ -n "$part" ] && [[ "$text" != *"$part"* ]]; }; then
    echo "FAIL $name: $method $path answered $got $text (wanted $want${part:+ with $part})"
    failures=$((failures + 1))
  else
    echo "ok   $name: $got $text"
  fi
  LAST_BODY=$text
}

check "health" 200 GET /health "" '"ok"'
check "create" 201 POST /todos '{"title":"  Write the smoke test  "}' '"title":"Write the smoke test","done":false'
id=$(printf '%s' "$LAST_BODY" | sed -E 's/.*"id":([0-9]+).*/\1/')
check "show" 200 GET "/todos/$id" "" "\"id\":$id"
check "list" 200 GET /todos "" "\"id\":$id"
check "blank title" 422 POST /todos '{"title":"   "}' '"title"'
check "missing title" 422 POST /todos '{"done":true}' '"title"'
check "not JSON" 400 POST /todos '{"title":'
check "mark done" 200 PATCH "/todos/$id" '{"done":true}' '"title":"Write the smoke test","done":true'
check "rename" 200 PATCH "/todos/$id" '{"title":"Renamed"}' '"title":"Renamed","done":true'
check "blank rename" 422 PATCH "/todos/$id" '{"title":""}' '"title"'
check "delete" 204 DELETE "/todos/$id"
check "deleted" 404 GET "/todos/$id" "" '"not found"'
check "delete again" 404 DELETE "/todos/$id"
check "not an id" 404 GET /todos/abc
check "patch nothing" 404 PATCH /todos/0 '{"done":true}'

rm -f /tmp/smoke-body.$$
if [ "$failures" -gt 0 ]; then
  echo "$failures failed"
  exit 1
fi
echo "all passed"
