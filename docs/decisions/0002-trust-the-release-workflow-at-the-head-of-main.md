---
status: "accepted"
date: 2026-10-28
decision-makers: the code owners of this repository
---

# Trust the release workflow at the head of main

## Context and Problem Statement

The reusable workflow `release-image.yml` of this repository builds a
container image and pushes it to a registry of the organization. A private
repository calls the workflow. The push uses a cloud role that trusts the
OpenID Connect (OIDC) token of the run. The role must trust one thing, and
that thing must be a commit that nobody can replay.

Three facts shape the problem:

- A re-run of a workflow keeps the commit (`GITHUB_SHA`) and the ref of the
  first run. A run of an old commit of `main` that is re-run later still looks
  like a run on `main`.
- A job that runs on a runner of the caller shares the machine with code of the
  caller. A credential on that machine is exposed to that code.
- A registry tag can be overwritten unless the registry forbids it.

## Decision Drivers

- The hub (this repository) is trusted at `main`. This was decided before
  this record.
- A release must refuse every commit that is not the head of `main`.
- The cloud credential must never reach a runner that runs code of a caller.
- A re-run must be safe: it returns the same image, or it fails.
- No claim of a guarantee that the platform does not give.

## Considered Options

- Trust any ref or tag of the workflow in the role.
- Trust `main` only, refuse every commit that is not the head of `main`, and
  publish on GitHub-hosted runners.
- Trust signed tags or releases.

## Decision Outcome

Chosen option: "Trust `main` only, refuse every commit that is not the head
of `main`, and publish on GitHub-hosted runners", because it is the only
option that refuses a replay of an old commit and keeps the credential away
from code of a caller, without a signing infrastructure that does not exist.

The design has these parts:

- **Runners.** The jobs `check-trigger` and `publish` run on `ubuntu-24.04`,
  a GitHub-hosted runner, whatever runner the caller chooses for the gate.
- **Siblings.** `release-image.yml` calls `gate`, `lint-workflows` and
  `secrets` as sibling jobs, with `$/` references that resolve to this
  repository. The job `publish` needs `check-trigger` and the three siblings.
- **Trigger check.** The composite action `check-trigger` checks the event,
  the ref, the input names, the owner of the repository by its numeric ID, and
  the head of `main`. The composite action `head-of-main` reads
  `/git/ref/heads/main` and requires the answer to equal `GITHUB_SHA`. If it
  cannot read the head, it fails.
- **Order in `publish`.** The head check comes first, before any credential.
  Then the job assumes the role, with a session name that holds the run ID and
  the attempt. It asserts that the registry repository is `IMMUTABLE`. It looks
  up the tag of the commit. It builds with a pinned BuildKit and pushes by
  digest, with no tag. It checks the head again. It then writes the tag
  `build-<sha>` with `put-image`, and a conflict makes it read the digest of
  the existing tag and return that digest.
- **Trust policy.** The role trusts five `StringEquals` conditions with no
  wildcard: `aud`, `repository_owner_id`, `repository_id`,
  `ref = refs/heads/main` and `job_workflow_ref` equal to this repository's
  `release-image.yml@refs/heads/main`. A caller uses `@main`.
- **No `concurrency` group.** GitHub cancels a pending run of a group even
  when `cancel-in-progress` is `false`, so a third run for one commit could
  cancel the pending release. Two runs of the same commit are safe without a
  group: `put-image` arbitrates them.

What protects what:

- The head checks refuse a commit that a newer head of `main` replaced.
- `put-image` only arbitrates two runs of the same commit.
- A window of a few seconds remains between the second head check and
  `put-image`. A commit that is released in that window was the head at the
  time of the check.

### Consequences

- Good, because a re-run or a late run of an old commit is refused.
- Good, because the credential exists only on a hosted runner that code of a
  caller never uses.
- Good, because a tag is immutable while it exists, and a repeated run returns
  the same digest.
- Bad, because the release needs GitHub-hosted minutes. A release fails until
  the hosted-runner billing is in order.
- Bad, because `main` of this repository is the root of trust. A change to a
  release file reaches every caller at once, so the ruleset requires a review
  of a code owner.
- Bad, because a re-run of failed jobs uses the workflow file of the first
  attempt. After a security fix to this file, cancel pending runs and use
  "Re-run all jobs" only.
- Bad, because a lifecycle policy of the registry may expire a tag, and the
  tag is immutable only while it exists.

### Confirmation

- Tests of the composite action scripts run with fake binaries and assert the
  exit code and the error text: every refusal of `check-trigger`, the cases of
  `head-of-main`, the lookup of the existing tag, the cases of `put-image`, the
  mutability assertion and the report of the digest.
- A generated grid of names checks the name rule against an independent oracle.
- The job `release-dry-run` of the CI of this repository calls the workflow
  with `dry-run: true` on every pull request, so the siblings and the build
  run without a push.
- A test in a registry repository that is `IMMUTABLE` checks the media type
  and both "already exists" answers before the first release.

## Pros and Cons of the Options

### Trust any ref or tag of the workflow in the role

- Good, because a caller can pin a tag and get a stable workflow.
- Bad, because any branch or tag of this public repository could then obtain
  the credential of every role, from any caller that points at it.
- Bad, because it does not refuse a replay of an old commit.

### Trust `main` only, refuse every commit that is not the head of `main`

- Good, because one condition set names one workflow file at one ref.
- Good, because the head check closes the replay of an old commit.
- Neutral, because a caller always runs the latest workflow of `main`, and not
  a pinned version.
- Bad, because a window of a few seconds remains, as stated above.

### Trust signed tags or releases

- Good, because a signature binds a release to a person.
- Bad, because a rebase merge replaces the commits of the author, and the
  organization has not set up signing.

## More Information

The decision does not cover the definition of the role and the registry
repositories. They live outside this repository, and they must match the trust
policy above.
