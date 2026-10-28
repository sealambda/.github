# Configure a repository

Set the GitHub settings that enforce the landing rules of the contributing
guide in a repository: rebase merges only, a reviewed and checked `main`,
safe Actions defaults, and private vulnerability reporting. Use this for a
new repository, and to check an existing one.

## Before you start

- You are an administrator of the repository, and `gh` is signed in with the
  `repo` scope.
- The repository runs a CI workflow with a job named `ci` that needs every
  other job of the workflow. The ruleset requires the check `ci` only, so one
  job decides for all. The job runs with `if: always()` and fails when a
  needed job failed or was cancelled. A skipped job, such as the job of a
  draft pull request, does not fail it.
- A second administrator can review. The ruleset below makes the person who
  pushed last unable to approve.
- Rulesets depend on the plan of the organization and on the visibility of the
  repository, as the GitHub page
  [about rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)
  explains. Where a ruleset is not available, steps 1 and 3 to 5 still apply,
  and the review rules hold by convention only.

## Steps

1. Allow the rebase merge only, and delete the branch after the merge:

   ```bash
   gh api --method PATCH repos/<owner>/<repo> \
     -F allow_merge_commit=false -F allow_squash_merge=false \
     -F allow_rebase_merge=true -F delete_branch_on_merge=true
   ```

2. Save this ruleset as `ruleset.json`, and create it. It protects the
   default branch: no deletion, no force push, a linear history, one approval
   from a code owner after the last push, stale approvals dismissed, rebase
   merges only, and the check `ci` on an up-to-date branch. It has no bypass
   actor.

   ```json
   {
     "name": "main",
     "target": "branch",
     "enforcement": "active",
     "bypass_actors": [],
     "conditions": {
       "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] }
     },
     "rules": [
       { "type": "deletion" },
       { "type": "non_fast_forward" },
       { "type": "required_linear_history" },
       {
         "type": "pull_request",
         "parameters": {
           "required_approving_review_count": 1,
           "dismiss_stale_reviews_on_push": true,
           "require_code_owner_review": true,
           "require_last_push_approval": true,
           "required_review_thread_resolution": false,
           "allowed_merge_methods": ["rebase"]
         }
       },
       {
         "type": "required_status_checks",
         "parameters": {
           "strict_required_status_checks_policy": true,
           "required_status_checks": [{ "context": "ci" }]
         }
       }
     ]
   }
   ```

   ```bash
   gh api --method POST repos/<owner>/<repo>/rulesets --input ruleset.json
   ```

   To change an existing ruleset, read it with
   `gh api repos/<owner>/<repo>/rulesets`, and send the changed body with
   `gh api --method PUT repos/<owner>/<repo>/rulesets/<id> --input ruleset.json`.

3. Add a `.github/CODEOWNERS` file. The ruleset takes its reviewers from it.
   GitHub does not inherit this file from the `.github` repository.

4. Make the token of a workflow read-only, and forbid Actions to approve pull
   requests. Require approval of the workflows of every outside contributor:

   ```bash
   gh api --method PUT repos/<owner>/<repo>/actions/permissions/workflow \
     -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false
   gh api --method PUT repos/<owner>/<repo>/actions/permissions/fork-pr-contributor-approval \
     -f approval_policy=all_external_contributors
   ```

   The organization has the same two settings under **Settings**, **Actions**,
   **General**. A setting of the organization limits the repository: the first
   command answers 409 when the organization forbids the change.

5. For a public repository, turn on private vulnerability reporting:

   ```bash
   gh api --method PUT repos/<owner>/<repo>/private-vulnerability-reporting
   ```

## Check the result

Read each setting back:

```bash
gh api repos/<owner>/<repo> --jq '[.allow_merge_commit, .allow_squash_merge, .allow_rebase_merge, .delete_branch_on_merge]'
gh api repos/<owner>/<repo>/rules/branches/<default branch> --jq '[.[].type]'
gh api repos/<owner>/<repo>/actions/permissions/workflow
gh api repos/<owner>/<repo>/private-vulnerability-reporting --jq .enabled
```

The first command prints `[false,false,true,true]`. The second lists
`deletion`, `non_fast_forward`, `required_linear_history`, `pull_request` and
`required_status_checks`. The third shows `"default_workflow_permissions":"read"`
and `"can_approve_pull_request_reviews":false`. The last prints `true` for a
public repository.

## If a step fails

- Step 2 answers an error: check whether the plan and the visibility of the
  repository offer rulesets. See "Before you start".
- A pull request waits for the check `ci` and never starts it: the workflow
  does not run for the event, or no job is named `ci`. Compare the name in
  `gh pr checks <PR>` with the `context` of the ruleset.
- No one can approve a pull request: the person who pushed last cannot
  approve it. Another code owner reviews.

## Related

- [Contributing guide](https://github.com/sealambda/.github/blob/main/CONTRIBUTING.md),
  the rules that these settings enforce.
- [Default files](../explanation/default-files.md), for the files that GitHub
  takes from the `.github` repository.
- [Undo a landed pull request](undo-a-landed-pull-request.md), which needs the
  rebase merge setting.
