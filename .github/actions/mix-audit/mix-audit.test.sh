#!/usr/bin/env bash
# Tests of mix-audit.sh. Each case builds a Git repository in a temporary
# directory, runs the script there with a fake `nix` and a fake `mix` first on
# PATH, and compares the exit status, the calls that the fakes logged and the
# error line with values written out by hand in this file.
#
# The fake `nix` accepts only `nix develop --no-update-lock-file FLAKE --command
# COMMAND...` and runs COMMAND; any other call is logged as unexpected and
# fails with status 99. The option keeps the audit from rewriting the flake lock
# file of the checkout. The fake `mix` logs its directory (relative to the repository root)
# and arguments. It fails `hex.info` in a directory that holds a file named
# `no-hex`, and `hex.audit` in a directory that holds a file named
# `audit-fails`.
#
# The flake check `mix-audit` runs this test (flake.nix). It needs Bash 4.4 or
# later and Git on PATH.
#
# Usage: mix-audit.test.sh
# Exit status: 0 when every case passes, 1 when a case fails.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="${script_dir}/mix-audit.sh"

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT
export HOME="${work}/home"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_CEILING_DIRECTORIES="${work}"
mkdir -p "${HOME}" "${work}/bin"

failures=0
log="${work}/calls.log"
output="${work}/output.txt"
status=0
# The log that the current case expects, one call per line.
expected=""

# Write the fake `nix` and `mix` into ${work}/bin.
install_fakes() {
  cat >"${work}/bin/nix" <<'FAKE'
#!/usr/bin/env bash
if [[ ${1:-} != develop || ${2:-} != --no-update-lock-file || ${4:-} != --command ]]; then
  echo "unexpected nix call: $*" >>"${FAKE_LOG}"
  exit 99
fi
echo "flake ${3}" >>"${FAKE_LOG}"
shift 4
exec "$@"
FAKE
  cat >"${work}/bin/mix" <<'FAKE'
#!/usr/bin/env bash
where="${PWD#"${FAKE_ROOT}"/}"
[[ ${PWD} == "${FAKE_ROOT}" ]] && where="."
echo "${where}|mix $*" >>"${FAKE_LOG}"
[[ ${1} == hex.info && -e no-hex ]] && exit 1
[[ ${1} == hex.audit && -e audit-fails ]] && exit 1
exit 0
FAKE
  chmod +x "${work}/bin/nix" "${work}/bin/mix"
}

# Start a case: an empty Git repository, which becomes the current directory.
# Arguments: the case name.
# Side effect: empties the log and the expected log.
new_repo() {
  local repo="${work}/${1}"
  mkdir "${repo}"
  git -C "${repo}" init --quiet
  : >"${log}"
  expected=""
  cd "${repo}"
}

# Create files, relative to the repository, and track them.
# Arguments: file paths.
track() {
  local path
  for path in "$@"; do
    mkdir -p -- "$(dirname -- "${path}")"
    : >"${path}"
    git add -- "${path}"
  done
}

# Run the script in the current directory; keep its output and status.
# Side effect: sets `status`, fills `output`.
run_script() {
  status=0
  FAKE_LOG="${log}" FAKE_ROOT="${PWD}" PATH="${work}/bin:${PATH}" \
    bash "${script}" >"${output}" 2>&1 || status=$?
}

# Expect the calls for one audited project directory: the flake that
# `nix develop` gets (the repository root, the current directory), then the
# three Mix calls.
# Arguments: the directory as the fake `mix` logs it.
# Side effect: appends to `expected`.
want_audit() {
  expected+="${expected:+$'\n'}flake ${PWD}"
  expected+=$'\n'"${1}|mix hex.info"$'\n'"${1}|mix deps.get"$'\n'"${1}|mix hex.audit"
}

# Record a failed expectation.
# Arguments: the case name, what differs.
fail() {
  echo "FAIL ${1}: ${2}" >&2
  failures=$((failures + 1))
}

