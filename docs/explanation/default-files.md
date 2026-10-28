# How the default files of the organization work

The organization keeps its community health files in one repository,
`sealambda/.github`, and GitHub shows them in the other repositories. This
page explains what GitHub does with those files, which files it leaves out,
and why the files say what they say.

## Context

GitHub applies a default file to every repository of the organization that has
no file of that type, whatever the visibility of the repository. GitHub looks
for a file of the repository first, in the `.github` folder, then in the root,
then in `docs`, and only then takes the default. The `.github` repository
must be public. See
[creating a default community health file](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file).

The organization has private and public repositories, and the defaults reach
all of them. Each rule below follows from that fact.

## How it works and why

### One file, shown in other repositories

GitHub shows `CONTRIBUTING.md` and `SECURITY.md` from the `.github`
repository. A relative link in such a file may resolve against the repository
that shows it. These files therefore use absolute links to
`github.com/sealambda/.github`.

### Issue forms replace the whole folder

A repository that defines valid issue templates or a chooser configuration in
its own `.github/ISSUE_TEMPLATE` folder gets none of the default folder. The
defaults are a fallback for a repository with no templates. A repository
that adds a single template also drops the bug form, the change form, the
security contact form and the chooser configuration, and must copy what it
wants to keep.

The required fields of a form are enforced in public repositories only. In a
private repository, a reporter can submit a form with empty fields. The
organization accepts this limit.

### The security policy covers public repositories

Private vulnerability reporting is a feature of public repositories, so the
policy names public repositories as its scope. A reporter of a private
repository is a member of the organization, and tells the maintainers of that
repository.

A public repository can have private vulnerability reporting turned off. The
fallback is the issue form **Request a security contact**. The form is
public, so it holds the name of the repository and no detail of the
vulnerability. Without the form, a reporter who finds the report page missing
has no working channel.

The policy sets targets: an acknowledgement within 5 business days, and a
coordinated disclosure within 90 days. They are goals and bind nobody.

A form or a chooser link cannot know which repository shows it. The issue
forms say "the security policy of this repository" and carry no link. The
chooser link must be an absolute URL, so it opens the policy of the
organization and says that the policy of the repository wins.

### Files that are not defaults

- `LICENSE`: GitHub cannot take a default license file. Each repository states
  its own license. A contribution to a repository is licensed under the
  license of that repository, by the
  [GitHub terms of service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service),
  section D.6. `sealambda/.github` uses MPL-2.0.
- `CODEOWNERS`: GitHub does not inherit this file from the `.github`
  repository. Each repository has its own, and the ruleset of the repository
  takes its reviewers from it.
- `AGENTS.md`: it is not a GitHub file. A repository links its own `AGENTS.md`
  to the section "Agent essentials" of the contributing guide, and adds its
  own commands.

### Files that are missing on purpose

The organization has no `CODE_OF_CONDUCT.md`. A code of conduct needs a
contact that receives reports, and no such contact exists. A file without a
contact promises a channel that does not work. The file is added when the
contact exists.

`SUPPORT.md` lists the routes that exist: the issue forms and the security
contact form. There is no separate channel for questions.

### Provenance

A rebase merge creates new commits, so the signature of an author does not
survive on `main`. The record of provenance is the pull request and its
required review. The organization does not require signed commits.

## Alternatives

- **Copy the files into each repository.** Each copy drifts. A fix to the
  process then needs one pull request per repository.
- **A security mailbox.** A mailbox needs no repository setting, but it needs
  an account and a person who reads it.
- **Keep `SECURITY.md` out of the defaults until every repository has
  private vulnerability reporting.** The policy is then absent where a
  reporter needs it most.

## Related

- [Configure a repository](../how-to/configure-a-repository.md), for the
  settings that these files rely on.
- [Decision 0003](../decisions/0003-security-reporting-scope.md), the record of
  the security reporting scope.
- [Decision 0005](../decisions/0005-license-the-repository-under-mpl-2-0.md), the
  record of the license.
