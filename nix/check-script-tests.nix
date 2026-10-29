# Tests scripts/check.sh with a fake `nix` that records its arguments, in a
# throwaway Git repository that the test builds.
#
# The cases check what the script itself decides: which flakes it locks, the
# flags it passes, the order of the commands, and that a failure of any
# command or of Git fails the gate. They do not test Nix.
#
# Arguments (an attribute set):
#   `pkgs`: the nixpkgs package set.
#   `script`: the path of scripts/check.sh.
# Returns: a derivation that builds when every case passes.
{ pkgs, script }:
let
  # Stands in for `nix`. It appends its arguments, joined by commas, as one
  # line to the file $NIX_CALLS, and exits 1 when that line is $NIX_FAIL_ON.
  fakeNix = pkgs.writeShellScript "nix" ''
    line="$(IFS=,; echo "$*")"
    echo "$line" >>"$NIX_CALLS"
    if [[ "$line" == "''${NIX_FAIL_ON:-}" ]]; then
      exit 1
    fi
  '';
in
pkgs.runCommandLocal "check-script"
  {
    nativeBuildInputs = [
      pkgs.git
      pkgs.diffutils
    ];
  }
  ''
        export HOME="$TMPDIR"
        mkdir fake-bin
        ln -s ${fakeNix} fake-bin/nix

        # Creates a repository with the script and the flakes named by the
        # arguments, all tracked, and one untracked flake.
        make_repository() {
          rm -rf repository
          mkdir -p repository/scripts
          cp ${script} repository/scripts/check.sh
          touch repository/flake.nix
          for flake in "$@"; do
            mkdir -p "repository/$flake"
            touch "repository/$flake/flake.nix"
          done
          mkdir repository/untracked
          touch repository/untracked/flake.nix
          git -C repository init --quiet
          git -C repository add scripts flake.nix "$@"
        }

        # Runs the script in the repository; sets $status and $NIX_CALLS.
        run_gate() {
          : >calls
          status=0
          (
            cd repository
            PATH="$PWD/../fake-bin:$PATH" NIX_CALLS="$PWD/../calls" bash scripts/check.sh
          ) >output 2>&1 || status=$?
        }

        # Fails the test unless the exit status of the run is $1 ("0", or
        # "nonzero" for any failure) and the calls equal the lines of $2, written
        # out by hand.
        expect() {
          local expected_status="$1"
          local expected_calls="$2"
          local status_ok=false
          if [[ "$expected_status" == nonzero ]]; then
            if ((status != 0)); then status_ok=true; fi
          elif ((status == expected_status)); then
            status_ok=true
          fi
          if [[ "$status_ok" != true ]]; then
            echo "FAIL $case_name: exit status $status, expected $expected_status" >&2
            cat output >&2
            exit 1
          fi
          printf '%s' "$expected_calls" >expected-calls
          if ! diff -u expected-calls calls >&2; then
            echo "FAIL $case_name: unexpected nix calls" >&2
            exit 1
          fi
        }

        case_name="locks every tracked flake in order, then checks the root"
        make_repository toolchain "docs kit" a/b
        run_gate
        expect 0 'flake,lock,--no-update-lock-file,./a/b
    flake,lock,--no-update-lock-file,./docs kit
    flake,lock,--no-update-lock-file,./toolchain
    flake,check,--no-update-lock-file,--print-build-logs
    '

        case_name="a repository with no subflake only checks the root"
        make_repository
        run_gate
        expect 0 'flake,check,--no-update-lock-file,--print-build-logs
    '

        case_name="a stale subflake lock fails the gate before the root check"
        make_repository toolchain "docs kit" a/b
        NIX_FAIL_ON='flake,lock,--no-update-lock-file,./docs kit' run_gate
        expect 1 'flake,lock,--no-update-lock-file,./a/b
    flake,lock,--no-update-lock-file,./docs kit
    '

        case_name="a failing root check fails the gate"
        make_repository toolchain
        NIX_FAIL_ON='flake,check,--no-update-lock-file,--print-build-logs' run_gate
        expect 1 'flake,lock,--no-update-lock-file,./toolchain
    flake,check,--no-update-lock-file,--print-build-logs
    '

        case_name="a Git failure fails the gate with no nix call"
        make_repository toolchain
        echo garbage >repository/.git/index
        run_gate
        expect nonzero ""

        case_name="a directory outside Git fails the gate with no nix call"
        make_repository toolchain
        rm -rf repository/.git
        GIT_CEILING_DIRECTORIES="$PWD" run_gate
        expect nonzero ""

        touch "$out"
  ''
