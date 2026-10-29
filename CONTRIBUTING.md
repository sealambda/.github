# Contributing

This guide is the process guide of the Sealambda organization. It tells
people and AI agents how to commit, review, land and undo changes in every
repository.

GitHub shows this file in each repository of the organization that has no
`CONTRIBUTING.md` of its own. A repository does not copy it. A repository
adds only its own commands and facts, and links here. The links in this file
are absolute, because GitHub shows the file in other repositories.

## Environment and checks

- A repository provides one development shell: `nix develop`. The shell holds
  the pinned tools of the toolchain.
  CI runs the same tools from the same lock files, and checks the PATH of the shell.
  A Git hook is optional. The hook setup of `sealambda/.github`
  (`lefthook.yml` and the `shellHook` of its `flake.nix`) is an example to copy.
- A repository lists its check commands in its `AGENTS.md`.
- The tools, their versions and the code conventions (for example, shell
  scripts are `*.sh` files that start with `#!/usr/bin/env bash` and
  `set -euo pipefail`) are in the
  [toolchain README](https://github.com/sealambda/.github/blob/main/toolchain/README.md).
  The documentation checks and page templates are in the
  [docs kit README](https://github.com/sealambda/.github/blob/main/docs-kit/README.md).

Checks run at two moments. An earlier check is faster and narrower.

| When                                       | What runs                                         | Rule                                                           |
| ------------------------------------------ | ------------------------------------------------- | -------------------------------------------------------------- |
| `git commit` (pre-commit hook, if present) | `nix fmt -- --fail-on-change` on the staged files | Seconds. Never use `--no-verify`.                              |
| A ready pull request, and `main`           | `scripts/check.sh` in CI                          | The check `ci` must pass to land. A red `main` is fixed first. |

A formatter that changes a file stops the commit. Review the change, stage
it and commit again.

## Commits

Each commit is one logical change. Use this form:

```text
type(scope)!: summary in the imperative

Why the change exists: the problem, and why this is the fix. Wrap at 72.

Assisted-by: <tool> (<model>)
```

- **Format:** [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).
  The specification requires `feat` and `fix` and allows other types. The
  organization uses `feat`, `fix`, `docs`, `build`, `ci`, `refactor`, `perf`,
  `test`, `chore` and `revert`. The scope names the area. `!` before the
  colon marks a breaking change.
- **First line:** the first line (type, scope, `!` and summary together) is at
  most 72 characters, in the imperative mood. The specification sets no
  limit. Git advises about 50 characters for the summary.
- **Body:** say why. The diff already shows what.
- **AI help:** when an AI tool wrote a non-trivial part, add the trailer
  `Assisted-by: <tool> (<model>)`. An AI is never an author. Never add an AI
  as `Co-authored-by:`. Never add a "Generated with" footer. The person who
  commits owns the change.
- **Each commit builds.** Before you ask for review, run the repository check
  on every commit. `<base>` is the branch that the pull request targets. For
  a layer of a stack, it is the branch of the layer below.

  ```bash
  git rebase -x '<the repository check command>' <base>
  ```

## Pull requests

- **One pull request is one change.** About 100 changed lines of written code
  is usually reasonable, and about 1,000 lines is usually too large. This is
  the guidance of the
  [Google engineering practices](https://google.github.io/eng-practices/review/developer/small-cls.html).
  The reviewer decides, and may ask to split a change at any size. Lock files
  and generated files do not count.
- **Title:** a Conventional Commit that names the whole change. The same
  72-character limit applies.
- **Body:** use the pull request template: Why, Change, Verification,
  Rollback, After deploy. Use plain lines, without HTML comments or
  checklists.
- **Branch names:** `<type>/<topic>`, for example `fix/listen-address`.
- **Drafts skip CI.** The jobs of a CI workflow hold
  `if: ${{ !github.event.pull_request.draft }}`. A reusable workflow cannot
  see the draft state of its caller, so the calling job holds the `if`. A push
  to a draft is cheap. Mark the pull request ready when it is ready for
  review.
- **Update a branch by rebase** onto its base. Never merge the base into the
  branch.
- **Stacks:** make dependent changes a stack: one pull request per layer,
  each based on the branch of the layer below. A stack needs plain Git only:
  `git rebase --update-refs` moves the branch of every layer that the rebase
  replays. Git does not move a branch that another worktree has checked out.

  ```bash
  git switch <top branch>
  git rebase --update-refs <base>   # every layer, after a change in the base
  git push --force-with-lease --force-if-includes origin <layer 1> <layer 2> <top branch>
  ```

## Review

- Fix review findings with fixup commits, so the reviewer sees only what
  changed: `git commit --fixup <commit>`. A fixup on a lower layer reaches the
  layers above after `git rebase --update-refs <lower layer>` on the top
  branch.
- Show a reworked series with `git range-diff`.
- Fold the fixups in before landing. The command opens no editor, and it needs
  `-i`, because Git before 2.44 applies `--autosquash` to interactive rebases
  only. Use the same `<base>` as in "Commits".

  ```bash
  GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash --update-refs <base>
  ```

## Landing

- **Rebase merge only.** GitHub adds the commits of the pull request onto
  `main` one by one, with their messages, and without a merge commit. `main`
  stays linear. Nobody pushes to `main`. Nobody rewrites it. GitHub creates
  new commits, so the SHAs on `main` differ from those of the branch. See
  [about pull request merges](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/about-pull-request-merges).
- **Review and checks are required.** A pull request needs the approval of a
  code owner who did not push last, and the check `ci` on an up-to-date branch.
  A new push dismisses earlier approvals. The ruleset of the repository
  enforces this and has no bypass actor. Where the plan or the visibility of a
  repository offers no rulesets, these rules hold by convention, and the
  reviewer checks them.
- **Settings:** the GitHub settings that enforce these rules are in
  [Configure a repository](https://github.com/sealambda/.github/blob/main/docs/how-to/configure-a-repository.md).
- **Provenance:** it comes from the pull request record and its required
  review. The organization does not require signed commits, and a rebase merge
  replaces the commits of the author with new ones.
- **Land a stack from the bottom.** Merge the lowest layer. Then move the layers
  above onto `main` and set the base of the next pull request to `main`:

  ```bash
  git fetch origin
  git switch <top branch>
  git rebase --update-refs --onto origin/main <landed branch>
  ```

## Undo

Undo a landed pull request with `git revert` over its range of commits, in a
new pull request. Or fix forward. Fix forward a change that a revert cannot
undo, such as an effect outside Git. The steps are in
[Undo a landed pull request](https://github.com/sealambda/.github/blob/main/docs/how-to/undo-a-landed-pull-request.md).

## License

A contribution to a repository is licensed under the license that the
repository states in its `LICENSE` file. See section D.6 of the
[GitHub terms of service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service).
`sealambda/.github` uses the Mozilla Public License 2.0 (MPL-2.0). In that
license, section 2.1 is the grant of a contributor.

## Docs and decisions

- **Structure:** follow [Diátaxis](https://diataxis.fr/): tutorials, how-to
  guides, reference and explanation are separate documents.
- **Current state only.** A document describes what exists now. It does not
  describe history or plans. Plans are issues.
- **Decision records:** write a [MADR 4.0.0](https://adr.github.io/madr/)
  record in `docs/decisions/` for each architectural decision, and for each
  deviation from a standard that this guide or another document cites. A
  process rule lives in this guide.
- **Only records in force stay in the tree.** A record has the status
  `proposed` or `accepted`. A record that is rejected, deprecated or
  superseded is deleted in the commit that adds its replacement or records the
  rejection. Its row in the ledger `docs/decisions/README.md` keeps the number,
  the reason and a permalink to the last text. This deviates on purpose from
  the append-only guidance. The reason is in
  [decision 0001](https://github.com/sealambda/.github/blob/main/docs/decisions/0001-keep-only-decisions-in-force-in-the-tree.md).
- **Process lives only in this guide.** A repository does not restate it.
- **Delete dead documents** in the pull request that makes them dead.
- **Writing style:** follow the principles of Simplified Technical English.
  Use one term for one concept. Write short sentences in the active voice.
  Avoid idioms and filler.

## Agent essentials

This section is the one source of the rules that agents must know. The
`AGENTS.md` of a repository links here and adds the commands of the
repository. It does not copy this list.

- Titles and commits follow Conventional Commits 1.0.0:
  `type(scope): imperative summary`. The first line is at most 72 characters.
- The commit body says why.
- Disclose AI help with `Assisted-by: <tool> (<model>)`. Never add an AI as
  author or co-author. Never add a "Generated with" footer.
- Never push to `main`. Never merge a pull request unless a person asks you
  to.
- Open pull requests as drafts. Drafts skip CI. Never use `--no-verify`.
- Each commit builds. One pull request is one change.
