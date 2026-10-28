# Cases of the development-shell PATH check (dev-shell-path-check.nix).
#
# Each case builds a shell with `mkShellNoCC`, from fake packages that install
# a command with a forbidden name, and applies the check to it. The names are
# written out here and never read from package-managers.nix, so a missing name
# in that list fails a case.
#
# A case that must fail uses `testBuildFailure'`: the check must fail with
# exit status 1 and print the finding for the command.
#
# Arguments (an attribute set):
#   pkgs               the nixpkgs package set of the system;
#   devShellPathCheck  the check builder (dev-shell-path-check.nix).
# Returns: a derivation that builds when every case behaves as expected.
{ pkgs, devShellPathCheck }:
let
  inherit (pkgs) lib;

  # Every name that the check must find, as the contract lists them.
  forbiddenNames = [
    "bun"
    "bunx"
    "corepack"
    "npm"
    "npx"
    "pnpx"
    "pnx"
    "yarn"
    "yarnpkg"
  ];

  # A package with a command of this name in `bin/`.
  fakeCommand = name: pkgs.writeShellScriptBin name "exit 0";

  # A package whose command is in its `bin` output, not in its default one,
  # as in a package with separate outputs. A shell that lists this package
  # gets the `dev` output, which propagates the others, so `bin` reaches PATH.
  fakeCommandInBinOutput =
    name:
    pkgs.stdenvNoCC.mkDerivation {
      name = "fake-${name}-split";
      outputs = [
        "out"
        "bin"
        "dev"
      ];
      dontUnpack = true;
      installPhase = ''
        mkdir -p "$out" "$dev" "$bin/bin"
        printf '#!/bin/sh\nexit 0\n' > "$bin/bin/${name}"
        chmod +x "$bin/bin/${name}"
      '';
    };

  # A package without commands that propagates another package, as a library
  # propagates its dependencies. The fixup phase of stdenv records the
  # propagation, so this uses `mkDerivation`.
  propagating =
    package:
    pkgs.stdenvNoCC.mkDerivation {
      name = "propagating-${package.name}";
      propagatedBuildInputs = [ package ];
      dontUnpack = true;
      installPhase = ''
        mkdir -p "$out"
      '';
    };

  # The package that provides the forbidden command `npm`, which most cases
  # put into a shell in a different way.
  npm = fakeCommand "npm";

  # A shell is clean when none of its commands has a forbidden name.
  cleanShell = pkgs.mkShellNoCC {
    name = "clean";
    packages = [ (fakeCommand "pnpm") ];
  };

  # The cases that must fail: the shell, and the command that the finding
  # names.
  failing = {
    direct-package = {
      shell = pkgs.mkShellNoCC {
        name = "direct";
        packages = [ npm ];
      };
      found = "npm";
    };
    build-inputs = {
      shell = pkgs.mkShellNoCC {
        name = "build-inputs";
        buildInputs = [ npm ];
      };
      found = "npm";
    };
    # A command in propagatedBuildInputs is on the PATH of the shell.
    propagated-build-inputs = {
      shell = pkgs.mkShellNoCC {
        name = "propagated";
        propagatedBuildInputs = [ npm ];
      };
      found = "npm";
    };
    propagated-native-build-inputs = {
      shell = pkgs.mkShellNoCC {
        name = "propagated-native";
        propagatedNativeBuildInputs = [ npm ];
      };
      found = "npm";
    };
    # A package brings the command through the propagated inputs of another
    # package.
    transitive-propagation = {
      shell = pkgs.mkShellNoCC {
        name = "transitive";
        packages = [ (propagating npm) ];
      };
      found = "npm";
    };
    # `mkShell` merges the inputs of its `inputsFrom` shells.
    inputs-from = {
      shell = pkgs.mkShellNoCC {
        name = "inputs-from";
        inputsFrom = [
          (pkgs.mkShellNoCC {
            name = "inner";
            propagatedBuildInputs = [ npm ];
          })
        ];
      };
      found = "npm";
    };
    # A command in the `bin` output counts, not only one in the default
    # output.
    bin-output = {
      shell = pkgs.mkShellNoCC {
        name = "bin-output";
        packages = [ (fakeCommandInBinOutput "npm") ];
      };
      found = "npm";
    };
  };

  # The test of one failing case: the check on the case's shell must fail with
  # status 1 and print the finding for the command.
  # Arguments: the case name and the case (`shell` and `found`).
  # Returns: a derivation that builds when the check fails as expected.
  failingDerivation =
    name:
    { shell, found }:
    pkgs.testers.testBuildFailure' {
      name = "dev-shell-path-${name}-fails";
      drv = devShellPathCheck pkgs shell;
      expectedBuilderExitCode = 1;
      expectedBuilderLogEntries = [
        "/bin/${found}: the development shell must not provide ${found}; use pnpm"
      ];
    };

  # One shell that provides every forbidden name: the check must name each.
  everyName = pkgs.testers.testBuildFailure' {
    name = "dev-shell-path-every-name-fails";
    drv = devShellPathCheck pkgs (
      pkgs.mkShellNoCC {
        name = "every-name";
        packages = map fakeCommand forbiddenNames;
      }
    );
    expectedBuilderExitCode = 1;
    expectedBuilderLogEntries = map (
      name: "/bin/${name}: the development shell must not provide ${name}; use pnpm"
    ) forbiddenNames;
  };
in
pkgs.linkFarm "dev-shell-path-cases" (
  [
    {
      name = "clean-shell";
      path = devShellPathCheck pkgs cleanShell;
    }
    {
      name = "every-name";
      path = everyName;
    }
  ]
  ++ lib.mapAttrsToList (name: case: {
    inherit name;
    path = failingDerivation name case;
  }) failing
)
