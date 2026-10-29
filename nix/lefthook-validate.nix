# Builds a check that fails when lefthook rejects the configuration file:
# invalid YAML, an unknown key, or a value of the wrong type.
#
# `lefthook validate` finds its configuration through the root of a Git
# repository and reports success without reading a file outside one, so the
# build creates an empty repository around a copy of the file. The check also
# requires the message `All good`, so a validation that silently found no
# configuration fails.
#
# Arguments (an attribute set):
#   `pkgs`: the nixpkgs package set.
#   `config`: the path of lefthook.yml.
# Returns: a derivation that builds when the configuration is valid.
{ pkgs, config }:
pkgs.runCommandLocal "lefthook-validate"
  {
    nativeBuildInputs = [
      pkgs.git
      pkgs.lefthook
    ];
  }
  ''
    export HOME="$TMPDIR"
    git init --quiet repository
    cp ${config} repository/lefthook.yml
    cd repository
    lefthook validate | tee ../output
    grep --quiet --fixed-strings "All good" ../output
    touch "$out"
  ''
