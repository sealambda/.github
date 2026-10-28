# Agent instructions

The organization's process guide is [CONTRIBUTING.md](CONTRIBUTING.md). Read
its section "Agent essentials" before you commit or open a pull request. That
section is the one source of the rules for agents. This file holds only the
commands of this repository.

## Checks

- `scripts/check.sh` runs the commands of the quality gate, as CI does:
  `nix flake check` and the lock checks of the subflakes.
- `nix fmt` formats and lints the whole tree. The pre-commit hook runs
  `nix fmt -- --fail-on-change` on the staged files.
- `git add` new files before `nix flake check`: Nix reads only the files that
  Git tracks.
- `nix develop` opens the development shell and installs the pre-commit hook.
