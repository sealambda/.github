#!/usr/bin/env bash
#
# Fails unless the commit of this run is the current head of main.
#
# A re-run keeps its commit and its ref, and two quick pushes can finish in
# either order, so a run can hold a commit that a newer head of main has
# superseded. The release builds the head only. The check fails closed: when
# the head cannot be read, the run stops.
#
# The workflow runs this check twice, before the credentials and before the
# tag is put. It refuses a commit that a newer head has superseded. It does not
# close the seconds between the last check and the tag; a commit released in
# that window was the head when the check ran.
#
# The token goes to curl on standard input, so it never appears in a process
# listing.
#
# Environment (all required):
#   GH_TOKEN         A token that can read the contents of REPOSITORY.
#   REPOSITORY       `owner/name`.
#   COMMIT_SHA       The commit of this run, 40 hexadecimal digits.
#   GITHUB_API_URL   The URL of the GitHub REST API.
#
# Exit status: 0 when COMMIT_SHA is the head of main, 1 otherwise. A failure
# prints a `::error::` line.

# The inputs are environment variables, listed above and set by action.yml, so
# ShellCheck cannot see where they are assigned.
# shellcheck disable=SC2154
set -euo pipefail

readonly SHA_PATTERN='^[0-9a-f]{40}$'

#######################################
# Prints an error and stops the run.
# Arguments:
#   The message.
# Outputs:
#   Writes a `::error::` workflow command to stdout.
#######################################
die() {
  echo "::error::$1"
  exit 1
}

#######################################
# Compares the commit of the run with the head of main.
# Globals:
#   GH_TOKEN, REPOSITORY, COMMIT_SHA, GITHUB_API_URL
# Outputs:
#   Writes a line to stdout when the commit is the head.
#######################################
main() {
  local body head_sha
  if ! body="$(
    curl --fail --silent --show-error \
      --retry 5 --retry-all-errors --retry-max-time 60 \
      --header 'Accept: application/vnd.github+json' \
      --header 'X-GitHub-Api-Version: 2022-11-28' \
      --config - \
      "${GITHUB_API_URL}/repos/${REPOSITORY}/git/ref/heads/main" \
      <<<"header = \"Authorization: Bearer ${GH_TOKEN}\""
  )"; then
    die "Cannot read the head of main of ${REPOSITORY}; a release does not go on without it."
  fi
  if ! head_sha="$(jq -r '.object.sha // empty' <<<"${body}")"; then
    die "The answer about the head of main of ${REPOSITORY} is not the JSON that was expected."
  fi
  if [[ ! ${head_sha} =~ ${SHA_PATTERN} ]]; then
    die "The answer about the head of main of ${REPOSITORY} holds no commit SHA."
  fi
  if [[ ${head_sha} != "${COMMIT_SHA}" ]]; then
    die "Commit ${COMMIT_SHA} is not the head of main (${head_sha}). A release builds the head only; release the newer commit."
  fi
  echo "Commit ${COMMIT_SHA} is the head of main."
}

main
