#!/usr/bin/env bash
# Harness and scenario files must parse and be pure ASCII (no emoji: D15).
. "$(dirname "$0")/lib.sh"
for f in "$ROOT/templates/harness.js" "$ROOT/templates/flow.js" "$ROOT/examples/counter/flow.js"; do
  name=${f#"$ROOT"/}
  if [ ! -f "$f" ]; then not_ok "$name missing"; continue; fi
  if node --check "$f" 2>/dev/null; then ok "$name parses"; else not_ok "$name has a syntax error"; fi
  if LC_ALL=C grep -n '[^[:print:][:space:]]' "$f" >/dev/null; then not_ok "$name has non-ASCII"; else ok "$name is ASCII"; fi
done
h=$(cat "$ROOT/templates/harness.js")
assert_has "desktop preset 1440x900" "$h" "desktop: { width: 1440, height: 900"
assert_has "mobile preset 390x844 dpr 3" "$h" "mobile: { width: 390, height: 844, dpr: 3"
assert_has "fresh context per phase" "$h" "browser.newContext("
assert_has "records headless, never in a headed window" "$h" "headless: true"
assert_has "secret fill hides the action overlay" "$h" "fillSecret:"
assert_has "each phase browser carries the pgrep marker" "$h" "--provenfix-recorder"

# Behaviour without a browser: load into a fake page and hit the paths that fail before any launch.
r=$(node -e '
const fs = require("fs");
const load = (f) => eval("(" + fs.readFileSync(f, "utf8") + ")");
(async () => {
  const L = { __ba: { stale: () => 1 } };
  const out = [await load(process.argv[1])(L), "stale" in L.__ba ? "stale kept" : "stale dropped"];
  for (const [kind, P] of [["flow", {}], ["flow", { base: "x" }], ["run", { base: "x" }]])
    out.push(await L.__ba.run(L, kind, P).then(() => "no error", (e) => e.message));
  out.push(await load(process.argv[2])(L), "run is " + typeof L.__ba.run);
  console.log(out.join("\n"));
})();' "$ROOT/templates/harness.js" "$ROOT/templates/flow.js" 2>&1)
assert_has "harness loads" "$r" "loaded page.__ba.run"
assert_has "harness reload drops scenarios of an earlier run" "$r" "stale dropped"
assert_has "missing base is refused" "$r" "params.base is required"
assert_has "a kind that is not loaded is refused" "$r" "page.__ba.flow is not loaded"
assert_has "run cannot call itself" "$r" "page.__ba.run is not loaded"
assert_has "scenario load keeps the harness" "$r" "run is function"
for f in "$ROOT/templates/flow.js" "$ROOT/examples/counter/flow.js"; do
  assert_has "${f#"$ROOT"/} registers its kind" "$(cat "$f")" "loader.__ba = { ...loader.__ba, [KIND]:"
done
done_testing
