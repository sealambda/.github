# shellcheck shell=bash
#
# Helpers for the tests of this repository's lints (checks.nix). A test script
# sources this file, calls `new_tree`, `write_file` and `run_tree_case` for
# each case, and ends with `finish`. The file is a library, so it sets no
# shell options.
#
# A case builds a small tree in a fresh directory, runs a lint there and
# compares the exit status and the output with the values that the case names.
# Those values are written by hand in checks.nix, never read from a lint.

# The number of cases that failed so far.
failures=0

#######################################
# Records a failed case.
# Globals:
#   failures
# Arguments:
#   The name of the case.
#   The reason.
# Outputs:
#   Writes the case name and the reason to stderr.
#######################################
fail_case() {
  echo "FAIL ${1}: ${2}" >&2
  failures=$((failures + 1))
}

#######################################
# Changes into a fresh, empty directory, the tree of the next case.
# Outputs:
#   Nothing. The directory is below the temporary directory of the build.
#######################################
new_tree() {
  local dir
  dir="$(mktemp -d)"
  cd "${dir}" || return
}

#######################################
# Writes one file of the tree, with the directories above it.
# Arguments:
#   The path, relative to the tree.
#   The file mode for chmod.
#   The content.
# Outputs:
#   Writes a message to stderr and counts a failure when the mode withholds
#   read access from the owner but the current user can still read the file.
#   That is the case for root, and such a test of an unreadable file would
#   test nothing.
# Limit:
#   The check of the mode cannot be tested here: a test needs a user that is
#   root, and the build user of Nix is not. The check stays as a guard for a
#   build that runs as root, and no case exercises it.
#######################################
write_file() {
  mkdir -p "$(dirname "$1")"
  printf '%s' "$3" >"$1"
  chmod "$2" "$1"
  if (((8#$2 & 8#400) == 0)) && [[ -r $1 ]]; then
    fail_case "write_file ${1}" "mode ${2} withholds read access, but the user can read the file (root?)"
  fi
}

#######################################
# Runs a lint in the current tree and compares status and output.
# Arguments:
#   The lint program.
#   The name of the case.
#   The expected exit status.
#   The expected output, standard output and standard error together.
#   The arguments of the lint (the files that treefmt would pass).
# Outputs:
#   Writes a message to stderr when the case fails.
#######################################
run_tree_case() {
  local lint="$1"
  local name="$2"
  local want_status="$3"
  local want_output="$4"
  shift 4
  local got_status=0
  local got_output
  got_output="$("${lint}" "$@" 2>&1)" || got_status=$?
  if [[ ${got_status} != "${want_status}" ]]; then
    fail_case "${name}" "exit status ${got_status}, want ${want_status}; output: ${got_output}"
  elif [[ ${got_output} != "${want_output}" ]]; then
    fail_case "${name}" "output \"${got_output}\", want \"${want_output}\""
  fi
}

#######################################
# Ends a test script: exits 1 when a case failed.
# Globals:
#   failures
# Outputs:
#   Writes the number of failed cases to stderr.
#######################################
finish() {
  if ((failures > 0)); then
    echo "${failures} case(s) failed" >&2
    exit 1
  fi
}
