# `sealambda/.github`

The shared foundation of the Sealambda organization: the default community
health files, the toolchain, the docs kit and the reusable workflows. This
repository is public, as GitHub requires for the default files. It holds no
internal facts.

## What it provides

| Part                         | What it is                                                                                         | How a repository uses it                                                                    |
| ---------------------------- | -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Community health files       | `CONTRIBUTING.md`, `SECURITY.md`, the issue forms and `config.yml`, and `pull_request_template.md` | Automatically, when the repository has no file of that type.                                |
| `toolchain/`                 | The toolchain flake: the versions of the tools, and the formatters and linters.                    | A flake input. See the [toolchain README](toolchain/README.md).                             |
| `docs-kit/`                  | The docs kit: a Vale style, a Markdown lint configuration, a link check and the page templates.    | A flake input, a Vale package or a workflow. See the [docs kit README](docs-kit/README.md). |
| `.github/workflows/docs.yml` | The reusable workflow that runs the docs check and the online link check.                          | `uses: sealambda/.github/.github/workflows/docs.yml@docs-kit-vN`                            |

### Community health files

GitHub applies a default file to every repository of the organization that has
no file of that type, whatever the visibility of the repository. See
[creating a default community health file](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file).

- [`CONTRIBUTING.md`](CONTRIBUTING.md) is the organization's only process
  guide: commits, pull requests, checks, review, landing, undo and
  documentation.
- [`SECURITY.md`](SECURITY.md) tells reporters to use private vulnerability
  reporting.
- `.github/ISSUE_TEMPLATE/` holds the issue forms for a bug report and for a
  feature or change request, and `config.yml`, which turns off blank issues.
  A repository that defines valid issue templates or a configuration uses
  its own folder only.
- `pull_request_template.md` is the body of a new pull request: Why, Change,
  Verification, Rollback, After deploy.
- A repository still needs its own `LICENSE`, because GitHub supports no
  default license file. `CODEOWNERS` is not a default file either. The file
  [`.github/CODEOWNERS`](.github/CODEOWNERS) applies to this repository only.
- [`AGENTS.md`](AGENTS.md) holds the agent instructions of this repository.
  Every repository copies the essentials block of `CONTRIBUTING.md` into its
  own `AGENTS.md`.

## Quality gate

The gate needs [Nix](https://nixos.org/download/) with the experimental
features `nix-command` and `flakes` enabled
([`experimental-features`](https://nix.dev/manual/nix/stable/command-ref/conf-file.html#conf-experimental-features)
in `nix.conf`).

`scripts/check.sh` is the gate. It checks that the lock file of each flake
below the root matches its `flake.nix`, then runs `nix flake check`, which
runs every check of this repository: the formatters and linters of the
toolchain, the pnpm-only lint, the docs check of the docs kit on the documents
of this repository, the lock file checks, and the checks of the toolchain and
the docs kit. Neither command writes a lock file, so a stale lock fails the
gate.
CI runs the script on each pull request that is ready and on `main`, on Linux
(x86_64 and arm64) and on macOS (arm64), because the toolchain's `version-line` check compares the
versions of the system that runs it (`.github/workflows/ci.yml`). Its job
`ci` is the one status to require in a ruleset. Each job of the `check`
matrix also opens `nix develop` once and looks up each forbidden
package-manager command (`toolchain/package-managers.nix`) in the PATH of that
shell. It reports each name that it finds. It exits 1 if it found any, or if
the list of commands or the PATH is empty, else 0. A second job calls the
reusable workflow `docs.yml`, as a repository that uses the docs kit does, and
a scheduled workflow (`links.yml`) requests the links to other sites. Run
`git rebase -x scripts/check.sh <base>` to check each commit of a series.

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
`editorconfig-checker` read it.

### Change the toolchain

After `nix flake update` in `toolchain/`, update the locks above it from the
bottom up: run `nix flake update toolchain` in `docs-kit/`, then
`nix flake update toolchain docs-kit` at the root. A lock copies the lock of
the subflake below it only when it is created or when that command runs, so
the locks drift apart otherwise. The check `lock-sync` fails until the three
locks agree. A tool that updates the locks automatically must update all
three in one change.
