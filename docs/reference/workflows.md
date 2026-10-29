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
| [`release-image.yml`](#release-image)   | The checks on the merged commit, then the image build and push to ECR           |

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
  `release-image.yml` runs its jobs `check-trigger` and `publish` on
  `ubuntu-24.04` whatever it passes. The workflows decide this from
  `github.event.repository.private`, which
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
- `aws-actions/configure-aws-credentials` (`release-image.yml` only)
- `docker/login-action` (`release-image.yml` only)
- `docker/setup-buildx-action` (`release-image.yml` only)
- `docker/build-push-action` (`release-image.yml` only)
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

| Action          | What it does                                                                                         |
| --------------- | ---------------------------------------------------------------------------------------------------- |
| `check-trigger` | The trigger, owner and name checks of a release, then `head-of-main`                                 |
| `docker-pull`   | `docker pull` of an image, retried up to five times with a jittered, bounded backoff                 |
| `ecr-put-tag`   | The ECR steps of a release: `inspect` the repository and the tag, `put` the tag, `report` the digest |
| `head-of-main`  | Fails unless `github.sha` is the head of `main` of the caller                                        |
| `mix-audit`     | `mix hex.audit` in every Mix project of the checkout                                                 |

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

## `release-image`

`release-image.yml` releases the container image of a commit on `main`. Its
jobs run in this order:

1. **`check-trigger`.** A release runs on a push to `main` only, for a
   repository of this organization. The job checks the format of
   `aws-account-id`, `aws-region` and the repository name, and that the commit
   is still the head of `main` ([Which commit may release](#which-commit-may-release)).
2. **`gate`, `lint-workflows` and `secrets`.** Three jobs in parallel: the
   workflows [`gate.yml`](#gate), [`lint-workflows.yml`](#lint-workflows) and
   [`secrets.yml`](#secrets), each on `github.sha`. On GitHub Free a private
   repository cannot require a check before a merge, so the release runs these
   checks itself, and builds only when all of them pass. A repository that
   releases needs no separate call of these three on `main`. The release calls
   them with `$/`, which names a file of this repository and not a file of the
   caller's repository.
3. **`publish`.** It needs the four jobs above. It checks the head of `main`,
   assumes the role, builds, checks the head again and tags the image.
   - It builds `Dockerfile` at the root of the commit for `linux/amd64`,
     without provenance or SBOM attestations, so the digest names one image
     manifest. The BuildKit image is pinned by digest. The build uses no cache
     and uploads no build record.
   - It pushes the image by digest, with no tag. Then it gives the image the
     tag `build-<sha>` with ECR `PutImage`.
   - It writes the digest to the job summary and to the output `digest`.

`check-trigger` and `publish` always run on the GitHub-hosted runner
`ubuntu-24.04`, whatever `runs-on` says. A self-hosted runner can keep files
from the jobs of other repositories, and `publish` holds the AWS credentials.

### Which commit may release

A release refuses every commit that is not the head of `main`. `check-trigger`
compares `github.sha` with the head of `main` at the start. `publish` compares
it again before it asks for credentials, and once more before it tags the
image. If a check cannot read the head, it fails and the release stops.

Because of this, the re-run of an old run is refused once a newer commit is on
`main`. That is intended: a re-run keeps its original commit, and a superseded
commit must not replace a newer release.

- The head checks refuse a commit that a newer head of `main` has superseded.
- `PutImage` decides only between two runs of the same commit.
- A window of a few seconds stays: the time between the last head check and
  `PutImage`. A commit that is released in this window was the head of `main`
  when the check ran.

A [dry run](#dry-run) checks neither the head nor anything else in `check-trigger`.

### Names

Every name comes from the caller's repository name, lower-cased. No input can
name another repository's image or role. The account and the region choose
where the role is looked up. A repository of another owner cannot release:
`check-trigger` compares the numeric ID of the owner.

| Name           | Value                                                                    |
| -------------- | ------------------------------------------------------------------------ |
| ECR repository | `<name>`                                                                 |
| Role           | `arn:aws:iam::<aws-account-id>:role/release-push-<name>`                 |
| Image          | `<aws-account-id>.dkr.ecr.<aws-region>.amazonaws.com/<name>:build-<sha>` |

The name has 2 to 51 characters: lower-case letters and digits, with single
`.`, `_` or `-` between them. The limit of 51 leaves room for `release-push-`
in the 64 characters of an IAM role name. ECR allows more names, such as
`data--sync`; this workflow accepts the stricter set. A repository with
another name cannot release.

### Release inputs

| Input                  | Type    | Default            | Description                                                                                            |
| ---------------------- | ------- | ------------------ | ------------------------------------------------------------------------------------------------------ |
| `aws-account-id`       | string  | `""`               | The AWS account of the registry, 12 digits; not used in a dry run                                      |
| `aws-region`           | string  | `""`               | The AWS region of the registry; not used in a dry run                                                  |
| `runs-on`              | string  | `'"ubuntu-24.04"'` | The runner of `gate`, `lint-workflows` and `secrets`, as JSON; `check-trigger` and `publish` ignore it |
| `gate-timeout-minutes` | number  | `60`               | The time limit of the gate's entry point                                                               |
| `dry-run`              | boolean | `false`            | Run the checks and build, but assume no role and push nothing                                          |

Pass the account and the region from repository variables. Organization
variables do not reach private repositories on GitHub Free.

### What the gate covers

The release runs exactly these checks on the commit:

- the caller's [entry point](#the-entry-point), `scripts/ci/gate.sh`;
- OSV-Scanner and `mix hex.audit` ([dependency audits](#dependency-audits));
- actionlint and zizmor on the caller's workflows and actions;
- gitleaks on the history of the commit.

The first check is the caller's own script, taken from the commit that is
released. A person who can push to the caller's `main` can change the script
in the same commit as the Dockerfile. On GitHub Free no rule prevents this in a
private repository. The gate is as strong as the caller's `scripts/ci/gate.sh`.

The gate and the image are independent. The gate runs in the caller's tools,
usually its Nix shell. The image is built from the caller's `Dockerfile`, with
its own base images. Nothing compares the two, so the versions that the gate
tested and the versions in the image can differ. Keep the versions of the
`Dockerfile` in step with the caller's toolchain.

### Release outputs

| Output   | Description                                         |
| -------- | --------------------------------------------------- |
| `digest` | The digest of the image manifest, `sha256:<64 hex>` |

### Release permissions

The caller's job grants `contents: read` and `id-token: write`. Only `publish`
holds `id-token: write`. The jobs that run the caller's code (`gate`,
`lint-workflows` and `secrets`) get `contents: read` only.

### The release role

The caller must use the reference `@main`: `release-image.yml` runs from
the `main` branch of this repository, and nothing else is trusted.

**Trust policy.** The role `release-push-<name>` trusts GitHub's OIDC provider
with these five conditions, all `StringEquals`, with no wildcard. Each
condition key has the prefix `token.actions.githubusercontent.com:`.

| Claim                 | Value                                                                   |
| --------------------- | ----------------------------------------------------------------------- |
| `aud`                 | `sts.amazonaws.com`                                                     |
| `repository_owner_id` | The numeric ID of the organization                                      |
| `repository_id`       | The numeric ID of the caller's repository                               |
| `ref`                 | `refs/heads/main`                                                       |
| `job_workflow_ref`    | `sealambda/.github/.github/workflows/release-image.yml@refs/heads/main` |

A `StringLike` on the file name, or a tag or branch wildcard, lets any other
branch or tag of this repository mint tokens for the role.

**Permissions.** The role needs these actions, and no others:

- On the resource `*`: `ecr:GetAuthorizationToken`.
- On the ECR repository `<name>` only: `ecr:BatchCheckLayerAvailability`,
  `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`,
  `ecr:CompleteLayerUpload`, `ecr:PutImage`, `ecr:BatchGetImage`,
  `ecr:DescribeImages` and `ecr:DescribeRepositories`.

[The AWS policy for pushing an image](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-push-iam.html)
holds `ecr:GetAuthorizationToken` and the six repository actions from
`ecr:BatchCheckLayerAvailability` to `ecr:BatchGetImage`. The role needs two
more, which that policy does not list: `ecr:DescribeImages` finds an existing
tag, and `ecr:DescribeRepositories` reads the tag mutability. `ecr:BatchGetImage`
reads the manifest of the pushed image, and `ecr:PutImage` tags it with that
manifest.

**Repository.** `publish` fails unless the ECR repository has
`imageTagMutability` `IMMUTABLE`. The values `MUTABLE` and
`IMMUTABLE_WITH_EXCLUSION` fail.

**Tag lifetime.** The tag `build-<sha>` is immutable while it exists. A
lifecycle policy of the repository can expire it. After that, a run for the
same commit builds and pushes again, and the new digest can differ. Only the
head of `main` can run, so this affects a re-run of the newest commit only.

**Re-run.** A second run for a released commit finds the tag `build-<sha>` and
returns its digest. If two runs of one commit tag the image at the same time,
`PutImage` accepts one. The other gets "image already exists", looks up the tag
and returns the same digest.

**Audit.** The role session is named `release-image-<run_id>-<run_attempt>`, so
CloudTrail tells the attempts of one run apart.

### Runbook: re-run a release

Use "Re-run all jobs". "Re-run failed jobs" and the re-run of a single job use
the file `release-image.yml` of the first attempt, and the trust policy accepts
every version of that file on `main`. After a security fix to this workflow,
cancel the pending runs, then use "Re-run all jobs". The head check refuses a
commit that is no longer the head of `main`.

### Dry run

`dry-run: true` runs `gate`, `lint-workflows`, `secrets` and the build, from
any event and any ref. `check-trigger` ends at once and checks nothing: not the
event, the ref, the repository name, the registry or the head of `main`. It
outputs no names. `publish` skips the head checks, the role and the push: it
exports the image to a file instead, and outputs the digest of that image. A
dry run needs no AWS role and no account. Use it to test a caller, or a change
to this workflow.

`ci.yml` of this repository runs a dry run on every pull request that is ready
for review, forks included, with the `Dockerfile` at the root of this
repository. A pull request from a fork gets no OIDC token, and the dry run
needs none.

`publish` still holds `id-token: write` in a dry run, because the caller must
grant the permissions that a called job declares. The job runs no script of
the caller. Only the Docker build runs the caller's code, and BuildKit `RUN`
steps get no variable of the runner, so they cannot request a token. Add no
step that runs the caller's scripts to `publish`.
