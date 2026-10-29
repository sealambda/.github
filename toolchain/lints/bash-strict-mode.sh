#!/usr/bin/env bash
#
# Fails when a shell script does not follow the organization's rule on shell
# options.
#
# An executable script starts with the shebang `#!/usr/bin/env bash` and runs
# exactly `set -euo pipefail` before its first command, so an unset variable,
# a failed command or a failed stage of a pipeline stops it. Only this
# literal line is accepted: `set -Eeuo pipefail` and `set -eu -o pipefail`
# are equivalent or stricter, but one accepted form keeps every script
# readable the same way.
#
# A library (a `.sh` file that is sourced, not executable) must not set shell
# options, because it would change them for the script that sources it. A
# library fails on a line that starts in column 0 with `set -…`, `set +…`
# (including `set -o …`) or `shopt -s`. `set --` (positional parameters) is
# allowed, and so is an indented line, which sits inside a function body.
#
# Usage: bash-strict-mode FILE...
#   treefmt passes the files.
#
# Exit status: 0 when every file passes, 1 when a file has a finding, 2 when
# a file cannot be read (a script or a library). An unreadable file is an
# error of the environment, not a finding, so the lint stops at the first one.
# Each finding is printed as `path: message` on standard output.

set -euo pipefail

readonly SHEBANG='#!/usr/bin/env bash'
readonly STRICT_MODE='set -euo pipefail'

# A line that changes shell options: `set -e`, `set +u`, `set -o errexit`,
# `shopt -s nullglob`. `set --` does not match, because the character after
# its dash is not a letter.
readonly OPTION_LINE_REGEX='^(set[[:space:]]+[-+][A-Za-z]|shopt[[:space:]]+-s)'

# The number of findings so far. Functions raise it instead of returning
# non-zero, so that a call stays a plain statement and `set -e` keeps its
# effect in the caller (ShellCheck SC2310).
findings=0

#######################################
# Records one finding.
# Globals:
#   findings
# Arguments:
#   The path of the file.
#   The message.
# Outputs:
#   Writes a `path: message` line to stdout.
#######################################
report() {
  echo "$1: $2"
  findings=$((findings + 1))
}

#######################################
# Stops the lint because a file cannot be read.
# Arguments:
#   The path of the file.
# Outputs:
#   Writes an error to stderr and exits 2.
#######################################
fail_unreadable() {
  echo "$1: cannot read the file" >&2
  exit 2
}

#######################################
# Checks an executable script: the shebang, then strict mode as the first
# command.
# Arguments:
#   The path of the file.
# Outputs:
#   Writes a finding for each rule that the file breaks. Writes an error to
#   stderr and exits 2 when the file cannot be read.
#######################################
check_executable() {
  local path="$1"
  if [[ ! -r ${path} ]]; then
    fail_unreadable "${path}"
  fi
  local first_line
  # `read` also fails at the end of a file that has no final newline, or no
  # content. The line it has read is still in `first_line`, so that failure
  # is not an error; the check above has already ruled out a read error.
  IFS= read -r first_line <"${path}" || true
  if [[ ${first_line} != "${SHEBANG}" ]]; then
    report "${path}" "the first line must be \"${SHEBANG}\""
    return 0
  fi
  # The first line that is not blank and not a comment must be strict mode.
  local first_command
  local grep_status=0
  first_command="$(grep -m 1 -vE '^[[:space:]]*(#|$)' "${path}")" || grep_status=$?
  if ((grep_status > 1)); then
    # grep exits 1 when no line matches; any other status is a read error.
    fail_unreadable "${path}"
  fi
  if [[ ${first_command} != "${STRICT_MODE}" ]]; then
    report "${path}" "the first command must be \"${STRICT_MODE}\""
  fi
}

#######################################
# Checks a library: no line in column 0 may change shell options.
# Arguments:
#   The path of the file.
# Outputs:
#   Writes a finding for the first line that changes shell options. Writes
#   an error to stderr and exits 2 when the file cannot be read.
#######################################
check_library() {
  local path="$1"
  local match
  local grep_status=0
  match="$(grep -n -E -m 1 -e "${OPTION_LINE_REGEX}" -- "${path}" 2>/dev/null)" || grep_status=$?
  if ((grep_status == 0)); then
    report "${path}" "a library must not set shell options, but line ${match%%:*} does"
  elif ((grep_status != 1)); then
    # grep exits 1 when no line matches; any other status is a read error.
    fail_unreadable "${path}"
  fi
}

#######################################
# Checks one file: an executable is a script, any other file is a library.
# Arguments:
#   The path of the file.
# Outputs:
#   Writes a finding for each rule that the file breaks.
#######################################
check_file() {
  local path="$1"
  if [[ -x ${path} ]]; then
    check_executable "${path}"
  else
    check_library "${path}"
  fi
}

#######################################
# Checks every file that the command line names.
# Arguments:
#   The paths of the files.
# Returns:
#   Exits 0 when no file has a finding, 1 otherwise.
#######################################
main() {
  local path
  for path in "$@"; do
    check_file "${path}"
  done
  if ((findings > 0)); then
    exit 1
  fi
}

main "$@"
