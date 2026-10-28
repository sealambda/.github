# This repository's own lints, as programs. treefmt.nix runs them on the tree
# and checks.nix tests them. They follow the layout of toolchain/lints/.
#
# Argument: the nixpkgs package set of one system.
# Returns: an attribute set of derivations.
pkgs: {
  # Fails on an absolute link into this repository whose path is not in the
  # tree (self-links.sh).
  selfLinks = pkgs.writeShellApplication {
    name = "self-links";
    runtimeInputs = [ pkgs.gnugrep ];
    text = builtins.readFile ./self-links.sh;
  };

  # Fails when a document does not quote the name of the security form
  # (security-form-name.sh).
  securityFormName = pkgs.writeShellApplication {
    name = "security-form-name";
    runtimeInputs = [
      pkgs.gnugrep
      pkgs.gnused
    ];
    text = builtins.readFile ./security-form-name.sh;
  };
}
