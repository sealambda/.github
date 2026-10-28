# The organization's toolchain: one version line of the tools that every
# repository builds with, the organization's formatters and linters, and the
# pnpm-only lint. A repository consumes a tag of it:
#
#   inputs.toolchain.url = "github:sealambda/.github?dir=toolchain&ref=toolchain-vN";
#   inputs.nixpkgs.follows = "toolchain/nixpkgs";
#
# README.md describes every output.
{
  description = "The Sealambda toolchain: versioned tools, formatters and linters";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      treefmt-nix,
    }:
    let
      inherit (nixpkgs) lib;

      # Apple silicon Macs and Linux. nixpkgs dropped x86_64-darwin after
      # 26.05. Exported as `lib.systems`, so that a consumer flake uses this
      # list instead of deriving one from the attribute names of an output.
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      # Calls `mkOutput pkgs` for every system, as an attribute set.
      eachSystem = mkOutput: lib.genAttrs systems (system: mkOutput nixpkgs.legacyPackages.${system});

      # The toolchain's packages for one system.
      packagesFor = system: import ./packages.nix nixpkgs.legacyPackages.${system};

      # The package managers that the repository does not use: the names of
      # their commands, files and directories (package-managers.nix).
      packageManagers = import ./package-managers.nix;

      # The pnpm-only lint for one package set: the script with the programs it
      # calls (pnpm-only-lint.sh).
      pnpmOnlyLintFor =
        pkgs:
        pkgs.writeShellApplication {
          name = "pnpm-only-lint";
          runtimeInputs = [
            pkgs.git
            pkgs.jq
          ];
          # The one list of package managers (package-managers.nix), as the
          # two Bash arrays that the script reads.
          runtimeEnv = {
            FOREIGN_FILE_PATTERNS = packageManagers.files;
            FOREIGN_DIRECTORY_NAMES = packageManagers.directories;
          };
          text = builtins.readFile ./pnpm-only-lint.sh;
        };

      # The development shell for one package set: every tool of
      # `packagesFor`.
      devShellFor =
        pkgs:
        pkgs.mkShellNoCC {
          name = "toolchain";
          packages = lib.attrValues (packagesFor pkgs.stdenv.hostPlatform.system);
        };
    in
    {
      # The toolchain's tools, and the pnpm-only lint
      # (`nix run …#pnpm-only-lint`).
      packages = eachSystem (
        pkgs:
        packagesFor pkgs.stdenv.hostPlatform.system
        // {
          pnpm-only-lint = pnpmOnlyLintFor pkgs;
        }
      );

      # A shell with the toolchain's tools. A repository adds it to its own
      # shell with `inputsFrom`.
      devShells = eachSystem (pkgs: {
        default = devShellFor pkgs;
      });

      lib = {
        # The systems that every output supports.
        inherit systems;

        # The version line: the exact version of each tool, as the locked
        # nixpkgs builds it for x86_64-linux, the system of CI and of
        # production. The `version-line` check holds every system to it.
        versions = lib.mapAttrs (_: package: package.version) (packagesFor "x86_64-linux");

        # treefmt-nix modules (`treefmt-nix.lib.evalModule pkgs { imports = [ … ]; }`).
        # `lib` holds them because Nix warns about an unknown flake output.
        treefmtModules = {
          default = ./treefmt.nix;
          elixir = import ./treefmt-elixir.nix { inherit packagesFor; };
        };

        # Builds a check that fails when a development shell provides a
        # package manager other than pnpm (dev-shell-path-check.nix).
        devShellPathCheck = import ./dev-shell-path-check.nix;
      };

      checks = eachSystem (
        pkgs:
        import ./checks.nix {
          inherit pkgs treefmt-nix;
          toolchain = packagesFor pkgs.stdenv.hostPlatform.system;
          inherit (self.lib) versions devShellPathCheck;
          pnpmOnlyLint = pnpmOnlyLintFor pkgs;
          devShell = devShellFor pkgs;
          elixirModule = self.lib.treefmtModules.elixir;
        }
      );
    };
}
