# Docs kit

The organization's kit for documentation: a prose style for Vale, a Markdown
lint configuration, a link check, a check that runs all three, and templates
and guides for the pages. This page is the reference for a repository that
consumes it.

The kit is a flake in this directory. A release is a tag `docs-kit-vN`.

## Contents

| Path                                                       | What it is                                                       |
| ---------------------------------------------------------- | ---------------------------------------------------------------- |
| [flake.nix](flake.nix)                                     | The outputs of the kit (see "Outputs").                          |
| [vale/Sealambda](vale/Sealambda)                           | The Vale package: the `.vale.ini`, the style and the vocabulary. |
| [base.markdownlint.yaml](base.markdownlint.yaml)           | The markdownlint configuration for pages.                        |
| [templates.markdownlint.yaml](templates.markdownlint.yaml) | The markdownlint configuration for template files.               |
| [lychee.toml](lychee.toml)                                 | The lychee configuration.                                        |
| [docs-check.sh](docs-check.sh)                             | The program behind `docs-check` and `apps.<system>.check`.       |
| [templates](templates)                                     | A template for a decision record and for each page type.         |
| [guides](guides/README.md)                                 | A short guide for each page type.                                |

## Outputs

| Output                           | What it is                                                                                                                    |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `apps.<system>.check`            | `docs-check`: Vale, markdownlint-cli2 and lychee (offline) on the Markdown files of a directory, which defaults to `.`.       |
| `packages.<system>.docs-check`   | The program of `apps.<system>.check`. It is also `packages.<system>.default`.                                                 |
| `packages.<system>.vale-package` | The Vale package for a release: `result/Sealambda.zip`.                                                                       |
| `lib.mkCheck pkgs src`           | A check that runs `docs-check` on `src`, a store path, in the build sandbox. `src` holds every file that a document links to. |
| `lib.treefmtModules.default`     | A treefmt-nix module that runs markdownlint-cli2 with the base, after Prettier.                                               |
| `lib.markdownlintConfig`         | The path of the markdownlint-cli2 base.                                                                                       |
| `lib.lycheeConfig`               | The path of the lychee configuration.                                                                                         |
| `checks.<system>`                | `vale-rules`, `vale-package`, `vale-package-pins` and `docs` (the documents of the kit).                                      |

The systems are those of the toolchain flake: `aarch64-darwin`,
`aarch64-linux` and `x86_64-linux`. The tools come from the nixpkgs that the
toolchain locks: Vale 3.25.1, markdownlint-cli2 0.23.3, lychee 0.24.2 and the
styles Google 0.7.1 and Microsoft 0.15.1.

## Consume it

### With Nix

A repository takes a tag of this flake as an input. The flake takes its
nixpkgs from the toolchain flake of the same tag, so the repository follows the
toolchain it already uses:

```nix
{
  inputs = {
    toolchain.url = "github:sealambda/.github?dir=toolchain&ref=toolchain-vN";
    nixpkgs.follows = "toolchain/nixpkgs";
    treefmt-nix.follows = "toolchain/treefmt-nix";
    docs-kit = {
      url = "github:sealambda/.github?dir=docs-kit&ref=docs-kit-vN";
      inputs.toolchain.follows = "toolchain";
    };
  };
}
```

Then use the outputs:

```nix
{
  # In outputs: markdownlint-cli2 with the base, after Prettier.
  treefmt-nix.lib.evalModule pkgs {
    imports = [
      toolchain.lib.treefmtModules.default
      docs-kit.lib.treefmtModules.default
    ];
  };

  # In checks: the docs check on the tracked files of the repository.
  checks.docs = docs-kit.lib.mkCheck pkgs self;
}
```

The root `flake.nix` of `sealambda/.github` is a complete example. To run the
check by hand, without an input:

```sh
nix run "github:sealambda/.github?dir=docs-kit&ref=docs-kit-vN#check" -- docs
```

The check reads every `.md` file below the directory, except in `.git` and
`node_modules`. It runs the three tools, prints all findings and exits with
status 1 when any tool finds a problem. The tools do not write files.

### As a Vale package

A repository without Nix, and an editor, take the package from the release
asset `Sealambda.zip` of a `docs-kit-vN` release. The repository's `.vale.ini`
needs two lines:

```ini
StylesPath = .vale/styles
Packages = https://github.com/sealambda/.github/releases/download/docs-kit-vN/Sealambda.zip
```

`vale sync` installs the Sealambda style and its vocabulary. The package's own
`.vale.ini` lists the pinned releases of Google and Microsoft as packages, so
`vale sync` installs them too. It also enables the styles for Markdown files
and sets the level of each rule, so the repository's file only adds what is
particular to it. Vale reads the package file first, and the repository's
file wins where both set one value.

Use the versioned URL, not `releases/latest/download`: the latest release of
this repository may be a release of another part, such as the toolchain. The
source archive of a tag cannot be the package, because its folder is not named
`Sealambda`.

### As a reusable workflow

The workflow `.github/workflows/docs.yml` of this repository runs the docs check, and
then lychee online. A caller pins the workflow by the tag, which also pins the
kit:

```yaml
jobs:
  docs:
    permissions:
      contents: read
    uses: sealambda/.github/.github/workflows/docs.yml@docs-kit-vN
```

The workflow runs on a GitHub-hosted runner for a public repository. A
private repository can pass `runs-on`. The online run keeps its cache in
`.lycheecache`, uses the token of the job for `github.com`, and accepts the
status 429 of a host that limits requests.

## Vale

