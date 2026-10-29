# Tests that the CI workflow (.github/workflows/ci.yml) and the reusable gate
# workflow (.github/workflows/gate.yml) keep the job token away from the
# scripts of the checked tree.
#
# `nixbuild/nix-quick-install-action` writes its `github_access_token` input
# (default: the job token) to `~/.netrc` and the Nix configuration, where
# every later step can read it. Each workflow therefore sets the input to an
# empty string on every install step. The CI workflow gives the token to one
# step only, the step that fetches the flake inputs, through the environment
# of that step. The gate workflow names the token nowhere.
#
# The test reads the workflows with yq and compares facts with values written
# by hand. For the CI workflow: the input of the install step, the names of the
# steps whose environment names the job token, and the environment of the
# workflow and of the job. For the gate workflow: the input of every install
# step (whatever their number, and at least one exists), and every string of
# the file at any depth, which must not name the job token. The scan matches
# the forms `github.token`, `github['token']`, `github["token"]`,
# `secrets.GITHUB_TOKEN` and `toJSON(github)`, which holds the token. Cases
# on small texts show that the scan finds each form and ignores the others
# that the workflows use. It does not test Nix or the action.
#
# Arguments (an attribute set):
#   `pkgs`: the nixpkgs package set.
#   `workflow`: the path of the CI workflow file.
#   `gateWorkflow`: the path of the gate workflow file.
# Returns: a derivation that builds when both workflows keep the token off the
#   disk and out of every other step.
{
  pkgs,
  workflow,
  gateWorkflow,
}:
let
  # The yq expression that lists every string of a YAML file, at any depth,
  # that names the job token. It is one text for the scan of the gate and for
  # the cases of the scan, so a case tests the expression that the gate uses.
  # The pattern is a Go regular expression, and it ignores case, as GitHub
  # expressions do. It uses the classes `[.]`, `[[]` and `[(]` for a literal
  # character, so that no backslash escape depends on the quoting of Nix, the
  # shell and yq.
  #   github.token, secrets.GITHUB_TOKEN: the two direct forms;
  #   github[...token...]: `github['token']` and `github["token"]`;
  #   toJSON(github): the whole context, which holds the token.
  tokenScan = ''.. | select(tag == "!!str") | select(test("(?i)github[.]token|github[[][^]]*token|secrets[.]github_token|tojson[(] *github *[)]"))'';
in
pkgs.runCommandLocal "ci-nix-token"
  {
    nativeBuildInputs = [
      pkgs.diffutils
      pkgs.yq-go
    ];
  }
  ''
    export HOME="$TMPDIR"

    # Prints the result of a yq expression on a workflow file as one line of
    # JSON and compares it with the expected text.
    #   $1: the case name, $2: the workflow file, $3: the yq expression,
    #   $4: the expected JSON.
    expect() {
      local name="$1" file="$2" expression="$3" expected="$4"
      yq -o=json -I=0 "$expression" "$file" >actual.json
      echo "$expected" >expected.json
      if ! diff -u expected.json actual.json >diff.txt; then
        echo "FAIL $name" >&2
        cat diff.txt >&2
        exit 1
      fi
    }

    expect "the install step passes an empty token to the action" ${workflow} \
      '.jobs.check.steps[] | select(.name == "Install Nix") | .with.github_access_token' \
      '""'

    expect "only the fetch step names the job token" ${workflow} \
      '[.jobs.check.steps[] | select((.env // {}) | to_entries | map(.value) | join(" ") | test("github[.]token")) | .name]' \
      '["Fetch the flake inputs"]'

    expect "the workflow and the job set no environment" ${workflow} \
      '[.env, .jobs.check.env]' \
      '[null,null]'

    expect "the gate has an install step" ${gateWorkflow} \
      '[.jobs[].steps[] | select((.uses // "") | test("^nixbuild/nix-quick-install-action@"))] | length > 0' \
      'true'

    expect "no install step of the gate passes a token to the action" ${gateWorkflow} \
      '[.jobs[] as $job | $job.steps[] | select((.uses // "") | test("^nixbuild/nix-quick-install-action@")) | select(.with.github_access_token != "") | $job.name + ": " + .name]' \
      '[]'

    # Any string of the gate, at any depth (environment of the workflow, of a
    # job or of a step, step inputs, scripts), that names the job token.
    expect "nothing in the gate names the job token" ${gateWorkflow} \
      '[${tokenScan}]' \
      '[]'

    # Prints the number of strings that the token scan finds in the YAML text
    # on the standard input and compares it with the expected number.
    #   $1: the case name, $2: the expected number.
    expect_scan_count() {
      cat >scan-input.yml
      expect "$1" scan-input.yml '[${tokenScan}] | length' "$2"
    }

    expect_scan_count "the scan finds github.token" 1 <<'EOF'
    run: echo ''${{ github.token }}
    EOF
    expect_scan_count "the scan finds secrets.GITHUB_TOKEN" 1 <<'EOF'
    run: echo ''${{ secrets.GITHUB_TOKEN }}
    EOF
    expect_scan_count "the scan finds a bracket lookup with single quotes" 1 <<'EOF'
    run: echo ''${{ github['token'] }}
    EOF
    expect_scan_count "the scan finds a bracket lookup with double quotes" 1 <<'EOF'
    run: echo ''${{ github["token"] }}
    EOF
    expect_scan_count "the scan finds the whole github context" 1 <<'EOF'
    run: echo ''${{ toJSON(github) }}
    EOF
    expect_scan_count "the scan finds the whole context in another spelling" 1 <<'EOF'
    run: echo ''${{ tojson( github ) }}
    EOF
    expect_scan_count "the scan ignores other contexts and other github keys" 0 <<'EOF'
    run: echo ''${{ github.sha }} ''${{ github['sha'] }} ''${{ toJSON(needs) }} ''${{ secrets.OTHER }}
    EOF

    touch "$out"
  ''
