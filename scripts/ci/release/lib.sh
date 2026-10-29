# shellcheck shell=bash
#
# Helpers for the tests of the release actions (.github/actions/check-trigger,
# head-of-main and ecr-put-tag).
#
# The tests sit next to their actions and source this file as
# scripts/ci/release/lib.sh of the repository root.
#
# A test script sources this file, calls `init_sandbox`, runs its cases with
# `expect_success` and `expect_failure`, and ends with `finish_tests`. Each case
# runs the script under test as a separate process, on a PATH that holds a fake
# `aws` and a fake `curl`, in an empty environment plus the variables of the
# case. The fakes answer from files that the test writes with `fake_response`
# and log every call, so a test can assert what the script sent as well as what
# it printed.
#
# This file is a library: it sets no shell options, so the sourcing script
# keeps its own.
#
# Globals of a test script:
#   BASE_ENV  An array of NAME=value pairs: the environment of every case.
#             A case overrides a pair by naming the variable again.
#   SCRIPT    The path of the script under test.

TESTS_PASSED=0
TESTS_FAILED=0
SANDBOX=''
RUN_STATUS=0
RUN_OUTPUT=''

#######################################
# Creates the sandbox: the fake commands, the files of one case and the cleanup
# on exit.
# Globals:
#   SANDBOX: set. PATH: the fake commands come first.
#######################################
init_sandbox() {
  SANDBOX="$(mktemp -d)"
  mkdir -p "${SANDBOX}/bin" "${SANDBOX}/fake" "${SANDBOX}/tmp"
  trap 'rm -rf "${SANDBOX}"' EXIT
  write_fake_aws "${SANDBOX}/bin/aws"
  write_fake_curl "${SANDBOX}/bin/curl"
  PATH="${SANDBOX}/bin:${PATH}"
}

#######################################
# Prints the first two lines of a fake command: the shebang and the strict
# mode. printf writes them, so that no line of this library starts with `set` in
# column 0, which the strict-mode lint reads as a change of this file's options.
# Outputs:
#   Writes the two lines to stdout.
#######################################
print_fake_preamble() {
  printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
}

