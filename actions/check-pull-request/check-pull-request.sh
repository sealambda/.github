#!/usr/bin/env bash
# Check a pull request against the organization's collaboration rules
# (CONTRIBUTING.md in this repository) before it merges:
#   - the title is a Conventional Commit: it becomes the merge commit's subject;
#   - every commit is one commit of curated history, as it lands on main:
#       a Conventional Commits subject of at most 72 characters,
#       no fixup!/squash!/amend! commit left for `git rebase --autosquash`,
#       one parent (the branch is rebased, never merged into),
#       a signature that GitHub verified;
#   - no commit and not the body credits an AI model or agent as co-author.
#     Disclose AI help with an `Assisted-by:` trailer instead.
#
# Usage: PR_TITLE=… [PR_BODY=…] check-pull-request.sh < commits
#   PR_TITLE  the pull request title (required)
#   PR_BODY   the pull request body (may be empty)
#   stdin     one JSON object per commit, in any order:
#             {"sha": "…", "parents": 1, "verified": true, "message": "…"}
#
# The check reads only its input; action.yml beside it fetches the commits.
# Agents are matched by the email of the trailer, not by the name, so a person
# named Claude is not flagged.
#
# Needs bash and jq. Prints one GitHub Actions `::error::` line per problem.
# Exit status: 0 when the pull request passes; 1 when it fails a check;
# 2 when PR_TITLE is not set or a commit line is not valid JSON.
set -euo pipefail

readonly TYPES="feat|fix|docs|build|ci|refactor|perf|test|chore|revert"
readonly SUBJECT_PATTERN="^($TYPES)(\([a-z0-9/_.-]+\))?!?: [^ ]"
readonly AUTOSQUASH_PATTERN="^(fixup|squash|amend)! "
readonly SUBJECT_MAX_LENGTH=72

# Emails that AI models and agents write into Co-authored-by trailers:
# Anthropic's Claude, GitHub Copilot (<id>+Copilot@users.noreply.github.com)
# and OpenAI's agents.
readonly AGENT_EMAIL_PATTERN='noreply@anthropic\.com|\+Copilot@users\.noreply\.github\.com|@openai\.com'

status=0

# Prints one error annotation and marks the check as failed.
fail() {
  echo "::error title=$1::$2"
  status=1
}

# Checks one subject line: the title, or a commit's first line. `$1` names
# what is checked in the messages.
check_subject() {
  local what="$1" subject="$2"
  if [[ "$subject" =~ $AUTOSQUASH_PATTERN ]]; then
    fail "$what" "'$subject' is a fixup commit; run git rebase -i --autosquash before merging"
    return
  fi
  if ! [[ "$subject" =~ $SUBJECT_PATTERN ]]; then
    fail "$what" "'$subject' is not 'type(scope)!: summary' with a type of $TYPES"
  fi
  if [ "${#subject}" -gt "$SUBJECT_MAX_LENGTH" ]; then
    fail "$what" "'$subject' has ${#subject} characters; the limit is $SUBJECT_MAX_LENGTH"
  fi
}

# Checks the trailers of one message for an AI co-author.
check_co_authors() {
  local what="$1" message="$2" trailer
  while IFS= read -r trailer; do
    [ -n "$trailer" ] || continue
    fail "$what" "remove '$trailer'; credit AI help with an Assisted-by: trailer, never as co-author"
  done < <(grep -iE '^co-authored-by:' <<<"$message" | grep -iE "$AGENT_EMAIL_PATTERN" || true)
}

# Checks one commit, given as one JSON line.
check_commit() {
  local line="$1" sha parents verified message
  if ! sha="$(jq -er '.sha[0:12]' <<<"$line" 2>/dev/null)"; then
    echo "error: a commit line is not valid JSON with a sha: $line" >&2
    exit 2
  fi
  parents="$(jq -r '.parents' <<<"$line")"
  verified="$(jq -r '.verified' <<<"$line")"
  message="$(jq -r '.message' <<<"$line")"

  check_subject "Commit $sha" "${message%%$'\n'*}"
  if [ "$parents" != 1 ]; then
    fail "Commit $sha" "a merge commit inside the pull request; rebase the branch onto its base instead"
  fi
  if [ "$verified" != true ]; then
    fail "Commit $sha" "the signature is missing or GitHub did not verify it; sign commits (git config commit.gpgsign true)"
  fi
  check_co_authors "Commit $sha" "$message"
}

if [ -z "${PR_TITLE:-}" ]; then
  echo "usage: PR_TITLE=<title> [PR_BODY=<body>] $0 < commits" >&2
  exit 2
fi

check_subject "Pull request title" "$PR_TITLE"
check_co_authors "Pull request body" "${PR_BODY:-}"
while IFS= read -r line; do
  [ -n "$line" ] || continue
  check_commit "$line"
done

exit "$status"
