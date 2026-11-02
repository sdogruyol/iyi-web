#!/usr/bin/env bash
# One worker against every core, on a CPU-bound endpoint and a light one:
# bench/cores.iyi under wrk, 32 keep-alive connections, each run its own
# server. For each it prints requests per second and the server's CPU, as
# a percentage of one core, from its /proc/PID/stat ticks over the run, and
# the best of the rounds by requests per second. Linux only (/proc); wrk
# must be on the PATH.
#
#   bash bench/cores.sh                       # 3 rounds of 10 s, workers 1 and the cores
#   bash bench/cores.sh --rounds 1 --seconds 5
#   bash bench/cores.sh --no-build --workers "1 4 12"
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

build=$root/bench/.build
rounds=3
seconds=10
connections=32
threads=4
port=3901
compile=1
workers="1 $(nproc)"

while [ $# -gt 0 ]; do
  case "$1" in
    --rounds) rounds=$2; shift 2 ;;
    --seconds) seconds=$2; shift 2 ;;
    --connections) connections=$2; shift 2 ;;
    --threads) threads=$2; shift 2 ;;
    --port) port=$2; shift 2 ;;
    --workers) workers=$2; shift 2 ;;
    --no-build) compile=0; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "cores.sh: unknown option $1" >&2; exit 2 ;;
  esac
done

command -v wrk > /dev/null || { echo "cores.sh: wrk is not on the PATH" >&2; exit 2; }
mkdir -p "$build"
if [ "$compile" = 1 ]; then
  echo "building bench/cores.iyi (--release)"
  iyi build --release bench/cores.iyi -o "$build/cores"
fi

ticks=$(getconf CLK_TCK)
server_pid=""
stop_server() {
  if [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
    server_pid=""
  fi
}
trap stop_server EXIT

# utime + stime of a process, in clock ticks (proc(5), fields 14 and 15,
# counted after the parenthesised name, which may hold spaces).
cpu_ticks() {
  local rest
  rest=$(sed 's/^.*) //' "/proc/$1/stat")
  set -- $rest
  echo $(( ${12} + ${13} ))
}

echo "$(nproc) cores, $connections connections, $seconds s a run, best of $rounds; load before: $(cut -d' ' -f1-3 /proc/loadavg)"
printf '%-8s %-8s %12s %8s\n' endpoint workers "req/s" "CPU %"
for path in /login /json; do
  for count in $workers; do
    best_rps=0
    best_cpu=0
    for round in $(seq 1 "$rounds"); do
      "$build/cores" -b 127.0.0.1 -p "$port" -w "$count" > "$build/cores.log" 2>&1 &
      server_pid=$!
      for _ in $(seq 1 100); do
        curl -s -o /dev/null "http://127.0.0.1:$port/json" && break
        sleep 0.05
      done
      # A second of warm-up, not counted.
      wrk -t "$threads" -c "$connections" -d 1s "http://127.0.0.1:$port$path" > /dev/null
      before=$(cpu_ticks "$server_pid")
      started=$(date +%s.%N)
      rps=$(wrk -t "$threads" -c "$connections" -d "${seconds}s" "http://127.0.0.1:$port$path" | awk '/^Requests\/sec:/ { print $2 }')
      ended=$(date +%s.%N)
      after=$(cpu_ticks "$server_pid")
      stop_server
      cpu=$(awk -v t="$((after - before))" -v hz="$ticks" -v a="$started" -v b="$ended" 'BEGIN { printf "%.0f", 100 * t / hz / (b - a) }')
      if awk -v r="$rps" -v best="$best_rps" 'BEGIN { exit !(r > best) }'; then
        best_rps=$rps
        best_cpu=$cpu
      fi
    done
    printf '%-8s %-8s %12s %8s\n' "$path" "$count" "$best_rps" "$best_cpu"
  done
done
echo "load after: $(cut -d' ' -f1-3 /proc/loadavg)"
