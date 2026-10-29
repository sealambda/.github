# Contributing

This guide is the only process document of the Sealambda organization. It
tells people and AI agents how to commit, review, land and undo changes in
every repository.

GitHub shows this file in each repository of the organization that has no
`CONTRIBUTING.md` of its own, private repositories included. A repository
does not copy it. A repository adds only its own commands and facts, and
links here.

GitHub Free cannot enforce these rules in a private repository. Nothing
blocks a push or a merge. Everyone follows the rules by hand.

## 1. Scope

- This guide covers process: commits, pull requests, checks, review,
  landing, undo, dependencies, documentation and repository settings.
- A repository documents its own commands, architecture and operations. It
  does not restate this guide.
- A repository shows an agent the rules in the block of section 13.

## 2. Environment

- Each repository provides one development shell: `nix develop`. CI runs the
  same tools from the same lock files, and checks the PATH of the shell.
- With direnv, an `.envrc` file with `use flake` loads the shell when you
  enter the directory.
- A repository lists its check commands in its `AGENTS.md`.

## 3. Work tracking

- Track planned work in GitHub Issues. Put each issue on the organization's
  project board, in a milestone when a date or a release depends on it.
- Label an issue `planned` when someone has agreed to do it.
- Do not keep `TODO` files or `TODO` lists in the repository. File an issue.
- Close an issue from the pull request that does the work: `Fixes #N` in the
  pull request body.

## 4. Commits

Each commit is one logical change. Use this form:

```text
type(scope)!: summary in the imperative, at most 72 characters

Why the change exists: the problem, and why this is the fix. Wrap at 72.

Assisted-by: Claude Code (claude-opus-5-5)
```

- **Format:** [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).
  Types: `feat`, `fix`, `docs`, `build`, `ci`, `refactor`, `perf`, `test`,
  `chore`, `revert`. The scope names the area. `!` marks a change that
  breaks a consumer.
- **Subject:** imperative mood, at most 72 characters.
- **Body:** say why. The diff already shows what.
- **Trailers:** `Fixes: <sha> ("<subject>")` for a bug fix. `Refs:` for
  related work.
- **AI help:** when an AI tool wrote a non-trivial part, add
  `Assisted-by: <tool> (<model>)`. Never add an AI as `Co-authored-by:`.
  Never add a "Generated with" footer. The person who commits owns the
  change.
- **No sign-off:** do not add `Signed-off-by:`. A sign-off certifies an
  outside contribution. The organization takes none.
- **Signing:** SSH signing is recommended, not required. A signed commit
  shows Verified on the pull request. Add the same key to GitHub as a
  **signing** key. An authentication key alone shows `unknown_key`.

  ```sh
  git config --global gpg.format ssh
  git config --global user.signingkey <your SSH public key, or its path>
  git config --global commit.gpgsign true
  ```

- **Each commit builds.** Before you ask for review, run the repository
  check on every commit:

  ```sh
  git rebase -x '<the repository check command>' <base>
  ```

  `<base>` is the branch that the pull request targets. For a layer of a
  stack, it is the branch of the layer below.

## 5. Pull requests

- **One pull request is one change.** Aim for about 100 changed lines of
  written code. Split a change that nears 1,000. Lock files and generated
  files do not count.
- **Title:** a Conventional Commit that names the whole change.
- **Body:** use the pull request template: Why, Change, Verification,
  Rollback, After deploy. Use plain lines, without HTML comments or
  checklists.
- **Branch names:** `<type>/<topic>`, for example `fix/listen-address`.
- **Drafts run no CI.** Every workflow of the gate skips a draft pull
  request. This is a rule that each repository writes into its workflows. A
  draft is cheap: push early and often. Mark the pull request ready when it
  is ready for review. Never use `--no-verify` to skip a local hook.
- **Update a branch by rebase** onto its base. Never merge the base into the
  branch. Never use the "Update branch" button.
- **Stacks:** make dependent changes a stack: one pull request per layer,
  each on top of the one below. Use `gh stack`. It is GitHub's stacked
  pull requests feature (generally available since 2026-10-06). The CLI is
  the `github/gh-stack` extension.

  ```sh
  gh extension install github/gh-stack
  gh stack init refactor/roots           # layer 1, on main
  gh stack add refactor/modules          # layer 2, on layer 1
  gh stack submit                        # one pull request per layer
  gh stack sync                          # rebase every layer after a change below
  ```

## 6. Quality

Checks run at five moments. A check at an earlier moment is faster and
narrower.

| When                                                                              | What runs                                                    | Where                                                                                                      | Rule                                                                        |
| --------------------------------------------------------------------------------- | ------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `git commit`                                                                      | formatters (auto-fix) and fast linters, on staged files only | a local hook that the development shell installs                                                           | Seconds. No tests. Never `--no-verify`.                                     |
| `git push`                                                                        | nothing                                                      | none                                                                                                       | Pushes and drafts are cheap.                                                |
| A pull request opens, reopens or becomes ready, or a push to a ready pull request | The full gate, as parallel jobs                              | a repo's gate workflow, on `pull_request`; drafts skipped; concurrency cancels older runs per pull request | This check is the merge decision. Aim for at most 10 minutes per job.       |
| A pull request that touches infrastructure code                                   | The infrastructure plan, with a summary in the job summary   | a repo that applies infrastructure plans on pull requests, with path filters                               | The plan is the review.                                                     |
| A push to `main`                                                                  | The gate, then the apply or the deploy                       | the repo's workflow for `main`, which calls the gate                                                       | A red `main` is fixed first.                                                |
| A schedule                                                                        | A drift plan                                                 | the repo's scheduled workflow                                                                              | A failed run alerts its cron editor (see below).                            |
| Weekly                                                                            | Dependency updates                                           | see section 10                                                                                             | Review them like any pull request. A pull request that deploys lands alone. |

