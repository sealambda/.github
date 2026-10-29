# Undo a landed pull request

Revert a pull request that landed on `main` by a rebase merge, in a new pull
request. Use this when a landed change must be undone and its effect is in
Git.

## Before you start

- You can open a pull request in the repository, and `gh` is signed in.
- The effect of the change is in Git. A revert cannot undo an effect outside
  Git, such as a migration that ran. Fix forward in that case: write a new
  change that corrects the effect.
- Your shell is Bash: step 2 uses process substitution.

## Steps

A rebase merge lands the commits of a pull request one after the other, with
new SHAs. The GitHub API reports the last commit as `merge_commit_sha`. Call
it `<last>`, and call the number of commits of the pull request `<count>`.

1. Fetch the current `main`, and read `<last>` and `<count>`:

   ```bash
   git fetch origin
   gh api repos/<owner>/<repo>/pulls/<PR> --jq '"\(.merge_commit_sha) \(.commits)"'
   ```

2. Check that the pull request landed as one run of rebased commits. The two
   lists of subjects must be equal. Without output, they are equal. If they
   differ, the pull request did not land as one run (for example, it was
   squashed): revert the commits that it landed instead.

   ```bash
   diff <(git log --reverse --format=%s <last>~<count>..<last>) \
     <(gh api --paginate repos/<owner>/<repo>/pulls/<PR>/commits \
         --jq '.[].commit.message | split("\n\n")[0] | gsub("\n"; " ")')
   ```

3. Revert the run on a branch from `main`:

   ```bash
   git switch -c revert/<topic> origin/main
   git revert --no-commit <last>~<count>..<last>
   git commit -m 'revert(<scope>): <what the pull request did>' \
     -m 'Reverts <the pull request URL>.'
   ```

4. Push the branch and open a pull request. The title follows the commit
   rules of the contributing guide, and the body says why the change is
   reverted.

## Check the result

`git diff origin/main` on the branch shows the inverse of the pull request,
and the checks of the repository pass.

## If a step fails

- `git revert` stops with a conflict: a later change touched the same lines.
  Resolve the conflict, run `git add` on the files, and run
  `git revert --continue`. If the later change depends on the reverted one,
  revert it first or fix forward.
- The first line of the commit is longer than 72 characters: shorten the
  `<what the pull request did>` part.

## Related

- [Contributing guide](https://github.com/sealambda/.github/blob/main/CONTRIBUTING.md),
  section "Landing", for the merge method that makes this procedure valid.
- [Configure a repository](configure-a-repository.md), for the settings that
  allow only rebase merges.
