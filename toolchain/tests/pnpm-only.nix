# Cases of the pnpm-only lint (pnpm-only-lint.sh), as data.
#
# Each case builds a small tree in the sandbox, runs a command on it and
# compares the exit status and the whole output with literals written here.
# The names of the foreign files are written out in the cases and never read
# from package-managers.nix, so a wrong entry in that list fails a case.
#
# A case is an attribute set:
#   files    attribute set of path to file content, created in the tree
#            (default none);
#   symlinks attribute set of path to link target, created after the files
#            (default none; a target may be missing);
#   git      `null` for a tree without Git, or an attribute set for a work
#            tree: `untracked` lists the paths that are not added to the
#            index, `deleted` lists added paths that the work tree then
#            removes (both default to none);
#   findListing  a list of paths (as `find` prints them, with a leading `./`)
#            that replaces the output of `find`, to fix the order of the
#            listing in a tree without Git (default: the real `find`);
#   command  the command to run, default `pnpm-only-lint .`;
#   exit     the expected exit status;
#   output   the expected output of the command (stdout and stderr), "" if
#            none; or `outputEnd`, the expected end of that output.
#
# The cases that expect status 0 build when the command passes. The others
# use `testBuildFailure'`: the case builds a failing derivation whose exit
# status and log must match.
#
# Arguments (an attribute set):
#   pkgs          the nixpkgs package set of the system;
#   pnpmOnlyLint  the lint package.
# Returns: a derivation that builds when every case behaves as expected.
{ pkgs, pnpmOnlyLint }:
let
  inherit (pkgs) lib;

  # The message of a foreign file or directory, and of a pin field.
  foreign = path: "${path}: remove this; the organization uses pnpm only";
  pinField = path: field: ''${path}: remove the "${field}" field; the toolchain flake pins pnpm'';

  # A tree with only a pnpm project, for the cases that add one file.
  pnpmProject = {
    "package.json" = ''{ "name": "app", "scripts": { "build": "tsc" } }'';
    "pnpm-lock.yaml" = "lockfileVersion: '9.0'\n";
  };

  # The cases, by name. Each name becomes a derivation name, so it uses
  # lower-case letters, digits and hyphens.
  cases = {
    # Foreign files, one case for each name that the contract lists.
    foreign-package-lock = {
      files."package-lock.json" = "{}";
      exit = 1;
      output = foreign "package-lock.json";
    };
    foreign-npm-shrinkwrap = {
      files."npm-shrinkwrap.json" = "{}";
      exit = 1;
      output = foreign "npm-shrinkwrap.json";
    };
    foreign-yarn-lock = {
      files."yarn.lock" = "";
      exit = 1;
      output = foreign "yarn.lock";
    };
    foreign-yarnrc = {
      files.".yarnrc" = "";
      exit = 1;
      output = foreign ".yarnrc";
    };
    foreign-yarnrc-yml = {
      files.".yarnrc.yml" = "";
      exit = 1;
      output = foreign ".yarnrc.yml";
    };
    foreign-pnp-cjs = {
      files.".pnp.cjs" = "";
      exit = 1;
      output = foreign ".pnp.cjs";
    };
    foreign-pnp-loader = {
      files.".pnp.loader.mjs" = "";
      exit = 1;
      output = foreign ".pnp.loader.mjs";
    };
    foreign-bun-lock = {
      files."bun.lock" = "";
      exit = 1;
      output = foreign "bun.lock";
    };
    foreign-bun-lockb = {
      files."bun.lockb" = "";
      exit = 1;
      output = foreign "bun.lockb";
    };
    foreign-bunfig = {
      files."bunfig.toml" = "";
      exit = 1;
      output = foreign "bunfig.toml";
    };
    foreign-nested-file = {
      files = pnpmProject // {
        "apps/web/yarn.lock" = "";
      };
      exit = 1;
      output = foreign "apps/web/yarn.lock";
    };

    # A directory of another package manager is reported once.
    foreign-yarn-directory = {
      files = {
        ".yarn/releases/yarn-4.cjs" = "";
        ".yarn/plugins/plugin.cjs" = "";
      };
      exit = 1;
      output = foreign ".yarn";
    };
    foreign-yarn-directory-in-git = {
      files = {
        ".yarn/releases/yarn-4.cjs" = "";
        ".yarn/plugins/plugin.cjs" = "";
      };
      git = { };
      exit = 1;
      output = foreign ".yarn";
    };
    foreign-nested-yarn-directory = {
      files."apps/web/.yarn/install-state.gz" = "";
      exit = 1;
      output = foreign "apps/web/.yarn";
    };
    # A lock file below a foreign directory is part of the directory: the
    # report names `.yarn` once, not the lock file as well.
    foreign-lock-file-in-yarn-directory = {
      files = {
        ".yarn/a.cjs" = "";
        ".yarn/yarn.lock" = "";
        ".yarn/z.cjs" = "";
      };
      git = { };
      exit = 1;
      output = foreign ".yarn";
    };
    # `find` does not sort. The files of one directory can arrive apart,
    # another finding between them, and the directory is still reported once.
    foreign-directory-listed-out-of-order = {
      files = {
        ".yarn/a.cjs" = "";
        ".yarn/z.cjs" = "";
        "package-lock.json" = "{}";
      };
      findListing = [
        "./.yarn/a.cjs"
        "./package-lock.json"
        "./.yarn/z.cjs"
      ];
      exit = 1;
      output = ''
        ${foreign ".yarn"}
        ${foreign "package-lock.json"}'';
    };

    # The lint keeps the reported names in an associative array. Paths with
    # array and expansion syntax are reported by name and not mistaken for
    # each other.
    foreign-path-with-shell-syntax = {
      files = {
        "a[1]/$(touch hit)/yarn.lock" = "";
        "a[1]/$(touch hit)/package-lock.json" = "";
        ".yarn/b]c" = "";
      };
      # Git lists the paths in byte order.
      git = { };
      exit = 1;
      output = ''
        ${foreign ".yarn"}
        ${foreign "a[1]/$(touch hit)/package-lock.json"}
        ${foreign "a[1]/$(touch hit)/yarn.lock"}'';
    };

    # A path with a non-ASCII character, as Git prints it quoted.
    foreign-non-ascii-path = {
      files."apps/café/package-lock.json" = "{}";
      git = { };
      exit = 1;
      output = foreign "apps/café/package-lock.json";
    };

    # Pin fields in a package.json.
    pin-package-manager = {
      files."package.json" = ''{ "name": "app", "packageManager": "pnpm@12.0.0" }'';
      exit = 1;
      output = pinField "package.json" "packageManager";
    };
    pin-dev-engines = {
      files."package.json" =
        ''{ "name": "app", "devEngines": { "packageManager": { "name": "pnpm" } } }'';
      exit = 1;
      output = pinField "package.json" "devEngines";
    };
    pin-both-fields = {
      files."package.json" = ''{ "packageManager": "pnpm@12.0.0", "devEngines": {} }'';
      exit = 1;
      output = ''
        ${pinField "package.json" "packageManager"}
        ${pinField "package.json" "devEngines"}'';
    };
    pin-nested-package-json = {
      files = pnpmProject // {
        "packages/lib/package.json" = ''{ "packageManager": "yarn@4.0.0" }'';
      };
      exit = 1;
      output = pinField "packages/lib/package.json" "packageManager";
    };

    # A package.json that the lint cannot read stops it with status 2, never
    # with a pass.
    # jq prints its own message first, so the cases compare the end.
    malformed-json-truncated = {
      files."package.json" = ''{ "packageManager": "npm@10", '';
      exit = 2;
      outputEnd = "pnpm-only-lint: cannot check package.json: it is not one JSON object";
    };
    malformed-json-empty = {
      files."package.json" = "";
      exit = 2;
      outputEnd = "pnpm-only-lint: cannot check package.json: it is not one JSON object";
    };
    malformed-json-array = {
      files."package.json" = "[]";
      exit = 2;
      outputEnd = "pnpm-only-lint: cannot check package.json: it is not one JSON object";
    };
    # Text after the first JSON document, or a second document, makes the file
    # unreadable for the lint: it reads exactly one object.
    malformed-json-trailing-text = {
      files."package.json" = ''{ "name": "x" } {'';
      exit = 2;
      outputEnd = "pnpm-only-lint: cannot check package.json: it is not one JSON object";
    };
    malformed-json-second-document = {
      files."package.json" = ''
        { "name": "x" }
        { "packageManager": "yarn@4.0.0" }
      '';
      exit = 2;
      outputEnd = "pnpm-only-lint: cannot check package.json: it is not one JSON object";
    };
    malformed-json-null = {
      files."package.json" = "null";
      exit = 2;
      outputEnd = "pnpm-only-lint: cannot check package.json: it is not one JSON object";
    };

    # A package.json that is a link to a missing file cannot be read. It
    # stops the lint, with Git (the link is tracked) and without.
    dangling-package-json-in-git = {
      symlinks."package.json" = "missing.json";
      git = { };
      exit = 2;
      output = "pnpm-only-lint: cannot check package.json: it is not a regular file";
    };
    dangling-package-json-without-git = {
      symlinks."package.json" = "missing.json";
      exit = 2;
      output = "pnpm-only-lint: cannot check package.json: it is not a regular file";
    };

    # A failed file listing stops the lint with status 2: the index is
    # corrupt, but the directory is still a work tree.
    listing-fails-in-git = {
      files = pnpmProject;
      git.corruptIndex = true;
      exit = 2;
      outputEnd = "pnpm-only-lint: cannot list the files of .";
    };

    # Usage errors.
    usage-two-arguments = {
      files = pnpmProject;
      command = "pnpm-only-lint . .";
      exit = 2;
      output = "usage: pnpm-only-lint [DIRECTORY]";
    };
    usage-not-a-directory = {
      files = pnpmProject;
      command = "pnpm-only-lint missing";
      exit = 2;
      output = "pnpm-only-lint: not a directory: missing";
    };

    # Passing trees.
    pass-pnpm-project = {
      files = pnpmProject // {
        "pnpm-workspace.yaml" = "packages:\n  - apps/*\n";
        ".pnpmfile.cjs" = "";
      };
      exit = 0;
      output = "";
    };
    pass-pnpm-project-in-git = {
      files = pnpmProject;
      git = { };
      exit = 0;
      output = "";
    };

    # A package.json that is a link to a readable file is read through the
    # link.
    pass-package-json-symlink = {
      files."shared/package.json" = ''{ "name": "shared" }'';
      symlinks."package.json" = "shared/package.json";
      git = { };
      exit = 0;
      output = "";
    };
    pin-package-json-symlink = {
      files."shared/package.json" = ''{ "packageManager": "yarn@4.0.0" }'';
      symlinks."package.json" = "shared/package.json";
      # Git lists the paths in sorted order; `find` does not.
      git = { };
      exit = 1;
      output = ''
        package.json: remove the "packageManager" field; the toolchain flake pins pnpm
        shared/package.json: remove the "packageManager" field; the toolchain flake pins pnpm'';
    };

    # The lint reads names and package.json fields only. A package manager
    # named in a value, a comment or prose is no finding.
    pass-names-in-text = {
      files = {
        "package.json" = ''{ "name": "app", "description": "uses yarn here, not npm" }'';
        ".github/dependabot.yml" = ''
          version: 2
          updates:
            - package-ecosystem: npm
              directory: /
        '';
        ".github/workflows/ci.yml" = ''
          # not npm, not yarn
          cache: yarn
          run: pnpm install # not npm
        '';
        "README.md" = "Do not run npm, yarn or bun here.\n";
      };
      exit = 0;
      output = "";
    };

    # Names that are close to a foreign name are not foreign.
    pass-near-miss-names = {
      files = {
        "yarn.lock.md" = "";
        "package-lock.json.md" = "";
        "my-yarn.lock" = "";
        "bunfig.toml.example" = "";
        ".yarnrc-notes/readme.md" = "";
        "yarn/readme.md" = "";
        ".pnp/readme.md" = "";
      };
      exit = 0;
      output = "";
    };

    # In a Git work tree only the tracked files count (see the header of the
    # lint).
    pass-untracked-foreign-file = {
      files = pnpmProject // {
        "yarn.lock" = "";
        "package-lock.json" = "{}";
      };
      git.untracked = [
        "yarn.lock"
        "package-lock.json"
      ];
      exit = 0;
      output = "";
    };
    pass-deleted-foreign-file = {
      files = pnpmProject // {
        "yarn.lock" = "";
      };
      git.deleted = [ "yarn.lock" ];
      exit = 0;
      output = "";
    };

    # Without Git every file counts except those below node_modules.
    pass-node-modules-without-git = {
      files = pnpmProject // {
        "node_modules/dep/package-lock.json" = "{}";
        "node_modules/dep/package.json" = ''{ "packageManager": "npm@10.0.0" }'';
      };
      exit = 0;
      output = "";
    };
  };

  # The shell commands that create a case's tree in the current directory.
  # Arguments: the case.
  # Returns: a string of shell commands.
  treeScript =
    case:
    let
      git = case.git or null;
      untracked = git.untracked or [ ];
      files = case.files or { };
      symlinks = case.symlinks or { };
      # The paths that `git add` receives: every file and link except the
      # untracked ones.
      tracked = lib.filter (path: !(lib.elem path untracked)) (
        lib.attrNames files ++ lib.attrNames symlinks
      );
      # The commands that write a file, with its parent directories.
      # Arguments: the path and the content.
      createFile = path: content: ''
        mkdir -p -- "$(dirname -- ${lib.escapeShellArg path})"
        printf '%s' ${lib.escapeShellArg content} > ${lib.escapeShellArg path}
      '';
      # The commands that create a symbolic link, with its parent directories.
      # The target need not exist.
      # Arguments: the path of the link and its target.
      createSymlink = path: target: ''
        mkdir -p -- "$(dirname -- ${lib.escapeShellArg path})"
        ln -s -- ${lib.escapeShellArg target} ${lib.escapeShellArg path}
      '';
      # The commands that make the tree a Git work tree in the state that the
      # case's `git` attributes describe.
      gitScript = ''
        git init --quiet
        ${lib.optionalString (tracked != [ ]) "git add -- ${lib.escapeShellArgs tracked}"}
        ${lib.concatMapStringsSep "\n" (path: "rm -- ${lib.escapeShellArg path}") (git.deleted or [ ])}
        ${lib.optionalString (git.corruptIndex or false) "printf 'not an index' > .git/index"}
      '';
    in
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList createFile files ++ lib.mapAttrsToList createSymlink symlinks
    )
    + lib.optionalString (git != null) gitScript;

  # The expected text of a case: its whole output, or the end of it (a case
  # sets `outputEnd` when the command also prints a message of a tool that
  # this repository does not control, such as Git).
  expectedText = case: case.output or case.outputEnd;

  # A `find` that prints a fixed listing and ignores its arguments, to fix the
  # order in which the lint receives the paths of a tree without Git.
  # Arguments: the list of paths.
  # Returns: a package with `bin/find`.
  findStub = listing: pkgs.writeShellScriptBin "find" "printf '%s\\0' ${lib.escapeShellArgs listing}";

  # The shell commands that put the stub first on PATH when a case sets
  # `findListing`, and nothing otherwise.
  # Arguments: the case.
  # Returns: a string of shell commands.
  findStubScript =
    case:
    lib.optionalString (case ? findListing) ''export PATH="${findStub case.findListing}/bin:$PATH"'';

  # The builder of a case: it builds the tree, runs the command, compares the
  # output with the expected one and exits with the command's status. A
  # different output exits with 99, which no case expects.
  runScript = case: ''
    export HOME="$TMPDIR" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
    ${findStubScript case}
    mkdir -p "$TMPDIR/tree"
    cd "$TMPDIR/tree"
    ${treeScript case}
    set +e
    output="$(${case.command or "pnpm-only-lint ."} 2>&1)"
    status=$?
    set -e
    if [[ "''${output}" != ${
      lib.optionalString (case ? outputEnd) "*"
    }${lib.escapeShellArg (expectedText case)} ]]; then
      echo "unexpected output of the command:" >&2
      printf '%s\n' "''${output}" >&2
      exit 99
    fi
    printf '%s\n' "''${output}"
    if (( status != 0 )); then
      exit "''${status}"
    fi
    touch "$out"
  '';

  # The derivation of one case. A case that expects status 0 is the builder
  # itself; any other case is a test that the builder fails with its status
  # and prints its output.
  # Arguments: the case name and the case.
  # Returns: a derivation that builds when the case behaves as expected.
  buildCase =
    name: case:
    let
      drv = pkgs.runCommandLocal "pnpm-only-${name}" {
        nativeBuildInputs = [
          pnpmOnlyLint
          pkgs.git
        ];
      } (runScript case);
    in
    if case.exit == 0 then
      drv
    else
      pkgs.testers.testBuildFailure' {
        name = "pnpm-only-${name}-fails";
        inherit drv;
        expectedBuilderExitCode = case.exit;
        expectedBuilderLogEntries = lib.filter (line: line != "") (
          lib.splitString "\n" (expectedText case)
        );
      };
in
pkgs.linkFarm "pnpm-only-cases" (
  lib.mapAttrsToList (name: case: {
    inherit name;
    path = buildCase name case;
  }) cases
)
