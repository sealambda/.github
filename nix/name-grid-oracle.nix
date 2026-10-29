# The oracle of the grid test of the repository-name rule
# (.github/actions/check-trigger/name-grid.test.sh).
#
# The verdicts come from this file, not from the script under test. Nix
# matches the AWS patterns of an ECR repository name and of an IAM role name
# against every name of the grid, in Nix's own regular-expression engine, and
# sorts each name into a class (see name-grid.test.sh). The grid holds every
# string of 1 to 5 characters over `a`, `B`, `0`, `.`, `_` and `-`, which covers
# the first and last character, the separators in every order, the upper case
# that the script lower-cases, and the minimum length, plus names around the
# longest length that an IAM role name allows.
#
# The value is the store path of a file with one `name<TAB>class` line per name.
{ pkgs }:
let
  inherit (pkgs) lib;

  # The characters that the grid combines: a lower-case letter, an upper-case
  # letter, a digit and the three separators.
  alphabet = [
    "a"
    "B"
    "0"
    "."
    "_"
    "-"
  ];

  # The length of the longest string that the grid builds from the whole
  # alphabet (6^5 = 7776 strings); 6^6 would make the test slow for no new class
  # of name.
  longestGridLength = 5;

  # Every string of exactly `length` characters over the alphabet.
  stringsOfLength =
    length:
    if length == 0 then
      [ "" ]
    else
      lib.concatMap (prefix: map (character: prefix + character) alphabet) (stringsOfLength (length - 1));

  # The string of `count` copies of `character`; `count` must not be negative.
  repeat = character: count: lib.concatStrings (lib.genList (_: character) count);

  # Names around the longest valid name: `release-push-` has 13 of the 64
  # characters that an IAM role name may have.
  boundaryNames = lib.concatMap (length: [
    (repeat "a" length)
    (repeat "B" length)
    (repeat "a" (length - 1) + ".")
    (repeat "a" (length - 2) + "-a")
    (repeat "a" (length - 2) + "_b")
  ]) (lib.range 49 53);

  # Every name of the test: the whole grid and the boundary names.
  names = lib.concatMap stringsOfLength (lib.range 1 longestGridLength) ++ boundaryNames;

  # The ECR CreateRepository pattern for one path component, and its minimum
  # length (aws ecr put-image help, --repository-name).
  ecrNamePattern = "[a-z0-9]+((\\.|_|__|-+)[a-z0-9]+)*";
  ecrMinimumLength = 2;

  # The IAM CreateRole pattern and maximum length of a role name (aws iam
  # create-role help, --role-name).
  iamRoleNamePattern = "[A-Za-z0-9+=,.@_-]{1,64}";

  # Whether `text` matches the whole of `pattern` (Nix anchors the pattern at
  # both ends).
  matches = pattern: text: builtins.match pattern text != null;

  # The class of a name: see name-grid.test.sh.
  classify =
    name:
    let
      lower = lib.toLower name;
      validForEcr = matches ecrNamePattern lower && lib.stringLength lower >= ecrMinimumLength;
      validForIam = matches iamRoleNamePattern "release-push-${lower}";
      hasDoubledSeparator = matches ".*[._-][._-].*" lower;
    in
    if !(validForEcr && validForIam) then
      "invalid"
    else if hasDoubledSeparator then
      "doubled"
    else
      "strict";
in
# The expected class of every name, one `name<TAB>class` line each.
pkgs.writeText "name-grid.tsv" (lib.concatMapStrings (name: "${name}\t${classify name}\n") names)
