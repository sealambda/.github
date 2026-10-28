# Builds a check that fails when a development shell puts a JavaScript
# package manager other than pnpm on PATH, or an alias of `pnpm dlx`.
#
# The check gives a build the shell's four lists of inputs, so that stdenv
# builds the PATH of the build as it builds the PATH of `nix develop`: it
# applies propagation, the `bin` output of each package and `inputsFrom` (an
# `mkShell` merges the lists of its `inputsFrom` shells into its own). Then
# `type -P` looks up each forbidden name, so a command is found whatever
# package brings it.
#
# Limit: a `shellHook` can change PATH when the shell starts. This check does
# not run the hook, so it does not see such a change. Only a lookup of the
# names in the real shell sees it; that lookup is a CI step of the repository
# that owns the shell. The step must run `nix develop --ignore-environment`:
# plain `nix develop` keeps the caller's PATH, which finds the commands of the
# host.
#
# Arguments: the nixpkgs package set, and the shell (a mkShell derivation).
# Returns: a derivation that builds when the shell is clean. A command found
# on PATH is printed as `path: message` and fails the build.
pkgs: shell:
let
  inherit (import ./package-managers.nix) commands;
in
pkgs.runCommandLocal "dev-shell-path-${shell.name}"
  {
    inherit (shell)
      nativeBuildInputs
      buildInputs
      propagatedNativeBuildInputs
      propagatedBuildInputs
      ;
  }
  ''
    status=0
    for command in ${pkgs.lib.escapeShellArgs commands}; do
      if found="$(type -P "''${command}")"; then
        echo "''${found}: the development shell must not provide ''${command}; use pnpm"
        status=1
      fi
    done
    if (( status != 0 )); then
      exit "''${status}"
    fi
    touch "$out"
  ''
