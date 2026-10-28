# Docs kit

The organization's kit for documentation: a prose style for Vale, a Markdown
lint configuration, a link check, a check that runs all three, a check for
decision records, and templates and guides for the pages. This page is the
reference for the kit.

- To use the kit in a repository, follow
  [Use the docs kit](../docs/how-to/use-the-docs-kit.md).
- To release a new version, follow
  [Release a component](../docs/how-to/release-a-component.md).
- To learn why the kit has this shape, read
  [The docs kit](../docs/explanation/docs-kit.md).

The kit is a flake in this directory.

## Versions

A release of the kit is a tag `docs-kit-vN`. `N` is a whole number that starts
at 1. A published tag is immutable: a change is a new number, and a tag is
never moved. Every example in these pages writes `N` for the number of the
release that you use.

## Contents

| Path                                                       | What it is                                                       |
| ---------------------------------------------------------- | ---------------------------------------------------------------- |
| [flake.nix](flake.nix)                                     | The outputs of the kit (see "Outputs").                          |
| [vale/Sealambda](vale/Sealambda)                           | The Vale package: the `.vale.ini`, the style and the vocabulary. |
| [base.markdownlint.yaml](base.markdownlint.yaml)           | The markdownlint configuration for pages.                        |
| [templates.markdownlint.yaml](templates.markdownlint.yaml) | The markdownlint configuration for template files.               |
| [lychee.toml](lychee.toml)                                 | The lychee configuration.                                        |
| [docs-check.sh](docs-check.sh)                             | The program behind `docs-check` and `apps.<system>.check`.       |
| [decisions-ledger.sh](decisions-ledger.sh)                 | The program behind `decisions-ledger`.                           |
| [templates](templates)                                     | A template for a decision record and for each page type.         |
| [guides](guides/README.md)                                 | A short guide for each page type.                                |

## Outputs

| Output                               | What it is                                                                                                                                                                                                                                                                                                                    |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `apps.<system>.check`                | `docs-check [--online] [--template GLOB]… [DIRECTORY]`: Vale, markdownlint-cli2 and lychee (offline) on the Markdown files of a directory, which defaults to `.`. `--online` runs lychee only, and also requests the links to other sites. `--template` marks more files as templates (see "Documents that the check reads"). |
| `packages.<system>.docs-check`       | The program of `apps.<system>.check`. It is also `packages.<system>.default`.                                                                                                                                                                                                                                                 |
| `packages.<system>.decisions-ledger` | The program that checks the decision records of a directory and their ledger.                                                                                                                                                                                                                                                 |
| `packages.<system>.vale-package`     | The Vale package for a release: `result/Sealambda.zip`.                                                                                                                                                                                                                                                                       |
| `lib.mkCheck pkgs src`               | A check that runs `docs-check` on `src`, a store path, in the build sandbox. `src` holds every file that a document links to.                                                                                                                                                                                                 |
| `lib.mkDecisionsCheck pkgs src`      | A check that runs `decisions-ledger` on `src`, the directory of the decision records.                                                                                                                                                                                                                                         |
| `lib.treefmtModules.default`         | A treefmt-nix module that runs markdownlint-cli2 with the base, after Prettier.                                                                                                                                                                                                                                               |
| `lib.markdownlintConfig`             | The path of the markdownlint-cli2 base.                                                                                                                                                                                                                                                                                       |
| `lib.lycheeConfig`                   | The path of the lychee configuration.                                                                                                                                                                                                                                                                                         |
| `checks.<system>`                    | `vale-rules`, `vale-vocabulary`, `vale-intensifiers-level`, `vale-package`, `decisions-ledger` and `docs-check-fixtures` (trees of documents that `docs-check` must reject or accept).                                                                                                                                        |

The systems are those of the toolchain flake: `aarch64-darwin`,
`aarch64-linux` and `x86_64-linux`. The tools come from the nixpkgs that the
toolchain locks, so the lock file of the toolchain holds their versions.

