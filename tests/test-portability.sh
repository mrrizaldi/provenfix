#!/usr/bin/env bash
# D15: scripts must run on any glibc Linux and on macOS (bash 3.2, BSD tools).
. "$(dirname "$0")/lib.sh"
shopt -s nullglob

b='(^|[^A-Za-z_-])'
banned="${b}(setsid|timeout|mapfile|readarray)([^A-Za-z_-]|\$)"
banned="$banned|${b}stat +-[A-Za-z]*c|${b}sed( +-[A-Za-z]+)* +-[A-Za-z]*i|${b}sed +--in-place"
banned="$banned|${b}readlink +(-[A-Za-z]*f|--canonicalize)|${b}grep +-[A-Za-z]*P|${b}date +(-[A-Za-z]*d|--date)"
banned="$banned|${b}(declare|local|typeset) +-[A-Za-z]*[An]"'|\$\{[^}]*(,,?|\^\^?)\}|\|&'
scan() { grep -nE "$banned" "$@"; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/bad.sh" <<'EOF'
setsid foo &
timeout 5 x
mapfile -t a
sed -ni 's/a/b/' f
sed -E -i 's/a/b/' f
grep -oP 'x' f
stat -c %s f
readlink -f x
date -d now
declare -gA m
local -n r=x
y=${1,,}
z=${a^}
cmd |& tee
EOF
cat > "$tmp/good.sh" <<'EOF'
curl -s --max-time 2 "$url"
apt update -d
sed -n 's/^x=//p' f
grep -oE 'x' f
v=${BA_READY_SECS:-180}
for f in ${copies[@]+"${copies[@]}"}; do :; done
EOF
assert_eq "pattern catches every banned form" "$(scan "$tmp/bad.sh" | wc -l | tr -d ' ')" "14"
assert_eq "pattern leaves portable code alone" "$(scan "$tmp/good.sh")" ""

files=("$ROOT"/scripts/*.sh "$ROOT"/examples/*/*.sh "$ROOT"/templates/*.sh)
if [ ${#files[@]} = 0 ]; then
  ok "no scripts yet"
else
  assert_eq "no banned commands in scripts" "$(scan "${files[@]}")" ""
fi
done_testing
