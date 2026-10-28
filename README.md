# sealambda/.github

The default community health files of the organization.

GitHub applies these files to every repository of the organization that has
no file of its own, private repositories included. This repository is
public, as GitHub requires for these defaults. It holds no internal facts.

- `CONTRIBUTING.md` is the organization's only process guide: commits, pull
  requests, quality, review, landing, undo, dependencies, documentation and
  settings.
- `pull_request_template.md` is the body of a new pull request: Why, Change,
  Verification, Rollback, After deploy.
- `toolchain/` is the organization's toolchain flake: the versions of the
  tools, and the formatters and linters of every repository. Its
  [README](toolchain/README.md) is the reference for a consumer.

## Quality gate

The gate needs [Nix](https://nixos.org/download/) with the experimental
features `nix-command` and `flakes` enabled
([`experimental-features`](https://nix.dev/manual/nix/stable/command-ref/conf-file.html#conf-experimental-features)
in `nix.conf`).

`scripts/check.sh` is the gate. It checks that the lock file of each flake
below the root matches its `flake.nix`, then runs `nix flake check`, which
runs every check of this repository: the formatters and linters of the
toolchain, the pnpm-only lint, the lock-file checks and the toolchain's own
checks. Neither command writes a lock file, so a stale lock fails the gate.
CI runs the script on each pull request, on Linux (x86_64 and arm64) and on
macOS (arm64), because the toolchain's `version-line` check compares the
versions of the system that runs it (`.github/workflows/ci.yml`). Its job
`ci` is the one status to require in a ruleset. Each CI job also opens
`nix develop` once and checks that its PATH holds no package manager other
than pnpm. Run `git rebase -x scripts/check.sh <base>` to check each commit
of a series.

- `nix develop` opens a shell with the same tools, and installs the Git hook
  of `lefthook.yml`: pre-commit runs
  `nix fmt -- --fail-on-change <staged files>`. The hook is the fast part of
  the gate. CI decides the merge, and a push runs no hook.
- `nix fmt` formats and lints the whole tree.

### Use it in another repository

The root `flake.nix` is a complete example of a repository that consumes the
toolchain: it builds the formatter, the development shell and the checks
from the toolchain's outputs. It takes the toolchain from `path:./toolchain`;
another repository takes a tag, as the
[toolchain README](toolchain/README.md) shows. The repository also needs the
`.editorconfig` of this repository as a start: shfmt, Prettier and
editorconfig-checker read it.

### Change the toolchain

After `nix flake update` in `toolchain/`, run `nix flake update toolchain` at
the root. The root lock copies `toolchain/flake.lock` only when it is created
or when that command runs, so the two locks drift apart otherwise. The check
`toolchain-lock-sync` fails until they agree. A tool that updates the locks
automatically must update both in one change.
