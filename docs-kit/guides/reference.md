# Write a reference page

A reference page states facts that a reader looks up while working: the
options of a command, the outputs of a flake, the fields of a file. The reader
does not read it from start to end. The source of this guide is the Diátaxis
page on [reference](https://diataxis.fr/reference/). The template is
[templates/reference.md](../templates/reference.md).

## What a reference page does

- It follows the structure of the thing that it describes, so that a reader
  finds a fact where the thing keeps it.
- It states each fact once, in a neutral voice, without advice or opinion.
- It is complete and accurate. A missing or wrong fact is a defect.
- It uses the same form for every entry of a group, such as one table row for
  each option.
- It gives a short example where the example shows the use of a fact.
- It is generated from the source when a tool can do it, so that the page and
  the code cannot differ.

## What a reference page does not do

- It does not teach or give steps. A tutorial or a how-to guide does that.
- It does not explain the reason for a design. A link leads to the explanation.

## Checks before you publish

- Compare each fact with the source, or run the command that prints it.
- Search for the words "should" and "because". They mark advice or an
  explanation that belongs on another page.
