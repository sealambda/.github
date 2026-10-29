#!/usr/bin/env bash
#
# Tests .github/actions/head-of-main/head-of-main.sh against a fake curl:
# a match, a mismatch, every way the head can be unreadable, and how the
# request is made (the URL, the flags, and the token kept out of the argument
# list).
#
# Usage: head-of-main.test.sh [REPOSITORY_ROOT]
#   REPOSITORY_ROOT defaults to the root of the tree that holds this file.
#
# Exit status: 0 when every case passes, 1 otherwise.

set -euo pipefail

root="${1:-$(dirname "${BASH_SOURCE[0]}")/../../..}"
# shellcheck disable=SC2034 # read by run_script in lib.sh
readonly SCRIPT="${root}/.github/actions/head-of-main/head-of-main.sh"
# shellcheck source=../../../scripts/ci/release/lib.sh
source "${root}/scripts/ci/release/lib.sh"

readonly COMMIT=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
readonly NEWER=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

# shellcheck disable=SC2034 # read by run_script in lib.sh
readonly -a BASE_ENV=(
  GH_TOKEN=token-for-the-test
  REPOSITORY=sealambda/billing_api
  "COMMIT_SHA=${COMMIT}"
  GITHUB_API_URL=https://api.example.test
)

#######################################
# Makes the fake curl answer like the GitHub API for the ref of main.
# Arguments:
#   The commit SHA of the head.
#######################################
fake_head() {
  fake_response curl 0 "{\"ref\":\"refs/heads/main\",\"object\":{\"sha\":\"$1\",\"type\":\"commit\"}}" ""
}

#######################################
# The commit is the head: the run goes on, and the request is well formed.
#######################################
test_match() {
  reset_case
  fake_head "${COMMIT}"
  expect_success "a run of the head passes" ""
  expect_output_contains "a pass says so" "Commit ${COMMIT} is the head of main"
  expect_log_line "asks for the ref of main of the repository" has curl.log \
    "https://api.example.test/repos/sealambda/billing_api/git/ref/heads/main"
  expect_log_line "fails on an HTTP error" has curl.log "--fail"
  expect_log_line "retries every error" has curl.log "--retry-all-errors"
  expect_flag_value "retries 5 times" curl.log --retry 5
  expect_flag_value "stops retrying after 60 seconds" curl.log --retry-max-time 60
  expect_flag_value "asks for the GitHub JSON type" curl.log --header "Accept: application/vnd.github+json"
  expect_flag_value "pins the version of the GitHub API" curl.log --header "X-GitHub-Api-Version: 2022-11-28"
  expect_log_lacks_text "keeps the token out of the arguments" curl.log "token-for-the-test"
  expect_file "sends the token on standard input" fake/curl.stdin \
    'header = "Authorization: Bearer token-for-the-test"'$'\n'
}

#######################################
# The commit is not the head, or the head cannot be read: the run stops.
#######################################
test_refusals() {
  reset_case
  fake_head "${NEWER}"
  expect_failure "refuses a superseded commit" 1 \
    "Commit ${COMMIT} is not the head of main (${NEWER})"
  fake_response curl 22 "" "curl: (22) The requested URL returned error: 404"
  expect_failure "refuses when the request fails" 1 "Cannot read the head of main of sealambda/billing_api"
  fake_response curl 0 "<html>Bad gateway</html>" ""
  expect_failure "refuses an answer that is not JSON" 1 "is not the JSON that was expected"
  fake_response curl 0 '{"message":"Not Found"}' ""
  expect_failure "refuses an answer without a commit" 1 "holds no commit SHA"
  fake_response curl 0 '{"object":{"sha":null}}' ""
  expect_failure "refuses a null commit" 1 "holds no commit SHA"
  fake_response curl 0 '{"object":{"sha":"abc123"}}' ""
  expect_failure "refuses a short commit" 1 "holds no commit SHA"
  fake_response curl 0 "" ""
  expect_failure "refuses an empty answer" 1 "holds no commit SHA"
}

#######################################
# Runs every case.
#######################################
main() {
  init_sandbox
  test_match
  test_refusals
  finish_tests
}

main
