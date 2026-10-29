# Call the reusable workflows

This guide connects a repository of the organization to the reusable
workflows of this repository. [Reusable workflows](../reference/workflows.md)
describes each input, job and permission.

## 1. Allow the actions

A reusable workflow runs its actions under the caller's Actions policy. When
the caller allows only selected actions, add the third-party actions that the
workflows use. The list is in
[Reusable workflows](../reference/workflows.md#actions-to-allow). A
self-hosted runner needs Docker, Bash 4.4 or later and the Actions runner
2.336.0 or later.

## 2. Accept the reference in zizmor

The callers name the workflows by the branch `main`. zizmor requires a SHA by
default. Allow the reference in the caller's `.github/zizmor.yml`:

```yaml
rules:
  unpinned-uses:
    config:
      policies:
        sealambda/.github/*: ref-pin
```

## 3. Add the entry point

Add an executable `scripts/ci/gate.sh` that runs every check of the repository's
pull request gate, as [the entry point](../reference/workflows.md#the-entry-point)
says. Run it once by hand before you commit it. The gate leaves the job token
out of `~/.netrc` and the Nix configuration, so the script and the `mix.exs`
files and dependencies that the `mix hex.audit` job runs get no token. Nix
fetches from GitHub unauthenticated, with a lower rate limit.

## 4. Call the workflows

Call `lint-workflows` and `secrets` on every pull request that is ready for
review. A repository that releases an image calls `release-image` on `main`:
it runs the gate, `lint-workflows` and `secrets` itself. Any other repository
calls `gate`, `lint-workflows` and `secrets` on `main` as well. The gate
checks the commit of the event, so it takes no commit input.

Give the caller a `concurrency` block. A newer push to a pull request then
cancels the older run, which would otherwise keep a runner busy. A run on
`main` always finishes: GitHub keeps only one pending run per group and
cancels the older pending one, so each push to `main` gets a group of its own.

The input `runs-on` is JSON. A repository variable that feeds it, such as
`RUNS_ON_SMALL` below, holds JSON too: `"ubuntu-24.04"`, with the quotes, to
move the jobs to GitHub-hosted runners, or `["self-hosted","linux","x64"]`. The
value `ubuntu-24.04` without quotes is not JSON: the run fails at the start
with an "invalid JSON" error on the run summary and no job log.

A private repository must not enable workflows for pull requests from forks
when it calls these workflows on self-hosted runners: the workflows treat a
private repository as trusted, and a fork would run its code there.

### Example: a Mix application on self-hosted runners

The repository is private. Its runners have Nix and Docker. A repository
variable can move the jobs to GitHub-hosted runners without a commit.

`scripts/ci/gate.sh`: the tests need PostgreSQL, so the script starts it first.
The container has no fixed name and no fixed host port, so that two gates on
one host do not collide. The script registers the cleanup before it starts the
container, waits for the health check with a deadline, and reads the port that
Docker chose.

```bash
#!/usr/bin/env bash
# The full gate of this repository for gate.yml of sealambda/.github: every
# check that the pull request gate runs, one after the other.
set -euo pipefail

container=""
trap 'if [[ -n "${container}" ]]; then docker rm --force "${container}" >/dev/null; fi' EXIT

container="$(docker run --detach --publish 127.0.0.1::5432 \
  --env POSTGRES_PASSWORD=postgres \
  --health-cmd 'pg_isready --username postgres' --health-interval 1s \
  public.ecr.aws/docker/library/postgres:18@sha256:edb0c08dc33befd0262ab3b5cf1c4f3f8cfd8b09e88c05b45adee29d6761ddb6)"

deadline=$((SECONDS + 60))
health=starting
while [[ "${health}" != healthy ]]; do
  if ((SECONDS >= deadline)); then
    echo "PostgreSQL was not healthy after 60 seconds." >&2
    exit 1
  fi
  sleep 1
  health="$(docker inspect --format '{{.State.Health.Status}}' "${container}")"
done

port="$(docker inspect --format '{{(index (index .NetworkSettings.Ports "5432/tcp") 0).HostPort}}' "${container}")"
export DATABASE_URL="ecto://postgres:postgres@127.0.0.1:${port}/app_test"
nix develop --command mix check
```

`.github/workflows/hub.yml`:

```yaml
name: Hub

# The organization's shared checks (sealambda/.github).
on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]
  push:
    branches: [main]

permissions: {}

# A newer push to a pull request cancels the older run. A run on main always
# finishes, because each push to main has its own group.
concurrency:
  group: hub-${{ github.event.pull_request.number || github.sha }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

jobs:
  lint-workflows:
    if: github.event_name == 'pull_request' && !github.event.pull_request.draft
    permissions:
      contents: read
    uses: sealambda/.github/.github/workflows/lint-workflows.yml@main
    with:
      runs-on: ${{ vars.RUNS_ON_SMALL || '["self-hosted","linux","x64","small"]' }}

  secrets:
    if: github.event_name == 'pull_request' && !github.event.pull_request.draft
    permissions:
      contents: read
    uses: sealambda/.github/.github/workflows/secrets.yml@main
    with:
      runs-on: ${{ vars.RUNS_ON_SMALL || '["self-hosted","linux","x64","small"]' }}

  release:
    if: github.event_name == 'push'
    permissions:
      contents: read
      id-token: write
    uses: sealambda/.github/.github/workflows/release-image.yml@main
    with:
      aws-account-id: ${{ vars.AWS_ACCOUNT_ID }}
      aws-region: ${{ vars.AWS_REGION }}
      runs-on: ${{ vars.RUNS_ON_SMALL || '["self-hosted","linux","x64","small"]' }}
      gate-timeout-minutes: 120
```

`release-image` runs `gate`, `lint-workflows` and `secrets` itself on the
commit that it releases, so the repository calls them on pull requests only
and does not call `gate.yml` on `main`. A failed check blocks the release.

### Example: an infrastructure repository with Nix and OpenTofu

The repository is private. `nix flake check` boots virtual machines, so the
gate runs on the runners that have `/dev/kvm`.

`scripts/ci/gate.sh`:

```bash
#!/usr/bin/env bash
# The full gate of this repository for gate.yml of sealambda/.github: the
# static checks, then the flake check. The plans need credentials and stay in
# the pull request workflow.
set -euo pipefail
nix develop --command scripts/check-static.sh
nix flake check -L
```

`.github/workflows/hub.yml` is the same as in the first example, with the
runner labels of the repository. The `gate` job uses the runners with
`/dev/kvm`:

```yaml
gate:
  if: github.event_name == 'push'
  permissions:
    contents: read
  uses: sealambda/.github/.github/workflows/gate.yml@main
  with:
    runs-on: ${{ vars.RUNS_ON_KVM || '["self-hosted","linux","x64","kvm"]' }}
    timeout-minutes: 60
```

## 5. Clear the first findings

The first run reports what is already in the repository:

- **secrets:** decide for each finding. Revoke a real secret. Add the
  fingerprint of a false positive, or of a revoked secret, to
  `.gitleaksignore`, with a comment that says why. List `.gitleaks.toml`,
  `.gitleaksignore`, `.github/zizmor.yml` and `.github/actionlint.yaml` in the
  repository's `CODEOWNERS`: the scanners read them from the tree they scan,
  so a pull request can otherwise disable its own scan.
- **osv-scanner:** update the vulnerable packages. Ignore a vulnerability that
  does not affect the repository in `osv-scanner.toml`, with a reason and an
  expiry date.
- **mix hex.audit:** update the retired and vulnerable packages. Ignore a
  finding that does not affect the repository in the `hex` key of `mix.exs`,
  with a comment that gives the reason and a date to review it.
