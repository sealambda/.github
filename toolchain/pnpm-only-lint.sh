#!/usr/bin/env bash
#
# Fails when a repository tracks the files of a JavaScript package manager
# other than pnpm.
#
# The organization uses pnpm only, and the toolchain flake pins it. This lint
# reads file names and one JSON document type; it never parses a command,
# because a pattern cannot find a command in shell, YAML, Nix or a Dockerfile.
# It finds two things:
#
#   1. a lock file or configuration file of another package manager, by name
#      (FOREIGN_FILE_PATTERNS), or any file below a directory of another
#      package manager (FOREIGN_DIRECTORY_NAMES);
#   2. a `packageManager` or `devEngines` field in a package.json, because the
#      toolchain alone pins pnpm (a pin field also writes a second document
#      into pnpm-lock.yaml).
#
# A command that runs another package manager is not read here. The
# development shell does not provide those commands, and the PATH check of
# the toolchain (dev-shell-path-check.nix) enforces that.
#
# The package (flake.nix) sets the two arrays FOREIGN_FILE_PATTERNS and
# FOREIGN_DIRECTORY_NAMES from package-managers.nix, the one list of names.
#
# Usage: pnpm-only-lint [DIRECTORY]
#   DIRECTORY defaults to the current directory. Inside a Git work tree, the
#   lint reads the tracked files only. Elsewhere (for example in the Nix build
#   sandbox, which has no .git), it reads every file except those below `.git`
#   and `node_modules`.
#
# Exit status:
#   0  nothing found;
#   1  at least one finding;
#   2  the lint cannot check: a usage error, a failed file listing, or a
#      package.json that is not a regular file (or a link to one) or not
#      exactly one JSON object (an empty file, a second document, trailing
#      text, `null` and an array included). A check that cannot run never
#      counts as a pass.
#
# Each finding is printed to stdout as `path: message`. Errors go to stderr.

set -euo pipefail

# The number of findings printed so far. A function adds to it, so that no
# function runs in a condition, where Bash would ignore `set -e` in it.
findings=0

#######################################
# Prints the NUL-separated paths to check, relative to the directory.
# Arguments:
#   The directory to list.
# Outputs:
#   Writes the paths to stdout, each followed by a NUL byte.
# Returns:
#   The status of the listing command.
#######################################
list_files() {
  local root="$1"
  if git -C "${root}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "${root}" ls-files -z
  else
    (cd "${root}" && find . \( -name .git -o -name node_modules \) -prune -o ! -type d -print0)
  fi
}

# What makes the last checked path foreign. `foreign_path` sets it; it is empty
# when the path is not foreign. The result is a global because command
# substitution forks one subshell per path, which is slow on a large tree.
FOREIGN=""

#######################################
# Names what makes a path foreign: the directory of FOREIGN_DIRECTORY_NAMES
# that contains it, or else the path itself when its base name matches a
# pattern of FOREIGN_FILE_PATTERNS. The directory comes first, so that every
# file below it, a lock file included, gives the same name.
# Arguments:
#   The path, relative to the directory.
# Globals:
#   FOREIGN  Set to the foreign path or directory, or to "" when the path is
#            not foreign.
#######################################
foreign_path() {
  local path="$1"
  local base="${path##*/}"
  local directory
  local pattern
  local prefix
  FOREIGN=""
  # The package sets both arrays before this script runs, so ShellCheck sees
  # no assignment; `main` checks that they exist.
  # shellcheck disable=SC2154
  for directory in "${FOREIGN_DIRECTORY_NAMES[@]}"; do
    if [[ /${path} == *"/${directory}/"* ]]; then
      prefix="/${path}"
      prefix="${prefix%%"/${directory}/"*}"
      FOREIGN="${prefix#/}${prefix:+/}${directory}"
      return 0
    fi
  done
  # shellcheck disable=SC2154
  for pattern in "${FOREIGN_FILE_PATTERNS[@]}"; do
    # The pattern is a glob on purpose.
    # shellcheck disable=SC2053
    if [[ ${base} == ${pattern} ]]; then
      FOREIGN="${path}"
      return 0
    fi
  done
}

