#!/usr/bin/env bash
# The entry point that the reusable workflow gate.yml runs on a commit of this
# repository (docs/reference/workflows.md#the-entry-point). It runs the whole
# gate of the repository through scripts/check.sh, the one source of the gate
# commands: `nix flake check`, which holds the formatters, the linters and the
# tests, Markdown included (flake.nix lists the checks), and the lock checks of
# the subflakes. The pull request job `check` of ci.yml runs the same script.
#
# Exit status: the status of scripts/check.sh, 0 when every check passes.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "${root}"
exec scripts/check.sh
