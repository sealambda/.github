# Adopt the hub in a repository

Use the hub's parts in a Sealambda repository. Each section below is
independent: adopt the parts the repository needs. The community files need no
step, because GitHub applies them.

## Add the toolchain

Add the hub as a flake input that the repository's nixpkgs follows, so that
every repository evaluates one nixpkgs revision.

1. Add the hub input, the development shell, the formatter and the formatting
   check to the repository's `flake.nix`. Replace `node` with a dev shell from
   [Toolchain versions](../reference/versions.md). Put the repository's own
   treefmt-nix modules in the list that `mkTreefmt` takes.

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
         pkgs = nixpkgs.legacyPackages.aarch64-darwin;
         treefmt = hub.lib.mkTreefmt pkgs [ ];
       in
       {
         devShells.aarch64-darwin.default = pkgs.mkShell {
           inputsFrom = [ hub.devShells.aarch64-darwin.node ];
         };
         formatter.aarch64-darwin = treefmt.config.build.wrapper;
         checks.aarch64-darwin.formatting = treefmt.config.build.check self;
       };
   }
   ```

2. Run `nix flake lock`, then `nix flake check`.

The repository's `flake.lock` pins the hub. To take a newer hub revision, run
`nix flake update hub`. Renovate opens the same update as a pull request.

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

2. Keep the repository's own `enabledManagers`, `constraints` and
   `packageRules` in the same file. Don't repeat a setting that the
   [preset](../reference/renovate-preset.md) already sets. To change one, such
   as the `schedule`, set it in the repository.

## Sync the tool configuration

Some tools read only a file in the repository. The `sync-config` app copies
the hub's version of each file into the repository.

1. Run `nix run github:sealambda/.github#sync-config` in the repository root.
   Commit the files that it writes.
2. Create the `Repository` Vale vocabulary,
   `.vale/styles/config/vocabularies/Repository/accept.txt`, with one term per
   line. An empty file is valid. The synced `.vale.ini` lists this vocabulary,
   and Vale stops with an error when a listed vocabulary is missing.
3. Run `vale sync` once to install the Vale packages. Add `.vale/styles/*` and
   `!.vale/styles/config/` to `.gitignore`, so that Git ignores the packages
   and tracks the vocabularies.
4. To fail CI when a copy differs from the hub, add the check to the
   repository's `flake.nix`:

   ```nix
   checks.aarch64-darwin.config-in-sync = hub.lib.mkConfigCheck pkgs self;
   ```

The check compares the copies with the hub revision that `flake.lock` pins. To
take a newer revision, run `nix flake update hub`, then `sync-config`.

To relax a markdownlint rule for one directory, add a `.markdownlint-cli2.yaml`
to it. markdownlint-cli2 merges that file with the synced one at the root, as
the hub does in `.github`.

## Call the reusable workflows

The hub offers `secrets.yml` and `docs.yml`. Each workflow runs its tools from
the repository's flake. The comment at the top of the workflow file states what
the flake must expose.

1. Get the full SHA of the current head of `main`:

   ```sh
   git ls-remote https://github.com/sealambda/.github refs/heads/main
   ```

   Alternatively, write `@main` once and merge the pin pull request that
   Renovate opens.

2. Call the workflow from a job. Pin it to the full 40-character commit SHA,
   and write the branch in a comment. The `runs-on` input is optional. It takes
   JSON.

   ```yaml
   jobs:
     docs:
       uses: sealambda/.github/.github/workflows/docs.yml@<40-hex-sha> # main
       permissions:
         contents: read
       with:
         runs-on: '["ubuntu-24.04-arm"]'
   ```

3. List the job in the `needs` of the repository's `ci` job, as the hub's
   `.github/workflows/ci.yml` does.

Renovate reads the comment and bumps the SHA when `main` moves. The
[preset](../reference/renovate-preset.md#timing) skips the release-age wait
for these updates.

Pin by SHA, not by `@main`, for these reasons:

- A SHA works when a repository requires actions to be pinned to a full-length
  commit SHA. GitHub states that a reusable workflow can still be referenced
  by tag under that policy. It doesn't document the branch form.
- Renovate keeps the SHA current.
- A caller runs a known version, and a change to `main` reaches it only
  through a reviewed pull request.

GitHub doesn't document whether the `job_workflow_ref` claim of the OpenID
Connect token names the SHA or `refs/heads/main` for a call by SHA. Don't write
a trust policy that depends on either form.
