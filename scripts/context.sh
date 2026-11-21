#!/usr/bin/env bash
# Read the issue or MR/PR behind a recording (spec step 1), on origin's forge: gh for GitHub, glab otherwise.
#
# context.sh --issue <n> | --mr <n> | --branch <name> | --mine
# stdout: forge=github|gitlab
#         source=issue <n> | mr <n>, then the text with every line prefixed "> " (third-party data)
#         mr=<n> <open|closed|merged> <title>   issue: MRs linked to it; --branch: its MRs in any state; --mine: yours, open
#         issue=<n> <title>                     --mr: issues it closes
#         warn=<text>
# exit:   0 read (no mr=/issue= lines = none found), 1 error or unreadable (no origin, auth, not found, CLI missing)
set -euo pipefail
. "$(dirname "$0")/lib.sh"

[ $# = 2 ] || [ "${1:-}" = --mine ] || die "usage: context.sh --issue <n> | --mr <n> | --branch <name> | --mine"
what=${1#--} arg=${2:-}
case $what in issue|mr|branch|mine) ;; *) die "unknown flag: $1" ;; esac
git rev-parse --git-dir >/dev/null 2>&1 || die "not a git work tree"
git remote get-url origin >/dev/null 2>&1 || die "no origin remote: no forge to read issues or MRs from"
forge=$(ba_forge)
echo "forge=$forge"

# text: quoted line by line so nothing in it can pass for a link line
text() { local t; t=$("$@" 2>&1) || die "cannot read $what $arg: $t"; echo "source=$what $arg"; printf '%s\n' "$t" | sed 's/^/> /'; }
links() { local l; if l=$("$@" 2>&1); then [ -z "$l" ] || printf '%s\n' "$l"; else echo "warn=could not list linked MRs/issues: $(printf '%s' "$l" | head -1)"; fi; }
list() { local l; l=$("$@" 2>&1) || die "cannot list MRs: $l"; [ -z "$l" ] || printf '%s\n' "$l"; }
gl_mrs() { glab api "$1" | ba_json 'j.map(m => "mr=" + m.iid + " " + ({ opened: "open", locked: "closed" }[m.state] || m.state) + " " + m.title)'; }
gl_closes() { glab api "projects/:id/merge_requests/$arg/closes_issues" | ba_json 'j.map(i => "issue=" + i.iid + " " + i.title)'; }
# --json, not --comments: gh before 2.5x asks for classic project cards there, which GitHub now refuses
gh_text='"title: \(.title)\nstate: \(.state)\nurl: \(.url)\n\n\(.body)" + ([.comments[] | "\n--- comment by \(.author.login), \(.createdAt):\n\(.body)"] | join(""))'
gh_mrs='.[] | "mr=\(.number) \(.state | ascii_downcase) \(.title)"'
gql() { # gql <field path> <query body> <jq>: one GraphQL call on this repo
  gh api graphql -F owner='{owner}' -F name='{repo}' -F n="$arg" \
    -f query="query(\$owner: String!, \$name: String!, \$n: Int!) { repository(owner: \$owner, name: \$name) { $1 } }" --jq "$2"
}

if [ "$forge" = github ]; then
  case $what in
    issue) text gh issue view "$arg" --json title,state,url,body,comments --jq "$gh_text"
           links gql 'issue(number: $n) { closedByPullRequestsReferences(first: 10, includeClosedPrs: true) { nodes { number state title } } }' \
             '.data.repository.issue.closedByPullRequestsReferences.nodes[] | "mr=\(.number) \(.state | ascii_downcase) \(.title)"' ;;
    mr)    text gh pr view "$arg" --json title,state,url,body,comments --jq "$gh_text"
           links gql 'pullRequest(number: $n) { closingIssuesReferences(first: 10) { nodes { number title } } }' \
             '.data.repository.pullRequest.closingIssuesReferences.nodes[] | "issue=\(.number) \(.title)"' ;;
    branch) list gh pr list --head "$arg" --state all --json number,state,title --jq "$gh_mrs" ;;
    mine)  list gh pr list --author @me --json number,state,title --jq "$gh_mrs" ;;
  esac
else
  case $what in
    issue) text glab issue view "$arg" --comments
           links gl_mrs "projects/:id/issues/$arg/related_merge_requests" ;;
    mr)    text glab mr view "$arg" --comments
           links gl_closes ;;
    branch) b=$(node -e 'console.log(encodeURIComponent(process.argv[1]))' "$arg")
           list gl_mrs "projects/:id/merge_requests?source_branch=$b&state=all" ;;
    mine)  list gl_mrs "projects/:id/merge_requests?scope=created_by_me&state=opened" ;;
  esac
fi
