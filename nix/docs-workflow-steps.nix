# Builds a check of the shell steps in the workflows docs.yml and links.yml.
#
# The workflow files run only on GitHub, so nothing else tests the shell in
# their `run:` blocks. The check reads each step with yq, runs it with fake
# programs (`nix`, `docs-check`, `gh`) and compares the arguments, the output
# and the exit status with values written by hand in
# docs-workflow-steps-test.sh, which holds the cases.
#
# Arguments (an attribute set): `pkgs`, and `root`, the repository's source.
# Returns: a derivation that builds when every case passes.
{ pkgs, root }:
pkgs.runCommandLocal "docs-workflow-steps"
  {
    nativeBuildInputs = [
      pkgs.jq
      pkgs.yq-go
    ];
  }
  ''
    ${pkgs.bash}/bin/bash ${./docs-workflow-steps-test.sh} ${root}/.github/workflows
    touch "$out"
  ''
