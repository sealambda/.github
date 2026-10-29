#!/usr/bin/env bash
#
# Tests .github/actions/check-trigger/check-trigger.sh: what it accepts, what
# it refuses and with which message, and the names it writes. Every expected
# value below is written by hand from the rules in the script's header.
#
# Usage: check-trigger.test.sh [REPOSITORY_ROOT]
#   REPOSITORY_ROOT defaults to the root of the tree that holds this file.
#
# Exit status: 0 when every case passes, 1 otherwise.

set -euo pipefail

root="${1:-$(dirname "${BASH_SOURCE[0]}")/../../..}"
# shellcheck disable=SC2034 # read by run_script in lib.sh
readonly SCRIPT="${root}/.github/actions/check-trigger/check-trigger.sh"
# shellcheck source=../../../scripts/ci/release/lib.sh
source "${root}/scripts/ci/release/lib.sh"

# shellcheck disable=SC2034 # read by run_script in lib.sh
readonly -a BASE_ENV=(
  DRY_RUN=false
  EVENT_NAME=push
  REF=refs/heads/main
  REPOSITORY=sealambda/billing_api
  REPOSITORY_OWNER_ID=59837963
  AWS_ACCOUNT_ID=123456789012
  AWS_REGION=eu-west-1
)

readonly REGISTRY=123456789012.dkr.ecr.eu-west-1.amazonaws.com

#######################################
# Expects a repository to be accepted, and the step outputs for its name.
# Arguments:
#   The name of the case.
#   The repository, `owner/name`.
#   The ECR repository name that the step must produce.
#######################################
expect_names() {
  local expected="repository=$3
role=arn:aws:iam::123456789012:role/release-push-$3
registry=${REGISTRY}
image=${REGISTRY}/$3"
  expect_success "$1" "${expected}" "REPOSITORY=$2"
}

#######################################
# Cases of a release that must be accepted, and the names they produce.
#######################################
test_accepted() {
  local long
  long="$(printf 'a%.0s' {1..51})"
  reset_case
  expect_names "accepts a push to main" sealambda/billing_api billing_api
  expect_names "lower-cases the name" sealambda/Sink sink
  expect_names "accepts a dot between parts" sealambda/web.app web.app
  expect_names "accepts a dash between parts" sealambda/ops-tools ops-tools
  expect_names "accepts 2 characters" sealambda/ab ab
  expect_names "accepts 51 characters" "sealambda/${long}" "${long}"
  expect_names "accepts 51 mixed-case characters" "sealambda/${long^^}" "${long}"
}

#######################################
# A dry run skips every check: a pull request of a fork has another event, ref
# and owner, a dry run has no registry, and the hub runs its own dry run in the
# repository `.github`, whose name the name rule refuses.
#######################################
test_dry_run() {
  reset_case
  expect_success "a dry run names nothing" "" \
    DRY_RUN=true EVENT_NAME=pull_request REF=refs/pull/7/merge \
    REPOSITORY=fork-owner/.github REPOSITORY_OWNER_ID=1 AWS_ACCOUNT_ID= AWS_REGION=
  expect_output_contains "a dry run says so" "Dry run"
  # The hub's own dry run runs in `.github`, a name that a release refuses.
  expect_success "a dry run skips the name rule" "" DRY_RUN=true REPOSITORY=sealambda/.github
  expect_failure "dry-run must be true or false" 1 "Input dry-run must be true or false" DRY_RUN=maybe
  expect_failure "an empty dry-run is refused" 1 "Input dry-run must be true or false" DRY_RUN=
}

