#!/usr/bin/env bash
# Table tests for check-pull-request.sh. Each case gives a title, a body and
# the commits as JSON lines, and states the expected exit status and a text
# the output must contain. The expectations come from the rules in
# CONTRIBUTING.md, not from the script.
#
# Usage: test.sh   (needs bash and jq; no network)
# Exit status: 0 when every case passes; 1 when any case fails.
set -euo pipefail

CHECK="$(dirname "${BASH_SOURCE[0]}")/check-pull-request.sh"
readonly CHECK

failures=0

# Prints one commit as a JSON line: commit <subject> [parents] [verified] [body].
commit() {
  jq -nc --arg subject "$1" --argjson parents "${2:-1}" --argjson verified "${3:-true}" \
    --arg body "${4:-}" \
    '{sha: "0123456789abcdef", parents: $parents, verified: $verified,
      message: (if $body == "" then $subject else $subject + "\n\n" + $body end)}'
}

# Runs one case: expect <name> <status> <text> <title> <body> [commit lines…].
expect() {
  local name="$1" want_status="$2" want_text="$3" title="$4" body="$5"
  shift 5
  local output got_status=0
  output="$(printf '%s\n' "$@" | PR_TITLE="$title" PR_BODY="$body" "$CHECK" 2>&1)" || got_status=$?
  if [ "$got_status" != "$want_status" ] || [[ "$output" != *"$want_text"* ]]; then
    echo "FAIL $name: status $got_status (want $want_status), output: $output"
    failures=$((failures + 1))
  else
    echo "ok   $name"
  fi
}

long_subject="fix: $(printf 'a%.0s' $(seq 1 68))"
max_subject="fix: $(printf 'a%.0s' $(seq 1 67))"

expect "clean pull request" 0 "" \
  "feat(tofu): add the backup root" "" \
  "$(commit 'feat(tofu): add the backup root')" "$(commit 'docs: describe the backup root')"
expect "breaking change and nested scope" 0 "" \
  "refactor(hq/staging)!: drop the old queue" "" "$(commit 'refactor(hq/staging)!: drop the old queue')"
expect "subject of 72 characters" 0 "" "$max_subject" "" "$(commit "$max_subject")"
expect "Assisted-by is allowed" 0 "" "fix: x" "" \
  "$(commit 'fix: x' 1 true 'Assisted-by: Claude Code (claude-opus-5-5)')"
expect "a person named Claude" 0 "" "fix: x" "Co-authored-by: Claude Monet <claude@example.com>" "$(commit 'fix: x')"

expect "title not a Conventional Commit" 1 "Pull request title" "Fix stuff" "" "$(commit 'fix: x')"
expect "title of 73 characters" 1 "the limit is 72" "$long_subject" "" "$(commit 'fix: x')"
expect "empty summary" 1 "is not 'type(scope)!: summary'" "feat: " "" "$(commit 'fix: x')"
expect "unknown type" 1 "is not 'type(scope)!: summary'" "feature: x" "" "$(commit 'fix: x')"
expect "subject in the middle of the stack" 1 "Commit 0123456789ab" "fix: x" "" \
  "$(commit 'fix: x')" "$(commit 'WIP')" "$(commit 'fix: y')"
expect "leftover fixup commit" 1 "git rebase -i --autosquash" "fix: x" "" "$(commit 'fixup! fix: x')"
expect "merge commit inside the pull request" 1 "rebase the branch onto its base" "fix: x" "" \
  "$(commit "fix: x" 2)"
expect "unsigned commit" 1 "signature is missing" "fix: x" "" "$(commit 'fix: x' 1 false)"
expect "AI co-author in a commit" 1 "credit AI help with an Assisted-by" "fix: x" "" \
  "$(commit 'fix: x' 1 true 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>')"
expect "Copilot co-author in the body" 1 "Pull request body" "fix: x" \
  "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" "$(commit 'fix: x')"

expect "no title" 2 "usage:" "" "" "$(commit 'fix: x')"
expect "broken commit line" 2 "not valid JSON" "fix: x" "" "not json"

if [ "$failures" -gt 0 ]; then
  echo "$failures case(s) failed"
  exit 1
fi
echo "all cases passed"
