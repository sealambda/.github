# Tests the two ways in which the pre-commit hook could silently do nothing,
# in throwaway Git repositories that the build creates.
#
#   1. The hook that `lefthook install` writes cannot find lefthook: the Nix
#      store path baked into it is gone, and lefthook is not on PATH. With
#      `assert_lefthook_installed: true` in lefthook.yml, the commit must
#      fail. Without it, lefthook prints a message and the commit passes with
#      no check.
#   2. `lefthook install` refuses to install (here because `core.hooksPath`
#      is set). The shell hook of the development shell must keep the shell
#      usable and say that the installation failed, with the reason that
#      lefthook printed.
#
# Arguments (an attribute set):
#   `pkgs`: the nixpkgs package set.
#   `config`: the path of lefthook.yml.
#   `shellHook`: the `shellHook` string of the development shell.
# Returns: a derivation that builds when both cases pass.
{
  pkgs,
  config,
  shellHook,
}:
let
  # The shell hook as a file, so that case 2 can run it with Bash inside a
  # test repository.
  shellHookFile = pkgs.writeText "shell-hook.sh" shellHook;
in
pkgs.runCommandLocal "lefthook-hook"
  {
    nativeBuildInputs = [
      pkgs.git
      pkgs.lefthook
    ];
  }
  ''
    export HOME="$TMPDIR"

    # Creates a repository with the real lefthook.yml and two staged files.
    make_repository() {
      rm -rf repository
      git init --quiet repository
      cp ${config} repository/lefthook.yml
      echo content >repository/file.txt
      git -C repository add file.txt lefthook.yml
    }

    # Prints the message and the files given after it, then fails the test.
    fail() {
      echo "FAIL $1" >&2
      shift
      for file in "$@"; do
        echo "--- $file" >&2
        cat "$file" >&2
      done
      exit 1
    }

    # Case 1: the baked store path is gone, and lefthook is not on PATH.
    make_repository
    (cd repository && lefthook install >/dev/null)
    sed -i "s|${pkgs.lefthook}/bin/lefthook|/nonexistent/lefthook|g" repository/.git/hooks/pre-commit
    if grep --quiet ${pkgs.lefthook} repository/.git/hooks/pre-commit; then
      fail "the test did not replace the store path of lefthook in the hook" repository/.git/hooks/pre-commit
    fi
    status=0
    (
      cd repository
      PATH="${pkgs.git}/bin:${pkgs.coreutils}/bin:${pkgs.gnused}/bin" \
        git -c user.name=test -c user.email=test@example.com commit --quiet --message test
    ) >commit.out 2>&1 || status=$?
    if (( status == 0 )); then
      fail "a commit passed although the hook could not find lefthook" commit.out
    fi
    if ! grep --quiet "aborted due to lefthook settings" commit.out; then
      fail "the commit failed for another reason" commit.out
    fi

    # Case 2: lefthook refuses to install.
    make_repository
    git -C repository config core.hooksPath .githooks
    status=0
    (cd repository && bash ${shellHookFile}) >install.out 2>install.err || status=$?
    if (( status != 0 )); then
      fail "the shell hook failed, so the shell would not open" install.out install.err
    fi
    if ! grep --quiet "core.hooksPath" install.out; then
      fail "the shell hook hides the reason that lefthook gives" install.out install.err
    fi
    if ! grep --quiet "lefthook install failed" install.err; then
      fail "the shell hook does not say that the installation failed" install.out install.err
    fi

    touch "$out"
  ''
