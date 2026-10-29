# The docs kit of the organization: Vale with the Sealambda prose style,
# markdownlint-cli2 with a base configuration, lychee for links, and templates
# and guides for documents. A repository consumes a tag of it:
#
#   inputs.docs-kit.url = "github:sealambda/.github?dir=docs-kit&ref=docs-kit-vN";
#   inputs.docs-kit.inputs.toolchain.follows = "toolchain";
#
# README.md describes every output.
{
  description = "The Sealambda docs kit: prose, Markdown and link checks, with templates";

  # The toolchain flake of the same repository fixes nixpkgs, so that the
  # organization has one pin of it. `path:../toolchain` is relative to this
  # flake in the same Git tree, and so it follows the tag of the kit.
  inputs = {
    toolchain.url = "path:../toolchain";
    nixpkgs.follows = "toolchain/nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      toolchain,
    }:
    let
      inherit (nixpkgs) lib;

      # Builds an attribute set with one entry for each system of the toolchain
      # (`toolchain.lib.systems`).
      # Argument: a function from the package set of a system to the entry.
      eachSystem =
        mkOutput: lib.genAttrs toolchain.lib.systems (system: mkOutput nixpkgs.legacyPackages.${system});

      # The programs and files of the kit for one system.
      # Argument: the package set of the system.
      # Returns: the attribute set that kit.nix describes.
      kitFor = pkgs: import ./kit.nix { inherit pkgs; };

      # Runs the docs check on `src`, a directory in the Nix store, in the
      # build sandbox. It needs no network, so lychee runs offline. `src` holds
      # every file that a document links to.
      mkCheck =
        pkgs: src:
        pkgs.runCommandLocal "docs-check" {
          nativeBuildInputs = [ self.packages.${pkgs.stdenv.hostPlatform.system}.docs-check ];
        } ''docs-check ${src} && touch "$out"'';
    in
    {
      packages = eachSystem (
        pkgs:
        let
          kit = kitFor pkgs;
        in
        {
          docs-check = kit.docsCheck;
          default = kit.docsCheck;
          # `Sealambda.zip`, the Vale package, for a release.
          vale-package = kit.valePackage;
        }
      );

      # `nix run …#check -- <directory>`: Vale, markdownlint-cli2 and lychee
      # (offline) on the Markdown files of the directory (default: the
      # current directory).
      apps = eachSystem (pkgs: {
        check = {
          type = "app";
          program = lib.getExe (kitFor pkgs).docsCheck;
          meta.description = "Check the prose, the structure and the local links of Markdown documents";
        };
      });

      lib = {
        # Builds a check that runs the docs check on a store path:
        # `docs-kit.lib.mkCheck pkgs ./.`.
        inherit mkCheck;

        # The treefmt-nix module with markdownlint-cli2 and the base.
        treefmtModules.default = ./treefmt.nix;

        # The configuration files, for a tool that reads them directly.
        markdownlintConfig = ./base.markdownlint.yaml;
        lycheeConfig = ./lychee.toml;
      };

      checks = eachSystem (
        pkgs:
        import ./checks.nix {
          inherit pkgs;
          kit = kitFor pkgs;
        }
      );
    };
}
