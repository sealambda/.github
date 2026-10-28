#!/usr/bin/env bash
#
# The quality gate of this repository: the one place that lists its commands.
# CI runs this script on every supported system, and anyone can run it before
# a push or for each commit of a series:
#
#   scripts/check.sh
#   git rebase -x scripts/check.sh <base>
#
# The gate has two parts:
#
#   1. Every flake below the repository root (for example toolchain/) has a
#      lock file that matches its flake.nix. The root `nix flake check` does
#      not see this: it reads the subflakes' inputs from the root lock file.
#   2. `nix flake check` of the root flake, which runs every formatter,
#      linter and test.
#
# Neither command may write a lock file, so a stale lock fails the gate
# instead of being repaired on the runner. Only a person changes a lock, with
# `nix flake update`.
#
# The script needs Bash 3.2 or later, because macOS ships that version.
#
# Exit status: 0 when the gate passes. Any other status is the status of the
# command that failed, or of Git when it cannot list the flakes.

set -euo pipefail

#######################################
# Fails when the lock file of any flake below the root is stale.
# Globals:
#   FLAKE_LIST: path of the file that holds the NUL-separated flake.nix paths.
# Arguments:
#   None.
# Returns:
#   Non-zero when `nix flake lock` fails for a flake.
#######################################
check_subflake_locks() {
  local flake_file
  while IFS= read -r -d '' flake_file; do
    nix flake lock --no-update-lock-file "./${flake_file%/flake.nix}"
  done <"${FLAKE_LIST}"
}

#######################################
# Runs the gate from the root of the Git repository that holds this script's
# working directory.
# Globals:
#   FLAKE_LIST: set here to a temporary file; removed on exit.
# Arguments:
#   None.
# Returns:
#   Non-zero when Git cannot find the root or list the flakes, or when a
#   flake check fails.
#######################################
main() {
  local root
  root="$(git rev-parse --show-toplevel)"
  cd -- "${root}"

  # Written to a file, not read from `<(git ls-files ...)`: a process
  # substitution hides the exit status of Git, and a failed listing would
  # then pass the gate with no flake checked.
  FLAKE_LIST="$(mktemp)"
  readonly FLAKE_LIST
  trap 'rm -f -- "${FLAKE_LIST}"' EXIT
  git ls-files -z -- '*/flake.nix' >"${FLAKE_LIST}"

  check_subflake_locks
  nix flake check --no-update-lock-file --print-build-logs
}

main "$@"
