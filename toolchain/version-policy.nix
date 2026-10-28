# The rules of the version policy (versions.nix), as pure functions, so that
# a test can run them on any input (tests/version-policy.nix).
#
# Argument: an attribute set with `lib`, the nixpkgs library.
# Returns: an attribute set with `inSeries` and `findings`.
{ lib }:
let
  # A policy value with this many parts or more is an exact pin: a full
  # `major.minor.patch`. A value with fewer parts is a series.
  exactPinParts = 3;

  # True when `version` is inside the policy value `wanted`.
  #
  # - A series ("26", "1.13") accepts every version that starts with the same
  #   parts, compared part by part: "1.2" accepts 1.2.9 and not 1.20.1.
  # - An exact pin ("3.1.3") accepts the same version and nothing else, so it
  #   rejects a longer version such as 3.1.3.1.
  #
  # Arguments: the policy value, and the version, both strings. An empty
  # policy value accepts no version.
  inSeries =
    wanted: version:
    let
      wantedParts = lib.splitVersion wanted;
      versionParts = lib.splitVersion version;
    in
    wantedParts != [ ]
    && (
      if lib.length wantedParts >= exactPinParts then
        wantedParts == versionParts
      else
        lib.take (lib.length wantedParts) versionParts == wantedParts
    );

  # The findings of the version-line check, as a list of messages; the list
  # is empty when the toolchain complies with the policy.
  #
  # Arguments (an attribute set):
  #   policy    the policy, tool name to policy value (versions.nix);
  #   actual    the version of each tool of this system, tool name to version;
  #   exported  the exported version line (`lib.versions`).
  findings =
    {
      policy,
      actual,
      exported,
    }:
    lib.optional (lib.attrNames policy != lib.attrNames actual)
      "versions.nix names ${toString (lib.attrNames policy)}, but packages.nix has ${toString (lib.attrNames actual)}"
    ++ lib.concatMap (
      name:
      lib.optional (
        policy ? ${name} && !inSeries policy.${name} actual.${name}
      ) "${name} ${actual.${name}} is outside the series ${policy.${name}} of versions.nix"
    ) (lib.attrNames actual)
    ++
      lib.optional (actual != exported)
        "this system's versions ${builtins.toJSON actual} differ from the exported line ${builtins.toJSON exported}";
in
{
  inherit inSeries findings;
}
