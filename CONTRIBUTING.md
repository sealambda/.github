# Contributing

This guide is the process guide of the Sealambda organization. It applies to
people and AI agents, in every repository that has no `CONTRIBUTING.md` of its
own. A repository adds its own commands and facts and links here.

## Commits

Each commit is one logical change. Use this form:

```text
type(scope)!: summary in the imperative, at most 72 characters

Why the change exists: the problem, and why this is the fix. Wrap at 72.

Assisted-by: <tool> (<model>)
```

- Follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).
  The scope names the area. `!` marks a breaking change.
- Say why in the body. The diff shows what.
- **Sign every commit.** Use SSH signing and add the key to GitHub as a
  signing key:

  ```sh
  git config --global gpg.format ssh
  git config --global user.signingkey <path to your public key>
  git config --global commit.gpgsign true
  ```

- When an AI tool helped, add the `Assisted-by: <tool> (<model>)` trailer.
  Never add an AI as `Co-authored-by`. Don't add `Signed-off-by`.
- Never use `--no-verify`. If a hook refuses a commit, fix the cause.
- Each commit passes the repository's checks.

## Pull requests

- One pull request is one change. Split a change that grows past a few
  hundred lines of written code.
- The title is a Conventional Commit. The body follows the pull request
  template.
- Branch names are `<type>/<topic>`, for example `fix/listen-address`.
- Update a branch by rebase. Never merge the base into it.
- Make dependent changes a stack: one pull request per layer, each on the
  branch of the layer below.

## Review and landing

- A code owner who didn't commit to the pull request approves it.
- Fix review findings with fixup commits. Fold them in before landing with
  `git rebase -i --autosquash`.
- Land with **Rebase and merge**. `main` stays linear. Nobody pushes to
  `main`.
- To undo a landed pull request, revert its commits in a new pull request.

## Dependencies

[Renovate](https://docs.renovatebot.com/) is the only dependency updater.
Commit lock files. Don't write update scripts.

## Documentation

Follow [Diátaxis](https://diataxis.fr/): tutorials, how-to guides, reference
and explanation are separate pages. Write about the current state. Record an
architecturally significant decision as a
[MADR 4.0.0](https://adr.github.io/madr/) record in `docs/decisions/`. Write
short sentences in the active voice, and use one term for one concept.

## Agents

An agent follows this guide and these rules:

- Never push to `main`. Never merge a pull request unless a person asks. This
  rule doesn't cover the Renovate merge of a security fix inside the declared
  range.
- Open pull requests as drafts.
- Disclose AI help with the `Assisted-by` trailer.
- Read a repository's `AGENTS.md` for its commands.