# Check the exit status, the fakes' calls and the output of the last run
# against `expected`.
# Arguments: the case name, the expected status, then the text that the output
# must contain ("" for no requirement).
expect() {
  local name="${1}" want_status="${2}" want_text="${3}"
  local got_log got_output
  got_log="$(<"${log}")"
  got_output="$(<"${output}")"
  if ((status != want_status)); then
    fail "${name}" "exit status ${status}, expected ${want_status}: ${got_output}"
  elif [[ ${got_log} != "${expected}" ]]; then
    fail "${name}" "calls were: ${got_log:-none}; expected: ${expected:-none}"
  elif [[ -n ${want_text} && ${got_output} != *"${want_text}"* ]]; then
    fail "${name}" "output lacks '${want_text}': ${got_output}"
  else
    echo "ok   ${name}"
  fi
}

# Case: a repository without a tracked mix.lock passes and calls nothing.
case_no_lock() {
  new_repo no-lock
  track mix.exs lib/app.ex
  run_script
  expect "no mix.lock passes without a call" 0 "No tracked mix.lock"
}

# Case: a mix.lock at the repository root is audited in the root.
case_root_project() {
  new_repo root-project
  track mix.lock
  run_script
  want_audit .
  expect "a root mix.lock is audited in ." 0 ""
}

# Case: a mix.lock that Git does not track is not audited.
case_untracked_lock() {
  new_repo untracked-lock
  track mix.lock
  mkdir ghost
  : >ghost/mix.lock
  run_script
  want_audit .
  expect "an untracked mix.lock is not audited" 0 ""
}

# Case: a tracked mix.lock of a vendored dependency, at any depth, is audited
# like every other project (documented in docs/reference/workflows.md).
case_vendored_lock() {
  new_repo vendored-lock
  track "deps/x/mix.lock" "apps/a/deps/y/mix.lock"
  run_script
  want_audit "apps/a/deps/y"
  want_audit "deps/x"
  expect "a vendored mix.lock is audited" 0 ""
}

# Case: a project directory with a space in its name is audited.
case_space() {
  new_repo space
  track "apps/my app/mix.lock"
  run_script
  want_audit "apps/my app"
  expect "a directory name with a space" 0 ""
}

# Case: a project directory with a non-ASCII name is audited.
case_non_ascii() {
  new_repo non-ascii
  track "apps/café/mix.lock"
  run_script
  want_audit "apps/café"
  expect "a non-ASCII directory name" 0 ""
}

# Case: a project directory whose name starts with - is audited, and the name
# is not read as an option.
case_leading_dash() {
  new_repo leading-dash
  track "-lib/mix.lock"
  run_script
  want_audit "-lib"
  expect "a directory name that starts with -" 0 ""
}

# Case: glob characters in a directory name are not expanded.
case_glob_characters() {
  new_repo glob
  track "apps/[x]*/mix.lock"
  run_script
  want_audit "apps/[x]*"
  expect "glob characters in a directory name" 0 ""
}

# Case: a failed audit does not stop the others; the step fails and names
# every failing directory.
case_failure_does_not_stop_the_loop() {
  new_repo failing
  track "a/mix.lock" "b c/mix.lock" "d/mix.lock"
  : >"a/audit-fails"
  : >"b c/audit-fails"
  run_script
  want_audit a
  want_audit "b c"
  want_audit d
  expect "every project is audited and the failing ones are named" 1 \
    "::error::mix hex.audit failed in: 'a', 'b c'"
}

# Case: a shell without Hex fails at `mix hex.info`, before `mix deps.get`.
case_hex_missing() {
  new_repo no-hex
  track "app/mix.lock"
  : >"app/no-hex"
  run_script
  expected="flake ${PWD}"$'\n'"app|mix hex.info"
  expect "a shell without Hex fails before deps.get" 1 \
    "::error::mix hex.audit failed in: 'app'"
}

# Case: a failure of Git fails the step and audits nothing.
case_git_failure() {
  new_repo git-failure
  rm -rf .git
  run_script
  expect "a git failure fails the step and audits nothing" 1 \
    "::error::git could not list the tracked files"
}

install_fakes
case_no_lock
case_root_project
case_untracked_lock
case_vendored_lock
case_space
case_non_ascii
case_leading_dash
case_glob_characters
case_failure_does_not_stop_the_loop
case_hex_missing
case_git_failure

((failures == 0))
