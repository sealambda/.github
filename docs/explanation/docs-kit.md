# The docs kit

Why does the organization ship its documentation checks as a kit, and why does
the kit make the choices it makes? This page explains the shape of the kit. The
facts are in the [reference](../../docs-kit/README.md).

## Context

Every repository of the organization has documents, and documents decay in the
same ways: a link breaks, a heading changes, a sentence promises a future that
never comes. A check that each repository writes for itself drifts from the
others. Two pull requests then get two different answers to the same question.

The kit gives every repository the same checks, at the same versions, from one
place. A repository takes a tag of the kit and gets the same tools, the same
rules and the same levels as every other repository on that tag.

## How it works and why

### Three routes, one rule set

A repository can take the kit as a Nix flake, as a Vale package, or as a
reusable workflow. The routes share one source. The Vale package is built from
the same files that the Nix check reads. The `Packages` line of the package,
which names the Google and Microsoft styles, is written from the versions in
the locked nixpkgs. No second list of versions exists, so no check has to keep
two lists equal.

### Errors are facts, suggestions are judgment

A rule at level `error` fails a pull request. A rule fails a pull request only
when a writer can fix the problem without a debate: a broken heading, a Latin
abbreviation, a word that has no use. A rule that flags words with a true use in
some places is a suggestion. It shows in an editor, and a writer decides.

This is why the filler words `simply` and `just` are errors, and the weak
intensifiers `really`, `very`, `actually` and `easy` are suggestions. A quotation
or a contrast needs an intensifier. A reader who struggles never needs `simply`.

### The style departs from Google where the reasons differ

The style is the Google developer documentation style guide with a few
Microsoft rules and some house rules. The organization writes Simplified
Technical English, so it avoids contractions and keeps sentences short. Google
recommends contractions, and its rule for them is off. The `.vale.ini` of the
package lists every departure with its reason.

### The vocabulary holds only unambiguous names

Vale reports every other case of a word in the vocabulary. A name such as
`GitHub` has one spelling, so it belongs there. A word such as `ssh`, `cd`,
`id` or `os` is also a command or a plain word in lower case. If the vocabulary
held `SSH`, every `ssh` command in prose would fail. The vocabulary holds the
names that the public documents of the organization use, and no more.

### Templates are skipped

A template holds placeholders, such as `{short title}`. Vale and lychee would
flag them, so the check skips a template for these two tools. The structure
check still reads it.

## Decision records

The organization keeps a decision record only while the decision is in force.
A record that is rejected, deprecated or superseded is deleted in the commit
that replaces it or rejects it. The ledger in `docs/decisions/README.md` keeps
one row for each deleted record: its number, its final status, the record that
replaces it, a one-line reason, and a permalink to its last text.

This departs from the usual practice. Nygard, who proposed the format in 2011,
keeps a reversed decision and marks it as superseded. MADR 4.0.0 lists
`superseded by ADR-0123` as a status. The AWS prescriptive guidance treats an
accepted record as immutable and marks the old one `Superseded`. The Azure
Well-Architected guidance calls the log append-only and says to link the old
and the new record. All four keep the old record in the tree.

The organization deletes it for one reason: what a reader sees in the tree is
what the reader follows. A person who opens the folder, or a coding agent that
searches it, reads a record in the same confident words whatever its status.
The status is one line in the front matter, and a reader who finds the text
through a search may never see it. A tree that holds only decisions in force
cannot mislead in this way. The history is not lost: Git keeps every text, and
the permalink in the ledger leads to the last one.

The permalink uses a commit that is already on `main` when the pull request
opens, because a commit of a branch does not survive a rebase merge. The branch
protection of `main` blocks force pushes, so the commit stays reachable. A
number is never reused, and a gap in the numbers is allowed.

The check `decisions-ledger` enforces the rule. It fails when a record in the
tree has another status than `proposed` or `accepted`, when a number appears
twice, when a replacement does not exist, and when a permalink has no full
commit SHA. Whether a permalink resolves is left to the scheduled link check,
so the kit has no second checker for the network.

## Alternatives

- **Keep the record and mark it superseded.** This is the practice in the
  sources above. The organization does not use it for the reason in "Decision
  records".
- **Move old records to an archive folder.** The records stay in the tree, so a
  search still finds them, and the reader still has to know which folder is
  safe.
- **One kit per tool.** Each tool has its own version and its own release. The
  organization would then have to keep the combination of versions that works,
  which is the job of the kit.

## Related

- [Docs kit](../../docs-kit/README.md): the reference for the outputs, the
  rules and the format of the ledger.
- [Use the docs kit](../how-to/use-the-docs-kit.md): how a repository takes the
  kit.
- [Release a component](../how-to/release-a-component.md): how a new version
  comes out.
- [Nygard, Documenting Architecture Decisions](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions),
  [MADR](https://adr.github.io/madr/),
  [AWS prescriptive guidance](https://docs.aws.amazon.com/prescriptive-guidance/latest/architectural-decision-records/adr-process.html)
  and [Azure Well-Architected](https://learn.microsoft.com/en-us/azure/well-architected/architect-role/architecture-decision-record):
  the sources for the practice that this page departs from.
