---
status: "accepted"
date: 2026-10-28
decision-makers: the code owners of this repository
---

# License the repository under MPL-2.0

## Context and Problem Statement

`sealambda/.github` is public, and other repositories consume and copy its
files: the toolchain, the docs kit, the workflows and the templates. The
repository had no license. Without a license, the authors keep all rights, and
no one else has a right to copy or change a file. GitHub cannot take a default
license file from this repository, so the license applies to this repository
only.

## Decision Drivers

- Consumers must have a clear right to use, copy and change the files.
- A change to a shared file should come back to the organization when someone
  distributes it.
- A consumer must be able to combine the files with code under other terms.
- A contribution must have a known inbound license.

## Considered Options

- No license.
- A permissive license (MIT or Apache-2.0).
- A file-level copyleft license, MPL-2.0.
- A strong copyleft license (GPL-3.0).

## Decision Outcome

Chosen option: "A file-level copyleft license, MPL-2.0" (the Mozilla Public
License 2.0), because its copyleft applies to the files that carry it, not to
the larger work, and it includes a grant of patent rights from each
contributor (section 2.1).

`LICENSE` holds the canonical text from
[mozilla.org](https://www.mozilla.org/media/MPL/2.0/index.txt). A contribution
to this repository is licensed under MPL-2.0, by section D.6 of the GitHub
terms of service. A file whose format allows comments can carry the line
`SPDX-License-Identifier: MPL-2.0`.

### Consequences

- Good, because a consumer may use and copy a file with a clear right.
- Good, because a consumer may combine a file with code under other terms in a
  larger work.
- Bad, because a consumer that changes a file and distributes it must publish
  the changed file under MPL-2.0.
- Bad, because a file that cannot carry a comment has no SPDX line. The
  license of the repository applies to it.

### Confirmation

`LICENSE` exists at the root, and the community profile of the repository
shows the license. No check reads the text of `LICENSE`. A reviewer compares
it with the published text when a pull request changes it. The formatters
leave the file unchanged.

## Pros and Cons of the Options

### No license

- Good, because it needs no decision.
- Bad, because no one may copy or change a file, which defeats the purpose of
  a shared repository.

### A permissive license (MIT or Apache-2.0)

- Good, because it asks nothing of a consumer.
- Bad, because a changed copy of a file need not come back.

### A file-level copyleft license, MPL-2.0

- Good, because the copyleft is limited to the covered files.
- Good, because it has an explicit patent grant.
- Bad, because a consumer that distributes a changed file has a duty.

### A strong copyleft license (GPL-3.0)

- Good, because every derived work stays open.
- Bad, because it constrains the larger work of a consumer, and a consumer
  with private code may not accept that.

## More Information

A repository that consumes these files keeps its own `LICENSE`. See
[How the default files of the organization work](../explanation/default-files.md).
