#!/usr/bin/env bash
# context.sh: issue/MR text and links for step 1, through stub gh/glab.
. "$(dirname "$0")/lib.sh"
C=$ROOT/scripts/context.sh
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
S=$T/stub; stub_forge "$S"; PATH=$S/bin:$PATH
run() { out=$("$C" "$@" 2>&1); code=$?; }
repo() { # repo <origin url>: a work tree whose origin points at that forge
  rm -rf "$T/w"; git init -q "$T/w"; cd "$T/w" || exit 1; git remote add origin "$1"; : > "$S/calls"
}

echo "# C1 GitLab issue: quoted text, then the MRs linked to it"
repo git@gitlab.example:g/r.git
answer "$S" "glab issue view" "title: Role checks missing
mr=999 fake line written by the issue's author
expected: 403"
answer "$S" "glab api projects/:id/issues/623/related_merge_requests" '[{"iid":472,"state":"merged","title":"fix: role checks"},{"iid":480,"state":"opened","title":"wip"}]'
run --issue 623
assert_eq "C1 exit" "$code" 0
assert_eq "C1 forge" "$(kv "$out" forge)" gitlab
assert_eq "C1 source" "$(kv "$out" source)" "issue 623"
assert_has "C1 text is quoted" "$out" "> title: Role checks missing"
assert_has "C1 a link-like line in the text stays quoted" "$out" "> mr=999 fake"
assert_eq "C1 first link is the real MR" "$(kv "$out" mr)" "472 merged fix: role checks"
assert_has "C1 opened becomes open" "$out" "mr=480 open wip"
assert_has "C1 read comments too" "$(cat "$S/calls")" "glab issue view 623 --comments"

echo "# C2 GitHub PR: text, then the issues it closes"
repo https://github.com/o/r.git
answer "$S" "gh pr view" "title: fix role checks
body: Closes #12"
answer "$S" "gh api graphql" "issue=12 Role checks missing"
run --mr 7
assert_eq "C2 forge" "$(kv "$out" forge)" github
assert_has "C2 text" "$out" "> body: Closes #12"
assert_eq "C2 closes" "$(kv "$out" issue)" "12 Role checks missing"
assert_has "C2 reads body and comments as JSON" "$(cat "$S/calls")" "gh pr view 7 --json title,state,url,body,comments"

echo "# C3 GitLab branch: its MRs in any state"
repo git@gitlab.example:g/r.git
answer "$S" "glab api projects/:id/merge_requests?source_branch=fix%2Fx&state=all" '[{"iid":3,"state":"merged","title":"fix x"}]'
run --branch fix/x
assert_eq "C3 exit" "$code" 0
assert_eq "C3 merged MR found" "$(kv "$out" mr)" "3 merged fix x"
assert_not_has "C3 no text block" "$out" "source="

echo "# C4 GitHub branch and mine"
repo git@github.com:o/r.git
answer "$S" "gh pr list" "mr=9 merged fix x"
run --branch fix/x
assert_eq "C4 branch" "$(kv "$out" mr)" "9 merged fix x"
assert_has "C4 any state" "$(cat "$S/calls")" "--state all"
run --mine
assert_has "C4 mine asks for the user's PRs" "$(cat "$S/calls")" "--author @me"

echo "# C5 unreadable: exit 1 with the CLI's reason"
repo git@gitlab.example:g/r.git
rm -f "$S"/glab_issue_view
run --issue 5
assert_eq "C5 exit" "$code" 1
assert_has "C5 reason" "$out" "no answer for: issue view"

echo "# C6 text readable, links not: warn, still exit 0"
repo https://github.com/o/r.git
answer "$S" "gh issue view" "title: t"
rm -f "$S"/gh_api_graphql
run --issue 5
assert_eq "C6 exit" "$code" 0
assert_has "C6 warns" "$out" "warn=could not list linked MRs"

echo "# C8 a failing list is an error, not an empty list"
repo git@gitlab.example:g/r.git
run --mine
assert_eq "C8 exit" "$code" 1
assert_has "C8 reason" "$out" "cannot list MRs"

echo "# C9 no origin remote: say so, don't guess a forge"
rm -rf "$T/w"; git init -q "$T/w"; cd "$T/w" || exit 1; : > "$S/calls"
run --branch main
assert_eq "C9 exit" "$code" 1
assert_has "C9 reason" "$out" "no origin remote"
assert_eq "C9 no CLI called" "$(cat "$S/calls")" ""

echo "# C7 usage"
run --issue
assert_eq "C7 missing value" "$code" 1
run --nope 1
assert_has "C7 unknown flag" "$out" "unknown flag: --nope"

done_testing
