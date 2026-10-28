#!/usr/bin/env bash
#
# Fails when a file with a shell shebang has no `.sh` or `.bash` extension.
#
# treefmt and every editor select files by name. A shell script without the
# extension reaches no formatter and no linter (shfmt, ShellCheck,
# bash-strict-mode), so the organization names every shell script `*.sh`
# (toolchain/README.md, "Shell scripts"). A program that a package installs
# on PATH has no extension, but it is built from a `.sh` source file.
#
# Usage: shell-script-names FILE...
#   treefmt passes the files.
#
# Exit status: 0 when every file passes, 1 when a file has a finding, 2 when
# a file cannot be read. An unreadable file is an error of the environment,
# not a finding, so the lint stops at the first one. Each finding is printed
# as `path: message` on standard output.

set -euo pipefail

# The shells whose scripts the organization's shell tools must read.
readonly SHELL_NAMES='(sh|bash|dash|ksh|zsh)'

# The characters that separate the words of a shebang: blank, tab and the
# carriage return of a file with Windows line ends.
readonly SHEBANG_BLANKS=$' \t\r'

# The number of findings so far. Functions raise it instead of returning
# non-zero, so that a call stays a plain statement and `set -e` keeps its
# effect in the caller (ShellCheck SC2310).
findings=0

#######################################
# Prints the name of the program that a shebang runs, without its directory.
# The program is the interpreter, or for `env` the first word that is neither
# an option nor a `NAME=value` assignment. The options `-u`, `-C` and `-a`
# (long forms `--unset`, `--chdir`, `--argv0`) take the next word as their
# argument, so that word is not the program. An option with an attached value
# (`-uNAME`, `--unset=NAME`) and `-S` are single words and are skipped.
#   #!/bin/sh   #!/usr/bin/env bash   #!/usr/bin/env -S bash -e
#   #!/usr/bin/env -u NAME bash   #!/nix/store/…-bash-5.3/bin/bash
# Arguments:
#   The first line of a file.
# Outputs:
#   Writes the program name to stdout. Writes nothing when the line is not a
#   shebang or names no program.
#######################################
shebang_program() {
  local first_line="$1"
  if [[ ${first_line} != '#!'* ]]; then
    return 0
  fi
  local -a words=()
  IFS="${SHEBANG_BLANKS}" read -r -a words <<<"${first_line#'#!'}"
  if ((${#words[@]} == 0)); then
    return 0
  fi
  local interpreter="${words[0]##*/}"
  if [[ ${interpreter} != env ]]; then
    echo "${interpreter}"
    return 0
  fi
  local index word
  for ((index = 1; index < ${#words[@]}; index++)); do
    word="${words[index]}"
    case ${word} in
      -u | -C | -a | --unset | --chdir | --argv0)
        index=$((index + 1))
        ;;
      -* | *=*) ;;
      *)
        echo "${word##*/}"
        return 0
        ;;
    esac
  done
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
# Checks one file.
# Globals:
#   findings
# Arguments:
#   The path of the file.
# Outputs:
#   Writes a `path: message` line to stdout for a finding. Writes an error to
#   stderr and exits 2 when a file that needs the check cannot be read.
#######################################
check_file() {
  local path="$1"
  if [[ ${path} == *.sh || ${path} == *.bash || ! -f ${path} ]]; then
    return 0
  fi
  if [[ ! -r ${path} ]]; then
    fail_unreadable "${path}"
  fi
  local first_line=""
  # `read` also fails at the end of a file that has no final newline, or no
  # content. The line it has read is still in `first_line`, so that failure
  # is not an error; the check above has already ruled out a read error.
  IFS= read -r first_line <"${path}" || true
  local program
  program="$(shebang_program "${first_line}")"
  if [[ ${program} =~ ^${SHELL_NAMES}$ ]]; then
    echo "${path}: a shell script needs the .sh extension, so that the shell formatter and linters read it"
    findings=$((findings + 1))
  fi
}

#######################################
# Checks every file that the command line names.
# Arguments:
#   The paths of the files.
# Returns:
#   Exits 0 when no file has a finding, 1 otherwise. Exits 2 when a file
#   cannot be read.
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
