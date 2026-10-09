# sealambda/.github

The organization's shared GitHub files.

- `CONTRIBUTING.md` and `pull_request_template.md` are GitHub's defaults for
  every repository of the organization that has none of its own: how every
  repository commits, reviews and merges.
- `actions/check-pull-request` checks a pull request: a Conventional Commits
  title, and every commit curated, single-parent, signed and free of AI
  co-author trailers. A repository calls it from a workflow, pinned by SHA:

  ```yaml
  on:
    pull_request:
      types: [opened, edited, synchronize, reopened]
  permissions:
    contents: read
    pull-requests: read
  jobs:
    pull-request:
      runs-on: ubuntu-latest
      steps:
        - uses: sealambda/.github/actions/check-pull-request@<sha> # main
  ```

This repository is public, as GitHub requires for these defaults: it holds no
internal facts. Run its checks with `nix develop -c actions/check-pull-request/test.sh`.