## Vale package

The release asset `Sealambda.zip` of a `docs-kit-vN` release is a Vale package
with one folder, `Sealambda`. It needs Vale 3.25.0 or later, the first version
that installs a vocabulary from a package
([Vale packages](https://docs.vale.sh/packages)). The package holds:

- a `.vale.ini` with the `Packages` line that installs Google and Microsoft,
  the enabled styles and the level of each rule;
- the style `Sealambda` and the vocabulary `Sealambda`.

The `Packages` line names the versions of Google and Microsoft that the locked
nixpkgs holds. The kit writes the line when it builds the asset, so the asset
and the Nix check use the same rules. The asset has no `*.test.yml` file.

## Vale

The Sealambda style follows the
[Google developer documentation style guide](https://developers.google.com/style),
with a few rules of the
[Microsoft Writing Style Guide](https://learn.microsoft.com/en-us/style-guide/welcome/),
and the house rules below. It departs from the Google guide where `.vale.ini`
says so. The main departure is that it avoids contractions, because it writes
Simplified Technical English. The kit does not copy rules of Google or
Microsoft: it uses them as packages. A house rule that changes one extends it
with `extends: Google.Name` and writes only what differs.

Vale runs with `--minAlertLevel=error` in the check. A rule at level `error`
fails the check. A rule at level `suggestion` shows in an editor and never
fails a check, because it is a judgment call or it flags words that technical
documents need. No rule has level `warning`. The `.vale.ini` of the package
holds the level of each Google rule, with the reason, and lists the rules
that are off.

### House rules

| Rule                       | What it checks                                                                                           | Level      |
| -------------------------- | -------------------------------------------------------------------------------------------------------- | ---------- |
| `Sealambda.Filler`         | Filler words that have no use: `simply`, `just`, `obviously`, `basically` and `of course`.               | error      |
| `Sealambda.Intensifiers`   | Weak intensifiers: `actually`, `easy`, `easily`, `really` and `very`.                                    | suggestion |
| `Sealambda.Terms`          | One term for one concept: `pull request`, `lock file` and `development shell` instead of their synonyms. | error      |
| `Sealambda.CurrentState`   | Words that tie a page to a moment, such as `currently`, `soon` and `TODO`. Extends `Google.Timeless`.    | error      |
| `Sealambda.Headings`       | Sentence case in headings, with the MADR section names as exceptions. Extends `Google.Headings`.         | error      |
| `Sealambda.SentenceLength` | Sentences of more than 25 words. Extends `Microsoft.SentenceLength`.                                     | suggestion |

To write a flagged word on purpose, see
[Use the docs kit](../docs/how-to/use-the-docs-kit.md#write-a-flagged-word-on-purpose).

The package also keeps the Google rules that are errors in the style guide and
that a writer fixes without judgment: the Latin abbreviations `e.g.` and
`i.e.`, exclamation marks, spaces around an em dash, ordinal numbers written
as digits with a suffix, and units without a space. The `.vale.ini` lists them
all.

The rule tests are the `*.test.yml` files next to the rules. Run them from this
directory with `vale test --coverage vale/Sealambda/styles/Sealambda`, or with
`nix flake check`, which also checks that every rule has an absolute `link`.

### Vocabulary

The vocabulary `Sealambda` (`vale/Sealambda/styles/config/vocabularies/Sealambda`)
holds the names and acronyms of the organization's documents.

- `accept.txt` lists a word with its spelling. Vale reports another case of
  the word (`Vale.Terms`). The list holds only names and acronyms that are
  always written in one way. It does not hold a word that is also a command
  or a plain word in lower case, such as `git`, `nix`, `ssh`, `cd`, `gpg`,
  `id`, `ip`, `os`, `prettier`, `elixir`, `markdown` and `vale`. Write a
  command, a file name and the name of a repository in code font.
- `reject.txt` lists a spelling that is wrong, such as `Diataxis`. The name has
  an accent.

To add words for one repository, see
[Use the docs kit](../docs/how-to/use-the-docs-kit.md#add-words-to-the-vocabulary).

### Spelling

`Vale.Spelling` is off: its dictionary does not know technical words. The
toolchain's `typos` finds misspellings.

## Documents that the check reads

`docs-check` reads the Markdown files that Git tracks in the directory
(`git ls-files`). Hidden directories such as `.github` are included. Outside a
Git repository it reads every `.md` file below the directory, except in `.git`
and `node_modules`. To skip a tracked file, list it under `ignores` in the
`.markdownlint-cli2.yaml` of the repository; this works for markdownlint-cli2
only, so Vale and lychee still read the file.

A template is form text with placeholders. Vale and lychee skip it.
markdownlint-cli2 checks it in a second run, with
[templates.markdownlint.yaml](templates.markdownlint.yaml): the base
configuration with the rule MD041 (a first-line heading) off, because a
template often starts with a lower heading level. A file is a template when its
path matches a location that GitHub documents, or a `--template` pattern:

- **Pull request template.** A file `pull_request_template.md` or a folder
  `PULL_REQUEST_TEMPLATE/` in the root, in `docs/` or in `.github/`. The
  letters can have any case.
- **Issue template.** A file in `.github/ISSUE_TEMPLATE/`, with any case of the
  letters. GitHub documents no other location, so a file in `docs/ISSUE_TEMPLATE/`
  is a page.
- **`--template GLOB`.** The option can be repeated. The glob is a
  case-sensitive Bash pattern for the path relative to the directory, and `*`
  also matches `/`.
- **`DOCS_CHECK_TEMPLATES`.** An environment variable with the same patterns,
  one on each line; an empty line is ignored. The patterns add to those of the
  option. The reusable workflow passes its input `templates` this way.

A name that only contains the word `template` is a page. The patterns of the
GitHub locations are in [kit.nix](kit.nix) (`githubTemplatePatterns`), and
`docs-check` and the treefmt module read them from there. The `ignores` key of
the `.markdownlint-cli2.yaml` of the repository skips a template, as it skips a
page. The treefmt module does not know the `--template` patterns of a
repository: the repository adds them to
`settings.formatter.markdownlint-templates.includes` and to
`settings.formatter.markdownlint.excludes`.

## Markdown lint

[base.markdownlint.yaml](base.markdownlint.yaml) extends
`markdownlint/style/prettier`, the style that the markdownlint project
publishes to avoid conflicts with Prettier. It adds the setting `siblings_only`
for the rule MD024 and turns MD060 off because Prettier aligns tables.
[templates.markdownlint.yaml](templates.markdownlint.yaml) extends it and turns
MD041 off, for the template files.

`markdownlint-cli2 --config <base>` uses the file as the base for the
directory, and it reads a `.markdownlint-cli2.yaml` of the repository after it
and merges the two. A repository without an exception has no file of its own.

## Link check

[lychee.toml](lychee.toml) holds the settings for both runs. Each key has the
reason in a comment. The offline run, which `docs-check` and `lib.mkCheck`
make, tests the links to files and the anchors of headings. The online run is
`docs-check --online`: it runs lychee only, and also requests the links to
other sites. A broken link is a finding (exit status 1 of `docs-check`). A
failure of lychee itself, such as a missing configuration file, ends
`docs-check` with status 2. The same holds for Vale and markdownlint-cli2: a
finding is status 1, and a tool that cannot run is status 2. lychee reads a
GitHub token from `GITHUB_TOKEN`, which raises the rate limit for links to
GitHub, and keeps its cache in `.lycheecache`. The run keeps results for one
day, requests four URLs at once for each host with a pause of 250 ms, retries
twice, and accepts 429 as an answer.

## Reusable workflow

`.github/workflows/docs.yml` runs the docs check of a calling repository, and
then the link check online when asked. A caller refers to it as
`sealambda/.github/.github/workflows/docs.yml@docs-kit-vN`. The tag also fixes
the version of the kit that the workflow runs. See
[Use the docs kit](../docs/how-to/use-the-docs-kit.md#check-the-documents-in-github-actions)
for a call.

| Input             | Default          | What it does                                                                   |
| ----------------- | ---------------- | ------------------------------------------------------------------------------ |
| `sha`             | the caller's SHA | The 40-character SHA of the commit to check.                                   |
| `runs-on`         | `"ubuntu-24.04"` | The runner, as JSON. A public repository always runs on GitHub-hosted runners. |
| `timeout-minutes` | `15`             | The time limit of the job.                                                     |
| `external-links`  | `false`          | Also request the links to other sites, with a cache of the results.            |
| `templates`       | empty            | Globs of extra template files, as `--template` of `docs-check`.                |

The workflow has the output `external-links-status`. It is the exit status of
the online link check: `0` (all links work), `1` (a link is broken) or `2` (the
check could not run). It is empty when the build of the kit or the offline
check failed first, or when `external-links` is `false`. A caller opens an issue
only for `1`, so a failure of the build opens none.

The caller grants `contents: read`. A caller whose organization allows only
selected actions must allow these:

- `actions/checkout`;
- `nixbuild/nix-quick-install-action`;
- `actions/cache`, which also covers `actions/cache/save`.

The workflow does not skip a draft pull request. A caller that wants this adds
`if: ${{ !github.event.pull_request.draft }}` to its job, as the CI workflow of
this repository does.

The workflow runs the Markdown configuration files of the checked tree, for
example `.markdownlint-cli2.cjs`. A caller must never call it from the
`pull_request_target` event, because that event would run code of a fork with
the permissions of the base repository.

## Decision records

`decisions-ledger [DIRECTORY]` checks the decision records of a directory
(default `docs/decisions`) and the ledger in its `README.md`. It prints every
finding and exits with status 0, 1 (a rule fails) or 2 (it cannot run).

| Rule               | What it checks                                                                    |
| ------------------ | --------------------------------------------------------------------------------- |
| Status in the tree | A record in the directory has the status `proposed` or `accepted`.                |
| Unique numbers     | A number is used once, in the tree or in the ledger.                              |
| Final status       | A ledger row has the final status `rejected`, `deprecated` or `superseded`.       |
| Replacement        | "Replaced by" is `none` or the number of a record. A superseded record names one. |
| Permalink          | The permalink has a commit SHA of 40 hexadecimal characters.                      |

A ledger row has these cells, in this order: number, title, final status,
replaced by, reason, permalink. The permalink is a Markdown link to the last
text of the record at a commit that is on `main`:
`https://github.com/OWNER/REPO/blob/<SHA>/PATH`. The check does not request the
permalink. The scheduled link check does.

## Templates and guides

- [templates/adr.md](templates/adr.md) is the decision record template of
  [MADR](https://adr.github.io/madr/) 4.0.0, the `adr-template.md` with all
  sections, and MADR's markers for the optional parts. The kit adds no field.
  Three changes come from the organization or from tools: the `status` value
  lists only `proposed` and `accepted`, because the tree keeps no other
  record; the closing quotation mark of the `status` line, which is missing in
  MADR 4.0.0; and the spacing and bullets that Prettier writes. The status
  value `superseded by ADR-0123` of MADR is not used here: see
  [The docs kit](../docs/explanation/docs-kit.md#decision-records). MADR is
  available under the MIT license or the CC0-1.0 license.
- [templates](templates) also has a template for a tutorial, a how-to guide, a
  reference page and an explanation.
- [guides](guides/README.md) has a guide for each page type, based on
  [Diátaxis](https://diataxis.fr/).
