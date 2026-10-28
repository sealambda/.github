# Tests the structure of the CI workflow (.github/workflows/ci.yml) that
# the `ci` status relies on, so that nobody weakens it without a red check.
#
# - `concurrency`: one group per pull request, cancelling the older run, and
#   one group per commit on main, never cancelling.
# - `check.strategy`: every system runs, even when one fails, on the three
#   runner labels of the toolchain's systems.
# - `ci`: needs every other job of the workflow, runs always (a skipped
#   required status counts as passed), and fails on any result other than
#   success or skipped.
#
# The test reads the workflow with yq and compares each fact with a value
# written by hand. It does not run the workflow or evaluate its expressions.
#
# Arguments (an attribute set):
#   `pkgs`: the nixpkgs package set.
#   `workflow`: the path of the workflow file.
# Returns: a derivation that builds when the workflow has the structure above.
{ pkgs, workflow }:
pkgs.runCommandLocal "ci-structure"
  {
    nativeBuildInputs = [
      pkgs.diffutils
      pkgs.yq-go
    ];
  }
  ''
    export HOME="$TMPDIR"

    # Compares the result of a yq expression with the expected text, which is
    # read from the standard input. Fails with the difference.
    #   $1: the case name, $2: the yq flags, $3: the yq expression.
    compare() {
      local name="$1" flags="$2" expression="$3"
      # $flags is deliberately unquoted: it holds at most two options.
      # shellcheck disable=SC2086
      yq $flags "$expression" ${workflow} >actual.txt
      cat >expected.txt
      if ! diff -u expected.txt actual.txt >diff.txt; then
        echo "FAIL $name" >&2
        cat diff.txt >&2
        exit 1
      fi
    }

    # A fact as one line of JSON. The expected line is the standard input.
    expect_json() {
      compare "$1" "-o=json -I=0" "$2"
    }

    # A scalar as plain text. The expected text is the standard input.
    expect_text() {
      compare "$1" "" "$2"
    }

    expect_json "a pull request has one group that a newer push cancels" \
      '.concurrency' <<'EOF'
    {"group":"ci-''${{ github.event.pull_request.number || github.sha }}","cancel-in-progress":"''${{ github.event_name == 'pull_request' }}"}
    EOF

    expect_json "every system runs, on the three runner labels" \
      '.jobs.check.strategy' <<'EOF'
    {"fail-fast":false,"matrix":{"os":["ubuntu-24.04","ubuntu-24.04-arm","macos-15"]}}
    EOF

    # The aggregator waits for every other job, so a job added later cannot
    # escape the `ci` status. The expected list is the workflow's own job ids
    # without `ci`, so this test needs no change when a job is added.
    expect_json "the aggregator needs every job but itself" \
      '.jobs.ci.needs | sort' <<EOF
    $(yq -o=json -I=0 '.jobs | keys | map(select(. != "ci")) | sort' ${workflow})
    EOF

    expect_text "the aggregator runs after a failure or a cancellation" \
      '.jobs.ci.if' <<'EOF'
    ''${{ always() }}
    EOF

    expect_text "the aggregator has one step, which fails on any other result" \
      '.jobs.ci.steps[].run' <<'EOF'
    jq -r 'to_entries[] | "\(.key): \(.value.result)"' <<<"''${NEEDS}"
    jq -e 'all(.[]; .result == "success" or .result == "skipped")' <<<"''${NEEDS}" >/dev/null

    EOF

    touch "$out"
  ''
