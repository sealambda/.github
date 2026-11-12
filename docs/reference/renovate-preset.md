# Renovate preset

`default.json` is the shared [Renovate](https://docs.renovatebot.com/) preset. A
repository extends it with `github>sealambda/.github`
([adopt the preset](../how-to/adopt-the-hub.md#extend-the-renovate-preset)). A
repository's `renovate.json` holds only what differs: its managers, constraints
and package rules. Renovate applies the package rules of the repository after
those of the preset, so a rule in the repository wins.

## Base presets

| Preset                          | Effect                                                                                                                                                                                                  |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `config:best-practices`         | The Renovate maintainers' recommended configuration. It pins GitHub Actions and Docker images by digest, proposes configuration migrations, flags abandoned packages and enables lock file maintenance. |
| `:semanticCommits`              | Commit messages and pull request titles use semantic prefixes.                                                                                                                                          |
| `:semanticCommitTypeAll(build)` | Every commit uses the type `build`.                                                                                                                                                                     |
| `:label(dependencies)`          | Every pull request gets the label `dependencies`.                                                                                                                                                       |
| `:approveMajorUpdates`          | A major version waits on the Dependency Dashboard until a person ticks it.                                                                                                                              |

The commit scope is `deps`, the Renovate default.

## Timing

All times are UTC, the Renovate default. The schedules use cron syntax, which
Renovate recommends over its deprecated text syntax. The minutes field is always
`*`, because Renovate has no minute granularity.

| Setting               | Value                                                                                                                                                                                   |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `schedule`            | `* 0-9 * * 1`: Monday before 10:00.                                                                                                                                                     |
| `lockFileMaintenance` | `* 0-9 1 * *`: the first day of the month, before 10:00.                                                                                                                                |
| `minimumReleaseAge`   | 7 days, for every package that has a release date, except a security fix. A lock file maintenance has no wait. A withdrawn or compromised release is less likely to reach a repository. |

Renovate cannot check the age of a lock file maintenance, a pin, a replacement,
a bump, a lock file update or a rollback. It cannot check the age of a Nix flake
input that follows a Git ref either. None of these updates has a release date.
The age check stays pending for them and Renovate never creates the branch, so
two rules set `minimumReleaseAge` to `null` for these updates. A third rule does
the same for a digest update of a reusable workflow of this hub. A repository
pins that workflow by commit SHA, with the branch name in a comment.

A repository that runs Renovate once a day needs a window of several hours,
because Renovate acts only when a run falls inside the window. A repository that
wants no window sets `schedule` to `["* * * * *"]`.

## Package rules

| Rule                                                                                     | Reason                                                                                              |
| ---------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Packages from the npm registry, which pnpm installs from, wait 7 days.                   | `config:best-practices` shortens the wait for that registry to 3 days.                              |
| Development dependencies keep their declared range.                                      | `config:best-practices` pins them to one version. The lock file already fixes the resolved version. |
| One pull request for the Mix minor and patch versions.                                   | Fewer pull requests and fewer deployments.                                                          |
| One pull request for the pnpm minor and patch versions.                                  | The same.                                                                                           |
| One pull request for the Elixir quality tools: Credo, Dialyxir, `mix_audit` and Sobelow. | The tools move together. The group takes the minor and patch versions.                              |
| One pull request for the minor and patch versions of the GitHub Actions.                 | The same as Mix.                                                                                    |
| A digest update of a reusable workflow of this hub gets its own pull request.            | It changes the checks of the repository, so Renovate never merges it.                               |
| OpenTofu providers come from the OpenTofu registry.                                      | `tofu init` uses that registry.                                                                     |
| The `required_version` of a Terraform root is ignored.                                   | It names OpenTofu, which Renovate would look up as Terraform.                                       |

## Other settings

- The Nix manager is on, and Renovate updates `flake.lock`. A repository lists
  the managers it uses in `enabledManagers`. The list must contain `nix` and
  `github-actions`. Without them, the `hub` input, the pinned workflows and the
  pinned actions get no updates.
- `osvVulnerabilityAlerts` is on. Renovate reads the OSV advisory database for
  direct dependencies, besides GitHub's Dependabot alerts. Renovate marks this
  option as experimental.

## Security fixes

The preset puts nothing in `vulnerabilityAlerts`. Renovate skips the release-age
wait and the schedule for a security fix. Two package rules add the label
`security` and decide the merge. They apply to the updates that Renovate finds
by its normal lookup:

- A fix that changes only the lock file merges automatically after the checks
  pass. If the rules of the repository require an approval, the merge waits for
  it.
- Any other fix changes a declared range or a major version. It opens as a draft
  pull request, and Renovate never merges it.

A fix for a transitive dependency is a remediation. Renovate builds it from
`vulnerabilityAlerts` alone and applies no package rule to it. It opens without
the label `security` and without an automatic merge, and a person merges it.

One exception follows from Renovate itself. Renovate forces its defaults for
`vulnerabilityAlerts` on a security fix, and these include no Dashboard
approval. A security fix for a major version therefore opens at once as a draft
pull request, without the tick that other majors need. The draft rule keeps it
from merging.

A repository that merges only through a person sets `automerge` to `false` in a
package rule that matches `isVulnerabilityAlert = true`.
