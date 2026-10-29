# The organization's own shell lints, as programs. treefmt.nix runs them on
# the tree and checks.nix tests them.
#
# Argument: the nixpkgs package set of one system.
# Returns: an attribute set of derivations.
pkgs: {
  # Fails on a file with a shell shebang and no `.sh` or `.bash` extension
  # (shell-script-names.sh).
  shellScriptNames = pkgs.writeShellApplication {
    name = "shell-script-names";
    text = builtins.readFile ./shell-script-names.sh;
  };

  # Fails on an executable Bash script without strict mode, and on a library
  # that sets shell options (bash-strict-mode.sh).
  bashStrictMode = pkgs.writeShellApplication {
    name = "bash-strict-mode";
    text = builtins.readFile ./bash-strict-mode.sh;
  };
}
