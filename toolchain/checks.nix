# The toolchain's own checks, for one system. `nix flake check` in this
# directory builds them.
#
# Arguments (an attribute set):
#   pkgs               the nixpkgs package set of the system;
#   toolchain          the toolchain's packages for the system (packages.nix);
#   versions           the exported version line (`lib.versions`);
#   pnpmOnlyLint       the pnpm-only lint package;
#   devShell           the toolchain's development shell;
#   devShellPathCheck  the exported check builder (`lib.devShellPathCheck`);
#   treefmt-nix        the treefmt-nix flake;
#   elixirModule       the treefmt module that formats Elixir
#                      (treefmt-elixir.nix).
# Returns: an attribute set of check derivations.
{
  pkgs,
  toolchain,
  versions,
  pnpmOnlyLint,
  devShell,
  devShellPathCheck,
  treefmt-nix,
  elixirModule,
}:
let
  inherit (pkgs) lib;

  # The version policy functions (version-policy.nix).
  versionPolicy = import ./version-policy.nix { inherit lib; };

  # The findings of the version-line check; empty when the toolchain
  # complies with versions.nix.
  versionFindings = versionPolicy.findings {
    policy = import ./versions.nix;
    actual = lib.mapAttrs (_: package: package.version) toolchain;
    exported = versions;
  };

  # Runs `script` in a build; it fails the check by exiting non-zero.
  check =
    name: inputs: script:
    pkgs.runCommandLocal name { nativeBuildInputs = inputs; } ''
      ${script}
      touch "$out"
    '';

  # A treefmt evaluation with only the Elixir module, for the `mix-format`
  # check. `.formatter.exs` marks the project root.
  elixirTreefmt = treefmt-nix.lib.evalModule pkgs {
    imports = [ elixirModule ];
    projectRootFile = ".formatter.exs";
  };

  # The reasons why the `pnpm` package does not keep what a consumer of
  # nixpkgs' `pnpm_12` relies on; empty when it does. The package must carry
  # exactly the `passthru` attributes of `pnpm_12`, and it must build locally
  # (it only links, so no remote builder should run it).
  pnpmProblems =
    lib.optional (
      lib.attrNames toolchain.pnpm.passthru != lib.attrNames pkgs.pnpm_12.passthru
    ) "the pnpm package does not have the passthru attributes of pnpm_12"
    ++ lib.optional (
      !(toolchain.pnpm.preferLocalBuild or false)
    ) "the pnpm package is not built locally";
in
{
  # Every tool is inside its series of versions.nix, and the version line is
  # the same on every system.
  version-line = check "version-line" [ ] (
    if versionFindings == [ ] then
      ""
    else
      ''
        printf '%s\n' ${lib.escapeShellArgs versionFindings} >&2
        exit 1
      ''
  );

  # The policy functions give the right answer for a table of cases and for a
  # grid of small versions (tests/version-policy.nix).
  version-policy = import ./tests/version-policy.nix { inherit pkgs versionPolicy; };

  # The pnpm-only lint gives the expected status and output for each case of
  # tests/pnpm-only.nix.
  pnpm-only-lint = import ./tests/pnpm-only.nix { inherit pkgs pnpmOnlyLint; };

  # The toolchain's own development shell provides no other package manager.
  dev-shell-path = devShellPathCheck pkgs devShell;

  # The PATH check finds a forbidden command however a shell gets it
  # (tests/dev-shell-path.nix).
  dev-shell-path-cases = import ./tests/dev-shell-path.nix { inherit pkgs devShellPathCheck; };

  # Hex is part of the development shell. The check runs `mix hex.info` with
  # the programs of the shell and an empty MIX_HOME: without Hex in the shell,
  # Mix cannot find the task `hex.info` and would try to download Hex, which
  # the build sandbox forbids.
  hex = check "hex-in-dev-shell" devShell.nativeBuildInputs ''
    export HOME="$TMPDIR"
    export MIX_HOME="$TMPDIR/mix"
    mix hex.info
  '';

  # The `pnpm` package keeps the `passthru` of `pnpm_12` and builds locally
  # (`pnpmProblems`).
  pnpm-package = check "pnpm-package" [ ] (
    lib.optionalString (pnpmProblems != [ ]) ''
      printf '%s\n' ${lib.escapeShellArgs pnpmProblems} >&2
      exit 1
    ''
  );

  # The Elixir module formats with the toolchain's Elixir: it rewrites
  # input.ex into expected.ex.
  mix-format = check "mix-format" [ elixirTreefmt.config.build.wrapper ] ''
    export HOME="$TMPDIR"
    cp -R ${./tests/mix-format} "$TMPDIR/work"
    chmod -R u+w "$TMPDIR/work"
    cd "$TMPDIR/work"
    treefmt --no-cache
    diff -u expected.ex input.ex
    ${lib.optionalString
      (elixirTreefmt.config.programs.mix-format.package.drvPath != toolchain.elixir.drvPath)
      ''
        echo "the mix-format module does not use the toolchain's Elixir" >&2
        exit 1
      ''
    }
  '';
}
