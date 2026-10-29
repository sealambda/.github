# `sealambda/.github`

The shared foundation of the Sealambda organization: the default community
health files, the toolchain, the docs kit and the reusable workflows. This
repository is public, as GitHub requires for the default files. It holds no
secrets and no account IDs, and the naming scheme of the release roles is
public. Do not add a secret or a private fact: treat every file as public.

The license of this repository is the [Mozilla Public License 2.0](LICENSE).

## What it provides

| Part                         | What it is                                                                                                       | How a repository uses it                                                                    |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Community health files       | `CONTRIBUTING.md`, `SECURITY.md`, `SUPPORT.md`, the issue forms and `config.yml`, and `pull_request_template.md` | Automatically, when the repository has no file of that type.                                |
| `toolchain/`                 | The toolchain flake: the versions of the tools, and the formatters and linters.                                  | A flake input. See the [toolchain README](toolchain/README.md).                             |
| `docs-kit/`                  | The docs kit: a Vale style, a Markdown lint configuration, a link check and the page templates.                  | A flake input, a Vale package or a workflow. See the [docs kit README](docs-kit/README.md). |
| `.github/workflows/docs.yml` | The reusable workflow that runs the docs check and the online link check.                                        | `uses: sealambda/.github/.github/workflows/docs.yml@docs-kit-vN`                            |

In a tag such as `docs-kit-vN` or `toolchain-vN`, `N` is the number of a
release. It is an integer. A release tag is never moved or deleted. The
[releases page](https://github.com/sealambda/.github/releases) lists the
numbers.

## Community health files

| File                                       | What it is                                                                                                                                    |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| [`CONTRIBUTING.md`](CONTRIBUTING.md)       | The organization's only process guide: commits, pull requests, checks, review, landing, undo, documentation and the agent essentials.         |
| [`SECURITY.md`](SECURITY.md)               | The security policy for public repositories: private vulnerability reporting, and a form that asks for a security contact.                    |
| [`SUPPORT.md`](SUPPORT.md)                 | The routes to get help.                                                                                                                       |
| `.github/ISSUE_TEMPLATE/`                  | The issue forms for a bug report, a feature or change request and a security contact request, and `config.yml`, which turns off blank issues. |
| `pull_request_template.md`                 | The body of a new pull request: Why, Change, Verification, Rollback, After deploy.                                                            |
| [`AGENTS.md`](AGENTS.md)                   | The agent instructions of this repository: a link to the agent essentials of the guide, and the local commands.                               |
| [`.github/CODEOWNERS`](.github/CODEOWNERS) | The code owners of this repository only. GitHub does not inherit this file.                                                                   |

There is no `CODE_OF_CONDUCT.md`. A code of conduct needs a contact that
receives reports, and no such contact exists. The file is added when the
contact exists.

A repository that defines issue templates of its own gets none of these
defaults, and an issue form enforces its required fields in public
repositories only. A repository needs its own `LICENSE`, because GitHub takes
no default license file. See
[How the default files of the organization work](docs/explanation/default-files.md).

## Quality gate

The gate needs [Nix](https://nixos.org/download/) with the experimental
features `nix-command` and `flakes` enabled
([`experimental-features`](https://nix.dev/manual/nix/stable/command-ref/conf-file.html#conf-experimental-features)
in `nix.conf`).

`scripts/check.sh` is the gate. It checks that the lock file of each flake
below the root matches its `flake.nix`, then runs `nix flake check`, which
runs every check of this repository: the formatters and linters of the
toolchain, the pnpm-only lint, the tests of the scripts that
`release-image.yml` runs, the docs check of the docs kit on the documents of
this repository, the lock file checks, and the checks of the toolchain and
the docs kit. Neither command writes a lock file, so a stale lock fails the
gate. CI runs the script on each pull request that is ready and on `main`, on
Linux (x86_64 and arm64) and on macOS (arm64), because the toolchain's
`version-line` check compares the versions of the system that runs it
(`.github/workflows/ci.yml`). Its job `ci` is the one status to require in a
ruleset. Each job of the `check` matrix also opens `nix develop` once and looks
up each forbidden package-manager command (`toolchain/package-managers.nix`) in
the PATH of that shell. It reports each name that it finds. It exits 1 if it
found any, or if the list of commands or the PATH is empty, else 0. A second job
calls the reusable workflow `docs.yml`, as a repository that uses the docs kit
does, and a scheduled workflow (`links.yml`) requests the links to other sites.
The job `release-dry-run` runs `lint-workflows.yml` and `secrets.yml` through
`release-image.yml`. They run gitleaks on the Git history and the online audits
of zizmor, which have no local equivalent. Run
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

## Reusable workflows

`.github/workflows/` also holds the organization's reusable workflows:
`gate.yml`, `lint-workflows.yml`, `secrets.yml` and `release-image.yml`.
Next to the jobs of the gate, `ci.yml` has one job for these workflows,
`release-dry-run`. It calls `release-image.yml` in dry-run mode on every pull
request. That run calls `gate.yml`, `lint-workflows.yml` and `secrets.yml` on
this repository, and builds the `Dockerfile` at the root. `scripts/check.sh` is
the gate of this repository.

- [Reusable workflows](docs/reference/workflows.md): the inputs, jobs and
  permissions of each workflow, and the entry point of the gate.
- [Call the reusable workflows](docs/how-to/call-the-reusable-workflows.md):
  connect a repository to them.

## More

- [Configure a repository](docs/how-to/configure-a-repository.md)
- [Undo a landed pull request](docs/how-to/undo-a-landed-pull-request.md)
- [Decision records](docs/decisions/README.md)
