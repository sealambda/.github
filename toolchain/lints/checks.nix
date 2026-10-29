# Tests of the organization's shell lints (default.nix), for one system.
# `nix flake check` builds them.
#
# A case writes a file, runs a lint and compares the exit status and the
# output with values written here by hand. No value is read from a lint or
# from its source, so a lint cannot make its own test pass.
#
# Argument: the nixpkgs package set of one system.
# Returns: an attribute set of check derivations.
pkgs:
let
  inherit (pkgs) lib;

  # The lints under test, built as in treefmt.nix.
  lints = import ./default.nix pkgs;

  # The message of `bash-strict-mode` for a wrong first line and first command.
  shebangMessage = "the first line must be \"#!/usr/bin/env bash\"";
  strictModeMessage = "the first command must be \"set -euo pipefail\"";

  # The message of `shell-script-names`.
  extensionMessage = "a shell script needs the .sh extension, so that the shell formatter and linters read it";

  # Builds a check: runs `script` (test-helpers.sh calls) with `lint` on PATH.
  # The check fails when a case fails.
  mkCheck =
    name: lint: script:
    pkgs.runCommandLocal name { nativeBuildInputs = [ lint ]; } ''
      source ${./test-helpers.sh}
      ${script}
      finish
      touch "$out"
    '';

  # One case of a lint that reads a single file.
  #   name    the case name, for the failure message;
  #   file    the file name that the lint gets;
  #   mode    the file mode for chmod, or "-" to leave the file out;
  #   content the file content;
  #   status  the expected exit status;
  #   output  the expected output, standard output and standard error together.
  fileCase = lintName: c: ''
    run_case ${
      lib.escapeShellArgs [
        lintName
        c.name
        c.file
        c.mode
        c.content
        (toString c.status)
        c.output
      ]
    }
  '';

  # The `run_case` calls of a list of cases, as one shell script.
  fileCases = lintName: cases: lib.concatMapStrings (fileCase lintName) cases;

  # An executable script (mode 755) with the given content that must pass.
  executablePass = name: content: {
    inherit name content;
    file = "script.sh";
    mode = "755";
    status = 0;
    output = "";
  };

  # An executable script that must fail with `message`.
  executableFail = name: content: message: {
    inherit name content;
    file = "script.sh";
    mode = "755";
    status = 1;
    output = "script.sh: ${message}";
  };

  # A library (mode 644) with the given content that must pass.
  libraryPass = name: content: {
    inherit name content;
    file = "lib.sh";
    mode = "644";
    status = 0;
    output = "";
  };

  # A library that must fail because `line` (1-based) sets a shell option.
  libraryFail = name: content: line: {
    inherit name content;
    file = "lib.sh";
    mode = "644";
    status = 1;
    output = "lib.sh: a library must not set shell options, but line ${toString line} does";
  };

  # The cases of `bash-strict-mode`: executable scripts (strict mode, the
  # shebang) and libraries (option lines). Messages and line numbers are
  # written out by hand.
  bashStrictModeCases = [
    # Executable scripts.
    (executablePass "executable with strict mode" "#!/usr/bin/env bash\nset -euo pipefail\n")
    (executablePass "comments and blank lines before strict mode" "#!/usr/bin/env bash\n#\n# Doc.\n\nset -euo pipefail\n")
    (executableFail "strict mode with -E" "#!/usr/bin/env bash\nset -Eeuo pipefail\n" strictModeMessage)
    (executableFail "strict mode split in two options" "#!/usr/bin/env bash\nset -eu -o pipefail\n"
      strictModeMessage
    )
    (executableFail "no strict mode" "#!/usr/bin/env bash\necho hi\n" strictModeMessage)
    (executableFail "strict mode after another command"
      "#!/usr/bin/env bash\necho hi\nset -euo pipefail\n"
      strictModeMessage
    )
    (executableFail "shebang /bin/bash" "#!/bin/bash\nset -euo pipefail\n" shebangMessage)
    (executableFail "empty executable" "" shebangMessage)

    # Libraries: files that are not executable.
    (libraryPass "library with a function" "# shellcheck shell=bash\nfoo() { :; }\n")
    (libraryPass "library with set --" "# shellcheck shell=bash\nset -- a b\n")
    (libraryPass "library with a commented option" "# shellcheck shell=bash\n# set -e\n")
    (libraryPass "library with an indented option in a function" "# shellcheck shell=bash\nfoo() {\n  set -e\n}\n")
    (libraryFail "library with set -e" "# shellcheck shell=bash\nset -e\n" 2)
    (libraryFail "library with strict mode" "set -euo pipefail\n" 1)
    (libraryFail "library with set -o" "# shellcheck shell=bash\n\nset -o errexit\n" 3)
    (libraryFail "library with set +e" "# shellcheck shell=bash\nset +e\n" 2)
    (libraryFail "library with shopt -s" "# shellcheck shell=bash\nshopt -s nullglob\n" 2)
    {
      # Mode 311: the owner may execute but not read the file, so the lint sees
      # an executable script that it cannot read. The case assumes that the
      # build user is not root, because root reads every file; the Nix build
      # sandbox does not run builds as root.
      name = "executable that cannot be read";
      file = "script.sh";
      mode = "311";
      content = "#!/usr/bin/env bash\nset -euo pipefail\n";
      status = 2;
      output = "script.sh: cannot read the file";
    }
    {
      name = "library that cannot be read";
      file = "lib.sh";
      mode = "-";
      content = "";
      status = 2;
      output = "lib.sh: cannot read the file";
    }
  ];

  # The single cases of `shell-script-names`: which names and first lines the
  # lint flags. The grid below covers the shebang forms.
  shellScriptNamesCases = [
    {
      name = "extensionless script with a bash shebang";
      file = "script";
      mode = "755";
      content = "#!/usr/bin/env bash\n";
      status = 1;
      output = "script: ${extensionMessage}";
    }
    {
      name = ".sh file with a shebang";
      file = "script.sh";
      mode = "755";
      content = "#!/usr/bin/env bash\n";
      status = 0;
      output = "";
    }
    {
      name = ".bash file with a shebang";
      file = "script.bash";
      mode = "755";
      content = "#!/usr/bin/env bash\n";
      status = 0;
      output = "";
    }
    {
      name = "extensionless Python script";
      file = "script";
      mode = "755";
      content = "#!/usr/bin/env python3\n";
      status = 0;
      output = "";
    }
    {
      name = "shebang on the second line";
      file = "script";
      mode = "755";
      content = "# header\n#!/bin/bash\n";
      status = 0;
      output = "";
    }
    {
      name = "comment that looks like a shebang";
      file = "script";
      mode = "644";
      content = "# !/bin/bash\n";
      status = 0;
      output = "";
    }
    {
      name = "empty file";
      file = "script";
      mode = "644";
      content = "";
      status = 0;
      output = "";
    }
    {
      name = "shebang with a carriage return";
      file = "script";
      mode = "755";
      content = "#!/usr/bin/env bash\r\n";
      status = 1;
      output = "script: ${extensionMessage}";
    }
    {
      # Mode 311: the owner may execute but not read the file. The case assumes
      # that the build user is not root, as the `bash-strict-mode` case does.
      name = "script that cannot be read";
      file = "script";
      mode = "311";
      content = "#!/usr/bin/env bash\n";
      status = 2;
      output = "script: cannot read the file";
    }
    {
      # `bash` is the argument of `-u`, so `env` has no command to run.
      name = "env option argument named like a shell";
      file = "script";
      mode = "755";
      content = "#!/usr/bin/env -u bash\n";
      status = 0;
      output = "";
    }
    {
      name = "env without a command";
      file = "script";
      mode = "755";
      content = "#!/usr/bin/env\n";
      status = 0;
      output = "";
    }
  ];

  # The grid of shebangs: every form below with every interpreter name. The
  # forms are the ways that a shell shebang is written: a plain
  # directory, `env` with options (some with a separate argument), a Nix store
  # path, a NixOS system path.
  shebangForms = {
    bin = "#!/bin/%s";
    usr-bin = "#!/usr/bin/%s";
    env = "#!/usr/bin/env %s";
    env-S = "#!/usr/bin/env -S %s -e";
    env-i = "#!/usr/bin/env -i %s";
    env-assignment = "#!/usr/bin/env FOO=1 %s";
    env-u = "#!/usr/bin/env -u FOO %s";
    env-unset = "#!/usr/bin/env --unset FOO %s";
    env-C = "#!/usr/bin/env -C /tmp %s";
    env-S-u = "#!/usr/bin/env -S -u FOO %s -e";
    nix-store = "#!/nix/store/0123456789abcdfghijklmnpqrsvwxyz-bash-5.3/bin/%s";
    nixos = "#!/run/current-system/sw/bin/%s";
    spaced = "#! /usr/bin/%s -x";
  };

  # The shells that the lint must recognize.
  shellNames = [
    "sh"
    "bash"
    "dash"
    "ksh"
    "zsh"
  ];

  # The interpreters that the lint must not flag: other languages, and names
  # that only start like a shell.
  otherNames = [
    "python3"
    "perl"
    "node"
    "fish"
    "bashful"
    "sh2"
  ];

  # Every form with every name, as `{ form, name, path }`; `path` is the file
  # that the grid script writes.
  shebangCells = map (cell: cell // { path = "grid/${cell.form}_${cell.name}"; }) (
    lib.cartesianProduct {
      form = lib.attrNames shebangForms;
      name = shellNames ++ otherNames;
    }
  );

  # The paths that the lint must flag: the cells whose interpreter is a shell.
  # The oracle is the list of shell names, not the lint's pattern.
  flaggedPaths = map (cell: cell.path) (
    lib.filter (cell: lib.elem cell.name shellNames) shebangCells
  );

  # Guards the grid against a mistake that would make the case vacuous:
  # 13 forms times 5 shells.
  checkedFlaggedPaths =
    assert lib.length flaggedPaths == 65;
    flaggedPaths;

  # The shell script that writes one file per cell (first line: the shebang),
  # then runs the lint on all of them and compares the flagged files.
  shebangGridScript = ''
    mkdir grid
    ${lib.concatMapStrings (cell: ''
      printf '%s\n' ${
        lib.escapeShellArg (builtins.replaceStrings [ "%s" ] [ cell.name ] shebangForms.${cell.form})
      } >${lib.escapeShellArg cell.path}
    '') shebangCells}
    run_set_case shell-script-names "shebang grid" ${lib.escapeShellArgs checkedFlaggedPaths}
  '';
in
{
  # `bash-strict-mode` accepts only the literal strict-mode line in an
  # executable script and rejects option lines in a library.
  bash-strict-mode = mkCheck "bash-strict-mode-cases" lints.bashStrictMode (
    fileCases "bash-strict-mode" bashStrictModeCases
  );

  # `shell-script-names` flags the shell shebang forms of the grid.
  shell-script-names = mkCheck "shell-script-names-cases" lints.shellScriptNames (
    fileCases "shell-script-names" shellScriptNamesCases + shebangGridScript
  );
}
