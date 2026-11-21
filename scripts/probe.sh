#!/usr/bin/env bash
# Start the probe server for one run (spec: backend proof). teardown.sh stops it (probe.pid).
# probe.sh --probes <file> --state <dir> --port <n> [--mask-env A,B]
# stdout: probe_url= probe_token=
set -euo pipefail
. "$(dirname "$0")/lib.sh"
here=$(cd "$(dirname "$0")" && pwd)

probes= state= port= mask=
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || die "missing value for $1"
  case $1 in
    --probes) probes=$2 ;;
    --state) state=$2 ;;
    --port) port=$2 ;;
    --mask-env) mask=$2 ;;
    *) die "unknown flag: $1" ;;
  esac
  shift 2
done
if [ -z "$probes" ] || [ -z "$state" ] || [ -z "$port" ]; then die "--probes, --state and --port are required"; fi
case $port in *[!0-9]*) die "--port must be a number" ;; esac
[ "$port" -ge 1 ] && [ "$port" -le 65535 ] || die "--port must be 1-65535"
[ -f "$probes" ] || die "no such probes file: $probes"
command -v node >/dev/null 2>&1 || die "node not found"
url=http://127.0.0.1:$port
if curl -s --noproxy '*' -o /dev/null --max-time 1 "$url/"; then die "port $port is already in use"; fi

probes=$(cd "$(dirname "$probes")" && pwd)/$(basename "$probes")
mkdir -p "$state"
state=$(cd "$state" && pwd)
token=$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')

# Own process group (set -m), same as provision.sh, so teardown.sh stops it unchanged.
set -m
(
  export BA_PROBE_TOKEN=$token
  exec nohup node "$here/probe-server.mjs" --probes "$probes" --run "$state" --port "$port" --mask-env "$mask"
) >"$state/probe.log" 2>&1 </dev/null &
pid=$!
set +m
echo "$pid $(ba_lstart "$pid")" >"$state/probe.pid"

stop() {
  kill -TERM -- "-$pid" 2>/dev/null || true
  rm -f "$state/probe.pid"
}
i=0
while :; do
  if ! kill -0 "$pid" 2>/dev/null; then
    tail -n 20 "$state/probe.log" >&2
    rm -f "$state/probe.pid"
    die "probe server exited (log: $state/probe.log)"
  fi
  [ "$(curl -s --noproxy '*' -o /dev/null -w '%{http_code}' --max-time 1 "$url/" || true)" = 401 ] && kill -0 "$pid" 2>/dev/null && break
  if [ "$i" -ge 50 ]; then stop; die "probe server not answering on $url (log: $state/probe.log)"; fi
  sleep 0.2
  i=$((i + 1))
done
echo "probe_url=$url"
echo "probe_token=$token"
