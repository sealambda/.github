# The quality gate of this repository: `nix flake check` runs every
# formatter, linter and test, `nix fmt` formats and lints the tree, and
# `nix develop` is the shell with the same tools and the pre-commit hook
# (lefthook.yml). scripts/check.sh is the gate that CI and a developer run:
# it also checks that the lock files of the flakes below this one are
# current. CI runs it (.github/workflows/ci.yml).
#
# The subflakes in toolchain/ and docs-kit/ are inputs, as in any consumer, so
# this repository tests them the way a consumer uses them.
{
  description = "The quality gate of sealambda/.github";

  inputs = {
    toolchain.url = "path:./toolchain";
    nixpkgs.follows = "toolchain/nixpkgs";
    treefmt-nix.follows = "toolchain/treefmt-nix";
    docs-kit = {
      url = "path:./docs-kit";
      inputs.toolchain.follows = "toolchain";
    };
  };

  outputs =
    {
      self,
      toolchain,
      nixpkgs,
      treefmt-nix,
      docs-kit,
    }:
    let
      inherit (nixpkgs) lib;

      # Calls `mkOutput pkgs` for every system that the toolchain supports,
      # and returns the results as an attribute set by system.
      eachSystem =
        mkOutput: lib.genAttrs toolchain.lib.systems (system: mkOutput nixpkgs.legacyPackages.${system});

      # The treefmt evaluation for one package set: the toolchain's module and
      # this repository's settings (treefmt.nix).
      treefmtFor =
        pkgs:
        treefmt-nix.lib.evalModule pkgs {
          imports = [
            toolchain.lib.treefmtModules.default
            docs-kit.lib.treefmtModules.default
            ./treefmt.nix
          ];
        };

      # The test of a composite action of this repository, run in the build
      # sandbox. The test script sits next to the action's script
      # (`.github/actions/<name>/<name>.test.sh`) and fakes every command that
      # the action runs. `bash` is the Bash of Nix, because the scripts need
      # Bash 4.4 or later and macOS ships 3.2.
      #   name   the action's directory name
      #   tools  packages that the test itself runs, besides Bash
      actionTest =
        pkgs: name: tools:
        let
          source = lib.fileset.toSource {
            root = ./.;
            fileset = ./.github/actions/${name};
          };
        in
        pkgs.runCommandLocal name { nativeBuildInputs = [ pkgs.bash ] ++ tools; } ''
          bash ${source}/.github/actions/${name}/${name}.test.sh
          touch "$out"
        '';

      # The development shell for one package set.
      devShellFor =
        pkgs:
        let
          treefmt = (treefmtFor pkgs).config.build;
        in
        pkgs.mkShellNoCC {
          name = "dot-github";
          # `treefmt` with this repository's configuration, every program it
          # runs (for editors), and the hook runner.
          packages = [
            treefmt.wrapper
            pkgs.lefthook
            toolchain.packages.${pkgs.stdenv.hostPlatform.system}.pnpm-only-lint
            docs-kit.packages.${pkgs.stdenv.hostPlatform.system}.docs-check
          ]
          ++ lib.attrValues treefmt.programs;
          # Installs the hook of lefthook.yml. It is idempotent, and it keeps
          # an existing hook as `<hook>.old`. A refusal (for example when
          # `core.hooksPath` is set) prints its reason; the shell still opens.
          shellHook = ''
            lefthook install || echo "lefthook install failed; see the message above, fix the cause and run it again." >&2
          '';
        };
    in
    {
      formatter = eachSystem (pkgs: (treefmtFor pkgs).config.build.wrapper);

      devShells = eachSystem (pkgs: {
        default = devShellFor pkgs;
      });

      checks = eachSystem (
        pkgs:
        let
          system = pkgs.stdenv.hostPlatform.system;
        in
        {
          # Every formatter and linter, on the tracked files; it fails on a
          # finding or on a file that a formatter would change.
          formatting = (treefmtFor pkgs).config.build.check self;

          # The docs check of the docs kit (Vale, markdownlint-cli2 and
          # lychee, offline) on every Markdown file of the repository. The
          # kit's templates hold placeholders, so Vale and lychee skip them.
          # `docs-kit.lib.mkCheck` has no option for template patterns, so
          # this check calls `docs-check` itself.
          docs = pkgs.runCommandLocal "docs" {
            nativeBuildInputs = [ docs-kit.packages.${system}.docs-check ];
          } ''docs-check --template 'docs-kit/templates/*' ${self} && touch "$out"'';

          # The decision records of docs/decisions and their ledger agree: a
          # record in the tree is in force, a number is used once, and a
          # replaced record names an existing successor.
          decisions = docs-kit.lib.mkDecisionsCheck pkgs ./docs/decisions;

          # The repository uses pnpm only. The lint reads the files that Git
          # tracks, and a flake's source has no .git: the build copies the
          # source into a new repository and tracks every file in it.
          pnpm-only =
            pkgs.runCommandLocal "pnpm-only"
              {
                nativeBuildInputs = [
                  pkgs.git
                  toolchain.packages.${system}.pnpm-only-lint
                ];
              }
              ''
                export HOME="$TMPDIR"
                cp -r ${self} source
                chmod -R u+w source
                git init --quiet source
                git -C source add --all --force
                pnpm-only-lint source
                touch "$out"
              '';

          # The composite actions of gate.yml, against fake `nix`, `mix` and
          # `docker`.
          mix-audit = actionTest pkgs "mix-audit" [ pkgs.git ];
          docker-pull = actionTest pkgs "docker-pull" [ ];

          # The development shell puts no package manager other than pnpm on
          # its PATH. The check builds the PATH from the shell's packages; it
          # does not run the `shellHook`, which the CI step reads from the real
          # shell (ci.yml).
          dev-shell-path = toolchain.lib.devShellPathCheck pkgs (devShellFor pkgs);

          # The root, toolchain and docs-kit lock files lock the same inputs,
          # and the comparison has its own cases (nix/lock-sync.nix).
          lock-sync = import ./nix/lock-sync.nix {
            inherit pkgs;
            root = self;
          };

          # The hook configuration is valid.
          lefthook-validate = import ./nix/lefthook-validate.nix {
            inherit pkgs;
            config = ./lefthook.yml;
          };

          # The pre-commit hook does not silently do nothing: a missing
          # lefthook fails the commit, and a refused installation is reported.
          lefthook-hook = import ./nix/lefthook-hook-tests.nix {
            inherit pkgs;
            config = ./lefthook.yml;
            inherit (devShellFor pkgs) shellHook;
          };

          # scripts/check.sh runs the right commands and fails when one of
          # them fails.
          check-script = import ./nix/check-script-tests.nix {
            inherit pkgs;
            script = ./scripts/check.sh;
          };

          # The CI step that looks the package managers up in the real
          # development shell ignores the PATH of the host, and fails when it
          # cannot get the list of commands or the PATH.
          ci-dev-shell-path-step = import ./nix/ci-dev-shell-path-step-tests.nix {
            inherit pkgs;
            workflow = ./.github/workflows/ci.yml;
            stepName = "Check that the development shell has no other package manager";
          };

          # The job token stays off the disk and out of every step except the
          # one that fetches the flake inputs of ci.yml. gate.yml gives it to
          # no step.
          ci-nix-token = import ./nix/ci-nix-token-tests.nix {
            inherit pkgs;
            workflow = ./.github/workflows/ci.yml;
            gateWorkflow = ./.github/workflows/gate.yml;
          };

          # The `ci` status keeps its structure: the concurrency groups, the
          # three-system matrix that does not stop at the first failure, and
          # an aggregator that runs always and fails on any result but
          # success or skipped.
          ci-structure = import ./nix/ci-structure-tests.nix {
            inherit pkgs;
            workflow = ./.github/workflows/ci.yml;
          };

          # The shell steps of docs.yml and links.yml, run with fake programs.
          docs-workflow-steps = import ./nix/docs-workflow-steps.nix {
            inherit pkgs;
            root = self;
          };
        }
        # The cases of the repository's own lints (lints/checks.nix): each lint
        # runs on small trees with hand-written expected results.
        // lib.mapAttrs' (name: lib.nameValuePair "lints-${name}") (import ./lints/checks.nix pkgs)
        # The subflakes' own checks; a root check does not run them otherwise.
        // lib.mapAttrs' (name: lib.nameValuePair "toolchain-${name}") toolchain.checks.${system}
        # The kit has no check of its own documents: they link to pages outside
        # its flake source, so the root `docs` check above reads them.
        // lib.mapAttrs' (name: lib.nameValuePair "docs-kit-${name}") docs-kit.checks.${system}
      );
    };
}
