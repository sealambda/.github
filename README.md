# sealambda/.github

The organization's shared GitHub files.

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

This repository is public: it holds no internal facts. Run its checks with `nix develop -c actions/check-pull-request/test.sh`.
