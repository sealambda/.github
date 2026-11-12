# Adopt the hub in a repository

Use the hub's parts in a Sealambda repository. You need Git, and Nix with the
`nix-command` and `flakes` features enabled
([install Nix](https://nixos.org/download/)). Follow the sections in order, from
the first to the last. Do not skip a section, because each one builds on the
sections before it. [Add the toolchain](#add-the-toolchain) adds the hub input,
and [Sync the tool configuration](#sync-the-tool-configuration) adds the files
and the `docs` dev shell. The community files need no step, because GitHub
applies them.

## Add the toolchain

Add the hub as a flake input that the repository's nixpkgs follows, so that
every repository evaluates one nixpkgs revision.

1. Add the hub input, the development shell, the formatter and the formatting
   check to the repository's `flake.nix`. Replace `base` with a dev shell from
   [Toolchain versions](../reference/versions.md) when the repository needs
   another one. Put the repository's own treefmt-nix modules in the list that
   `mkTreefmt` takes.

   The snippet defines every output for the three systems that the hub supports.
   `forAllSystems` applies a function to the package set of each system. The
   later snippets of this page add their checks to the set that `checks` builds
   with it. CI runs `nix flake check` on Linux, so a check that only
   `aarch64-darwin` defines does not run there.

   ```nix
   {
     inputs = {
       hub.url = "github:sealambda/.github";
       nixpkgs.follows = "hub/nixpkgs";
     };

     outputs =
       {
         self,
         nixpkgs,
         hub,
         ...
       }:
       let
         systems = [
           "x86_64-linux"
           "aarch64-linux"
           "aarch64-darwin"
         ];
         forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
         treefmtFor = forAllSystems (pkgs: hub.lib.mkTreefmt pkgs [ ]);
       in
       {
         devShells = forAllSystems (pkgs: {
           default = pkgs.mkShell {
             inputsFrom = [ hub.devShells.${pkgs.stdenv.hostPlatform.system}.base ];
           };
         });
         formatter = forAllSystems (
           pkgs: treefmtFor.${pkgs.stdenv.hostPlatform.system}.config.build.wrapper
         );
         checks = forAllSystems (pkgs: {
           formatting = treefmtFor.${pkgs.stdenv.hostPlatform.system}.config.build.check self;
         });
       };
   }
   ```

2. In a Git repository, Nix reads only the files that Git tracks. Run
   `git add flake.nix` now, and run `git add` on every later new file before a
   Nix command needs it. Then run `nix flake lock`, then `nix flake check`.
3. In a repository that already has files, the `formatting` check can fail. Run
   `nix fmt`: it rewrites the files that `nixfmt`, Prettier and `shfmt` format,
   and it reports what `actionlint`, `shellcheck`, `typos` and `zizmor` find.
   Correct each report, run `nix fmt` again, and commit the result. If `typos`
   flags a word wrongly, add the word as both key and value under
   `[default.extend-words]` in a `typos.toml` at the repository root, as the
   [typos configuration](https://github.com/crate-ci/typos/blob/master/docs/reference.md)
   explains.

The repository's `flake.lock` pins the hub. To take a newer hub revision, run
`nix flake update hub`. Renovate opens the same update as a pull request.

## Run a hub app

The hub offers the app `sync-config`. Run it in the repository, with the option
`--inputs-from .`:

```sh
nix run --inputs-from . hub#sync-config
```

The option makes `hub` mean the hub revision that the repository's `flake.lock`
pins, so the app is the version that the checks run. The address
`github:sealambda/.github#sync-config` without the option runs the latest `main`
of the hub, which can differ from the pinned revision.

The command needs the `hub` input and its lock, which
[Add the toolchain](#add-the-toolchain) creates. A repository without a `hub`
input has no pinned revision, and Nix stops with the error
`cannot find flake 'flake:hub' in the flake registries`. Add the input first.

## Extend the Renovate preset

Renovate resolves `github>sealambda/.github` to `default.json` at the root of
the hub.

1. Extend the preset in the repository's `renovate.json`:

   ```json
   {
     "$schema": "https://docs.renovatebot.com/renovate-schema.json",
     "extends": ["github>sealambda/.github"]
   }
   ```

2. Keep the repository's own `enabledManagers`, `constraints` and `packageRules`
   in the same file. The `enabledManagers` list must contain `nix` and
   `github-actions`. Without them, the `hub` input, the pinned workflows and the
   pinned actions get no updates. Do not repeat a setting that the
   [preset](../reference/renovate-preset.md) already sets. To change one, such
   as the `schedule`, set it in the repository.

## Sync the tool configuration

Some tools read only a file in the repository. The `sync-config` app copies the
hub's version of each file into the repository.

1. Run `nix run --inputs-from . hub#sync-config` in the repository root, as
   [Run a hub app](#run-a-hub-app) explains. It writes seven files:
   `.commitlintrc.yaml`, `.editorconfig`, `.markdownlint-cli2.yaml`,
   `.vale.ini`, `lefthook-commit-msg.yml`, `lychee.toml` and
   `.vale/styles/config/vocabularies/Sealambda/accept.txt`. The app replaces a
   file of the same name, so run `git diff` to see what changed, and commit all
   seven. Do not edit a synced file in the repository: `config-in-sync` fails
   when a copy differs from the hub, and `sync-config` restores the hub's copy.
   Put a need of the repository elsewhere:
   - A rule for one folder goes in a `.editorconfig` or a
     `.markdownlint-cli2.yaml` in that folder. The tool merges it with the
     synced file at the root. `shfmt` runs with `-i 2` and ignores every
     `.editorconfig`.
   - An accepted term goes in the `Repository` vocabulary of the next step.
   - Any other change to a synced file is a change request to the hub. Open the
     **Feature or change request**
     [issue form](https://github.com/sealambda/.github/issues/new/choose).

   `config-in-sync` compares only the seven file names above. A tool prefers
   another configuration file when one exists, such as
   `.markdownlint-cli2.jsonc` or `.commitlintrc.json`, and the check stays
   green. A reviewer rejects a second configuration file for a tool whose
   configuration is synced.

2. Create the `Repository` Vale vocabulary,
   `.vale/styles/config/vocabularies/Repository/accept.txt`, with one term per
   line, and run `git add` on it, as [Add the toolchain](#add-the-toolchain)
   explains. An empty file is valid. The synced `.vale.ini` lists this
   vocabulary, and Vale stops with an error when a listed vocabulary is missing.
3. Reuse the hub's shell as the repository's `docs` shell. Add this attribute
   next to `default` in the set that `devShells` defines
   ([Add the toolchain](#add-the-toolchain)):

   ```nix
   docs = hub.devShells.${pkgs.stdenv.hostPlatform.system}.docs;
   ```

   Add these two rules to the repository's `.gitignore`, so that nobody commits
   a style directory:

   ```gitignore
   .vale/styles/*
   !.vale/styles/config/
   ```

4. Run Vale in the `docs` dev shell. Enter the shell and run Vale on a file,
   with no flags:

   ```sh
   nix develop .#docs
   vale <file>
   ```

   Vale comes from the hub's `vale.withStyles` package, which sets
   `VALE_STYLES_PATH`, so Vale finds the Google and Sealambda styles in the Nix
   store. The project `StylesPath`, `.vale/styles`, holds only the tracked
   vocabularies. Do not run `vale sync`: the synced `.vale.ini` lists no
   packages. Do not pass `--no-global`: that flag makes Vale ignore
   `VALE_STYLES_PATH`, and Vale then stops with the error
   `Style 'Google' isn't on the StylesPath`. Outside `nix develop` or direnv,
   for example in an editor extension, Vale finds no styles and reports the same
   error. The `default` shell has no Vale. Start the editor from the `docs`
   shell, or write `use flake .#docs` in the `.envrc` of direnv. Vale can report
   findings in a file that exists already.
   [Gate the documentation](#gate-the-documentation) explains how to fix them.

5. To fail CI when a copy differs from the hub, add this attribute next to
   `formatting` in the set that `checks` defines through `forAllSystems`
   ([Add the toolchain](#add-the-toolchain)):

   ```nix
   config-in-sync = hub.lib.mkConfigCheck pkgs self;
   ```

The check compares the copies with the hub revision that `flake.lock` pins. To
take a newer revision, run `nix flake update hub`, then `sync-config`.

To relax a markdownlint rule for one directory, add a `.markdownlint-cli2.yaml`
to it. markdownlint-cli2 merges that file with the synced one at the root, as
the hub does in `.github`.

## Gate the documentation

The `docs` check lints every Markdown file with markdownlint-cli2, lychee and
Vale. Vale also lints the comments of code files: Python, Elixir, TypeScript,
JavaScript, CSS, shell, YAML, TOML, Dockerfile, SQL, Nix and HCL. The language
decides which rules apply, as
[Code comments](../reference/writing-style.md#code-comments) explains. Where the
Nix sandbox is enabled, which it always is on Linux CI, the check reads no
personal configuration and needs no network. Every tool reads its configuration
from the repository, so the repository needs the files that `sync-config` writes
and the `Repository` Vale vocabulary
([Sync the tool configuration](#sync-the-tool-configuration)).

1. Add the check to the set that `checks` defines through `forAllSystems` in the
   repository's `flake.nix`. Pass `self`, not a list of Markdown files, because
   lychee also checks links to files that are not Markdown.

   ```nix
   docs = hub.lib.mkDocsCheck pkgs self;
   ```

2. Run `nix build .#checks.<system>.docs -L --no-link`, with your system for
   `<system>`, such as `aarch64-darwin`. The flag `--no-link` leaves no `result`
   link in the repository. The output lists each finding of level error, as
   [Write the current state](#write-the-current-state) explains. Fix each
   finding:
   - Replace each contraction with its full form.
   - Split each sentence of more than 25 words.
   - Write each future-tense sentence in the present tense.
   - Delete each filler word.
   - Change each page that `Sealambda.CurrentState` flags to state what is true
     now. Move a plan or an open question into an issue.
   - Fix each misspelling that `Vale.Spelling` reports. Add a valid term, such
     as a product name, to
     `.vale/styles/config/vocabularies/Repository/accept.txt`. The entries are
     regular expressions, as
     [Writing style](../reference/writing-style.md#rules) explains.
   - Fix each link that the anchor check reports.
3. Remove the repository's own Prettier setup for Markdown. The hub's `*.md`
   override wins: treefmt passes `--config`, so Prettier ignores a `.prettierrc`
   of the repository. Run `nix fmt` once and commit the result.
4. Run `nix flake check`. CI needs no separate job: the job that runs
   `nix flake check` runs this check too.

The check builds its tools from the hub's own nixpkgs, whatever nixpkgs the
repository follows. Every repository at the same hub revision then runs the same
version of each tool and of each Vale style. An override of the hub's `nixpkgs`
input changes that. The command `nix flake update hub` updates them. The
repository needs no `nixpkgs.follows = "hub/nixpkgs"` for this check, and no hub
package set that it passes by hand.

For an interactive run or an editor, use the `docs` dev shell. A personal global
Vale configuration can change the result there. The check is the reference
result.

### Write the current state

The Vale style `Sealambda` keeps a page in the present tense.
[Writing style](../reference/writing-style.md) lists its rules, the level of
each rule and the words that it flags. The check fails on a finding of level
error.

The synced `.vale.ini` turns `Sealambda.CurrentState` and `Google.Will` off for
`docs/decisions/` and `docs/specs/`. A word that `Sealambda.CurrentState` lists
can be true in one passage. Turn the rule off for that passage with a Vale
comment, as the reference shows.

The synced `lychee.toml` also checks the anchors of local links. A link such as
`page.md#heading`, or `#heading` in the same file, fails when the page has no
such heading.

## Gate the commit messages

The hub checks the commit messages and the pull request text of its own
repository with commitlint and Vale.
[Writing style](../reference/writing-style.md#commit-messages-and-pull-requests)
defines the rules. A consumer adds the same checks:

1. The files of the checks are already in the repository:
   [Sync the tool configuration](#sync-the-tool-configuration) wrote
   `.commitlintrc.yaml`, the commit section of `.vale.ini` and the hook
   definition `lefthook-commit-msg.yml`.
2. The `inputsFrom` of a hub shell brings commitlint and lefthook into the
   development shell. The hook runs its commands in the `docs` shell, which has
   Vale and which [Sync the tool configuration](#sync-the-tool-configuration)
   added.
3. Add the `extends` key to the repository's `lefthook.yml`, and create the file
   when the repository has none:

   ```yaml
   extends:
     - lefthook-commit-msg.yml
   ```

4. Run `lefthook install` in the development shell, once per clone.
5. Call the reusable workflow `change-text.yml`, as
   [Call the reusable workflow](#call-the-reusable-workflow) shows. The job runs
   for a pull request only. After an edit of the title or the body, re-run the
   job.

## Call the reusable workflow

The hub offers the reusable workflows `secrets.yml` and `change-text.yml`.
`change-text.yml` runs its tools from the repository's flake. `secrets.yml` runs
its scanner from the hub. The comment at the top of each workflow file states
what the flake and the caller must provide.

1. Copy the hub's own workflow,
   [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml), to the same
   path in the repository. The hub's checks lint that file. It runs
   `nix flake check`, calls both reusable workflows and ends with the job `ci`.
   Delete a job together with its entry in `needs` only on purpose. Without
   `secrets` no secret scan runs, without `change-text` no text check runs,
   without `flake-check` no flake check runs, and `ci` still passes.

   Move a job of an existing workflow into the copy when the required check must
   cover it, and add the job to the `needs` of `ci`. The copy sets
   `permissions: {}` for the workflow, so each moved job declares the
   permissions it needs. The copy runs on `pull_request` and on pushes to `main`
   only. A job that runs on a schedule, on a tag or on `workflow_dispatch` stays
   in its own workflow.

2. Change only the two `uses:` lines. The hub calls its own files with a local
   path. Pin the call to the commit SHA of the hub revision in the lock file of
   the repository. The workflows and the flake tools run one revision when you
   make the pin. Renovate later updates the lock file and the workflow pin in
   separate pull requests. Name the branch or the tag in a comment after the
   SHA. Print the SHA with:

   ```sh
   nix eval --raw --impure --expr 'let l = builtins.fromJSON (builtins.readFile ./flake.lock); in l.nodes.${l.nodes.root.inputs.hub}.locked.rev'
   ```

   Renovate updates a SHA according to the comment, and it does not update a
   bare SHA
   ([Renovate documentation](https://docs.renovatebot.com/modules/manager/github-actions/)).
   Drop the `zizmor: ignore` comment of the local form.

   ```yaml
   uses: sealambda/.github/.github/workflows/secrets.yml@<full commit SHA> # main
   uses: sealambda/.github/.github/workflows/change-text.yml@<full commit SHA> # main
   ```

   The `runs-on` input of each workflow is optional. It is a string that holds
   JSON, so quote it under `with:`. This line selects an Arm runner. A plain
   runner is `'"ubuntu-latest"'`:

   ```yaml
   with:
     runs-on: '["ubuntu-24.04-arm"]'
   ```

   Both workflows install Nix on the runner, and the install action writes the
   job token into the Nix configuration of the runner. They expect an ephemeral
   runner. The change text workflow also uses `gh` and `jq` from the runner, so
   a self-hosted runner needs both.

3. Keep the other lines. The job `ci` is the one required status check. Without
   its `if: always()`, GitHub skips the job when a needed job fails, and it
   counts a skipped required check as passing. Every needed job must succeed,
   except that `change-text` is skipped on a push. Each job holds the least
   `permissions` that it needs. Add a job of the repository to the `needs` of
   `ci`.

The `secrets.yml` scan runs the `gitleaks` package of the hub's flake, at the
commit that the caller pins, and not a gitleaks from the repository. The scanner
and its rules come from the hub and not from the tree of the pull request. The
scan uses the default rules and ignores the `.gitleaks.toml` of the repository.
A pull request can still change the calling workflow and the flake files. Review
those changes, and require a code owner for `.github/workflows/` and `flake.*`
in a consumer. A pull request can add a fingerprint to `.gitleaksignore` or a
`gitleaks:allow` comment to suppress one finding. A reviewer sees either in the
diff. The scan reads every branch and tag, files that `.gitattributes` marks
`-diff` and the changes of merge commits.

The scan does not see these:

- The paths that the default rules of gitleaks skip, for example `node_modules`,
  image files, lock files such as `pnpm-lock.yaml` and `.bin` files.
- The text of commit messages.
- A commit that only a deleted branch or the head of another pull request
  reaches.
