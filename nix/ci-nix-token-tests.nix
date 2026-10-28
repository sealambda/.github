# Tests that the `check` job of the CI workflow (.github/workflows/ci.yml)
# keeps the job token away from the scripts of the checked tree.
#
# `nixbuild/nix-quick-install-action` writes its `github_access_token` input
# (default: the job token) to `~/.netrc` and the Nix configuration, where
# every later step can read it. The workflow therefore sets the input to an
# empty string and gives the token to one step only, the step that fetches
# the flake inputs, through the environment of that step.
#
# The test reads the workflow with yq and compares three facts with values
# written by hand: the input of the install step, the names of the steps whose
# environment names the job token, and the environment of the workflow and of
# the job. It does not test Nix or the action.
#
# Arguments (an attribute set):
#   `pkgs`: the nixpkgs package set.
#   `workflow`: the path of the workflow file.
# Returns: a derivation that builds when the workflow keeps the token off the
#   disk and out of every other step.
{ pkgs, workflow }:
pkgs.runCommandLocal "ci-nix-token"
  {
    nativeBuildInputs = [
      pkgs.diffutils
      pkgs.yq-go
    ];
  }
  ''
    export HOME="$TMPDIR"

    # Prints the result of a yq expression as one line of JSON and compares
    # it with the expected text.
    #   $1: the case name, $2: the yq expression, $3: the expected JSON.
    expect() {
      local name="$1" expression="$2" expected="$3"
      yq -o=json -I=0 "$expression" ${workflow} >actual.json
      echo "$expected" >expected.json
      if ! diff -u expected.json actual.json >diff.txt; then
        echo "FAIL $name" >&2
        cat diff.txt >&2
        exit 1
      fi
    }

    expect "the install step passes an empty token to the action" \
      '.jobs.check.steps[] | select(.name == "Install Nix") | .with.github_access_token' \
      '""'

    expect "only the fetch step names the job token" \
      '[.jobs.check.steps[] | select((.env // {}) | to_entries | map(.value) | join(" ") | test("github[.]token")) | .name]' \
      '["Fetch the flake inputs"]'

    expect "the workflow and the job set no environment" \
      '[.env, .jobs.check.env]' \
      '[null,null]'

    touch "$out"
  ''
