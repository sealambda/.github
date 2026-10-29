#!/usr/bin/env bash
# Audit the dependencies of every Mix project in a checkout with `mix hex.audit`.
#
# A Mix project is a directory with a tracked `mix.lock`, at any depth; a
# vendored dependency whose `mix.lock` is tracked counts as a project too. In
# each project the script runs, inside the default dev shell of the flake at the
# root of the checkout (`nix develop --no-update-lock-file`, so that the audit
# never rewrites the flake's lock file and fails when the lock file is not
# current):
#
#   mix hex.info    fails when the shell has no Hex, instead of letting Mix
#                   download whatever Hex version hex.pm serves that day
#   mix deps.get    `mix hex.audit` reads the dependencies before `mix.lock`
#   mix hex.audit   fails on a retired package or a package with an advisory
#
# Every project is audited, even after a failure, so that one report names all
# failing projects. Contract: docs/reference/workflows.md#dependency-audits.
#
# Usage: mix-audit.sh
#   Run it from the root of the checkout. It takes no arguments.
#
# Requirements: Bash 4.4 or later (`mapfile -d`, namerefs), git, nix.
#
# Exit status: 0 when every project passes or when there is no Mix project;
# 1 when an audit fails or when git cannot list the tracked files.
set -euo pipefail

# Set `projects` to the directories of the tracked Mix projects, relative to
# the current directory: `.` for a root `mix.lock`. Names are NUL-delimited all
# the way, so a space, a leading `-` or a non-ASCII character is safe.
#
# The list goes through a file because a failure of `git` would otherwise hide
# in a pipeline or in a process substitution, and the audit would pass on an
# empty list.
#
# Arguments: the name of the array variable to fill.
# Exit status: exits the script with 1 when `git ls-files` fails.
find_mix_projects() {
  local -n found="${1}"
  local list lock dir
  local -a locks
  list="$(mktemp)"
  if ! git ls-files -z -- 'mix.lock' '**/mix.lock' >"${list}"; then
    rm -f -- "${list}"
    echo "::error::git could not list the tracked files, so the Mix projects are unknown."
    exit 1
  fi
  mapfile -d '' -t locks <"${list}"
  rm -f -- "${list}"
  found=()
  for lock in "${locks[@]}"; do
    dir="${lock%mix.lock}"
    dir="${dir%/}"
    found+=("${dir:-.}")
  done
}

# Audit every project, in its own directory and with the flake at the root.
# A failing project does not stop the loop.
#
# Arguments: the name of the array variable that receives the failing
# directories, the flake root, then the project directories.
# Exit status: always 0; the caller reads the failures from the array.
audit_projects() {
  local -n failed_dirs="${1}"
  local root="${2}"
  shift 2
  local dir
  for dir in "$@"; do
    echo "::group::${dir}"
    if ! (cd -- "${dir}" && nix develop --no-update-lock-file "${root}" --command \
      sh -c 'mix hex.info && mix deps.get && mix hex.audit'); then
      failed_dirs+=("${dir}")
    fi
    echo "::endgroup::"
  done
}

# Print one error line that names the failing directories, each in quotes.
# Arguments: the failing directories.
report_failures() {
  local joined="" dir
  for dir in "$@"; do
    joined+="${joined:+, }'${dir}'"
  done
  echo "::error::mix hex.audit failed in: ${joined}"
}

# Audit the Mix projects of the checkout in the current directory.
# Exit status: see the header.
main() {
  local -a projects=() failed=()
  find_mix_projects projects
  if ((${#projects[@]} == 0)); then
    echo "No tracked mix.lock: nothing to audit."
    return 0
  fi
  audit_projects failed "${PWD}" "${projects[@]}"
  if ((${#failed[@]} > 0)); then
    report_failures "${failed[@]}"
    return 1
  fi
}

main
