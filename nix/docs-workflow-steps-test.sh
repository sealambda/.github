#!/usr/bin/env bash
#
# Tests the logic of the shell steps in the workflows docs.yml and links.yml,
# and the wiring between their jobs, without GitHub.
#
# Usage: docs-workflow-steps-test.sh WORKFLOW_DIRECTORY
#   WORKFLOW_DIRECTORY holds docs.yml and links.yml.
#
# Each case reads the `run:` text of a step from the workflow file with yq, and
# runs it as GitHub does (`bash --noprofile --norc -eo pipefail`) in a scratch
# directory. The programs that the step calls are fakes on the PATH that record
# their arguments and give the status and the output that the case needs. The
# expected values in the cases are written by hand.
#
# Needs bash 4.4 or later (mapfile), yq (the Go implementation) and jq.
# Exit status: 0 when every case passes, 1 when a case fails.

set -euo pipefail

if (($# != 1)); then
  echo "usage: docs-workflow-steps-test.sh WORKFLOW_DIRECTORY" >&2
  exit 2
fi
readonly DOCS_YML="$1/docs.yml"
readonly LINKS_YML="$1/links.yml"

# The state of the run. The functions below read and write it.
FAILURES=0    # the number of failed checks
ROOT_DIR=""   # the directory that holds one scratch directory for each case
SANDBOX=""    # the scratch directory of the current case
STEP_STATUS=0 # the exit status of the last step that `run_step` ran

#######################################
# Records a failed check and prints what was expected.
# Arguments:
#   The label of the check, the expected value, the actual value.
# Globals:
#   FAILURES
#######################################
report_failure() {
  FAILURES=$((FAILURES + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}

#######################################
# Fails the run unless two values are equal.
# Arguments:
#   The label of the check, the expected value, the actual value.
#######################################
check_equals() {
  if [[ $3 == "$2" ]]; then
    echo "ok: $1"
  else
    report_failure "$1" "$2" "$3"
  fi
}

#######################################
# Fails the run unless the second value contains the first one.
# Arguments:
#   The label of the check, the text that must be there, the value.
#######################################
check_contains() {
  if [[ $3 == *"$2"* ]]; then
    echo "ok: $1"
  else
    report_failure "$1" "a text with: $2" "$3"
  fi
}

#######################################
# Creates the scratch directory of a case: `bin` for the fake programs, `work`
# for the working directory of the step, and the empty file for GITHUB_OUTPUT.
# Globals:
#   ROOT_DIR, SANDBOX
#######################################
new_sandbox() {
  SANDBOX="$(mktemp -d "${ROOT_DIR}/case.XXXXXX")"
  mkdir "${SANDBOX}/bin" "${SANDBOX}/work"
  : >"${SANDBOX}/github-output"
  : >"${SANDBOX}/steps.log"
}

#######################################
# Writes a fake program that records its arguments, one on each line, in
# `<name>.args` of the scratch directory, prints a text and exits with a status.
# Arguments:
#   The name of the program, the exit status, the text to print.
# Globals:
#   SANDBOX
#######################################
install_fake() {
  local name="$1" status="$2" output="$3"
  {
    printf '#!%s\n' "${BASH}"
    printf 'printf "%%s\\n" "$@" >>%q\n' "${SANDBOX}/${name}.args"
    printf 'printf "%%s" %q\n' "${output}"
    printf 'exit %d\n' "${status}"
  } >"${SANDBOX}/bin/${name}"
  chmod +x "${SANDBOX}/bin/${name}"
  : >"${SANDBOX}/${name}.args"
}

#######################################
# Writes a fake `gh` for the issue step of links.yml. `gh issue list` applies
# the `--jq` filter of the call to `issues.json` of the scratch directory with
# jq, as gh does. Any other call records its arguments in `gh-<words>.args`.
# Globals:
#   SANDBOX
#######################################
install_fake_gh() {
  printf '#!%s\n' "${BASH}" >"${SANDBOX}/bin/gh"
  cat >>"${SANDBOX}/bin/gh" <<'FAKE_GH'
dir="${FAKE_GH_DIR}"
if [[ "$1 $2" == "issue list" ]]; then
  filter=""
  for ((i = 1; i < $#; i++)); do
    if [[ "${!i}" == "--jq" ]]; then
      j=$((i + 1))
      filter="${!j}"
    fi
  done
  jq -r "${filter}" "${dir}/issues.json"
else
  printf '%s\n' "$@" >"${dir}/gh-$1-$2.args"
fi
FAKE_GH
  chmod +x "${SANDBOX}/bin/gh"
}

#######################################
# Runs the `run:` text of one step of a workflow, as GitHub runs a bash step.
# Arguments:
#   The workflow file, the job name, the step name, then the environment of the
#   step as NAME=value words. GITHUB_OUTPUT and the fake programs are always set.
# Globals:
#   SANDBOX, STEP_STATUS
# Outputs:
#   The log of the step is in `step.log` of the scratch directory.
#######################################
run_step() {
  local file="$1" job="$2" step="$3"
  shift 3
  local script="${SANDBOX}/step.sh"
  JOB="${job}" STEP="${step}" yq \
    '.jobs[strenv(JOB)].steps[] | select(.name == strenv(STEP)) | .run' \
    "${file}" >"${script}"
  STEP_STATUS=0
  (
    cd "${SANDBOX}/work"
    exec env -i "PATH=${SANDBOX}/bin:${PATH}" "HOME=${SANDBOX}" \
      "GITHUB_OUTPUT=${SANDBOX}/github-output" "FAKE_GH_DIR=${SANDBOX}" "$@" \
      "${BASH}" --noprofile --norc -eo pipefail "${script}"
  ) >"${SANDBOX}/step.log" 2>&1 || STEP_STATUS=$?
}

#######################################
# Fails the run unless a file of the scratch directory exists or does not
# exist, as expected.
# Arguments:
#   The label of the check, `yes` or `no`, the file name in the scratch
#   directory.
# Globals:
#   SANDBOX
#######################################
check_exists() {
  local found=no
  if [[ -e ${SANDBOX}/$3 ]]; then
    found=yes
  fi
  check_equals "$1" "$2" "${found}"
}

#######################################
# The step "Build the docs check": the output names the program of the store
# path that `nix build` prints, and a failure of `nix build` fails the step. A
# command substitution inside `echo "...=$(nix build ...)"` would hide that
# failure behind the status of `echo`.
#######################################
test_build_step() {
  local kit="github:sealambda/.github/0123456789abcdef?dir=docs-kit"
  local actual

  new_sandbox
  install_fake nix 0 "/nix/store/aaaa-docs-check"
  run_step "${DOCS_YML}" docs "Build the docs check" "DOCS_KIT=${kit}"
  check_equals "build: the step passes" 0 "${STEP_STATUS}"
  actual="$(<"${SANDBOX}/github-output")"
  check_equals "build: the output names the program" \
    "program=/nix/store/aaaa-docs-check/bin/docs-check" "${actual}"
  actual="$(<"${SANDBOX}/nix.args")"
  check_equals "build: the call of nix" \
    $'build\n--no-link\n--print-out-paths\n'"${kit}#docs-check" "${actual}"

  new_sandbox
  install_fake nix 1 ""
  run_step "${DOCS_YML}" docs "Build the docs check" "DOCS_KIT=${kit}"
  if ((STEP_STATUS == 0)); then
    report_failure "build: a failed nix build fails the step" "a status other than 0" 0
  else
    echo "ok: build: a failed nix build fails the step"
  fi
  actual="$(<"${SANDBOX}/github-output")"
  check_equals "build: a failed nix build writes no output" "" "${actual}"
}

#######################################
# The step "Run the docs check": it calls docs-check with the directory only
# (docs-check reads the templates from its own variable, see test_wiring), and
# the status of docs-check is the status of the step.
#######################################
test_run_step() {
  local actual

  new_sandbox
  install_fake docs-check 0 ""
  run_step "${DOCS_YML}" docs "Run the docs check" \
    "DOCS_CHECK=${SANDBOX}/bin/docs-check" $'DOCS_CHECK_TEMPLATES=templates/*\n'
  check_equals "run: the step passes" 0 "${STEP_STATUS}"
  actual="$(<"${SANDBOX}/docs-check.args")"
  check_equals "run: the call of docs-check has the directory only" "." "${actual}"

  new_sandbox
  install_fake docs-check 1 ""
  run_step "${DOCS_YML}" docs "Run the docs check" \
    "DOCS_CHECK=${SANDBOX}/bin/docs-check"
  check_equals "run: a finding of docs-check fails the step" 1 "${STEP_STATUS}"
}

#######################################
# The step "Check the links to other sites": the options are `--online` and the
# directory; the step writes the status of docs-check to its output and ends
# with the same status, for each of 0, 1 and 2.
#######################################
test_links_step() {
  local status actual
  for status in 0 1 2; do
    new_sandbox
    install_fake docs-check "${status}" ""
    run_step "${DOCS_YML}" docs "Check the links to other sites" \
      "DOCS_CHECK=${SANDBOX}/bin/docs-check" "GITHUB_TOKEN=token" \
      $'DOCS_CHECK_TEMPLATES=templates/*\n'
    check_equals "links: the step ends with status ${status}" \
      "${status}" "${STEP_STATUS}"
    actual="$(<"${SANDBOX}/github-output")"
    check_equals "links: the output has status ${status}" \
      "status=${status}" "${actual}"
  done
  actual="$(<"${SANDBOX}/docs-check.args")"
  check_equals "links: the options" $'--online\n.' "${actual}"
}

#######################################
# The step "Open or update the issue" of links.yml: an open issue with the
# exact title gets a comment, and an issue whose title only contains it does
# not; without an exact match, the step creates one issue.
#######################################
test_issue_step() {
  local title actual
  title="$(yq '.jobs.report.env.TITLE' "${LINKS_YML}")"
  local -a step_env=("TITLE=${title}" "GH_REPO=sealambda/.github"
    "RUN_URL=https://example.test/run/9")

  new_sandbox
  install_fake_gh
  jq -n --arg title "${title}" \
    '[{number: 5, title: ($title + " (old)")}, {number: 7, title: $title}]' \
    >"${SANDBOX}/issues.json"
  run_step "${LINKS_YML}" report "Open or update the issue" "${step_env[@]}"
  check_equals "issue: the step passes" 0 "${STEP_STATUS}"
  actual="$(<"${SANDBOX}/gh-issue-comment.args")"
  check_contains "issue: a comment on the issue with the exact title" \
    $'issue\ncomment\n7\n--body\n' "${actual}"
  check_contains "issue: the comment links the run" \
    "https://example.test/run/9" "${actual}"
  check_exists "issue: no second issue" no gh-issue-create.args

  new_sandbox
  install_fake_gh
  jq -n --arg title "${title}" '[{number: 5, title: ($title + " (old)")}]' \
    >"${SANDBOX}/issues.json"
  run_step "${LINKS_YML}" report "Open or update the issue" "${step_env[@]}"
  check_equals "issue: the step passes without an open issue" 0 "${STEP_STATUS}"
  actual="$(<"${SANDBOX}/gh-issue-create.args")"
  check_contains "issue: a new issue with the title" \
    $'issue\ncreate\n--title\n'"${title}"$'\n--body\n' "${actual}"
  check_exists "issue: no comment on a title that only contains the title" \
    no gh-issue-comment.args
}

#######################################
# Prints the places in a workflow file that name or carry a credential, as a
# compact JSON array of [scope, path] pairs in the order of the file. The scope
# is "workflow", the name of a job, or the name of a step. The path is the
# location of the value inside the scope, such as "env.GITHUB_TOKEN" or
# "with.github_access_token". Every value of the file counts, whatever the
# section (`env`, `with`, `run`, `if`, ...): a place matches when its path or
# its value contains "token", "secret", "password" or "credential", or the word
# "pat", in any case. A reference such as secrets.PAT matches by "secret".
# Arguments:
#   The workflow file.
# Outputs:
#   The JSON array on stdout.
#######################################
credential_places() {
  yq -o=json '.' "$1" | jq -c '
    # The filter of paths() keeps a value when it outputs true, so `scalars`
    # would drop the values false and null.
    def leaves($scope):
      . as $node
      | paths(type | . != "object" and . != "array") as $path
      | [$scope, ($path | map(tostring) | join(".")), ($node | getpath($path) | tostring)];
    [
      (del(.jobs) | leaves("workflow")),
      (.jobs | to_entries[] | .key as $job | .value
        | (del(.steps) | leaves($job)),
          (.steps[]? | leaves(.name // "unnamed step")))
      | select((.[1] + " " + .[2])
          | test("token|secret|password|credential|(^|[^a-z])pat([^a-z]|$)"; "i"))
      | [.[0], .[1]]
    ]'
}

#######################################
# The wiring that the steps rely on: the outputs of the step, the job and the
# workflow chain to the `report` condition; no `env` map of the workflow, a job
# or a step holds a token except the two that need one (the build step and the
# link step); the step that installs Nix gets an empty token; the checkout step
# does not persist the job token in the git configuration; the steps pass the
# input `templates` to docs-check in its variable, with no loop of their own.
#######################################
test_wiring() {
  local actual
  # The start of a GitHub expression. Two parts, because a literal with `$` and
  # `{` in single quotes gets a warning from shellcheck, and in double quotes
  # shfmt changes it.
  local expression_start='$'
  expression_start+='{{'

  actual="$(yq '.jobs.docs.steps[] | select(.name == "Check the links to other sites") | .id' "${DOCS_YML}")"
  check_equals "wiring: the id of the link step" "external-links" "${actual}"
  actual="$(yq '.jobs.docs.outputs.external-links-status' "${DOCS_YML}")"
  check_equals "wiring: the job output reads the step output" \
    "${expression_start} steps.external-links.outputs.status }}" "${actual}"
  actual="$(yq '.on.workflow_call.outputs.external-links-status.value' "${DOCS_YML}")"
  check_equals "wiring: the workflow output reads the job output" \
    "${expression_start} jobs.docs.outputs.external-links-status }}" "${actual}"

  actual="$(yq '.jobs.report.needs' "${LINKS_YML}")"
  check_equals "wiring: report needs the job that calls docs.yml" "links" "${actual}"
  actual="$(yq '.jobs.report.if' "${LINKS_YML}")"
  check_contains "wiring: report runs for the status 1 of the link job" \
    "needs.links.outputs.external-links-status == '1'" "${actual}"

  # Every value of the workflow, in the order of the file: the workflow, each
  # job and each step, in `env`, `with`, `run` or any other key. A credential in
  # the `env` of the workflow or of the job reaches every step, including the
  # step that runs code of the checked tree. The two steps that need the job
  # token are the only ones that hold it; the other places are the two settings
  # that keep a credential away.
  actual="$(credential_places "${DOCS_YML}")"
  check_equals "wiring: only the two steps that need the token have a credential" \
    '[["Check out the commit","with.persist-credentials"],["Install Nix","with.github_access_token"],["Build the docs check","env.NIX_CONFIG"],["Check the links to other sites","env.GITHUB_TOKEN"]]' \
    "${actual}"
  actual="$(STEP="Build the docs check" yq \
    '.jobs.docs.steps[] | select(.name == strenv(STEP)) | .env.NIX_CONFIG' "${DOCS_YML}")"
  check_equals "wiring: the build step gives nix the token as access-tokens" \
    "access-tokens = github.com=${expression_start} github.token }}" "${actual}"
  actual="$(yq '.jobs.docs.steps[] | select(.name == "Install Nix") | .with.github_access_token' "${DOCS_YML}")"
  check_equals "wiring: the Nix installer gets an empty token" "" "${actual}"
  actual="$(yq '.jobs.docs.steps[] | select(.name == "Check out the commit") | .with.persist-credentials' "${DOCS_YML}")"
  check_equals "wiring: the checkout does not keep the job token in the git configuration" \
    "false" "${actual}"

  # The templates reach docs-check through its variable, and no step parses them.
  local step
  for step in "Run the docs check" "Check the links to other sites"; do
    actual="$(STEP="${step}" yq \
      '.jobs.docs.steps[] | select(.name == strenv(STEP)) | .env.DOCS_CHECK_TEMPLATES' "${DOCS_YML}")"
    check_equals "wiring: '${step}' passes the input templates" \
      "${expression_start} inputs.templates }}" "${actual}"
    actual="$(STEP="${step}" yq \
      '.jobs.docs.steps[] | select(.name == strenv(STEP)) | .run' "${DOCS_YML}")"
    if [[ ${actual} == *"--template"* || ${actual} == *"for "* ]]; then
      report_failure "wiring: '${step}' has no loop over the templates" \
        "no --template and no loop" "${actual}"
    else
      echo "ok: wiring: '${step}' has no loop over the templates"
    fi
  done
}

#######################################
# Runs every case and ends with the status of the run.
# Globals:
#   ROOT_DIR, FAILURES
#######################################
main() {
  ROOT_DIR="$(mktemp -d)"
  trap 'rm -rf -- "${ROOT_DIR}"' EXIT

  test_build_step
  test_run_step
  test_links_step
  test_issue_step
  test_wiring

  if ((FAILURES > 0)); then
    echo "${FAILURES} check(s) failed" >&2
    exit 1
  fi
  echo "all checks passed"
}

main
