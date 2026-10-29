#!/usr/bin/env bash
# Tests of docker-pull.sh against a fake `docker` and a fake `sleep` first on
# PATH. The fake `docker` fails its first FAKE_FAILURES calls and then
# succeeds. The fake `sleep` returns at once and logs its argument. The cases
# compare the exit status, the number of pulls and the waits with values
# written out by hand in this file: at most five pulls, and a wait after
# failed attempt n between 0 and 2, 4, 8 and 16 seconds.
#
# Most cases let Bash draw the random numbers, so they can check only the
# upper bound of each wait. One case pins `RANDOM` to a fixed number: Bash runs
# the file named by BASH_ENV before the script, and that file unsets the special
# variable and gives it the value of FAKE_RANDOM. The wait is then the number
# modulo (ceiling + 1), which the case calculates by hand. With 0 every wait is
# 0. With 764 every wait is its ceiling (764 + 1 is a multiple of 3, 5, 9 and
# 17). With 13 the four waits differ, so that a missing, constant or linear
# back-off fails.
#
# The flake check `docker-pull` runs this test (flake.nix). It needs Bash 4 or
# later.
#
# Usage: docker-pull.test.sh
# Exit status: 0 when every case passes, 1 when a case fails.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="${script_dir}/docker-pull.sh"

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT
mkdir "${work}/bin"

image="registry.example/tool:1.2.3@sha256:0000000000000000000000000000000000000000000000000000000000000000"
failures=0
status=0
pulls_log="${work}/pulls.log"
sleeps_log="${work}/sleeps.log"
output="${work}/output.txt"
# The number that RANDOM is pinned to in the next run; empty: Bash draws.
pinned_random=""

# Write the fake `docker` and `sleep` into ${work}/bin, and the file that
# BASH_ENV names, which pins RANDOM when FAKE_RANDOM is not empty.
install_fakes() {
  cat >"${work}/pin-random.sh" <<'PIN'
if [[ -n ${FAKE_RANDOM:-} ]]; then
  unset RANDOM
  RANDOM="${FAKE_RANDOM}"
fi
PIN
  cat >"${work}/bin/docker" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >>"${FAKE_PULLS}"
calls="$(wc -l <"${FAKE_PULLS}")"
((calls > FAKE_FAILURES))
FAKE
  cat >"${work}/bin/sleep" <<'FAKE'
#!/usr/bin/env bash
echo "${1}" >>"${FAKE_SLEEPS}"
FAKE
  chmod +x "${work}/bin/docker" "${work}/bin/sleep"
}

# Run the script with the arguments given and a number of failing pulls.
# Arguments: the number of pulls that fail first, then the script's arguments.
# Side effect: sets `status`, fills the logs and `output`. Uses `pinned_random`.
run_script() {
  local failing="${1}"
  shift
  : >"${pulls_log}"
  : >"${sleeps_log}"
  status=0
  FAKE_PULLS="${pulls_log}" FAKE_SLEEPS="${sleeps_log}" FAKE_FAILURES="${failing}" \
    FAKE_RANDOM="${pinned_random}" BASH_ENV="${work}/pin-random.sh" \
    PATH="${work}/bin:${PATH}" bash "${script}" "$@" >"${output}" 2>&1 || status=$?
}

# Record a failed expectation.
# Arguments: the case name, what differs.
fail() {
  echo "FAIL ${1}: ${2}" >&2
  failures=$((failures + 1))
}

