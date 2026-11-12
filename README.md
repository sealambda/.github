# Sealambda hub

This repository holds Sealambda's engineering standards. It is not a community
project. It is public because GitHub reads default community files only from a
public `.github` repository, and private repositories consume it without
credentials ([ADR 0002](docs/decisions/0002-public-hub-repository.md)). It holds
no secrets and no operational detail.

Sealambda repositories consume it. Each repository follows the adoption guide in
order and keeps its own facts. The guide needs Git, and Nix with the
`nix-command` and `flakes` features enabled.

## What it provides

- **Community files.** `CONTRIBUTING.md`, `SECURITY.md`,
  [`SUPPORT.md`](SUPPORT.md), the issue forms and the pull request template.
  GitHub shows them in every repository of the organization, public or private,
  that has no file of its own
  ([GitHub documentation](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file)).
  A repository inherits them without any step. A file of the same name in the
  repository overrides one. The issue forms follow a rule per folder, not per
  file. A repository that has valid issue templates or a `config.yml` in its own
  `.github/ISSUE_TEMPLATE` folder uses none of the hub's forms.
- **Toolchain.** A Nix flake with pinned development shells and the
  organization's treefmt configuration, `lib.mkTreefmt`.
- **Dependency updates.** `default.json`, a shared
  [Renovate](https://docs.renovatebot.com/) preset for update timing, grouping
  and security fixes. A repository's `renovate.json` extends it and adds only
  its own managers, constraints and rules.
- **Tool configuration.** Settings for the tools that read only a file in the
  repository: EditorConfig, markdownlint-cli2, Vale, lychee, commitlint and the
  lefthook commit-msg hook. The `sync-config` app copies the files, and the
  `config-in-sync` check fails when a copy differs.
- **CI building blocks.** The reusable workflows
  [`secrets.yml`](.github/workflows/secrets.yml) (gitleaks from the hub's flake)
  and [`change-text.yml`](.github/workflows/change-text.yml) (commit messages
  and pull request text; it needs the `docs` dev shell of the caller).
  [Call the reusable workflow](docs/how-to/adopt-the-hub.md#call-the-reusable-workflow)
  shows how to call them. The flake check `lib.mkDocsCheck` runs
  markdownlint-cli2, lychee and Vale with the Google style and the hub's own
  style. The hub's style keeps pages in the present tense.

## Documentation

The pages follow [Diátaxis](https://diataxis.fr/).

- **How-to guides.**
  [Adopt the hub in a repository](docs/how-to/adopt-the-hub.md),
  [Change a toolchain version](docs/how-to/change-a-toolchain-version.md).
- **Reference.** [Toolchain versions](docs/reference/versions.md),
  [Elixir quality checks](docs/reference/elixir-qa.md), the
  [Renovate preset](docs/reference/renovate-preset.md),
  [decision records](docs/reference/decision-records.md) and
  [writing style](docs/reference/writing-style.md).
- **Explanation.** The [decision records](docs/decisions/) say why the hub works
  as it does. They are Markdown files that people review.
- **Templates.** [Templates](templates/README.md) for decision records and
  pages. A decision record starts from the MADR 4.0.0 template.

## Work on the hub

- Enter the shell with `nix develop`. Install the hooks once per clone with
  `lefthook install` inside it. The pre-commit hook fails on an unformatted file
  and formats it, so stage the file and commit again. It also fails on a
  misspelling and rewrites nothing.
- Run every check with `nix flake check`. Format with `nix fmt`.
- The tool files in the root, such as `.vale.ini`, `lychee.toml`,
  `.editorconfig` and `lefthook-commit-msg.yml`, are copies of the files in
  `config/`. Edit `config/`, then run `nix run .#sync-config`. The
  `config-in-sync` check fails when a copy differs.

## Contribute

Read [CONTRIBUTING.md](CONTRIBUTING.md). To report a vulnerability, read
[SECURITY.md](SECURITY.md).

## License

[Mozilla Public License 2.0](LICENSE).
