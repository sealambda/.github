# Tests the comparison of nix/toolchain-lock-sync.nix on lock sets that this
# file generates, so that no fixture file exists. Each case states by hand
# which inputs the two locks disagree about. One more case builds the real
# check on a drifted pair and tests its failure: exit status, remedy and diff.
#
# The cases use the real shape of the two locks. The toolchain lock has the
# inputs `nixpkgs` and `treefmt-nix`, and `treefmt-nix` follows `nixpkgs`.
# The root lock holds the toolchain below its node `toolchain`, with other
# node names, and follows the same inputs through `follows` paths.
#
# Arguments (an attribute set): `pkgs`.
# Returns: a derivation that builds when every case passes. On a failure it
#   prints the failing cases as JSON and exits 1.
{ pkgs }:
let
  inherit (pkgs) lib;

  # A `locked` attribute set for one input at a revision.
  lockedAt = repo: rev: {
    type = "github";
    owner = "example";
    inherit repo rev;
  };

  # The toolchain lock for the given revisions of its two inputs.
  # `withTreefmt = false` leaves the input `treefmt-nix` out.
  toolchainLock =
    {
      nixpkgs,
      treefmt,
      withTreefmt ? true,
    }:
    {
      root = "root";
      nodes = {
        root.inputs = {
          nixpkgs = "nixpkgs";
        }
        // lib.optionalAttrs withTreefmt { treefmt-nix = "treefmt-nix"; };
        nixpkgs.locked = lockedAt "nixpkgs" nixpkgs;
        treefmt-nix = {
          inputs.nixpkgs = [ "nixpkgs" ];
          locked = lockedAt "treefmt-nix" treefmt;
        };
      };
    };

  # The root lock, which holds the toolchain below the node `toolchain`.
  rootLock =
    { nixpkgs, treefmt }:
    {
      root = "root";
      nodes = {
        root.inputs = {
          toolchain = "toolchain";
          nixpkgs = [
            "toolchain"
            "nixpkgs"
          ];
          treefmt-nix = [
            "toolchain"
            "treefmt-nix"
          ];
        };
        toolchain.inputs = {
          nixpkgs = "nixpkgs_2";
          treefmt-nix = "treefmt-nix_2";
        };
        nixpkgs_2.locked = lockedAt "nixpkgs" nixpkgs;
        treefmt-nix_2 = {
          inputs.nixpkgs = [
            "toolchain"
            "nixpkgs"
          ];
          locked = lockedAt "treefmt-nix" treefmt;
        };
      };
    };

  # The names of the inputs that two lock sets disagree about.
  disagreementsOf =
    {
      root,
      toolchain,
    }:
    (import ./toolchain-lock-sync.nix {
      inherit pkgs;
      rootLock = rootLock root;
      toolchainLock = toolchainLock toolchain;
    }).disagreements;

  # The cases. `runTests` runs only the names that start with `test`.
  cases = {
    testAgreeingLocksHaveNoDisagreement = {
      expr = disagreementsOf {
        root = {
          nixpkgs = "r1";
          treefmt = "t1";
        };
        toolchain = {
          nixpkgs = "r1";
          treefmt = "t1";
        };
      };
      expected = [ ];
    };

    testOneDifferentRevisionIsOneDisagreement = {
      expr = disagreementsOf {
        root = {
          nixpkgs = "r1";
          treefmt = "t1";
        };
        toolchain = {
          nixpkgs = "r1";
          treefmt = "t2";
        };
      };
      expected = [ "treefmt-nix" ];
    };

    # `treefmt-nix` follows `nixpkgs`, so its resolved inputs differ as well.
    testDriftOfAFollowedInputReachesItsFollower = {
      expr = disagreementsOf {
        root = {
          nixpkgs = "r1";
          treefmt = "t1";
        };
        toolchain = {
          nixpkgs = "r2";
          treefmt = "t1";
        };
      };
      expected = [
        "nixpkgs"
        "treefmt-nix"
      ];
    };

    testInputMissingFromTheToolchainLockIsADisagreement = {
      expr = disagreementsOf {
        root = {
          nixpkgs = "r1";
          treefmt = "t1";
        };
        toolchain = {
          nixpkgs = "r1";
          treefmt = "t1";
          withTreefmt = false;
        };
      };
      expected = [ "treefmt-nix" ];
    };
  };

  # The real check on a drifted pair of locks: `treefmt-nix` is locked at `t1`
  # in the root lock and at `t2` in the toolchain lock.
  driftedCheck = import ./toolchain-lock-sync.nix {
    inherit pkgs;
    rootLock = rootLock {
      nixpkgs = "r1";
      treefmt = "t1";
    };
    toolchainLock = toolchainLock {
      nixpkgs = "r1";
      treefmt = "t2";
    };
  };

  # The failing branch of the check: it must fail with exit status 1, name the
  # remedy, and print a diff with one key per line, so that the changed
  # revision is one line of the diff. The expected lines are written by hand
  # from `diff -u toolchain.json root.json` (the toolchain side first) of the
  # key-sorted JSON; a diff of unformatted JSON would be one line that holds
  # every input. The drifted input is the 6-space-indented `rev` below
  # `treefmt-nix` and `locked`.
  driftFails = pkgs.testers.testBuildFailure' {
    drv = driftedCheck;
    expectedBuilderExitCode = 1;
    expectedBuilderLogEntries = [
      "lock different toolchain inputs: treefmt-nix"
      "Run: nix flake update toolchain"
      "-      \"rev\": \"t2\","
      "+      \"rev\": \"t1\","
    ];
  };

  # `runTests` skips a case whose name does not start with `test`; the check
  # must not pass because a case was skipped.
  skipped = lib.filter (name: !(lib.hasPrefix "test" name)) (lib.attrNames cases);
  failures = lib.debug.runTests cases;
in
# `inherit driftFails` makes the failure test a dependency: this check builds
# only when that test builds.
pkgs.runCommandLocal "toolchain-lock-sync-tests" { inherit driftFails; } (
  if skipped == [ ] && failures == [ ] then
    ''touch "$out"''
  else
    ''
      echo ${lib.escapeShellArg (builtins.toJSON { inherit skipped failures; })} >&2
      exit 1
    ''
)
