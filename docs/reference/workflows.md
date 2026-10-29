# Reusable workflows

This repository holds the reusable workflows of the organization. Another
repository calls one from a job with `uses:`. The workflows are in
`.github/workflows/`. [Call the reusable workflows](../how-to/call-the-reusable-workflows.md)
shows complete callers.

| Workflow                                | Purpose                                                                         |
| --------------------------------------- | ------------------------------------------------------------------------------- |
| [`gate.yml`](#gate)                     | The full gate of the caller on one commit, and the dependency audits            |
| [`lint-workflows.yml`](#lint-workflows) | actionlint and zizmor on the caller's workflows, zizmor on the caller's actions |
| [`secrets.yml`](#secrets)               | gitleaks on the history of the checked-out commit                               |
| [`docs.yml`](#docs)                     | The docs check of the caller's documents, from the docs kit                     |

## Rules for every workflow

- **The caller owns the context.** A reusable workflow runs in the caller's
  repository: `github.repository`, `github.sha`, `github.ref`, the token and
  the configuration files all belong to the caller.
- **Runners.** Each workflow takes the input `runs-on`: the runner as JSON,
  either one label in quotes (`'"ubuntu-24.04"'`) or an array of labels
  (`'["self-hosted","linux","x64"]'`). A private repository passes its
  self-hosted labels. A public repository always runs on the GitHub-hosted
  runner `ubuntu-24.04`, whatever it passes, because its pull requests come
  from forks and code from a fork must never run on a self-hosted runner.
  The workflows decide this from `github.event.repository.private`, which
  reads the caller's event. An event without that field also gets the
  GitHub-hosted runner. A private repository whose organization allows
  workflows to run on pull requests from forks has `private == true`, so fork
  code would run on its self-hosted runners: do not enable fork pull request
  workflows on a private repository that calls these workflows on self-hosted
  runners. GitHub has no workflow-level value for `runs-on`, so a file with
  several jobs states the expression once, in its first job, with the YAML
  anchor `&runner`, and the other jobs use `*runner`
  ([GitHub changelog, 2025-09-18](https://github.blog/changelog/2025-09-18-actions-yaml-anchors-and-non-public-workflow-templates/)).
  An anchor works inside one file, so each workflow file has its own copy.
  zizmor prints a warning for a file with anchors, because its support for
  them is in beta; the warning is not a finding.
- **Self-hosted runner requirements.** Docker, Bash 4.4 or later, and the
  Actions runner 2.336.0 or later, which resolves the `$/` references to the
  composite actions of this repository (see
  [Composite actions](#composite-actions)).
- **Docker.** The tools of `gate`, `lint-workflows` and `secrets` run in their
  official container images, pinned by digest (`docs` runs its tools from
  Nix). Each image is pulled first by the composite action `docker-pull`,
  which retries a failed pull. A container drops all capabilities and cannot
  gain any (`--cap-drop ALL --security-opt no-new-privileges`). The containers
  of actionlint and gitleaks run without a network (`--network none`). The
  container of OSV-Scanner has a network, because it queries the OSV database.
  The container of zizmor has a network, because its online audits call the
  GitHub API with the job token.
- **Permissions.** Each job of a reusable workflow declares the least it
  needs. The caller's job must grant at least the same, or GitHub refuses the
  run. The permissions to grant are under each workflow below.
- **Shell.** Every workflow sets `defaults.run.shell: bash`, so that a `run:`
  block fails on the first error and on a failure in a pipeline.
- **Pins.** Every action is pinned to a full commit SHA, and every image to a
  digest, with the version in a comment. actionlint and zizmor are pinned twice:
  as an image digest, which CI runs, and in the Nix lock of the
  [toolchain](../../toolchain/README.md), which `nix flake check` runs (zizmor
  at the pedantic persona and offline, against the default persona and the
  online audits here). Nothing compares the two pins, so a bump of one needs a
  bump of the other. gitleaks is pinned once, as an image digest in
  `secrets.yml`; `nix flake check` does not run it.
- **Downloads outside the pins.** `nixbuild/nix-quick-install-action` pins its
  script by SHA, but the script downloads the Nix archive from a release asset
  without a checksum. The organization accepts this residual risk. The archive
  is the Nix that evaluates the caller's flake, and it runs before any caller
  code.
- **Secrets.** No workflow takes a secret.
- **Local checks.** `nix flake check` runs actionlint and zizmor offline, but
  it does not run gitleaks over the history or zizmor's online audits. Only
  these workflows do, so a pull request can pass the local gate and fail them.

### Actions to allow

The workflows use these actions. A caller that allows only selected actions
allows them:

- `actions/checkout` (owned by GitHub)
- `nixbuild/nix-quick-install-action` (GitHub-hosted runners only)
- `actions/cache`, which also covers `actions/cache/restore` and
  `actions/cache/save` (only `docs.yml` with `external-links: true`)
- The composite actions of this repository, `sealambda/.github/.github/actions/*`,
  when the policy refuses a run that uses them (GitHub's documentation of `$/`
  does not say how the policy treats these references)

The tools themselves are container images, not actions:
`ghcr.io/google/osv-scanner-action`, `ghcr.io/gitleaks/gitleaks`,
`rhysd/actionlint` and `ghcr.io/zizmorcore/zizmor`.

### Composite actions

Steps that need more than a few lines of shell live in composite actions in
`.github/actions/`. Each one is a directory with `action.yml` and a script that
the tests cover. The workflows reference them as `$/.github/actions/<name>`:
GitHub resolves `$/` against the repository of the workflow file, at the
running commit, and needs the runner 2.336.0 or later
([GitHub changelog, 2026-07-30](https://github.blog/changelog/2026-07-30-reference-same-repository-actions-with-self-repository-syntax)).
A reference with `./` would resolve against the caller's repository and run
the caller's file instead.

actionlint 1.7.12 rejects `$/` in a step
([rhysd/actionlint#711](https://github.com/rhysd/actionlint/issues/711)). The
file `.github/actionlint.yaml` of this repository ignores that one message in
each file that needs it, and names the condition to remove it.

| Action        | What it does                                                                         |
| ------------- | ------------------------------------------------------------------------------------ |
| `docker-pull` | `docker pull` of an image, retried up to five times with a jittered, bounded backoff |
| `mix-audit`   | `mix hex.audit` in every Mix project of the checkout                                 |

## `gate`

`gate.yml` checks the commit `github.sha` of the caller. Three jobs run in
parallel. The caller's job fails when one of them fails.

| Job                  | What it runs                                                                          |
| -------------------- | ------------------------------------------------------------------------------------- |
| `scripts/ci/gate.sh` | The caller's [entry point](#the-entry-point)                                          |
| `osv-scanner`        | [OSV-Scanner](https://google.github.io/osv-scanner/) on every lock file of the commit |
| `mix hex.audit`      | `mix hex.audit` in every directory with a tracked `mix.lock`                          |

### Inputs

| Input             | Type   | Default            | Description                             |
| ----------------- | ------ | ------------------ | --------------------------------------- |
| `runs-on`         | string | `'"ubuntu-24.04"'` | The runner of every job, as JSON        |
| `timeout-minutes` | number | `60`               | The time limit of the entry point's job |

The commit to check is not an input: it is `github.sha` of the caller's event.

### Outputs

None. The result of the caller's job is the result of the gate.

### Permissions

The caller's job grants `contents: read`.

### The entry point

The gate runs the caller's own complete gate through one fixed entry point:
the executable file `scripts/ci/gate.sh` in the caller's repository.

- The file is tracked with the executable bit (`git update-index --chmod=+x`).
- The gate runs it with no arguments, from the root of a checkout of the
  commit `github.sha` with all of its history.
- It runs on the caller's runner. A GitHub-hosted runner gets Nix first, so
  the script can use `nix develop` and `nix flake check` on every runner.
- The file name ends in `.sh`, like every shell script of the organization
  ([toolchain README](../../toolchain/README.md#shell-scripts)). The
  entry point of `sealambda/.github` is the smallest example:
  [`scripts/ci/gate.sh`](../../scripts/ci/gate.sh) runs
  [`scripts/check.sh`](../../scripts/check.sh), the script that holds the
  gate commands of this repository.
- It gets no credential of the cloud or of a registry, and the job token can
  only read the repository. The checkout keeps no token, and the Nix install
  step receives an empty `github_access_token`, so the action does not write
  the job token to the Nix configuration or to `~/.netrc`. The same holds for
  the `mix hex.audit` job, which runs the `mix.exs` files and the dependencies
  of the caller after the same install step
  ([Dependency audits](#dependency-audits)). The Nix installed without a token
  fetches from GitHub unauthenticated, which has a lower rate limit. A check
  that needs a cloud credential does not belong in the entry point.
- Exit status 0 means that the commit passed. Any other status fails the gate.
- It runs every check that the repository's pull request gate runs, so that
  the gate on `main` decides the same as the review did. A repository whose
  pull request gate is parallel jobs runs them one after the other here, and
  sets `timeout-minutes` to fit.

### Dependency audits

- **OSV-Scanner** scans every lock file that it supports, recursively from the
  root, and fails on a known vulnerability. A commit without a lock file
  passes. It runs the image of Google's `osv-scanner-action`, pinned by digest:
  the action names that image by a tag that can move, and the project's
  reusable workflow uploads to code scanning, which private repositories on
  GitHub Free do not have.
- An `osv-scanner.toml` file next to a lock file can ignore a vulnerability of
  that lock file. Give each ignore a `reason` and an `ignoreUntil` date.
  OSV-Scanner does not require these two fields; the review of the pull
  request that adds an ignore does.
- **`mix hex.audit`** runs in each directory that has a tracked `mix.lock`,
  inside the default shell of the caller's flake
  (`nix develop --no-update-lock-file`: the job never rewrites `flake.lock`,
  and fails when the lock file is not current). The composite action
  `mix-audit` finds the projects with `git ls-files`, so an untracked
  `mix.lock` does not count, and a failure of `git` fails the job. It reads
  `mix.lock` files at any depth, and so a tracked `mix.lock` of a vendored
  dependency (such as `deps/x/mix.lock`) is a project too and is audited. In
  each project it runs `mix hex.info`, `mix deps.get` and `mix hex.audit`, then
  reports every failing directory together. A commit without a `mix.lock`
  passes. The shell must provide Elixir and Hex 2.5.1 or later; the
  `devShells.<system>.default` of the organization's
  [toolchain](../../toolchain/README.md) does, and a caller that builds its own
  shell adds the toolchain's `hex` package. `mix hex.info` fails when the shell
  has no Hex, so that Mix never downloads whatever Hex version hex.pm serves
  that day. The audit fails on a retired package or on a package with a
  security advisory.
- `mix.exs` can ignore a finding:
  `hex: [ignore_advisories: [...], ignore_retirements: [...]]`. Give each
  ignore a comment with its reason and the date to review it. Hex does not
  require these comments; the review of the pull request that adds an ignore
  does.

## `lint-workflows`

`lint-workflows.yml` checks the caller's workflows and actions in
`.github/`: workflows with actionlint and zizmor, actions with zizmor.

| Job          | What it runs                                                                                                                                                                                                                                                                             |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `actionlint` | [actionlint](https://github.com/rhysd/actionlint) on the workflow files, with ShellCheck on their `run:` scripts. It does not read action files (`action.yml`), so it does not check their scripts. It reads `.github/actionlint.yaml` when the caller has one.                          |
| `zizmor`     | [zizmor](https://docs.zizmor.sh/) online on the workflows and the actions, at its default persona. It reads `.github/zizmor.yml` when the caller has one. Online audits, such as the check that a pinned SHA belongs to the action's repository, use the job token, which can only read. |

A composite action whose scripts are real `.sh` files gets ShellCheck from the
caller's own formatting check, as in this repository.

| Input     | Type   | Default            | Description                      |
| --------- | ------ | ------------------ | -------------------------------- |
| `runs-on` | string | `'"ubuntu-24.04"'` | The runner of every job, as JSON |

Outputs: none. Permissions: the caller's job grants `contents: read`.

Both tools read their configuration from the tree under check. A pull request
can change `.github/actionlint.yaml` or `.github/zizmor.yml` and so disable a
finding of its own. A change to either file needs an explicit review; a
repository that has a `CODEOWNERS` file lists them there.

## `secrets`

`secrets.yml` scans every commit reachable from the checked-out commit with
[gitleaks](https://github.com/gitleaks/gitleaks), the secret scanner that the
organization uses. It does not scan other branches of the caller. A finding
fails the job. The log names the rule, the file,
the line and the commit, and redacts the secret.

- gitleaks reads `.gitleaks.toml` at the root of the caller's repository, when
  there is one: rules, and allowlists for paths and patterns. It reads that
  file and `.gitleaksignore` from the tree under scan, so a pull request can
  add an allowlist for its own secret: a change to either file needs an
  explicit review, and a repository that has a `CODEOWNERS` file lists them
  there.
- A finding that is not a secret, or a secret that is already revoked and
  stays in old history, goes into `.gitleaksignore` at the root, one
  fingerprint per line. The log of the failed job prints each fingerprint.
- A real secret is revoked first. Removing it from the files does not remove
  it from history.

| Input     | Type   | Default            | Description                    |
| --------- | ------ | ------------------ | ------------------------------ |
| `runs-on` | string | `'"ubuntu-24.04"'` | The runner of the job, as JSON |

Outputs: none. Permissions: the caller's job grants `contents: read`.

## `docs`

`docs.yml` runs the docs check of the caller's repository on one commit: Vale,
markdownlint-cli2 and lychee (offline), from the [docs kit](../../docs-kit/README.md#reusable-workflow).
With `external-links: true` it also requests the links to other sites. The kit
is the version of the workflow file, so a caller that refers to
`sealambda/.github/.github/workflows/docs.yml@docs-kit-vN` gets the kit
`docs-kit-vN`. `N` is an immutable whole number that starts at 1. The runner
needs Nix: a GitHub-hosted runner gets it from `nixbuild/nix-quick-install-action`,
and the self-hosted runners of the organization have it.

| Input             | Type    | Default            | Description                                                                              |
| ----------------- | ------- | ------------------ | ---------------------------------------------------------------------------------------- |
| `sha`             | string  | empty              | The 40-character SHA of the commit to check. Empty: the commit of the caller's event     |
| `runs-on`         | string  | `'"ubuntu-24.04"'` | The runner, as JSON                                                                      |
| `timeout-minutes` | number  | `15`               | The time limit of the job                                                                |
| `templates`       | string  | empty              | Bash patterns of the repository's template files, one per line (`docs-check --template`) |
| `external-links`  | boolean | `false`            | Also request the links to other sites, with a cache of the results                       |

Permissions: the caller's job grants `contents: read`. The job checks out the
whole commit, because the documents link to other files of the repository.

| Output                  | Value                                                                                                                                                                                                               |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `external-links-status` | The exit status of the check of the links to other sites: `0` when the links work, `1` when a link is broken, `2` when the check could not run. Empty when the check did not start, or when `external-links` is off |

- A workflow that is called cannot see whether the pull request of its caller
  is a draft. A caller that skips drafts puts
  `if: ${{ !github.event.pull_request.draft }}` on the job that calls it.
- markdownlint-cli2 runs the files `.markdownlint-cli2.cjs` and
  `.markdownlint-cli2.mjs` of the checked tree as JavaScript. Never call this
  workflow from `pull_request_target` or `workflow_run`: the code of a fork
  would run with the token and the secrets of the base repository.
- The links to other sites are off by default, because a page of another site
  that moves would fail every open pull request. This repository checks them
  on a schedule.
