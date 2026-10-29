# Builds a check that fails when the lock file of a subflake and the lock file
# above it lock different revisions of the same inputs.
#
# This repository holds three flakes: the root flake, and the subflakes
# `toolchain/` and `docs-kit/`. A flake takes a subflake as a relative path
# input (`path:./toolchain`), and `docs-kit/` takes `toolchain/` the same way
# (`path:../toolchain`). Nix copies the lock of a subflake into the lock above
# it only when that lock is created or `nix flake update <input>` runs. A later
# update inside the subflake leaves the lock above it behind, and Nix gives no
# warning. A consumer of a released tag reads the lock of the subflake, not the
# lock of the root, so the three locks must agree.
#
# The check compares the locked sources of the inputs of each subflake, with
# every `follows` resolved, and ignores the node names, which differ between
# locks. It ignores the locked path of a relative path input, which differs by
# design (`./toolchain` in the root, `../toolchain` in docs-kit).
#
# This check does not compare a lock with the `flake.nix` next to it. The
# command `nix flake lock --no-update-lock-file`, run in each flake directory,
# does that (scripts/check.sh).
#
# The comparison has its own cases, evaluated on lock files that this file
# generates. They run inside the check, so a change that makes the comparison
# accept every pair of locks fails the build instead of passing for ever. The
# failure report has a case too: the check runs it on generated locks that
# disagree and reads what it prints.
#
# Arguments (an attribute set): `pkgs`, and `root`, the repository's source.
# Returns: a derivation that builds when the locks agree. Fix a failure with
# the commands that its message prints.
{ pkgs, root }:
let
  inherit (pkgs) lib;

  # A lock file of the repository, as an attribute set.
  # Argument: the path of the file, relative to the repository root.
  readLock = path: lib.importJSON (root + "/${path}");

  # The node that an input reference names: a node name, or a `follows`
  # path of input names from the lock's root node.
  resolve =
    lock: reference:
    if builtins.isList reference then
      lib.foldl' (node: input: resolve lock lock.nodes.${node}.inputs.${input}) lock.root reference
    else
      reference;

  # The locked source of every input below a node, by input name, with
  # `follows` resolved. A relative path input has no locked source of its own.
  lockedInputs =
    lock: node:
    lib.mapAttrs (
      _: reference:
      let
        target = resolve lock reference;
        locked = lock.nodes.${target}.locked;
      in
      {
        locked = if locked.type == "path" then null else locked;
        inputs = lockedInputs lock target;
      }
    ) (lock.nodes.${node}.inputs or { });

  # The inputs of the subflake that `lock` takes as the input `name`.
  inputsOf = lock: name: lockedInputs lock (resolve lock lock.nodes.${lock.root}.inputs.${name});

  # The inputs of the flake that a lock file belongs to.
  ownInputs = lock: lockedInputs lock lock.root;

  # The pairs to compare, each with a label: what a parent lock records for a
  # subflake, and what the lock of the subflake records.
  # Argument: the three lock files, as attribute sets (`rootLock`,
  # `toolchainLock` and `docsKitLock`).
  comparisons =
    {
      rootLock,
      toolchainLock,
      docsKitLock,
    }:
    [
      {
        label = "flake.lock (toolchain) and toolchain/flake.lock";
        parent = inputsOf rootLock "toolchain";
        child = ownInputs toolchainLock;
      }
      {
        label = "flake.lock (docs-kit) and docs-kit/flake.lock";
        parent = inputsOf rootLock "docs-kit";
        child = ownInputs docsKitLock;
      }
      {
        label = "docs-kit/flake.lock (toolchain) and toolchain/flake.lock";
        parent = inputsOf docsKitLock "toolchain";
        child = ownInputs toolchainLock;
      }
    ];

  # The comparisons whose two sides differ.
  disagreements =
    locks: lib.filter (comparison: comparison.parent != comparison.child) (comparisons locks);

  # The locked source of nixpkgs at a revision, as a lock file records it.
  # Argument: the revision, any string.
  nixpkgsAt = rev: {
    type = "github";
    owner = "NixOS";
    repo = "nixpkgs";
    inherit rev;
  };

  # The locked source of a relative path input, as a lock file records it.
  # Argument: the path, such as `./toolchain`.
  pathInput = path: {
    type = "path";
    inherit path;
  };

  # A generated set of the three lock files, for the cases below. The set has
  # the shape of the real locks: a toolchain lock that locks nixpkgs, a docs-kit
  # lock that takes the toolchain as a path input, and a root lock that takes
  # both, with docs-kit following the toolchain.
  # Argument: an attribute set with the nixpkgs revision that each of the three
  # locks records: `root`, `toolchain` and `docsKit`.
  # Returns: the attribute set `rootLock`, `toolchainLock`, `docsKitLock`.
  lockSet =
    {
      root,
      toolchain,
      docsKit,
    }:
    {
      toolchainLock = {
        version = 7;
        root = "root";
        nodes = {
          root.inputs.nixpkgs = "nixpkgs";
          nixpkgs.locked = nixpkgsAt toolchain;
        };
      };
      docsKitLock = {
        version = 7;
        root = "root";
        nodes = {
          root.inputs = {
            toolchain = "toolchain";
            nixpkgs = [
              "toolchain"
              "nixpkgs"
            ];
          };
          toolchain = {
            inputs.nixpkgs = "nixpkgs";
            locked = pathInput "../toolchain";
          };
          nixpkgs.locked = nixpkgsAt docsKit;
        };
      };
      rootLock = {
        version = 7;
        root = "root";
        nodes = {
          root.inputs = {
            toolchain = "toolchain";
            docs-kit = "docs-kit";
          };
          toolchain = {
            inputs.nixpkgs = "nixpkgs";
            locked = pathInput "./toolchain";
          };
          docs-kit = {
            inputs = {
              toolchain = [ "toolchain" ];
              nixpkgs = [
                "toolchain"
                "nixpkgs"
              ];
            };
            locked = pathInput "./docs-kit";
          };
          nixpkgs.locked = nixpkgsAt root;
        };
      };
    };

  # The labels of the comparisons that disagree, in the order of `comparisons`.
  # Argument: a set of the three lock files, as `lockSet` returns it.
  labelsOf = locks: map (comparison: comparison.label) (disagreements locks);

  # Expected values are written by hand: a change in one lock disagrees with
  # the two comparisons that involve that lock, and with no other.
  cases = {
    testThreeLocksAgree = {
      expr = labelsOf (lockSet {
        root = "a";
        toolchain = "a";
        docsKit = "a";
      });
      expected = [ ];
    };
    testToolchainLockIsBehind = {
      expr = labelsOf (lockSet {
        root = "a";
        toolchain = "b";
        docsKit = "a";
      });
      expected = [
        "flake.lock (toolchain) and toolchain/flake.lock"
        "docs-kit/flake.lock (toolchain) and toolchain/flake.lock"
      ];
    };
    testDocsKitLockIsBehind = {
      expr = labelsOf (lockSet {
        root = "a";
        toolchain = "a";
        docsKit = "b";
      });
      expected = [
        "flake.lock (docs-kit) and docs-kit/flake.lock"
        "docs-kit/flake.lock (toolchain) and toolchain/flake.lock"
      ];
    };
    testRootLockIsBehind = {
      expr = labelsOf (lockSet {
        root = "b";
        toolchain = "a";
        docsKit = "a";
      });
      expected = [
        "flake.lock (toolchain) and toolchain/flake.lock"
        "flake.lock (docs-kit) and docs-kit/flake.lock"
      ];
    };
    testAnInputMissingInOneLock = {
      expr = labelsOf (
        let
          locks = lockSet {
            root = "a";
            toolchain = "a";
            docsKit = "a";
          };
        in
        locks
        // {
          toolchainLock = locks.toolchainLock // {
            nodes.root.inputs = { };
          };
        }
      );
      expected = [
        "flake.lock (toolchain) and toolchain/flake.lock"
        "docs-kit/flake.lock (toolchain) and toolchain/flake.lock"
      ];
    };
  };

  # `lib.debug.runTests` runs only the attributes whose name starts with
  # `test`, so a misspelt name would skip a case without a failure. The
  # assertion guards against that.
  caseFailures =
    assert lib.all (name: lib.hasPrefix "test" name) (lib.attrNames cases);
    lib.debug.runTests cases;

  # The shell that stops the build when a case fails.
  caseScript =
    if caseFailures == [ ] then
      ""
    else
      ''
        echo "lock-sync: the comparison of the locks fails its own cases:" >&2
        jq . ${builtins.toFile "failures.json" (builtins.toJSON caseFailures)} >&2
        exit 1
      '';

  # The three lock files of the repository.
  locks = {
    rootLock = readLock "flake.lock";
    toolchainLock = readLock "toolchain/flake.lock";
    docsKitLock = readLock "docs-kit/flake.lock";
  };

  # The shell that prints one disagreement: both sides as indented JSON, so
  # that `diff` shows the field that differs, not one long line. The attribute
  # names are already in sorted order: `builtins.toJSON` writes them that way.
  describe = comparison: ''
    echo "locked differently: ${comparison.label}" >&2
    jq . ${builtins.toFile "child.json" (builtins.toJSON comparison.child)} > child.json
    jq . ${builtins.toFile "parent.json" (builtins.toJSON comparison.parent)} > parent.json
    diff -u --label "the lock of the subflake" --label "the lock above it" \
      child.json parent.json >&2 || test $? -eq 1
  '';

  # The program that reports disagreeing comparisons: it describes each one,
  # prints the commands that fix the locks, and exits with status 1. It is a
  # separate program, so that `set -e` stays active inside it and a test can
  # run it and read its exit status.
  # Argument: the disagreeing comparisons, as `disagreements` returns them.
  report =
    found:
    pkgs.writeShellScript "lock-sync-report" (
      "set -eu\n"
      + lib.concatMapStrings describe found
      + ''
        echo "The locks move in lock step. Update them from the bottom up:" >&2
        echo "  (cd docs-kit && nix flake update toolchain)" >&2
        echo "  nix flake update toolchain docs-kit" >&2
        echo "An update tool must update all three locks in one change." >&2
        exit 1
      ''
    );

  # The shell that runs the report on generated locks, where the toolchain lock
  # is behind, and checks what it prints: the label of a comparison, the line
  # of each side of the diff as indented JSON, and the fix commands. Without
  # it, the text would run only when the real locks drift.
  reportScript =
    let
      toolchainBehind = lockSet {
        root = "a";
        toolchain = "b";
        docsKit = "a";
      };
    in
    ''
      status=0
      ${report (disagreements toolchainBehind)} 2> report.txt || status=$?
      test "$status" -eq 1
      grep -qxF 'locked differently: flake.lock (toolchain) and toolchain/flake.lock' report.txt
      grep -qE '^-[[:space:]]+"rev": "b",?$' report.txt
      grep -qE '^\+[[:space:]]+"rev": "a",?$' report.txt
      grep -qxF '  nix flake update toolchain docs-kit' report.txt
      grep -qxF 'An update tool must update all three locks in one change.' report.txt
    '';

  # The comparisons of the real lock files that disagree. Empty when the locks
  # are in sync.
  mismatches = disagreements locks;
in
pkgs.runCommandLocal "lock-sync" { nativeBuildInputs = [ pkgs.jq ]; } (
  caseScript + reportScript + (if mismatches == [ ] then ''touch "$out"'' else "${report mismatches}")
)