Two GitHub behaviors shape these rules:

- **Drift alerts go to one person.** GitHub notifies only the user who last
  edited the `cron` line of the workflow when a scheduled run fails. Whoever
  edits that line owns the alerts. Keep that person current.
- **A bot pull request does not run CI.** A pull request that a bot opens
  with `GITHUB_TOKEN` triggers no workflows. A person closes and reopens it
  to run the gate.

## 7. Review

- Review within one business day.
- Fix review findings with fixup commits, so the reviewer sees only what
  changed: `git commit --fixup <commit>`.
- Show a reworked series with `git range-diff`.
- Fold the fixups in before landing: `git rebase -i --autosquash <base>`.
  Use the same `<base>` as in section 4.

## 8. Landing

1. **Rebase merge only.** GitHub replays the commits of the pull request onto
   `main` in order, with their messages. `main` stays linear. Nobody pushes
   to `main`. Nobody rewrites it.
2. **Land a stack in batches.** A batch holds at most one change to
   production: a deploy, a cloud resource or a permission. A layer that
   changes nothing in production joins the batch of the next change.
3. **Land a batch in one step:** `gh stack merge <top PR of the batch> --rebase`.
   This lands that layer and every unmerged layer below it, in one push.
   Then run `gh stack sync`.
4. **Watch the deploy.** Wait for it to pass before the next batch.

## 9. Undo

Undo a landed pull request with `git revert` over its range of commits, in a
new pull request. Or fix forward. Fix forward a change that a revert cannot
undo, such as a created cloud account or moved infrastructure state.

A rebase merge lands the commits of a pull request one after the other. The
last one is its `merge_commit_sha`. Find the range and check it first:

```sh
git fetch origin
gh api repos/<owner>/<repo>/pulls/<PR> --jq '"\(.merge_commit_sha) \(.commits)"'
# The two lists must match. If not, the pull request did not land as one run
# of rebased commits (for example, it was squashed): revert the commits it landed.
diff <(git log --reverse --format=%s <last>~<commits>..<last>) \
  <(gh api --paginate repos/<owner>/<repo>/pulls/<PR>/commits \
      --jq '.[].commit.message | split("\n\n")[0] | gsub("\n"; " ")')
git revert --no-commit <last>~<commits>..<last>
git commit -m 'revert(<scope>): <what the pull request did>' -m 'Reverts <the pull request URL>.'
```

## 10. Dependencies

- **Dependabot** updates dependencies weekly. Group updates per ecosystem.
  Use the `build(deps)` commit prefix. Keep the default cooldown.
- **Nix flakes in private repositories:** Dependabot's `nix` ecosystem does
  not support private repositories. Use the
  [`DeterminateSystems/update-flake-lock`](https://github.com/DeterminateSystems/update-flake-lock)
  action.
- **Where neither reaches,** write the manual steps in the repository's
  `AGENTS.md`.
- **No custom update scripts.**
- Constraints allow updates up to the last compatible boundary. Commit the
  lock files.

## 11. Docs and decisions

- **Structure:** follow [Diátaxis](https://diataxis.fr/): tutorials, how-to
  guides, reference and explanation are separate documents.
- **Current state only.** A document describes what exists now. It does not
  describe history or plans. Plans are issues.
- **Decision records:** write a [MADR 4.0.0](https://adr.github.io/madr/)
  record in `docs/decisions/` only for an architecturally significant
  decision. Do not write one for a process rule.
- **Superseded records are deleted.** The new record links the old text by
  permalink to its last commit. This deviates on purpose from the
  append-only guidance, so that the tree shows only decisions in force.
- **Process lives only in this guide.** A repository does not restate it.
- **Delete dead documents** in the pull request that makes them dead.
- **Writing style:** follow the principles of Simplified Technical English.
  Use one term for one concept. Write short sentences in the active voice.
  Avoid idioms and filler.

## 12. Repository settings

Set these once, by hand, in **Settings → General** of each repository:

- **Pull Requests:** allow only **Allow rebase merging**.
- Turn on **Automatically delete head branches**.
- Leave **Allow auto-merge** and **Always suggest updating pull request
  branches** off.

When the organization needs enforcement, it moves to GitHub Team and adds a
ruleset. The ruleset requires a pull request and linear history. Do not
imitate a ruleset with scripts.

## 13. Agent essentials

Every repository's `AGENTS.md` copies this block verbatim. Agents read local
files, so this is a deliberate exception to "one source".

```text
- Titles and commits follow Conventional Commits 1.0.0: type(scope): imperative subject, at most 72 characters.
- The commit body says why.
- Disclose AI help with `Assisted-by: <tool> (<model>)`. Never add an AI as co-author. Never add a "Generated with" footer.
- Never push to `main`. Never merge a pull request unless a person asks you to.
- Open pull requests as drafts. Drafts skip CI. Never use `--no-verify`.
- Each commit builds. One pull request is one change.
- Before you commit or open a pull request, read the guide:
  https://github.com/sealambda/.github/blob/main/CONTRIBUTING.md
```