# Check that every wait is a whole number between 0 and its ceiling, and that
# there is one wait per ceiling.
# Arguments: the case name, then the ceilings in seconds, one per expected wait.
expect_waits() {
  local name="${1}" wait_seconds
  local -a ceilings=("${@:2}") waits=()
  mapfile -t waits <"${sleeps_log}"
  if ((${#waits[@]} != ${#ceilings[@]})); then
    fail "${name}" "${#waits[@]} waits (${waits[*]:-none}), expected ${#ceilings[@]}"
    return 0
  fi
  local i
  for i in "${!waits[@]}"; do
    wait_seconds="${waits[i]}"
    if [[ ! ${wait_seconds} =~ ^[0-9]+$ ]] || ((wait_seconds > ceilings[i])); then
      fail "${name}" "wait ${i} is '${wait_seconds}', expected 0 to ${ceilings[i]}"
    fi
  done
}

# Check that the waits of the last run are exactly the values given.
# Arguments: the case name, then the expected waits in seconds, in order.
expect_exact_waits() {
  local name="${1}" got
  got="$(paste -sd ' ' "${sleeps_log}")"
  if [[ ${got} != "${*:2}" ]]; then
    fail "${name}" "waits were '${got}', expected '${*:2}'"
  else
    echo "ok   ${name}"
  fi
}

# Check the exit status and the number of pulls of the last run, and that every
# pull was `docker pull --quiet IMAGE`.
# Arguments: the case name, the expected status, the expected number of pulls.
expect_pulls() {
  local name="${1}" want_status="${2}" want_pulls="${3}"
  local got_pulls
  got_pulls="$(wc -l <"${pulls_log}" | tr -d ' ')"
  if ((status != want_status)); then
    fail "${name}" "exit status ${status}, expected ${want_status}"
  elif ((got_pulls != want_pulls)); then
    fail "${name}" "${got_pulls} pulls, expected ${want_pulls}"
  elif [[ -n "$(grep -vxF -- "pull --quiet ${image}" "${pulls_log}" || true)" ]]; then
    fail "${name}" "unexpected pull arguments: $(<"${pulls_log}")"
  else
    echo "ok   ${name}"
  fi
}

# Case: a pull that works needs one pull and no wait.
case_first_pull_succeeds() {
  run_script 0 "${image}"
  expect_pulls "a pull that works is made once" 0 1
  expect_waits "a pull that works does not wait"
}

# Case: two failed pulls, then a success, with two waits.
case_succeeds_after_failures() {
  run_script 2 "${image}"
  expect_pulls "two failures, then a success" 0 3
  expect_waits "two failures wait up to 2 and 4 seconds" 2 4
}

# Case: four failed pulls, then a success on the fifth and last pull.
case_succeeds_on_the_last_attempt() {
  run_script 4 "${image}"
  expect_pulls "four failures, then a success on the fifth pull" 0 5
  expect_waits "four failures wait up to 2, 4, 8 and 16 seconds" 2 4 8 16
}

# Case: the wait follows the draw and grows with the number of failed attempts.
# With RANDOM pinned to R, the wait after failed attempt n is R modulo
# (ceiling(n) + 1), with the ceilings 2, 4, 8 and 16: the moduli are 3, 5, 9 and 17.
# Side effect: sets and clears `pinned_random`.
case_waits_follow_the_draw() {
  pinned_random=0
  run_script 4 "${image}"
  expect_exact_waits "a draw of 0 waits 0 seconds every time" 0 0 0 0
  pinned_random=764
  run_script 4 "${image}"
  expect_exact_waits "the highest draw waits the ceiling, which doubles" 2 4 8 16
  pinned_random=13
  run_script 4 "${image}"
  expect_exact_waits "a draw of 13 waits 1, 3, 4 and 13 seconds" 1 3 4 13
  pinned_random=""
}

# Case: five failed pulls end in exit status 1, an error line, and no wait
# after the last pull.
case_gives_up() {
  run_script 100 "${image}"
  expect_pulls "five failures give up" 1 5
  expect_waits "giving up waits only between pulls" 2 4 8 16
  if ! grep -qF "::error::docker pull of ${image} failed 5 times." "${output}"; then
    fail "five failures give up" "no error line: $(<"${output}")"
  fi
}

# Case: a call without an image is a usage error with exit status 2 and no pull.
case_usage() {
  run_script 0
  expect_pulls "no image is a usage error" 2 0
}

install_fakes
case_first_pull_succeeds
case_succeeds_after_failures
case_succeeds_on_the_last_attempt
case_waits_follow_the_draw
case_gives_up
case_usage

((failures == 0))
