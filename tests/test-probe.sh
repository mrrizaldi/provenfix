#!/usr/bin/env bash
# probe.sh + probe-server.mjs + teardown.sh (spec: backend proof).
. "$(dirname "$0")/lib.sh"
S=$ROOT/scripts/probe.sh
D=$ROOT/scripts/teardown.sh
T=$(mktemp -d)
T=$(cd "$T" && pwd)
cleanup() { "$D" --state "$T/run" >/dev/null 2>&1; rm -rf "$T"; }
trap cleanup EXIT
freeport() { python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }

cat > "$T/probes.sh" <<'EOF'
case "${1:-}" in
  echo_args) # cmd: printf '%s|' "$@"
    shift; printf '%s|' "$@" ;;
  cmd_vars) # cmd: grep -c "$2" ${BA_SIDE}.log on $BA_PORT (${1})
    echo ok ;;
  edge) printf '%s' "$(head -c 4094 /dev/zero | tr '\0' x)MY_TOKEN_VALUE_zzz1234" ;;
  env_info) echo "$BA_SIDE $BA_PORT $BA_RUN token=${BA_PROBE_TOKEN:-unset}" ;;
  fail) echo oops >&2; exit 3 ;;
  big) head -c 10000 /dev/zero | tr '\0' x ;;
  slow) sleep 30.5 ;;
  bgjob) sleep 41.5 & echo done ;;
  leak) echo "pw=$BA_PASS key=$MY_API_KEY short=$MY_TOKEN plain=$PLAIN_VAR"
    echo "valkey=$VALKEY_HOST keyid=$AWS_ACCESS_KEY_ID anon=$SUPABASE_ANON_KEY ttl=$JWT_TOKEN_EXPIRY_MINUTES rows=10080"
    echo "dbuser=$DB_USER dbpass=$DB_PASSWORD url=postgres://app:s3cretpw9@localhost:5432/app" ;;
  *) exit 2 ;;
esac
EOF

export BA_PROBE_KILL_MS=1500
export BA_PASS=hunter22 MY_API_KEY=abcd1234 EDGE_SECRET=MY_TOKEN_VALUE_zzz1234 MY_TOKEN=abc PLAIN_VAR=visible1
export VALKEY_HOST=valkeyhost AWS_ACCESS_KEY_ID=AKIAEXAMPLE1 SUPABASE_ANON_KEY=anonpublic1
export JWT_TOKEN_EXPIRY_MINUTES=10080 DB_USER=appuser DB_PASSWORD=appuser
pp=$(freeport)
out=$("$S" --probes "$T/probes.sh" --state "$T/run" --port "$pp" --mask-env BA_PASS 2>&1)
assert_eq "probe.sh starts" "$?" 0
url=$(kv "$out" probe_url)
tok=$(kv "$out" probe_token)
assert_eq "url is loopback" "$url" "http://127.0.0.1:$pp"
assert_eq "token is 32 hex" "$(printf '%s' "$tok" | grep -cE '^[0-9a-f]{32}$')" 1
assert_has "pid file written" "$(cat "$T/run/probe.pid")" " "
assert_has "binds loopback only" "$(cat "$ROOT/scripts/probe-server.mjs")" "listen(Number(opt.port), '127.0.0.1')"

code() { curl -s --noproxy '*' -o /dev/null -w '%{http_code}' "$@"; }
q() { curl -s --noproxy '*' -H "X-Probe-Token: $tok" "$url/$1"; }
assert_eq "no token is 401" "$(code "$url/echo_args?side=before&port=1")" 401
assert_eq "wrong token is 401" "$(code -H 'X-Probe-Token: nope' "$url/echo_args?side=before&port=1")" 401
assert_eq "bad name is 400" "$(code -H "X-Probe-Token: $tok" "$url/Bad-Name?side=before&port=1")" 400
assert_eq "unknown name is 404" "$(code -H "X-Probe-Token: $tok" "$url/nope?side=before&port=1")" 404
assert_eq "bad side is 400" "$(code -H "X-Probe-Token: $tok" "$url/echo_args?side=prod&port=1")" 400
assert_eq "bad port is 400" "$(code -H "X-Probe-Token: $tok" "$url/echo_args?side=before&port=x")" 400

