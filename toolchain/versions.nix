# The version policy of the toolchain: the series that each tool in
# packages.nix must stay in.
#
# A value with fewer than three parts is a series: "26" accepts any 26.x.y,
# and "1.13" accepts any 1.13.x. A value with three or more parts is an exact
# pin: "3.1.3" accepts only 3.1.3 (`exactPinParts` in version-policy.nix). The
# `version-line` check fails when a lock refresh moves a tool out of its
# series, so that move needs a reviewed edit here.
#
# Each entry says why it has that width:
{
  # The attribute name fixes the major (nodejs-slim_26, pnpm_12,
  # postgresql_18, erlang_29, elixir_1_20); the check guards the attribute.
  nodejs = "26";
  pnpm = "12";
  postgresql = "18";
  erlang = "29";
  elixir = "1.20";

  # nixpkgs has one unversioned `hex` per BEAM package set. A Hex minor
  # release can change the output and exit status of `mix hex.audit`, so the
  # series is the minor.
  hex = "2.6";

  # nixpkgs has one unversioned `opentofu`, and an OpenTofu minor release
  # changes the state format and the provider protocol, so the series is the
  # minor.
  opentofu = "1.13";

  # Exact: podman verifies only cosign's legacy signature format, which
  # cosign v4 removes, so every cosign change needs a review of the release
  # signing path. nixpkgs' own build is used, not an overridden one, so the
  # binary cache still serves it.
  cosign = "3.1.3";
}
