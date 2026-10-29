#!/usr/bin/env bash
# Pull a Docker image, and retry a failed pull a bounded number of times.
#
# A registry can answer a pull with a transient error or with
# `429 Too Many Requests` (Docker Hub limits anonymous pulls per source IP).
# The script makes at most MAX_ATTEMPTS pulls. After a failed pull it waits for
# a random time between 0 and BASE_DELAY * 2^(n-1) seconds, where n is the
# number of the failed attempt (full jitter), so that runners behind one
# address do not retry in step. The longest total wait is
# BASE_DELAY * (2^(MAX_ATTEMPTS-1) - 1) = 30 seconds. A pull that hangs is
# limited by the timeout of the job. The script cannot tell a transient error
# from a permanent one (a wrong digest), so it retries both; the cost is at
# most the 30 seconds.
#
# Usage: docker-pull.sh IMAGE
#   IMAGE  the image reference to pull, ideally with a digest.
#
# Requirements: Bash 4 or later, docker.
#
# Exit status: 0 after a successful pull; 1 when every attempt failed;
# 2 when no image is given.
set -euo pipefail

readonly MAX_ATTEMPTS=5
readonly BASE_DELAY=2

# Sleep for a random number of whole seconds, between 0 and the ceiling of the
# failed attempt (BASE_DELAY * 2^(attempt-1)), both included.
# Arguments: the number of the attempt that failed, starting at 1.
wait_before_retry() {
  local ceiling=$((BASE_DELAY * 2 ** (${1} - 1)))
  sleep "$((RANDOM % (ceiling + 1)))"
}

# Pull the image with retries.
# Arguments: the image reference.
# Exit status: see the header.
main() {
  if (($# != 1)); then
    echo "usage: docker-pull.sh IMAGE" >&2
    return 2
  fi
  local image="${1}" attempt
  for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
    if docker pull --quiet "${image}"; then
      return 0
    fi
    if ((attempt < MAX_ATTEMPTS)); then
      echo "::warning::docker pull of ${image} failed (attempt ${attempt} of ${MAX_ATTEMPTS}); retrying."
      wait_before_retry "${attempt}"
    fi
  done
  echo "::error::docker pull of ${image} failed ${MAX_ATTEMPTS} times."
  return 1
}

main "$@"
