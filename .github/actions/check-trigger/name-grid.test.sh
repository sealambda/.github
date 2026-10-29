#!/usr/bin/env bash
#
# Tests the repository-name rule of check-trigger.sh over a generated grid of
# names, against verdicts that the Nix side computed on its own
# (nix/name-grid-oracle.nix: the AWS patterns of an ECR repository name and of
# an IAM role name, matched by Nix, not by this script's regular expression).
#
# The oracle sorts each name into one of three classes:
#   invalid  ECR or IAM would refuse the name.
#   strict   Both accept it and it has no two separators in a row.
#   doubled  Both accept it, and it has `__`, `--` or the like. ECR allows
#            these; this workflow refuses them by design.
# The rule must accept exactly the strict names. That makes it sound (it never
# accepts a name that ECR or IAM would refuse) and shows that the only valid
# names it refuses are the doubled ones.
#
# The flake check `check-trigger` runs this test (flake.nix) and sets
# NAME_GRID_EXPECTED.
#
# Usage: name-grid.test.sh [REPOSITORY_ROOT]
#   REPOSITORY_ROOT defaults to the root of the tree that holds this file.
#
# Environment:
#   NAME_GRID_EXPECTED  The path of a file with one `name<TAB>class` line per
#                       name (required).
#
# Exit status: 0 when the rule agrees on every name, 1 otherwise.

set -euo pipefail

expected_file="${NAME_GRID_EXPECTED:?set NAME_GRID_EXPECTED to the file of expected classes}"
root="${1:-$(dirname "${BASH_SOURCE[0]}")/../../..}"
# shellcheck source=../../../.github/actions/check-trigger/check-trigger.sh
source "${root}/.github/actions/check-trigger/check-trigger.sh"

#######################################
# Compares the rule with the oracle on every name of the file.
# Arguments:
#   The path of the file.
# Globals:
#   failures, set by check_repository_name in check-trigger.sh.
# Outputs:
#   Writes each disagreement and the totals.
# Returns:
#   Exits 1 on a disagreement, or when a class has no name.
#######################################
compare_all() {
  local name class accepted should_accept disagreements=0 total=0
  local -A per_class=([invalid]=0 [strict]=0 [doubled]=0)
  while IFS=$'\t' read -r name class; do
    failures=0
    check_repository_name "grid/${name}" >/dev/null
    accepted=false
    if ((failures == 0)); then
      accepted=true
    fi
    should_accept=false
    if [[ ${class} == strict ]]; then
      should_accept=true
    fi
    total=$((total + 1))
    per_class[${class}]=$((per_class[${class}] + 1))
    if [[ ${should_accept} != "${accepted}" ]]; then
      echo "FAIL '${name}': class ${class}, accepted by the rule: ${accepted}" >&2
      disagreements=$((disagreements + 1))
    fi
  done <"$1"
  echo "${total} names: ${per_class[invalid]} invalid, ${per_class[strict]} strict, ${per_class[doubled]} doubled; ${disagreements} disagreements"
  # An oracle that sorted every name into one class would test nothing.
  if ((disagreements > 0 || per_class[invalid] == 0 || per_class[strict] == 0 || per_class[doubled] == 0)); then
    exit 1
  fi
}

compare_all "${expected_file}"
