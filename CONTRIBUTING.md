# Contributing

How every Sealambda repository commits, reviews and merges. GitHub shows this
file in every repository of the organization that has no `CONTRIBUTING.md` of
its own. A repository's own file adds what is specific to it and links here.
Organization members find the reasons and sources for each rule in
`sealambda/infra`, `docs/adr/0010-collaboration.md`.

## The model

Merge commits over curated history, as Git, Kubernetes, Rust and nixpkgs
work:

- **A commit is one logical change** that builds and passes the checks on its
  own, so `git bisect` can stop on any commit.
- **A pull request is one concern**, small enough to review in one sitting:
  about 100 changed lines of written code; split anything near 1000. Lock
  files and generated files do not count.
- **A pull request merges with a merge commit.** Its commits land on `main`
  exactly as reviewed and signed. The merge commit's subject is the pull
  request title and its message is the pull request body.
- **`main` is never rewritten.** Read it one pull request at a time with
  `git log --first-parent`.

## Commits

```text
type(scope)!: summary in the imperative, about 50 characters, at most 72

Why the change exists: the problem, and why this is the fix. Wrap at 72.

Assisted-by: Claude Code (claude-opus-5-5)
```

- **Types:** `feat`, `fix`, `docs`, `build`, `ci`, `refactor`, `perf`,
  `test`, `chore`, `revert` ([Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/)).
  The scope is the area the change touches. `!` marks a change that breaks a
  consumer.
- **Trailers:** `Fixes: <sha> ("<subject>")` for a bug fix, `Refs:` for
  related work. When an AI tool wrote a non-trivial part, add
  `Assisted-by: <tool> (<model>)`. Never add `Co-authored-by:` or
  `Signed-off-by:` for an AI: the person who commits owns the change.
- **Sign every commit:**

  ```sh
  git config --global gpg.format ssh
  git config --global user.signingkey <your SSH public key, or its path>
  git config --global commit.gpgsign true
  ```

  Add the same key to GitHub as a **signing** key, so commits show
  Verified.
- **Check that every commit builds on its own** before you ask for review:

  ```sh
  git rebase -x '<the repository check command>' origin/main
  ```

## Branches and stacks

- **Branch names** are `<type>/<topic>`, such as `fix/loki-listen-address`.
- **Dependent changes are a stack:** one pull request per layer, each on top of
  the one below. Use the `gh stack` CLI:

  ```sh
  gh stack init refactor/roots           # layer 1, on main
  gh stack add refactor/modules          # layer 2, on layer 1
  gh stack submit                        # one pull request per layer
  gh stack sync                          # rebase every layer after a change below
  ```

- **Update a branch by rebasing it onto its base,** never by merging the base
  into it, and never with the "Update branch" button.

## Review

- **Fix review findings with fixup commits,** so the reviewer sees only what
  changed: `git commit --fixup <commit>`.
- **Show a reworked series** with `git range-diff`.
- **Fold the fixups in before merging:** `git rebase -i --autosquash`.

## Title and body

The title and the body become the merge commit, so write them as a commit
message. The title is a Conventional Commit. The body uses the template:

- **Why:** the problem and why this change solves it.
- **Change:** what changes, in the order a reviewer should read it.
- **Verification:** how it was checked, and what the reviewer should expect,
  such as a plan or test output.
- **Rollback:** how to undo it, or why it must be fixed forward instead.

Write them as plain lines: no HTML comments and no checklists, because they
would land in `git log`.

## Merge

1. **Use "Create a merge commit"**, the only method a repository allows.
2. **Merge a stack in batches.** A batch holds at most one change to
   production: a deploy, a cloud resource or a permission. Layers that change
   nothing in production join the batch of the next change.
3. **Merge a batch layer by layer, bottom first,** so each pull request gets
   its own merge commit and its own Revert button. Merge the layers in quick
   succession. A deploy workflow with a `concurrency` group and
   `cancel-in-progress: false` runs one deploy and keeps only the newest
   waiting, so a batch costs at most two deploys.
4. **Wait for the repository's deploy to pass** before the next batch.

## Undo

- **Press Revert on the merged pull request.** GitHub opens a pull request
  that reverts its merge commit (`git revert -m 1`). Review and merge it like
  any other.
- **Fix forward** a change that a revert cannot undo, such as a created cloud
  account or moved infrastructure state.

## Checks

The action `sealambda/.github/actions/check-pull-request` checks every pull
request: the title, and every commit's subject, parent count, signature and
trailers. On a private repository on GitHub Free no check can block a merge,
so a red check is the author's to fix before merging.
