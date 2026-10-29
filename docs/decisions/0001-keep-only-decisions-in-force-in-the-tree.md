---
status: "accepted"
date: 2026-10-28
decision-makers: the code owners of this repository
---

# Keep only decisions in force in the tree

## Context and Problem Statement

A decision record is a file that explains why the organization chose a design.
Records change status over time: a later decision replaces an earlier one, or
a proposal is rejected. Where does a record go when it is no longer in force?

The common practice, from the first description of the format, keeps the old
record in the tree and marks its status. People and AI agents read the tree
to learn what holds. A reader, or a search over file contents, finds a
replaced record and can apply it, because the text of the record does not
change when its status does.

## Decision Drivers

- The tree must show the decisions in force and nothing else.
- An agent must not need to read the status of every file to know what holds.
- The reason for a past decision must stay reachable.
- A check must be able to keep the rule without a person.

## Considered Options

- Keep every record and mark its status (`superseded by ADR-0123`).
- Move a record that left force to an archive folder.
- Delete a record that left force, and keep a ledger with a permalink.

## Decision Outcome

Chosen option: "Delete a record that left force, and keep a ledger with a
permalink", because it is the only option in which every file in the tree is a
decision in force.

A record in `docs/decisions/` has the status `proposed` or `accepted`. A
record that is rejected, deprecated or superseded is deleted in the commit that
adds its replacement or records the rejection. The same commit adds a row to
the ledger in `docs/decisions/README.md`. The row holds the number, the title,
the final status (`rejected`, `deprecated` or `superseded`), the number of the
replacing record, a reason in one line, and a permalink of the form
`https://github.com/<owner>/<repository>/blob/<40 hex digits>/docs/decisions/<file>`.
The commit of the permalink is on `main` when the pull request opens. A
number is never reused, and a gap is allowed.

### Consequences

- Good, because a reader or an agent finds only decisions in force in the tree.
- Good, because the reason of a past decision stays reachable by its permalink
  and by Git history.
- Bad, because the practice deviates from the sources below, which keep
  superseded records. A reader who knows them must learn the rule.
- Bad, because the permalinks depend on `main` keeping its history. The ruleset
  of `main` blocks force pushes and deletion, and the permalink uses a
  commit that is on `main`.

### Confirmation

The flake check `decisions` (its program is `decisions-ledger`) checks these
rules: the status of a record in the tree is `proposed` or `accepted`; a
number is unique across the tree and the ledger; a permalink has a 40-digit
commit; and the number in `Replaced by` resolves. That a permalink opens is
left to the scheduled link check, so there is no second online checker.

## Pros and Cons of the Options

### Keep every record and mark its status

This is the practice of Michael Nygard, who writes that a reversed decision
is kept "but mark it as superseded" in
[Documenting architecture decisions](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions).
The MADR 4.0.0 template lists `superseded by ADR-0123` as a status. The
[AWS prescriptive guidance](https://docs.aws.amazon.com/prescriptive-guidance/latest/architectural-decision-records/adr-process.html)
treats an accepted record as immutable and sets the old one to `Superseded`.
The
[Azure Well-Architected guidance](https://learn.microsoft.com/en-us/azure/well-architected/architect-role/architecture-decision-record)
calls the log append-only.

- Good, because it is the established practice, and tools and readers know it.
- Good, because the history of the thinking sits next to the current decision.
- Bad, because the tree holds text that no longer holds, and a reader that
  ignores the status applies it.

### Move a record that left force to an archive folder

- Good, because the history stays in the tree, and the folder of records in
  force is clean.
- Bad, because a search over the tree still finds the archive.
- Bad, because the archive grows without limit.

### Delete a record that left force, and keep a ledger with a permalink

- Good, because a search over the tree finds only decisions in force.
- Good, because the ledger is short, and it holds the reason in one line.
- Neutral, because the full text of an old record is one click away, in Git.
- Bad, because the practice is a deviation that needs this record.

## More Information

The rule is the organization's rule. The contributing guide states it in one
sentence and links here. The decision record template of the docs kit offers
the in-tree statuses only.