#######################################
# Writes a fake `aws ecr <operation> ...`. It appends its arguments to
# ${FAKE_DIR}/aws.log, one per line with a `--` line after each call, copies the
# file behind a `file://` argument to ${FAKE_DIR}/manifest.copy, then prints
# ${FAKE_DIR}/<operation>.out and ${FAKE_DIR}/<operation>.err and exits with the
# status in ${FAKE_DIR}/<operation>.status (0 when absent).
# Arguments:
#   The path of the fake.
#######################################
write_fake_aws() {
  {
    print_fake_preamble
    cat <<'FAKE'
{
  printf '%s\n' "$@"
  echo '--'
} >>"${FAKE_DIR}/aws.log"
operation="$2"
for argument in "$@"; do
  if [[ ${argument} == file://* ]]; then
    cp "${argument#file://}" "${FAKE_DIR}/manifest.copy"
  fi
done
if [[ -f ${FAKE_DIR}/${operation}.err ]]; then
  cat "${FAKE_DIR}/${operation}.err" >&2
fi
if [[ -f ${FAKE_DIR}/${operation}.out ]]; then
  cat "${FAKE_DIR}/${operation}.out"
fi
if [[ -f ${FAKE_DIR}/${operation}.status ]]; then
  exit "$(<"${FAKE_DIR}/${operation}.status")"
fi
FAKE
  } >"$1"
  chmod +x "$1"
}

#######################################
# Writes a fake `curl`. It logs its arguments one per line to
# ${FAKE_DIR}/curl.log, copies standard input to ${FAKE_DIR}/curl.stdin, prints
# ${FAKE_DIR}/curl.out and exits with the status in ${FAKE_DIR}/curl.status.
# Arguments:
#   The path of the fake.
#######################################
write_fake_curl() {
  {
    print_fake_preamble
    cat <<'FAKE'
printf '%s\n' "$@" >"${FAKE_DIR}/curl.log"
cat >"${FAKE_DIR}/curl.stdin"
if [[ -f ${FAKE_DIR}/curl.out ]]; then
  cat "${FAKE_DIR}/curl.out"
fi
if [[ -f ${FAKE_DIR}/curl.status ]]; then
  exit "$(<"${FAKE_DIR}/curl.status")"
fi
FAKE
  } >"$1"
  chmod +x "$1"
}

#######################################
# Clears the answers and the logs of the fakes. run_script clears the outputs
# and the summary of the script on every run.
#######################################
reset_case() {
  rm -rf "${SANDBOX}/fake"
  mkdir -p "${SANDBOX}/fake"
}

#######################################
# Sets what a fake command answers to one operation.
# Arguments:
#   The operation: an aws ecr subcommand, or `curl`.
#   The exit status.
#   What the command prints on stdout.
#   What the command prints on stderr.
#######################################
fake_response() {
  local prefix="${SANDBOX}/fake/$1"
  printf '%s' "$3" >"${prefix}.out"
  printf '%s' "$4" >"${prefix}.err"
  printf '%s' "$2" >"${prefix}.status"
}

#######################################
# Sets what the fake aws answers to one operation with a service error, in the
# text of the AWS CLI v2: `An error occurred (Name) when calling the Api
# operation: ...`.
# Arguments:
#   The operation: an aws ecr subcommand.
#   The exit status of the CLI for a service error: 254.
#   The exception name.
#   The name of the API call in the message, such as DescribeImages.
#######################################
fake_aws_error() {
  fake_response "$1" "$2" "" "An error occurred ($3) when calling the $4 operation: the test says so"
}

#######################################
# Runs the script under test in an empty environment.
# Arguments:
#   NAME=value pairs that override BASE_ENV.
# Globals:
#   RUN_STATUS, RUN_OUTPUT: set. RUN_OUTPUT holds stdout and stderr.
#######################################
# BASE_ENV and SCRIPT belong to the sourcing test script.
# shellcheck disable=SC2154
run_script() {
  : >"${SANDBOX}/github-output"
  : >"${SANDBOX}/step-summary"
  RUN_STATUS=0
  RUN_OUTPUT="$(
    env -i PATH="${PATH}" TMPDIR="${SANDBOX}/tmp" FAKE_DIR="${SANDBOX}/fake" \
      GITHUB_OUTPUT="${SANDBOX}/github-output" \
      GITHUB_STEP_SUMMARY="${SANDBOX}/step-summary" \
      "${BASE_ENV[@]}" "$@" bash "${SCRIPT}" 2>&1
  )" || RUN_STATUS=$?
}

#######################################
# Records a passed or failed case.
# Arguments:
#   The name of the case.
#   Empty for a pass, else the reason of the failure.
#######################################
record() {
  if [[ -z $2 ]]; then
    echo "ok   $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo "FAIL $1: $2" >&2
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

#######################################
# Expects the script to fail with an exact status and a message.
# Arguments:
#   The name of the case.
#   The expected exit status.
#   A text that the output must contain.
#   NAME=value pairs that override BASE_ENV.
#######################################
expect_failure() {
  local name="$1" status="$2" text="$3"
  shift 3
  run_script "$@"
  local why=''
  if ((RUN_STATUS != status)); then
    why="status ${RUN_STATUS}, expected ${status}"
  elif [[ ${RUN_OUTPUT} != *"${text}"* ]]; then
    why="the output lacks '${text}': ${RUN_OUTPUT}"
  fi
  record "${name}" "${why}"
}

#######################################
# Expects the script to succeed and to write exactly the given step outputs.
# Arguments:
#   The name of the case.
#   The expected content of GITHUB_OUTPUT.
#   NAME=value pairs that override BASE_ENV.
#######################################
expect_success() {
  local name="$1" expected="$2"
  shift 2
  run_script "$@"
  local actual why=''
  actual="$(<"${SANDBOX}/github-output")"
  if ((RUN_STATUS != 0)); then
    why="status ${RUN_STATUS}: ${RUN_OUTPUT}"
  elif [[ ${actual} != "${expected}" ]]; then
    why="outputs '${actual}', expected '${expected}'"
  fi
  record "${name}" "${why}"
}

#######################################
# Expects the output of the last run to contain a text.
# Arguments:
#   The name of the case.
#   The text.
#######################################
expect_output_contains() {
  local why=''
  if [[ ${RUN_OUTPUT} != *"$2"* ]]; then
    why="the output lacks '$2': ${RUN_OUTPUT}"
  fi
  record "$1" "${why}"
}

#######################################
# Expects a file of the sandbox to hold exactly the given content.
# Arguments:
#   The name of the case.
#   The path of the file in the sandbox: `step-summary`, or a file of the
#   fakes such as `fake/curl.stdin`.
#   The expected content, byte for byte.
#######################################
expect_file() {
  local why=''
  printf '%s' "$3" >"${SANDBOX}/expected"
  if [[ ! -f ${SANDBOX}/$2 ]]; then
    why="$2 does not exist"
  elif ! cmp -s "${SANDBOX}/$2" "${SANDBOX}/expected"; then
    why="$2 differs from the expected content"
  fi
  record "$1" "${why}"
}

#######################################
# Expects a log of the fakes to hold a line, or not.
# Arguments:
#   The name of the case.
#   `has` or `lacks`.
#   The log file in the fake directory: aws.log or curl.log.
#   The line, compared as a whole.
#######################################
expect_log_line() {
  local found=lacks why=''
  if [[ -f ${SANDBOX}/fake/$3 ]] && grep -qxF -- "$4" "${SANDBOX}/fake/$3"; then
    found=has
  fi
  if [[ ${found} != "$2" ]]; then
    why="$3 ${found} the line '$4', expected it to be '$2'"
  fi
  record "$1" "${why}"
}

#######################################
# Expects no part of a log of the fakes to contain a text. Use it for a secret:
# expect_log_line compares whole lines, so it misses a secret inside a longer
# argument such as `Authorization: Bearer <secret>`.
# Arguments:
#   The name of the case.
#   The log file in the fake directory: aws.log or curl.log.
#   The text, compared as a fixed string.
#######################################
expect_log_lacks_text() {
  local why=''
  if [[ -f ${SANDBOX}/fake/$2 ]] && grep -qF -- "$3" "${SANDBOX}/fake/$2"; then
    why="$2 contains '$3'"
  fi
  record "$1" "${why}"
}

#######################################
# Expects a flag in a log of the fakes to be followed by a value. The log holds
# one argument per line, so the flag and the value are two lines in a row.
# Arguments:
#   The name of the case.
#   The log file in the fake directory: aws.log or curl.log.
#   The flag.
#   The value, compared as a whole line.
#######################################
expect_flag_value() {
  local lines=() previous='' line why="no '$3 $4' pair in $2"
  if [[ -f ${SANDBOX}/fake/$2 ]]; then
    mapfile -t lines <"${SANDBOX}/fake/$2"
  fi
  for line in "${lines[@]}"; do
    if [[ ${previous} == "$3" && ${line} == "$4" ]]; then
      why=''
    fi
    previous="${line}"
  done
  record "$1" "${why}"
}

#######################################
# Prints the totals and ends the test script.
# Returns:
#   Exits 0 when every case passed, 1 otherwise or when no case ran.
#######################################
finish_tests() {
  echo "${TESTS_PASSED} passed, ${TESTS_FAILED} failed"
  if ((TESTS_FAILED > 0 || TESTS_PASSED == 0)); then
    exit 1
  fi
  exit 0
}
