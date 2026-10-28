# Use the docs kit

Check the Markdown documents of a repository with the docs kit: the prose with
Vale, the structure with markdownlint-cli2, and the links with lychee. Follow
this guide when a repository has documents and no docs check.

## Before you start

- You know the number `N` of a release of the kit. The releases of the kit are
  the tags `docs-kit-vN` of `sealambda/.github`.
- For the Nix route, the repository has a flake that follows the toolchain of
  the organization, and Nix has the `nix-command` and `flakes` features on.
- For the package route, you have Vale 3.25.0 or later.

## Steps

1. Take the kit as a flake input, next to the toolchain. The kit takes its
   nixpkgs from the toolchain, so the repository keeps one pin of nixpkgs:

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

2. Add the formatter module and the check to the outputs of the flake:

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

   The root `flake.nix` of `sealambda/.github` is a complete example.

3. Lock the new input and run the checks:

   ```bash
   nix flake lock
   nix flake check
   ```

4. To check a directory by hand, without an input, run the kit as an app:

   ```bash
   nix run "github:sealambda/.github?dir=docs-kit&ref=docs-kit-vN#check" -- docs
   ```

## Check the result

`nix flake check` builds the check `docs`. The check prints one section for
each tool and exits with status 1 when a tool finds a problem. The tools do not
write files.

## Use the Vale package without Nix

A repository without Nix, and an editor, take the package from the release
asset of a `docs-kit-vN` release.

1. Put two lines in the `.vale.ini` of the repository:

   ```ini
   StylesPath = .vale/styles
   Packages = https://github.com/sealambda/.github/releases/download/docs-kit-vN/Sealambda.zip
   ```

2. Run `vale sync`. It installs the Sealambda style and its vocabulary. The
   package also lists Google and Microsoft, so `vale sync` installs them too.

Use the versioned URL, not `releases/latest/download`: the latest release of
the repository can be a release of another component, such as the toolchain. The
source archive of a tag cannot be the package, because its folder is not named
`Sealambda`.

Vale reads the package file first, and the file of the repository wins where
both set one value. The repository file adds only what is particular to it.

## Check the documents in GitHub Actions

Call the reusable workflow from a job of the repository. The tag of the
workflow also fixes the version of the kit:

```yaml
jobs:
  docs:
    if: ${{ !github.event.pull_request.draft }}
    permissions:
      contents: read
    uses: sealambda/.github/.github/workflows/docs.yml@docs-kit-vN
```

The `if` line skips a draft pull request. It belongs to the calling job,
because the workflow does not skip drafts itself. The [README of the kit](../../docs-kit/README.md#reusable-workflow) lists the
inputs, the actions that a repository with a restricted policy must allow, and
the runner rules. Never call the workflow from the `pull_request_target` event.

## Write a flagged word on purpose

A word that a rule flags can be right in one place, for example the name of a
column. Put a Vale comment around the passage, with the reason before it:

```markdown
<!-- The word is the name of a column of the report. -->
<!-- vale Sealambda.CurrentState = NO -->

The column currently shows the state of the job.

<!-- vale Sealambda.CurrentState = YES -->
```

A code span needs no comment, because Vale does not check code.

## Add words to the vocabulary

1. Create `config/vocabularies/<Name>/accept.txt` below the `StylesPath` of the
   repository. Write one word for each line, in the spelling that the text
   must use.
2. Add `Vocab = <Name>` to the `.vale.ini` of the repository.

The check reads the file, because Vale lays the file of the repository over the
file of the kit. Do not list a word that is also a command or a plain word in
lower case: Vale would flag the lower case.

## If a step fails

- `vale sync` fails, or the style does not load: check `vale --version`. The
  package needs Vale 3.25.0 or later, and an older Vale does not install the
  vocabulary of a package.
- The check flags the placeholders of a template: tell the check that the file
  is a template. Pass `--template GLOB`, or set `DOCS_CHECK_TEMPLATES` (one
  glob on each line). The README of the kit lists how it finds templates.

## Related

- [Docs kit](../../docs-kit/README.md): the reference for every output.
- [The docs kit](../explanation/docs-kit.md): why the kit has this shape.
- [Release a component](release-a-component.md): how a new `docs-kit-vN` comes
  out.