The Sealambda style follows the
[Google developer documentation style guide](https://developers.google.com/style),
with a few rules of the
[Microsoft Writing Style Guide](https://learn.microsoft.com/en-us/style-guide/welcome/),
and the house rules below. The kit does not copy rules of Google or Microsoft:
it uses them as packages. A house rule that changes one extends it with
`extends: Google.Name` and writes only what differs.

Vale runs with `--minAlertLevel=error` in the check. A rule at level `error`
fails the check. A rule at level `suggestion` shows in an editor and never
fails a check, because it is a judgment call or it flags words that technical
documents need. No rule has level `warning`. The `.vale.ini` of the package
holds the level of each Google rule, with the reason, and lists the rules
that are off.

### House rules

| Rule                       | What it checks                                                                                           | Level      |
| -------------------------- | -------------------------------------------------------------------------------------------------------- | ---------- |
| `Sealambda.Filler`         | Filler words, such as `simply`, `just`, `easy`, `obviously` and `very`.                                  | error      |
| `Sealambda.Terms`          | One term for one concept: `pull request`, `lock file` and `development shell` instead of their synonyms. | error      |
| `Sealambda.CurrentState`   | Words that tie a page to a moment, such as `currently`, `soon` and `TODO`. Extends `Google.Timeless`.    | error      |
| `Sealambda.Headings`       | Sentence case in headings, with the MADR section names as exceptions. Extends `Google.Headings`.         | error      |
| `Sealambda.SentenceLength` | Sentences of more than 25 words. Extends `Microsoft.SentenceLength`.                                     | suggestion |

A true use of a flagged word needs a Vale comment around the passage and the
reason before it:

```markdown
<!-- The word is the name of the setting. -->
<!-- vale Sealambda.CurrentState = NO -->

The `now` option runs the job at once.

<!-- vale Sealambda.CurrentState = YES -->
```

The package also keeps the Google rules that are errors in the style guide and
that a writer fixes without judgment: the Latin abbreviations `e.g.` and
`i.e.`, exclamation marks, spaces around an em dash, ordinal numbers written
as digits with a suffix, and units without a space. The `.vale.ini` lists them all.

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

A repository adds its own words in a vocabulary of its own. Put the words in
`config/vocabularies/<Name>/accept.txt` below the `StylesPath` of the
repository, and add `Vocab = <Name>` to its `.vale.ini`. The check reads that
file, because Vale lays the repository's file over the kit's.

### Spelling

`Vale.Spelling` is off: its dictionary does not know technical words. The
toolchain's `typos` finds misspellings.

### Templates

Vale and lychee skip a template, because it holds placeholders. A template is
a file in a `templates` directory, in a `ISSUE_TEMPLATE` or
`PULL_REQUEST_TEMPLATE` directory, or a file whose name contains `template` or
`TEMPLATE`. markdownlint-cli2 checks a template and does not require a
first-line heading in it.

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
make, tests the links to files and the anchors of headings. The online run of
`docs.yml` also requests the links to other sites. It keeps results for one
day, requests four URLs at once for each host with a pause of 250 ms, retries
twice, and accepts 429 as an answer.

## Templates and guides

- [templates/adr.md](templates/adr.md) is the decision record template of
  [MADR](https://adr.github.io/madr/) 4.0.0, the `adr-template.md` with all
  sections, and MADR's markers for the optional parts. The kit adds no field.
  Two changes come from tools: the closing quotation mark of the `status` line,
  which is missing in MADR 4.0.0, and the spacing and bullets that Prettier
  writes. MADR is available under the MIT license or the CC0-1.0 license.
- [templates](templates) also has a template for a tutorial, a how-to guide, a
  reference page and an explanation.
- [guides](guides/README.md) has a guide for each page type, based on
  [Diátaxis](https://diataxis.fr/).

## Update it

1. Change the files in this directory, and run `nix flake check` at the root
   of the repository. It also runs the checks of this flake.
2. The Vale packages Google and Microsoft are pinned twice: in the `Packages`
   line of [vale/Sealambda/.vale.ini](vale/Sealambda/.vale.ini), and in nixpkgs,
   which the toolchain locks. The check `vale-package-pins` fails when they
   differ. After a `nix flake update` in `toolchain/`, change the line to the
   versions that the failure message shows.
3. This flake takes the toolchain as `path:../toolchain`, so its lock file holds
   the toolchain's inputs. After a change in `toolchain/flake.lock`, run
   `nix flake update toolchain` in this directory, and then
   `nix flake update toolchain docs-kit` at the root. The root check
   `lock-sync` fails until the three lock files agree.

## Release it

A release is a tag `docs-kit-vN` on `main`, and a GitHub release for the tag
that has the asset `Sealambda.zip`. The asset must be built from
`docs-kit/vale/Sealambda`, because Vale installs the package from it.

1. Land the change on `main`. Choose `N`, one more than the last `docs-kit-v`
   tag.
2. Tag the commit: `git tag -a docs-kit-vN -m "docs-kit-vN" <commit>`, and
   push the tag.
3. Build the asset from the tag:
   `nix build "github:sealambda/.github?dir=docs-kit&ref=docs-kit-vN#vale-package"`.
   The file is `result/Sealambda.zip`.
4. Create the release and attach the asset:
   `gh release create docs-kit-vN result/Sealambda.zip --title docs-kit-vN`.
5. In each consumer, change the tag in the flake input, the `Packages` URL in
   `.vale.ini` and the `uses:` line of the workflow, and run
   `nix flake update docs-kit`.
