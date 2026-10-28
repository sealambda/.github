---
status: "accepted"
date: 2026-10-28
decision-makers: the code owners of this repository
---

# Scope security reporting to public repositories

## Context and Problem Statement

`SECURITY.md` in this repository is the default security policy of every
repository of the organization that has none of its own. GitHub applies it at
once, whatever the visibility of the repository. A policy must give a reporter
a channel that works.

GitHub offers private vulnerability reporting (PVR) to the owners of public
repositories, and a repository has it turned off until an administrator turns
it on. A policy that names PVR as its only channel leaves a reporter without
a channel in a repository that has not turned it on. A policy that tells the
reporter to open an issue needs an issue form for that purpose, or the
reporter has no place to start.

## Decision Drivers

- A reporter must always have a working channel, in every public repository.
- A vulnerability must never be described in a public issue.
- The fallback must need no repository setting.
- The policy must not promise what the maintainers cannot keep.

## Considered Options

- Private reporting as the only channel.
- A security mailbox of the organization.
- Private reporting, with a contact request form that holds no detail.
- Keep `SECURITY.md` out of the defaults until PVR is on everywhere.

## Decision Outcome

Chosen option: "Private reporting, with a contact request form that holds no
detail", because it gives a channel in a repository that has not
turned PVR on, and it needs no account that a person must read.

The policy has these parts:

- **Scope:** public repositories. For a private repository, the reporter tells
  its maintainers.
- **Supported versions:** `main` and the latest tag of each component.
- **Channel:** PVR, on the **Security and quality** tab. The fallback is the
  form **Request a security contact**, which holds the name of the repository
  and a confirmation that the issue holds no detail.
- **Targets:** an acknowledgement within 5 business days and a coordinated
  disclosure within 90 days. The targets do not bind the maintainers.
- **Safe harbor:** a short statement that research in good faith under the
  policy is treated as authorized. It covers the repositories under the
  policy, and no other system.
- **Rollout:** every public repository of the organization has PVR on before
  the policy lands. A read of
  `repos/<owner>/<repo>/private-vulnerability-reporting` returns
  `enabled: true` for each of them.

### Consequences

- Good, because every public repository has a private channel or a form that
  leads to one.
- Good, because the issue forms of a repository name "the security policy of
  this repository", and they are true when the repository has its own policy.
- Bad, because an administrator must turn on PVR in each public repository.
  The REST endpoint works for one repository at a time.
- Bad, because a maintainer answers the form by hand.
- Bad, because the issue form enforces its required fields in public
  repositories only, which is where the policy applies.

### Confirmation

- The merge of the policy waits for the read of PVR in each public repository.
- The validation of the issue forms with their schema runs in the `formatting`
  check of the flake.

## Pros and Cons of the Options

### Private reporting as the only channel

- Good, because the report stays in GitHub, and the maintainers get a private
  advisory.
- Bad, because a repository with PVR off has no channel. The report page is
  not found, and the policy leads nowhere.

### A security mailbox of the organization

- Good, because it needs no repository setting.
- Bad, because it needs an account and a person who reads it.

### Private reporting, with a contact request form that holds no detail

- Good, because it works in a repository with PVR off.
- Good, because a maintainer chooses the private channel.
- Bad, because the issue is public, so the form must warn the reporter and ask
  for no detail.

### Keep `SECURITY.md` out of the defaults until PVR is on everywhere

- Good, because no policy has a dead channel.
- Bad, because a repository then shows no policy where a reporter needs it.

## More Information

The explanation
[How the default files of the organization work](../explanation/default-files.md)
gives the context of the defaults.