r=$(q "echo_args?side=before&port=1&a=1&a=two%20words")
assert_has "args arrive as argv" "$r" '"out":"1|two words|"'
assert_has "exit code returned" "$r" '"code":0'
assert_has "cmd comment shown" "$r" '"cmd":"printf'

enc=$(node -p 'encodeURIComponent(process.argv[1])' ";\$(touch $T/pwned)")
r=$(q "echo_args?side=before&port=1&a=$enc")
assert_has "shell syntax comes back literally" "$r" 'touch'
assert_eq "shell syntax not run" "$([ -e "$T/pwned" ] && echo yes || echo no)" no

r=$(q "env_info?side=after&port=4242")
assert_has "probe env: side, port, run dir" "$r" "after 4242 $T/run"
assert_has "token not passed to probes" "$r" "token=unset"

r=$(q "fail?side=before&port=1")
assert_has "non-zero exit passes through" "$r" '"code":3'
assert_has "stderr captured" "$r" 'oops'

r=$(q "leak?side=before&port=1")
assert_not_has "--mask-env value masked" "$r" "hunter22"
assert_not_has "*KEY* env value masked" "$r" "abcd1234"
assert_has "masked values show ***" "$r" "pw=*** key=***"
assert_has "short values left alone" "$r" "short=abc"
assert_has "other env values left alone" "$r" "plain=visible1"
assert_has "KEY must be a whole name part (VALKEY is not)" "$r" "valkey=valkeyhost"
assert_has "*_ID names are not secret" "$r" "keyid=AKIAEXAMPLE1"
assert_has "PUBLIC/ANON names are not secret" "$r" "anon=anonpublic1"
assert_has "numeric settings left alone (no masked row counts)" "$r" "ttl=10080 rows=10080"
assert_has "password equal to a plain value left alone" "$r" "dbuser=appuser dbpass=appuser"
assert_has "URL credentials masked" "$r" "url=postgres://app:***@localhost:5432/app"

r=$(q "big?side=before&port=1")
assert_has "big output cut" "$r" '...[cut]'
assert_eq "cut near 4 KB" "$([ ${#r} -lt 4300 ] && echo yes || echo no)" yes

r=$(q "cmd_vars?side=after&port=4242&a=deleted%20note")
assert_has "cmd comment gets positionals and BA_ vars" "$r" '"cmd":"grep -c \"deleted note\" after.log on 4242 (cmd_vars)"'

r=$(q "edge?side=before&port=1")
assert_not_has "secret straddling the 4 KB cut leaves no prefix" "$r" "MY_TOK"
assert_has "cut marker kept" "$r" '...[cut]'

SECONDS=0
r=$(q "slow?side=before&port=1")
assert_has "slow probe killed with 124" "$r" '"code":124'
assert_eq "killed within the limit" "$([ "$SECONDS" -lt 6 ] && echo yes || echo no)" yes

SECONDS=0
r=$(q "bgjob?side=before&port=1")
assert_has "backgrounded work is not a timeout" "$r" '"code":0'
assert_has "output kept" "$r" '"out":"done\n"'
assert_eq "returned quickly" "$([ "$SECONDS" -lt 3 ] && echo yes || echo no)" yes
sleep 0.3
assert_eq "leftover background job killed" "$(pgrep -f 'sleep 41[.]5' | wc -l | tr -d ' ')" 0

out=$("$S" --probes "$T/probes.sh" --state "$T/run2" --port 0 2>&1)
assert_has "port 0 refused" "$out" "--port must be 1-65535"
out=$("$S" --probes "$T/probes.sh" --state "$T/run2" --port "$pp" 2>&1)
assert_has "busy port refused" "$out" "port $pp is already in use"
out=$("$S" --probes "$T/missing.sh" --state "$T/run2" --port "$(freeport)" 2>&1)
assert_has "missing probes file refused" "$out" "no such probes file"

q "slow?side=before&port=1" >/dev/null &
sleep 0.5
out=$("$D" --state "$T/run")
sleep 0.3
assert_eq "teardown kills in-flight probes" "$(pgrep -f 'sleep 30[.]5' | wc -l | tr -d ' ')" 0
assert_has "teardown stops the probe server" "$out" "stopped=probe"
assert_eq "server gone after teardown" "$(code --max-time 2 "$url/")" 000
done_testing
