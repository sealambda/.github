# Writing style

A page states what is true now. This page defines the Vale rules that check
that, and the places where they do not apply. The rule that a document describes
only the current state is in
[CONTRIBUTING.md](../../CONTRIBUTING.md#current-state-only). Google's style
guide gives the same advice. Write in the present tense.

The rules are the Vale style `Sealambda`. Its source is the folder
`vale/Sealambda` in the hub. The `docs` check runs it with the style Google, as
[Adopt the hub](../how-to/adopt-the-hub.md#gate-the-documentation) shows. Every
rule at level error fails the check: the style `Vale` (spelling and repetition),
the error rules of the [Google style](https://developers.google.com/style) and
the `Sealambda` rules below.

## Rules

| Rule                              | Level      | What it flags                                                                                                        |
| --------------------------------- | ---------- | -------------------------------------------------------------------------------------------------------------------- |
| `Sealambda.CurrentState`          | error      | A word of a plan or a gap.                                                                                           |
| `Sealambda.History`               | suggestion | A word of a history.                                                                                                 |
| `Sealambda.Contractions`          | error      | A contraction, such as `isn't`.                                                                                      |
| `Sealambda.SentenceLength`        | error      | A sentence of more than 25 words.                                                                                    |
| `Sealambda.CommentSentenceLength` | error      | A sentence of more than 25 words in a [code comment](#code-comments) of a shell, YAML, TOML, Dockerfile or SQL file. |
| `Sealambda.Filler`                | error      | A filler word, such as `simply`.                                                                                     |
| `Google.Will`                     | error      | The future tense, such as `will do`.                                                                                 |

The `docs` check runs Vale with `--minAlertLevel=error`. A finding of level
error fails the check. A finding of level suggestion shows in an editor that
runs Vale, and in a run of Vale without that flag.

A repository accepts a valid term, such as a product name, in the vocabulary
`.vale/styles/config/vocabularies/Repository/accept.txt`, one entry per line.
Each entry is a regular expression that Vale applies to every rule, so an entry
such as `.*` silences the whole check. Write plain terms only, and review every
change to the file. `Vale.Terms` flags a word whose case differs from an entry:
the word `zorblax` gives an error when the file has the entry `Zorblax`. To
accept both cases of a name that can start a sentence, write `[Zz]orblax`.

The rules match whole words in any letter case. In Markdown, and in the comments
of the languages that Vale reads as Markdown, they skip code spans and code
blocks. A flag or a command in code font never matches there. The comments of
other languages differ, as [Code comments](#code-comments) shows.

## Current state

`Sealambda.CurrentState` flags these words:

- `currently`
- `for now`
- `in the future`
- `will be`
- `phase 2`
- `TODO`
- `FIXME`

These words mark a plan or a gap. A page that has them describes a system that
does not exist yet. Write what is true today, and open an issue for the rest.

The words `target` and `planned` are not on the list. Each has a true present
meaning, such as a build target or a planned maintenance window, that a word
list cannot tell from a plan.

### Where the rule is off

`config/vale.ini` turns `Sealambda.CurrentState` and `Google.Will` off in two
folders:

- `docs/decisions/`, because a decision record states what a decision changes.
- `docs/specs/`, because a design spec describes work that is not built yet.

The folders can sit under another folder. A path such as
`services/api/docs/specs/` counts too.

In `docs/decisions/`, `config/vale.ini` also turns `Google.Headings` off. MADR
4.0.0 fixes the section titles of a record, such as `Decision Drivers`, and they
are not in sentence case.

### A true use of a listed word

When a listed word is true, turn the rule off for the passage. Put the reason in
a comment before it:

```markdown
<!-- This section quotes the wording of the vendor contract. -->
<!-- vale Sealambda.CurrentState = NO -->

The vendor is currently paid on the first day of the month.
<!-- vale Sealambda.CurrentState = YES -->
```

## Full forms

`Sealambda.Contractions` flags a contraction, such as `isn't` or `it's`. Write
the full form: `is not`, `it is`. The rule checks `'s` only after a fixed list
of words, such as `it` and `that`, so a possessive passes. The rule applies to
Markdown and to [code comments](#code-comments). `Google.Contractions` is off,
because it asks for the opposite.

## Sentence length

`Sealambda.SentenceLength` flags a sentence of more than 25 words. Split it into
two sentences. The rule skips table cells, code spans and code blocks. It also
checks [code comments](#code-comments). In shell, YAML, TOML, Dockerfile and SQL
files, `Sealambda.CommentSentenceLength` makes the same check. That rule is an
approximation. A parenthesis, a quote, a backtick, a slash or a hyphen with a
space on each side ends the count, so some long sentences pass.

## Filler words

`Sealambda.Filler` flags `simply`, `actually` and `really`. Delete the word: it
adds no fact. The rule does not flag `just`, because the word has a true meaning
about as often as it is a filler, as in `just short of`. The rule skips table
cells and headings. It also checks [code comments](#code-comments).

## Future tense

`Google.Will` flags the word `will`, because a page states what is true now.
Write the verb in the present tense: `works`, not `will work`. The rule is off
in the folders listed in [Where the rule is off](#where-the-rule-is-off). It
also checks [code comments](#code-comments).

## Code comments

Vale checks the comments, and nothing else, of files with the extensions below.
Vale has no parser for some of these languages. The `[formats]` section of
`config/vale.ini` maps each extension to a language that Vale can read, and a
section of the same file sets the rules per group. The mapping uses the comment
patterns of the other language. It was measured on Vale 3.25.1.

| Group                              | Extensions                                                                                          | Vale reads it as | Rules                                                |
| ---------------------------------- | --------------------------------------------------------------------------------------------------- | ---------------- | ---------------------------------------------------- |
| Markdown comments                  | `.py`, `.ex`, `.exs`, `.ts`, `.tsx`, `.js`, `.mjs`, `.cjs`, `.jsx`, `.mts`, `.cts`, `.css`, `.scss` | Markdown         | Full forms, filler, future tense and sentence length |
| Shell, YAML, TOML, Dockerfile, SQL | `.sh`, `.bash`, `.bats`, `.zsh`, `.yml`, `.yaml`, `.toml`, `Dockerfile`, `.dockerfile`, `.sql`      | R and Haskell    | Full forms, filler, future tense and sentence length |
| Nix and HCL                        | `.nix`, `.tf`, `.tofu`, `.tfvars`, `.hcl`                                                           | PowerShell       | Full forms, filler and future tense                  |

In every group, `Sealambda.CurrentState` is off, because words such as `Phase 2`
are domain terms in code. Vale checks the comments and nothing else. The
Markdown group checks no string literal. The other two groups have the
exceptions below.

Vale does not check `Makefile`, a name such as `Dockerfile.prod`, or the
comments of other languages. Write them by the same rules.

### Markdown comments

Vale parses the comment text as Markdown. The rules apply to a comment, a Python
docstring, an Elixir `@moduledoc` or `@doc`, and a JSDoc block. The sentence
length rule is `Sealambda.SentenceLength`.

- Vale skips code in a doc comment: a code span, a fenced block and an indented
  block. It also skips an example that starts with `iex>` or `>>>`, together
  with its result.

### Shell, YAML, TOML, Dockerfile and SQL

Vale checks the `#` comments of shell, YAML, TOML and Dockerfile files, and the
`--` comments of SQL files. The file `Dockerfile` can sit in any folder. A `#`
in a string, a here document, a YAML block scalar or a shell variable such as
`${#name}` or `$#` is not a comment. Vale joins the lines of a comment run, so
the sentence length rule, `Sealambda.CommentSentenceLength`, counts a sentence
across lines.

- Vale checks text in backticks, because it sees no code span in these comments.
  A flag such as `isn't` in backticks gets a finding.
- A `--` inside any SQL string literal, such as a quoted or a dollar-quoted
  string, is read as a comment start.
- Vale does not check a `/* */` comment of SQL.

### Nix and HCL

Vale checks the `#` comments of Nix and HCL files. Vale reads these files one
line at a time, so no rule joins the lines of a comment. The files have no
sentence length rule.

- Vale checks text in backticks, because it sees no code span in these comments.
- A `#` inside a string on the same line is read as a comment start. Vale then
  checks the rest of that line, so `"x # it isn't"` gets a finding. The
  `${y#pre}` of a Nix string starts a comment too.
- A line that starts with `#` inside a Nix `''` string or an HCL here document
  is read as a comment, indented or not.
- Vale does not check a `/* */` comment, and it does not check a `//` comment of
  HCL.

## Line length

Prettier wraps the prose of a Markdown file at 80 columns. Run `nix fmt` to wrap
it. The `formatting` check fails on a file that Prettier would change.
markdownlint checks the structure of a page and not the length of a line.

## Commit messages and pull requests

The commit section of `config/vale.ini` applies only the style `Sealambda` to a
commit message and to a pull request title and body, and not the styles `Vale`
and `Google`. In that style, `Sealambda.CurrentState`, `Sealambda.History` and
`Sealambda.CommentSentenceLength` are off, because a message describes a change
and `currently` and `previously` are true there. The sentence length,
contraction and filler rules stay on. `Google.Will` does not apply.

commitlint checks the form with `@commitlint/config-conventional`. The pull
request title is a Conventional Commit too, as
[CONTRIBUTING.md](../../CONTRIBUTING.md#pull-requests) says. Two checks run the
rules:

- The `commit-msg` hook of `config/lefthook-commit-msg.yml` runs commitlint and
  Vale on the message before Git makes the commit. Run `lefthook install` once
  per clone.
- The reusable workflow `.github/workflows/change-text.yml` runs commitlint on
  every commit of a pull request and on its title. It runs Vale on every commit,
  the title and the body, except for a pull request from a bot.

Vale reads a message on stdin with `--ext=.md --path=COMMIT_EDITMSG`: the path
selects the section, and the extension gives Vale the `sentence` scope that
`Sealambda.SentenceLength` needs. The hook removes the comment lines of Git and
the diff that `git commit -v` adds below the scissors line before Vale reads the
message.

## History

`Sealambda.History` flags these words:

- `previously`
- `formerly`
- `no longer`
- `used to`
- `superseded`
- `was renamed`

These words describe the past of the system. History lives in git and in
decision records, and a page states the current rationale. The level is
suggestion, because a word of the list can have a true present meaning. An
example is the sentence `The script is used to run the tests`. Change a flagged
sentence when it tells a history. Leave it when it states a fact.
