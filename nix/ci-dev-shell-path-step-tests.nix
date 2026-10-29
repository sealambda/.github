# Tests the CI step that looks the package managers up in the PATH of the real
# development shell (.github/workflows/ci.yml), with a fake `nix`.
#
# The test extracts the `run` text of the step with yq and runs it the way
# GitHub does for `shell: bash`: `bash --noprofile --norc -eo pipefail`. The
# fake `nix` records its arguments. It prints the command names that the test
# gives it for `nix eval`. For `nix develop` it runs the command with the PATH
# that the test gives it, and, like the real command, appends the PATH of the
# caller unless `--ignore-environment` is among the arguments. The cases check
# what the step decides: which PATH it looks in, what it reports, and that a
# failure or an empty answer fails the step. They do not test Nix.
#
# Arguments (an attribute set):
#   `pkgs`: the nixpkgs package set.
#   `workflow`: the path of the workflow file.
#   `stepName`: the `name` of the step.
# Returns: a derivation that builds when every case passes.
{
  pkgs,
  workflow,
  stepName,
}:
let
  # Stands in for `nix`. It appends its arguments, joined by commas, as one
  # line to the file $NIX_CALLS. Environment variables of the test:
  #   NIX_EVAL_FAILS: when not empty, `nix eval` exits 1.
  #   NIX_EVAL_OUTPUT: what `nix eval` prints.
  #   SHELL_PATH: the PATH of the fake development shell.
  #   SHELL_HOOK_OUTPUT: a line that the fake shell hook prints first.
  fakeNix = pkgs.writeShellScript "nix" ''
    line="$(IFS=,; echo "$*")"
    echo "$line" >>"$NIX_CALLS"
    case "$1" in
      eval)
        if [[ -n "''${NIX_EVAL_FAILS:-}" ]]; then
          exit 1
        fi
        printf '%s' "$NIX_EVAL_OUTPUT"
        ;;
      develop)
        ignore_environment=false
        command=()
        for argument in "$@"; do
          if [[ "$argument" == --ignore-environment ]]; then
            ignore_environment=true
          fi
        done
        found_command=false
        for argument in "$@"; do
          if [[ "$found_command" == true ]]; then
            command+=("$argument")
          elif [[ "$argument" == --command ]]; then
            found_command=true
          fi
        done
        if [[ -n "''${SHELL_HOOK_OUTPUT:-}" ]]; then
          echo "$SHELL_HOOK_OUTPUT"
        fi
        if [[ "$ignore_environment" == true ]]; then
          exec env "PATH=$SHELL_PATH" "''${command[@]}"
        fi
        exec env "PATH=$SHELL_PATH:$PATH" "''${command[@]}"
        ;;
    esac
  '';
in
pkgs.runCommandLocal "ci-dev-shell-path-step"
  {
    nativeBuildInputs = [
      pkgs.diffutils
      pkgs.yq-go
    ];
  }
  ''
    export HOME="$TMPDIR"
    export STEP_NAME=${pkgs.lib.escapeShellArg stepName}
    yq '.jobs.check.steps[] | select(.name == strenv(STEP_NAME)) | .run' ${workflow} >step.sh
    if [[ ! -s step.sh ]]; then
      echo "FAIL the workflow has no step named '$STEP_NAME'" >&2
      exit 1
    fi

    mkdir fake-bin host-bin shell-bin
    ln -s ${fakeNix} fake-bin/nix
    # The host (the runner) has npm. The fake shell never has it unless a case
    # says so.
    printf '#!/bin/sh\n' >host-bin/npm
    chmod +x host-bin/npm
    for command in yarn bun; do
      printf '#!/bin/sh\n' >"shell-bin/$command"
      chmod +x "shell-bin/$command"
    done
    mkdir clean-shell-bin
    ln -s ${pkgs.coreutils}/bin/printenv clean-shell-bin/printenv

    # Runs the step. Sets $status, writes the output to `output` and the
    # recorded `nix` calls to `calls`. The variables of the fake `nix` come
    # from the caller's environment. The PATH of the shell is $SHELL_PATH.
    run_step() {
      : >calls
      status=0
      PATH="$PWD/fake-bin:$PWD/host-bin:$PATH" NIX_CALLS="$PWD/calls" \
        bash --noprofile --norc -eo pipefail step.sh >output 2>&1 || status=$?
    }

    # Fails the test unless the exit status of the run is $1 ("0", or
    # "nonzero" for any failure), the output equals $2 and the calls equal
    # $3. Both are written out by hand.
    expect() {
      local expected_status="$1"
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
      printf '%s' "$2" >expected-output
      if ! diff -u expected-output output >&2; then
        echo "FAIL $case_name: unexpected output" >&2
        exit 1
      fi
      printf '%s' "$3" >expected-calls
      if ! diff -u expected-calls calls >&2; then
        echo "FAIL $case_name: unexpected nix calls" >&2
        exit 1
      fi
    }

    eval_call='eval,--raw,--file,toolchain/package-managers.nix,commands,--apply,builtins.concatStringsSep "\n"'
    develop_call='develop,--no-update-lock-file,--ignore-environment,--command,printenv,PATH'
    export NIX_EVAL_OUTPUT=$'bun\nnpm\nyarn'

    case_name="a command on the PATH of the host only passes"
    SHELL_PATH="$PWD/clean-shell-bin" run_step
    expect 0 "" "$eval_call
    $develop_call
    "

    case_name="a command in the shell fails the step and is named"
    SHELL_PATH="$PWD/clean-shell-bin:$PWD/shell-bin" run_step
    expect 1 "$PWD/shell-bin/bun: the development shell must not provide bun
    $PWD/shell-bin/yarn: the development shell must not provide yarn
    " "$eval_call
    $develop_call
    "

    case_name="a line that the shell hook prints is not the PATH"
    SHELL_HOOK_OUTPUT="$PWD/host-bin:" SHELL_PATH="$PWD/clean-shell-bin" run_step
    expect 0 "" "$eval_call
    $develop_call
    "

    case_name="a failing nix eval fails the step before the shell opens"
    NIX_EVAL_FAILS=1 SHELL_PATH="$PWD/clean-shell-bin" run_step
    expect nonzero "" "$eval_call
    "

    case_name="an empty list of commands fails the step"
    NIX_EVAL_OUTPUT="" SHELL_PATH="$PWD/clean-shell-bin" run_step
    expect 1 "The list of commands or the PATH of the shell is empty.
    " "$eval_call
    $develop_call
    "

    touch "$out"
  ''
