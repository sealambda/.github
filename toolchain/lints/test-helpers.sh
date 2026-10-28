# shellcheck shell=bash
#
# Helpers for the tests of the shell lints (checks.nix). A test script sources
# this file, calls `run_case` or `run_set_case` for each case, and ends with
# `finish`. The file is a library, so it sets no shell options.
#
# A case runs a lint on files that the case creates in a fresh directory, and
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
# Runs a lint on one file and compares status and output.
# Arguments:
#   The lint program.
#   The name of the case.
#   The file name, relative to a fresh directory. The lint gets this name.
#   The file mode for chmod, or "-" to leave the file out.
#   The file content.
#   The expected exit status.
#   The expected output, standard output and standard error together.
# Outputs:
#   Writes a message to stderr when the case fails.
#######################################
run_case() {
  local lint="$1"
  local name="$2"
  local file="$3"
  local mode="$4"
  local content="$5"
  local want_status="$6"
  local want_output="$7"
  local dir
  dir="$(mktemp -d)"
  if [[ ${mode} != "-" ]]; then
    printf '%s' "${content}" >"${dir}/${file}"
    chmod "${mode}" "${dir}/${file}"
  fi
  local got_status=0
  local got_output
  got_output="$(cd "${dir}" && "${lint}" "${file}" 2>&1)" || got_status=$?
  rm -rf "${dir}"
  if [[ ${got_status} != "${want_status}" ]]; then
    fail_case "${name}" "exit status ${got_status}, want ${want_status}; output: ${got_output}"
  elif [[ ${got_output} != "${want_output}" ]]; then
    fail_case "${name}" "output \"${got_output}\", want \"${want_output}\""
  fi
}

#######################################
# Runs a lint on many files at once and compares the files it flags.
# The files are created by the caller in the directory `grid` of the current
# directory; the lint gets every file of it.
# Arguments:
#   The lint program.
#   The name of the case.
#   The paths that the lint must flag, such as `grid/env_bash`. No path means
#   that the lint must pass every file.
# Outputs:
#   Writes a message to stderr when the case fails.
#######################################
run_set_case() {
  local lint="$1"
  local name="$2"
  shift 2
  local want_status=0
  if (($# > 0)); then
    want_status=1
  fi
  local got_status=0
  local got_output
  got_output="$("${lint}" grid/* 2>&1)" || got_status=$?
  if [[ ${got_status} != "${want_status}" ]]; then
    fail_case "${name}" "exit status ${got_status}, want ${want_status}"
    return 0
  fi
  local line
  local got_paths=()
  while IFS= read -r line; do
    if [[ -n ${line} ]]; then
      got_paths+=("${line%%: *}")
    fi
  done <<<"${got_output}"
  local got_list=""
  if ((${#got_paths[@]} > 0)); then
    got_list="$(printf '%s\n' "${got_paths[@]}" | sort)"
  fi
  local want_list=""
  if (($# > 0)); then
    want_list="$(printf '%s\n' "$@" | sort)"
  fi
  if [[ ${got_list} != "${want_list}" ]]; then
    fail_case "${name}" "flagged:
${got_list}
want:
${want_list}"
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
