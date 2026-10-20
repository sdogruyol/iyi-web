#!/usr/bin/env bash
# Builds the benchmarks in release mode, runs the microbenchmarks and the
# end-to-end load test, and writes every result to one JSON file
# (bench/results.json unless --out says otherwise). Run it from anywhere:
# it works on the checkout it lives in.
#
#   bash bench/run.sh                     # build, micro, e2e
#   bash bench/run.sh --repeat 3          # each part three times; compare takes the median
#   bash bench/run.sh --no-e2e --filter radix
#   bash bench/run.sh --no-build --out /tmp/again.json
#   bash bench/run.sh --only-build        # what CI does before timing anything
#
# Then `bench/compare` reads two such files; see bench/compare.iyi.
set -euo pipefail

caller=$PWD
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

# Relative to the checkout by default; a path given on the command line is
# relative to where the script was run from, as any other command's is.
out=$root/bench/results.json
build=$root/bench/.build
from_caller() {
  case "$1" in
    /*|[A-Za-z]:*) printf '%s' "$1" ;;
    *) printf '%s/%s' "$caller" "$1" ;;
  esac
}
repeat=1
seconds=1
warmup=0.3
filter=""
duration=5
connections=32
port=3900
micro=1
e2e=1
compile=1

usage() {
  cat <<'EOF'
usage: bash bench/run.sh [options]
  --out FILE          where the results go (bench/results.json)
  --build DIR         where the binaries go (bench/.build)
  --repeat N          run the micro and e2e parts N times each (1)
  --seconds S         measuring time per microbenchmark (1)
  --warmup S          warm-up per microbenchmark (0.3)
  --filter TEXT       only the microbenchmarks whose name contains TEXT
  --duration S        measuring time per e2e target (5)
  --connections N     concurrent keep-alive connections for e2e (32)
  --port P            port the e2e server listens on (3900)
  --no-micro          skip the microbenchmarks
  --no-e2e            skip the end-to-end run
  --no-build          use the binaries already in the build directory
  --only-build        build the binaries and stop
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --out) out=$(from_caller "$2"); shift 2 ;;
    --build) build=$(from_caller "$2"); shift 2 ;;
    --repeat) repeat=$2; shift 2 ;;
    --seconds) seconds=$2; shift 2 ;;
    --warmup) warmup=$2; shift 2 ;;
    --filter) filter=$2; shift 2 ;;
    --duration) duration=$2; shift 2 ;;
    --connections) connections=$2; shift 2 ;;
    --port) port=$2; shift 2 ;;
    --no-micro) micro=0; shift ;;
    --no-e2e) e2e=0; shift ;;
    --no-build) compile=0; shift ;;
    --only-build) compile=2; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "run.sh: unknown option $1" >&2; usage >&2; exit 2 ;;
  esac
done

# `iyi build -o NAME` writes NAME as given; Windows runs it only with .exe.
ext=""
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*|Windows_NT) ext=.exe ;;
esac

mkdir -p "$build"
if [ "$compile" != 0 ]; then
  for program in micro server load; do
    echo "building bench/$program.iyi (--release)"
    iyi build --release "bench/$program.iyi" -o "$build/$program$ext"
  done
  [ "$compile" = 2 ] && exit 0
fi

micro_lines="$build/micro.jsonl"
e2e_lines="$build/e2e.jsonl"
: > "$micro_lines"
: > "$e2e_lines"

server_pid=""
stop_server() {
  if [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
    server_pid=""
  fi
}
trap stop_server EXIT

for round in $(seq 1 "$repeat"); do
  if [ "$micro" = 1 ]; then
    echo
    echo "== microbenchmarks, run $round of $repeat"
    args=(--seconds "$seconds" --warmup "$warmup" --json "$build/micro-run.jsonl")
    [ -n "$filter" ] && args+=(--filter "$filter")
    "$build/micro$ext" "${args[@]}"
    cat "$build/micro-run.jsonl" >> "$micro_lines"
  fi

  if [ "$e2e" = 1 ]; then
    echo
    echo "== end to end, run $round of $repeat"
    "$build/server$ext" -b 127.0.0.1 -p "$port" > "$build/server.log" 2>&1 &
    server_pid=$!
    # load waits for the server to take connections before it starts.
    "$build/load$ext" --port "$port" --connections "$connections" --duration "$duration" --json "$build/e2e-run.jsonl"
    stop_server
    cat "$build/e2e-run.jsonl" >> "$e2e_lines"
  fi
done

# One object per line becomes one list per part.
join_lines() {
  local joined
  joined=$(paste -sd, "$1")
  printf '[%s]' "$joined"
}

commit=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
version=$(iyi version | head -n 1)
{
  printf '{"schema":1,"commit":"%s","iyi":"%s","os":"%s","repeat":%s,\n' "$commit" "$version" "$(uname -s)" "$repeat"
  printf '"micro":%s,\n' "$(join_lines "$micro_lines")"
  printf '"e2e":%s}\n' "$(join_lines "$e2e_lines")"
} > "$out"
echo
echo "results written to $out"
