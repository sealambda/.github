# Decision records

This folder holds the decision records of the repository, and the ledger of
the records that left it. A record follows the template of the docs kit,
which is [MADR 4.0.0](https://adr.github.io/madr/). The contributing guide
says when a decision gets a record.

## Rules

- A record in this folder has the status `proposed` or `accepted`. The
  folder shows the decisions in force.
- A file is named `NNNN-title-in-lower-case.md`. `NNNN` is the number of the
  decision. A number is never reused. A gap is allowed.
- A record that is rejected, deprecated or superseded is deleted in the commit
  that adds its replacement or records the rejection. The commit adds a row to
  the ledger below. The status `superseded by` of MADR is not used here.
- The permalink of a row points to the last text of the record on `main`. Take
  the commit with `git log -1 --format=%H origin/main -- <file>`. Use a commit
  that is on `main` when the pull request opens, because a rebase merge
  replaces the SHAs of a branch.

## Ledger

The ledger lists every record that left the folder. The columns are:

- **Number** and **Title** of the record.
- **Status** at the end: `rejected`, `deprecated` or `superseded`.
- **Replaced by** the number of the record that replaces it, or `none`.
- **Reason**: one line.
- **Text**: the permalink `https://github.com/<owner>/<repository>/blob/<40 hex digits of the commit>/docs/decisions/<file>`.

| Number | Title | Status | Replaced by | Reason | Text |
| ------ | ----- | ------ | ----------- | ------ | ---- |
