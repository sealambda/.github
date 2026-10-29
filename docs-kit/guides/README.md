# Page types

Every documentation page of the organization has one of four types. The types
come from [Diátaxis](https://diataxis.fr/), a framework that sorts
documentation by what the reader needs at that moment. A page of one type does
not do the job of another type. When a page does two jobs, split it.

| Type                          | The reader wants to   | The page is       | Template                                                |
| ----------------------------- | --------------------- | ----------------- | ------------------------------------------------------- |
| [Tutorial](tutorial.md)       | learn by doing a task | a guided lesson   | [templates/tutorial.md](../templates/tutorial.md)       |
| [How-to guide](how-to.md)     | finish a real task    | a list of steps   | [templates/how-to.md](../templates/how-to.md)           |
| [Reference](reference.md)     | look up a fact        | a neutral catalog | [templates/reference.md](../templates/reference.md)     |
| [Explanation](explanation.md) | understand a topic    | a discussion      | [templates/explanation.md](../templates/explanation.md) |

To choose a type, ask two questions. Does the reader act or think? Does the
reader study or work? The [Diátaxis compass](https://diataxis.fr/compass/)
maps the four answers to the four types.

## Decision records

A decision record is an explanation that has a fixed form: the
[MADR](https://adr.github.io/madr/) template in
[templates/adr.md](../templates/adr.md). Write one only for a decision that
shapes the architecture. The record states the context, the options and the
reason for the choice, and it does not teach or list facts. Records are in
`docs/decisions/`.

## Folders

Put a page in the folder of its type: `docs/tutorials/`, `docs/how-to/`,
`docs/reference/` or `docs/explanation/`. Put a decision record in
`docs/decisions/`. Do not create a folder for a type that has no page yet. An
empty folder promises content that does not exist.