#######################################
# Prints a finding for each pin field in a package.json and counts it.
# Exits with status 2 when the path is not a regular file or a link to one (a
# dangling symlink, for example) or the file is not exactly one JSON object.
# Arguments:
#   The directory, and the path of the package.json relative to it.
# Outputs:
#   Writes `path: message` lines to stdout.
#######################################
check_package_json() {
  local root="$1"
  local path="$2"
  local messages
  if [[ ! -f ${root}/${path} ]]; then
    echo "pnpm-only-lint: cannot check ${path}: it is not a regular file" >&2
    exit 2
  fi
  # `jq -s` collects every document of the file into one array and fails on
  # text that is not JSON. The program rejects an array that does not hold
  # exactly one object: an empty file, a second document, `null` or an array
  # as the document. Each such file stops the lint instead of passing it.
  if ! messages="$(jq -s -r --arg path "${path}" '
      if length == 1 and (.[0] | type) == "object" then
        .[0]
        | ["packageManager", "devEngines"][] as $field
        | select(has($field))
        | "\($path): remove the \"\($field)\" field; the toolchain flake pins pnpm"
      else
        error("not one JSON object")
      end
    ' "${root}/${path}")"; then
    echo "pnpm-only-lint: cannot check ${path}: it is not one JSON object" >&2
    exit 2
  fi
  if [[ -n ${messages} ]]; then
    printf '%s\n' "${messages}"
    findings=$((findings + 1))
  fi
}

#######################################
# Checks the directory named by the arguments, as the header describes.
# Arguments:
#   An optional directory; the default is the current directory.
# Outputs:
#   Writes the findings to stdout and the errors to stderr.
# Returns:
#   Exits with the status that the header lists.
#######################################
main() {
  if (($# > 1)); then
    echo "usage: pnpm-only-lint [DIRECTORY]" >&2
    exit 2
  fi
  local root="${1:-.}"
  if [[ ! -d ${root} ]]; then
    echo "pnpm-only-lint: not a directory: ${root}" >&2
    exit 2
  fi
  if ! declare -p FOREIGN_FILE_PATTERNS FOREIGN_DIRECTORY_NAMES >/dev/null 2>&1; then
    echo "pnpm-only-lint: FOREIGN_FILE_PATTERNS and FOREIGN_DIRECTORY_NAMES are not set; run the package from the toolchain flake" >&2
    exit 2
  fi

  # `mapfile` hides the status of the listing (ShellCheck SC2312), so `wait`
  # reads it.
  local -a paths
  # shellcheck disable=SC2312
  mapfile -d '' -t paths < <(list_files "${root}")
  if ! wait "$!"; then
    echo "pnpm-only-lint: cannot list the files of ${root}" >&2
    exit 2
  fi

  local path
  # The foreign names printed so far. A set reports a name once whatever the
  # order of the listing, which `find` does not sort.
  local -A reported=()
  # `find` prints `./path`; Git prints `path`. Drop the `./`.
  for path in "${paths[@]#./}"; do
    # A tracked path that the work tree deleted is not there to check.
    if [[ ! -e ${root}/${path} && ! -L ${root}/${path} ]]; then
      continue
    fi
    foreign_path "${path}"
    if [[ -n ${FOREIGN} ]]; then
      if [[ -z ${reported["${FOREIGN}"]+set} ]]; then
        printf '%s: remove this; the organization uses pnpm only\n' "${FOREIGN}"
        findings=$((findings + 1))
        reported["${FOREIGN}"]=1
      fi
    elif [[ ${path##*/} == package.json ]]; then
      check_package_json "${root}" "${path}"
    fi
  done
  if ((findings > 0)); then
    exit 1
  fi
}

main "$@"
