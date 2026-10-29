#!/usr/bin/env bash
#
# Decides whether a workflow run may release an image, and names the image.
#
# A release is a push to main of a repository of the organization, with a
# valid registry. The AWS role refuses any other ref and any other owner; this
# script fails earlier and says why, before the gate spends its time. A dry run
# builds and pushes nothing, so it skips every check, the repository-name rule
# included, and names nothing. The rule cannot apply: the hub's own dry run
# runs in `.github`, a name that the rule refuses. A repository whose name the
# rule refuses passes a dry run and fails at its first release.
#
# The names come from the repository name alone, so no input can name another
# repository's image or role. The account and the region choose only where the
# role is looked up. ECR wants lower case and an alphanumeric first character;
# an IAM role name has at most 64 characters, 13 of them `release-push-`. GitHub
# repository names are unique without regard to case, so lower case maps two
# repositories to one name never.
#
# The head of main is checked by the head-of-main action, which this script's
# action (action.yml) runs after this script.
#
# Environment (all required):
#   DRY_RUN              `true` or `false`.
#   EVENT_NAME           github.event_name.
#   REF                  github.ref.
#   REPOSITORY           github.repository, `owner/name`.
#   REPOSITORY_OWNER_ID  github.repository_owner_id.
#   AWS_ACCOUNT_ID       The 12 digits of the AWS account of the registry.
#   AWS_REGION           The AWS region of the registry.
#   GITHUB_OUTPUT        The file of the step outputs.
#
# Outputs (written to GITHUB_OUTPUT, empty in a dry run): repository, role,
# registry, image.
#
# Exit status: 0 when the run may release or is a dry run, 1 when a check
# fails. Each failed check prints a `::error::` line.

# The inputs are environment variables, listed above and set by action.yml, so
# ShellCheck cannot see where they are assigned.
# shellcheck disable=SC2154
set -euo pipefail

# The account ID of the sealambda organization. The IAM trust policy also
# requires it; an identifier, unlike a name, cannot be freed and reclaimed.
readonly SEALAMBDA_OWNER_ID=59837963

# ECR repository names have at least 2 characters.
readonly MIN_NAME_LENGTH=2

# An IAM role name has at most 64 characters, 13 of them `release-push-`.
readonly MAX_NAME_LENGTH=51

# One alphanumeric run, then runs joined by a single `.`, `_` or `-`. ECR allows
# more (`__` and runs of `-`); this workflow accepts the stricter rule.
readonly NAME_PATTERN='^[a-z0-9]+([._-][a-z0-9]+)*$'

readonly ACCOUNT_PATTERN='^[0-9]{12}$'
readonly REGION_PATTERN='^[a-z]{2}(-[a-z]+)+-[0-9]+$'

# The number of failed checks. The check functions add to it, so that a failed
# check never depends on `set -e` inside a condition.
failures=0

# The lower-case repository name; set by check_repository_name.
repository_name=''

#######################################
# Records a failed check.
# Arguments:
#   The message.
# Outputs:
#   Writes a `::error::` workflow command to stdout.
# Globals:
#   failures: incremented.
#######################################
fail() {
  echo "::error::$1"
  failures=$((failures + 1))
}

#######################################
# Checks that the run is a push to main.
# Globals:
#   EVENT_NAME, REF
#######################################
check_event() {
  if [[ ${EVENT_NAME} != push || ${REF} != refs/heads/main ]]; then
    fail "A release runs on a push to main, not on '${EVENT_NAME}' of '${REF}'."
  fi
}

#######################################
# Checks that the repository belongs to the organization, by owner ID.
# Globals:
#   REPOSITORY_OWNER_ID
#######################################
check_owner() {
  if [[ ${REPOSITORY_OWNER_ID} != "${SEALAMBDA_OWNER_ID}" ]]; then
    fail "Only repositories of the sealambda organization (owner ID ${SEALAMBDA_OWNER_ID}) release images, not owner ID '${REPOSITORY_OWNER_ID}'."
  fi
}

#######################################
# Checks the account and the region of the registry. The messages do not repeat
# the values, which the caller controls.
# Globals:
#   AWS_ACCOUNT_ID, AWS_REGION
#######################################
check_registry() {
  if [[ ! ${AWS_ACCOUNT_ID} =~ ${ACCOUNT_PATTERN} ]]; then
    fail "Input aws-account-id must be 12 digits."
  fi
  if [[ ! ${AWS_REGION} =~ ${REGION_PATTERN} ]]; then
    fail "Input aws-region must be an AWS region such as eu-west-1."
  fi
}

#######################################
# Checks the repository name against the rule of the names section above.
# Arguments:
#   The repository, `owner/name`.
# Globals:
#   repository_name: set to the lower-case name.
#######################################
check_repository_name() {
  local name="${1#*/}"
  repository_name="${name,,}"
  if [[ ! ${repository_name} =~ ${NAME_PATTERN} ]] \
    || ((${#repository_name} < MIN_NAME_LENGTH || ${#repository_name} > MAX_NAME_LENGTH)); then
    fail "Repository name '${repository_name}' is refused: this workflow accepts ${MIN_NAME_LENGTH} to ${MAX_NAME_LENGTH} characters, lower case letters and digits, and a single '.', '_' or '-' between them (ECR allows more)."
  fi
}

#######################################
# Writes the names of the image and the role to the step outputs.
# Globals:
#   repository_name, AWS_ACCOUNT_ID, AWS_REGION, GITHUB_OUTPUT
#######################################
write_names() {
  local registry="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  {
    echo "repository=${repository_name}"
    echo "role=arn:aws:iam::${AWS_ACCOUNT_ID}:role/release-push-${repository_name}"
    echo "registry=${registry}"
    echo "image=${registry}/${repository_name}"
  } >>"${GITHUB_OUTPUT}"
}

#######################################
# Runs every check, then writes the names. A dry run skips both.
# Globals:
#   DRY_RUN and the variables of the checks above.
#######################################
main() {
  case "${DRY_RUN}" in
    true)
      echo "::notice::Dry run: the image is built and not pushed."
      exit 0
      ;;
    false) ;;
    *)
      fail "Input dry-run must be true or false."
      exit 1
      ;;
  esac
  check_event
  check_owner
  check_registry
  check_repository_name "${REPOSITORY}"
  if ((failures > 0)); then
    exit 1
  fi
  write_names
}

# Run only when executed; the tests source this file to call the functions.
if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
  main
fi
