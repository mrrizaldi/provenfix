#!/usr/bin/env bash
# Harness and scenario files must parse and be pure ASCII (no emoji: D15).
. "$(dirname "$0")/lib.sh"
for f in "$ROOT/templates/harness.js" "$ROOT/templates/flow.js" "$ROOT/examples/counter/flow.js" "$ROOT/examples/notes-api/flow.js"; do
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
assert_has "each phase browser carries the pgrep marker, scoped to its side port" "$h" '--provenfix-recorder=${new URL(P.base).port'
assert_has "request panel helper" "$h" "request: async (method, path, opts = {})"
assert_has "requests show redirects instead of following them" "$h" "maxRedirects: opts.maxRedirects ?? 0"
assert_has "non-GET requests carry the app Origin like a browser" "$h" "Origin: new URL(P.base).origin"
assert_has "multipart supported" "$h" "o.multipart = opts.multipart"
assert_has "secret-looking body fields hidden" "$h" "isSecret(k) && !keep(k, v) ? '***'"
assert_has "console helper sends the probe token" "$h" "'X-Probe-Token': P.probe.token"
assert_has "console refuses without a probe server" "$h" "ui.console needs P.probe"
assert_has "request line shows the sent URL" "$h" "const sentUrl = new URL(P.base.replace(/\\/+$/, '') + path)"
assert_has "request panel shows non-secret request headers" "$h" "!isSecret(k) && !/^origin\$/i.test(k)"
assert_has "request path gets a leading slash" "$h" "path.startsWith('/')"
assert_has "probe output masked in the console helper" "$h" "const out = hideSecrets(raw.out)"
assert_has "final URL shown when it differs" "$h" "(final: "
assert_has "secret masking in shown text" "$h" "const hideSecrets = "
assert_has "side from label or P.side" "$h" "cannot tell the side from label"
assert_has "request errors keep one line" "$h" "request to \${P.base} failed:"
assert_has "probe errors keep one line" "$h" "probe server unreachable at"
assert_has "stage helper" "$h" "stage: async (title, sub = '')"
assert_has "P.stage draws the stage before recording starts" "$h" "if (P.stage) await renderStage(P.stage, P.stageSub || '')"
assert_has "panels are centred and larger on the stage page" "$h" "const box = staged"
assert_has "single-fetch redirect shown with its real target" "$h" "(single-fetch redirect: "
assert_has "panels feed the transcript" "$h" "transcript.push(text)"
p=$(cat "$ROOT/templates/probes.sh")
assert_has "probes template rejects unknown names" "$p" 'exit 2'
assert_has "probes template states what it touches" "$p" "Touches:"
if bash -n "$ROOT/templates/probes.sh"; then ok "probes template parses"; else not_ok "probes template has a syntax error"; fi

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

# hideSecrets: what the request panel may show (masking is structural, see harness.js).
r=$(node -e '
const fs = require("fs");
const L = {};
eval("(" + fs.readFileSync(process.argv[1], "utf8") + ")")(L);
const hs = L.__ba.hideSecrets;
if (typeof hs !== "function") { console.log("hideSecrets is not exposed"); process.exit(); }
const bad = [];
const chk = (input, has, not) => {
  const o = hs(input);
  for (const s of has) if (!o.includes(s)) bad.push("missing [" + s + "] in " + o);
  for (const s of not) if (o.includes(s)) bad.push("leaked [" + s + "] in " + o);
};
chk("{\"access_token\":\"eyJabc\",\"role\":\"admin\",\"authorized\":false,\"status\":\"forbidden\"}", ["\"access_token\":\"***\"", "\"role\":\"admin\"", "\"authorized\":false", "\"status\":\"forbidden\""], ["eyJabc"]);
chk("{\"password\":\"my pass phrase\"}", [], ["pass phrase"]);
chk("{\"tokens\":[\"a1\",\"b2\"],\"session\":{\"id\":\"sid9\"}}", [], ["a1", "sid9"]);
chk("{\"otp\":\"123456\",\"session_count\":3}", ["\"session_count\":3"], ["123456"]);
chk("{\"url\":\"http://x/reset?token=abc123&x=1\"}", ["x=1"], ["abc123"]);
chk("Location: http://localhost:3000/reset?token=abc123&x=1", [], ["abc123"]);
chk("password_changed: true", ["password_changed: true"], []);
chk("Authorization: Bearer eyJhbGciOi.abc.def", [], ["eyJhbGciOi"]);
chk("footprint=42&error=invalid token", ["footprint=42&error=invalid token"], []);
chk("{\"accessToken\":\"eyJ1\",\"refreshToken\":\"r2\",\"csrfToken\":\"c3\",\"sessionId\":\"s4\",\"newPassword\":\"n5\",\"clientSecret\":\"k6\",\"passwd\":\"p7\",\"userName\":\"ann\"}", ["\"userName\":\"ann\""], ["eyJ1", "r2", "c3", "s4", "n5", "k6", "p7"]);
chk("Authorization: Basic dXNlcjpwYXNz", [], ["dXNlcjpwYXNz"]);
chk("{\"id\":9007199254740993,\"role\":\"viewer\"}", ["9007199254740993"], []);
// React Router single fetch (turbo-stream), bodies encoded with the encoder of react-router 7.12:
// a key and its value live in separate slots of one flat array.
const tsRedirect = JSON.stringify([{"_1":2,"_3":4,"_5":6,"_7":6,"_8":6},"redirect","/login","status",302,"revalidate",false,"reload","replace"]);
const tsLeak = JSON.stringify([{"_1":2},"data",{"_3":4,"_5":6,"_12":13,"_14":15},"ok",true,"provider",{"_7":8,"_9":10,"_11":8},"username","leak-demo-1","password","S3cret!pw9","slug","accessToken","eyJxyz","role","viewer"]);
chk(tsLeak, ["leak-demo-1", "\"viewer\"", "\"password\""], ["S3cret!pw9", "eyJxyz"]);
if (hs(tsRedirect) !== tsRedirect) bad.push("turbo-stream without secrets changed: " + hs(tsRedirect));
if (hs(tsLeak + "\nP1:[\"x\"]").indexOf("S3cret!pw9") >= 0) bad.push("turbo-stream with a streamed tail leaked");
const sfr = L.__ba.singleFetchRedirect;
if (typeof sfr !== "function") bad.push("singleFetchRedirect is not exposed");
else {
  const r = sfr(tsRedirect);
  if (!r || r.status !== 302 || r.to !== "/login") bad.push("redirect not decoded: " + JSON.stringify(r));
  if (sfr(tsLeak) !== null || sfr("{\"redirect\":\"/x\"}") !== null || sfr("not json") !== null) bad.push("false redirect found");
}
for (const big of ["a=".repeat(10000), "a-".repeat(50000), "a.".repeat(50000)]) {
  const t0 = Date.now();
  hs(big);
  if (Date.now() - t0 > 300) bad.push("slow on " + big.slice(0, 4) + ": " + (Date.now() - t0) + " ms");
}
console.log(bad.length ? bad.join("\n") : "hideSecrets ok");' "$ROOT/templates/harness.js" 2>&1)
assert_has "hideSecrets masks secrets and keeps the rest" "$r" "hideSecrets ok"
for f in "$ROOT/templates/flow.js" "$ROOT/examples/counter/flow.js" "$ROOT/examples/notes-api/flow.js"; do
  assert_has "${f#"$ROOT"/} registers its kind" "$(cat "$f")" "loader.__ba = { ...loader.__ba, [KIND]:"
done
done_testing