#######################################
# Cases of the event, the ref and the owner.
#######################################
test_trigger() {
  reset_case
  expect_failure "refuses a pull request" 1 "not on 'pull_request' of 'refs/heads/main'" EVENT_NAME=pull_request
  expect_failure "refuses a manual run" 1 "not on 'workflow_dispatch'" EVENT_NAME=workflow_dispatch
  expect_failure "refuses another branch" 1 "of 'refs/heads/other'" REF=refs/heads/other
  expect_failure "refuses a tag" 1 "of 'refs/tags/v1'" REF=refs/tags/v1
  expect_failure "refuses a branch that only starts like main" 1 "of 'refs/heads/main2'" REF=refs/heads/main2
  expect_failure "refuses another owner" 1 "not owner ID '1'" REPOSITORY_OWNER_ID=1
  expect_failure "refuses an owner ID that only starts like the organization's" 1 "not owner ID '598379631'" REPOSITORY_OWNER_ID=598379631
  expect_failure "reports every failed check" 1 "Input aws-region must be" \
    EVENT_NAME=pull_request REPOSITORY_OWNER_ID=1 AWS_REGION=nowhere
  expect_output_contains "reports the event too" "A release runs on a push to main"
  expect_output_contains "reports the owner too" "Only repositories of the sealambda organization"
}

#######################################
# Cases of the account and the region.
#######################################
test_registry() {
  reset_case
  expect_failure "refuses 11 digits" 1 "Input aws-account-id must be 12 digits" AWS_ACCOUNT_ID=12345678901
  expect_failure "refuses 13 digits" 1 "Input aws-account-id must be 12 digits" AWS_ACCOUNT_ID=1234567890123
  expect_failure "refuses letters" 1 "Input aws-account-id must be 12 digits" AWS_ACCOUNT_ID=12345678901a
  expect_failure "refuses a newline after the digits" 1 "Input aws-account-id must be 12 digits" "AWS_ACCOUNT_ID=123456789012"$'\n'
  expect_failure "refuses an empty account" 1 "Input aws-account-id must be 12 digits" AWS_ACCOUNT_ID=
  expect_failure "refuses upper case in the region" 1 "Input aws-region must be an AWS region" AWS_REGION=EU-WEST-1
  # Each of the next two names holds a valid region after a prefix; only an anchor at the start refuses them.
  expect_failure "refuses a letter before the region" 1 "Input aws-region must be an AWS region" AWS_REGION=xeu-west-1
  expect_failure "refuses a digit before the region" 1 "Input aws-region must be an AWS region" AWS_REGION=1eu-west-1
  expect_failure "refuses a region without a number" 1 "Input aws-region must be an AWS region" AWS_REGION=eu-west-
  expect_failure "refuses a newline after the region" 1 "Input aws-region must be an AWS region" "AWS_REGION=eu-west-1"$'\n'
  expect_failure "refuses an empty region" 1 "Input aws-region must be an AWS region" AWS_REGION=
}

#######################################
# Cases of the repository name: the boundaries of the rule.
#######################################
test_names() {
  local long
  long="$(printf 'a%.0s' {1..51})"
  reset_case
  expect_failure "refuses the .github repository" 1 "Repository name '.github' is refused" REPOSITORY=sealambda/.github
  expect_failure "refuses 1 character" 1 "Repository name 'a' is refused" REPOSITORY=sealambda/a
  expect_failure "refuses 52 characters" 1 "is refused" "REPOSITORY=sealambda/${long}a"
  expect_failure "refuses 52 mixed-case characters" 1 "is refused" "REPOSITORY=sealambda/${long^^}A"
  expect_failure "refuses a doubled dash" 1 "(ECR allows more)" REPOSITORY=sealambda/a--b
  expect_failure "refuses a doubled underscore" 1 "is refused" REPOSITORY=sealambda/a__b
  expect_failure "refuses a dot next to a dash" 1 "is refused" REPOSITORY=sealambda/a.-b
  expect_failure "refuses a trailing dot" 1 "is refused" REPOSITORY=sealambda/ab.
  expect_failure "refuses a trailing underscore" 1 "is refused" REPOSITORY=sealambda/ab_
  expect_failure "refuses a trailing dash" 1 "is refused" REPOSITORY=sealambda/ab-
  expect_failure "refuses a leading dash" 1 "is refused" REPOSITORY=sealambda/-ab
  expect_failure "refuses a leading underscore" 1 "is refused" REPOSITORY=sealambda/_ab
  expect_failure "names the rule in the message" 1 "2 to 51 characters" REPOSITORY=sealambda/a
}

#######################################
# Runs every case.
#######################################
main() {
  init_sandbox
  test_accepted
  test_dry_run
  test_trigger
  test_registry
  test_names
  finish_tests
}

main
