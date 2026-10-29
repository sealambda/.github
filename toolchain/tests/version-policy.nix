# Tests of the version policy functions (version-policy.nix): named cases for
# the known edge cases, and an exhaustive grid of small versions against an
# independent oracle.
#
# Arguments (an attribute set):
#   pkgs           the nixpkgs package set of the system;
#   versionPolicy  the policy functions (version-policy.nix).
# Returns: a derivation that builds when every case and every grid point
# passes. It fails with the failing cases printed as JSON.
{ pkgs, versionPolicy }:
let
  inherit (pkgs) lib;
  inherit (versionPolicy) inSeries findings;

  # A table row: `inSeries wanted version` must be `expected`. The values are
  # written by hand from the rule in versions.nix, not computed.
  seriesCase = wanted: version: expected: {
    expr = inSeries wanted version;
    inherit expected;
  };

  # `runTests` runs only the names that start with `test`; the assertion
  # below fails when a case would be skipped.
  cases = {
    # A series accepts every version that starts with its parts.
    testMajorAcceptsPatch = seriesCase "26" "26.3.1" true;
    testMajorAcceptsMajorOnly = seriesCase "26" "26" true;
    testMinorAcceptsPatch = seriesCase "1.13" "1.13.4" true;

    # A series rejects another value, also when only a string prefix matches.
    testMajorRejectsNextMajor = seriesCase "26" "27.0.0" false;
    testMajorRejectsLongerNumber = seriesCase "26" "260.1.0" false;
    testMajorRejectsMinorPart = seriesCase "2" "1.2.0" false;
    testMinorRejectsLongerNumber = seriesCase "1.2" "1.20.1" false;
    testMinorAcceptsExactMinor = seriesCase "1.2" "1.2.9" true;
    testMinorRejectsNextMinor = seriesCase "1.13" "1.14.0" false;
    testMinorRejectsOtherMajor = seriesCase "1.13" "2.13.0" false;
    testSeriesRejectsShorterVersion = seriesCase "1.13" "1" false;

    # An exact pin accepts the same version and nothing else.
    testPinAcceptsItself = seriesCase "3.1.3" "3.1.3" true;
    testPinRejectsPatchBump = seriesCase "3.1.3" "3.1.4" false;
    testPinRejectsMinorBump = seriesCase "3.1.3" "3.2.3" false;
    testPinRejectsLongerNumber = seriesCase "3.1.3" "3.1.30" false;
    testPinRejectsLongerVersion = seriesCase "3.1.3" "3.1.3.1" false;
    testPinRejectsSuffix = seriesCase "3.1.3" "3.1.3-rc1" false;

    # An empty value is a mistake and accepts nothing.
    testEmptyAcceptsNothing = seriesCase "" "1.0.0" false;

    # The findings of the version-line check.
    testFindingsEmptyWhenCompliant = {
      expr = findings {
        policy = {
          node = "26";
          tofu = "1.13";
        };
        actual = {
          node = "26.1.0";
          tofu = "1.13.2";
        };
        exported = {
          node = "26.1.0";
          tofu = "1.13.2";
        };
      };
      expected = [ ];
    };
    testFindingsToolOutsideSeries = {
      expr = findings {
        policy.node = "26";
        actual.node = "27.0.0";
        exported.node = "27.0.0";
      };
      expected = [ "node 27.0.0 is outside the series 26 of versions.nix" ];
    };
    testFindingsPolicyWithoutPackage = {
      expr = findings {
        policy = {
          node = "26";
          tofu = "1.13";
        };
        actual.node = "26.1.0";
        exported.node = "26.1.0";
      };
      expected = [ "versions.nix names node tofu, but packages.nix has node" ];
    };
    testFindingsPackageWithoutPolicy = {
      expr = findings {
        policy.node = "26";
        actual = {
          node = "26.1.0";
          tofu = "1.13.2";
        };
        exported = {
          node = "26.1.0";
          tofu = "1.13.2";
        };
      };
      expected = [ "versions.nix names node, but packages.nix has node tofu" ];
    };
    testFindingsSystemDiffersFromExportedLine = {
      expr = findings {
        policy.node = "26";
        actual.node = "26.2.0";
        exported.node = "26.1.0";
      };
      expected = [
        ''this system's versions {"node":"26.2.0"} differ from the exported line {"node":"26.1.0"}''
      ];
    };
  };

  # Every case must run: a name that does not start with `test` would be
  # skipped and would pass silently. The count is a literal, so that a case
  # that is removed or renamed shows in review.
  allCasesRun =
    lib.length (lib.attrNames cases) == 23
    && lib.all (name: lib.hasPrefix "test" name) (lib.attrNames cases);

  # The grid. A version is a list of numbers; the numbers include 10 and 20
  # so that a string-prefix mistake ("1.2" against "1.20") shows. Policy
  # values have 1 to 3 parts, versions 1 to 4.
  components = [
    0
    1
    2
    10
    20
  ];

  # Every list of `length` numbers from `components`.
  sequencesOfLength =
    length:
    let
      positions = lib.genList (position: "p${toString position}") length;
    in
    map (combination: map (position: combination.${position}) positions) (
      lib.cartesianProduct (lib.genAttrs positions (_: components))
    );

  # Every list of 1 to `maxLength` numbers from `components`.
  sequencesUpTo = maxLength: lib.concatMap sequencesOfLength (lib.range 1 maxLength);

  # The version text of a list of numbers: `[ 1 2 ]` gives "1.2".
  dotted = parts: lib.concatMapStringsSep "." toString parts;

  # The oracle works on text, the function under test on parts: a series
  # accepts the same text or a text that continues it after a dot; an exact
  # pin (3 parts) accepts the same text only.
  oracle =
    wantedParts: versionParts:
    let
      wanted = dotted wantedParts;
      version = dotted versionParts;
    in
    if lib.length wantedParts >= 3 then
      version == wanted
    else
      version == wanted || lib.hasPrefix "${wanted}." version;

  # The grid points where `inSeries` differs from the oracle: every policy
  # value of 1 to 3 parts against every version of 1 to 4 parts. Empty when
  # the function is right everywhere.
  gridFailures = lib.concatMap (
    wantedParts:
    lib.concatMap (
      versionParts:
      let
        got = inSeries (dotted wantedParts) (dotted versionParts);
        expected = oracle wantedParts versionParts;
      in
      lib.optional (got != expected) {
        wanted = dotted wantedParts;
        version = dotted versionParts;
        inherit got expected;
      }
    ) (sequencesUpTo 4)
  ) (sequencesUpTo 3);

  # What the build prints when it fails: the failing named cases and the first
  # failing grid points. Both lists are empty when the tests pass.
  failures = {
    cases = lib.debug.runTests cases;
    # The first failures are enough to see the pattern.
    grid = lib.take 20 gridFailures;
  };
in
assert allCasesRun;
pkgs.runCommandLocal "version-policy-tests"
  {
    failuresJson = builtins.toJSON failures;
  }
  ''
    if [[ "''${failuresJson}" != '{"cases":[],"grid":[]}' ]]; then
      echo "version policy failures:" >&2
      printf '%s\n' "''${failuresJson}" >&2
      exit 1
    fi
    touch "$out"
  ''
