# The organization's toolchain: one package per tool, from versioned nixpkgs
# attributes wherever nixpkgs has them, so a lock refresh moves only within a
# series. OpenTofu and cosign have no versioned attribute; versions.nix bounds
# them instead.
#
# Argument: the nixpkgs package set of one system.
# Returns: an attribute set of derivations, keyed by tool name.
pkgs:
let
  # The BEAM package set of the Erlang series that versions.nix names. Its
  # `erlang`, `elixir_1_20` and `hex` come from one nixpkgs scope.
  beamPackages = pkgs.beam.packages.erlang_29;

  # The toolchain's Elixir: the series that versions.nix names, built for the
  # Erlang above. `hex` is built for this Elixir too.
  elixir = beamPackages.elixir_1_20;

  # pnpm 12 also installs `pnpx` and `pnx`, both aliases of `pnpm dlx`, which
  # runs a package that no lock file pins. This package links only `pnpm` and
  # its alias `pn`, so neither alias reaches a PATH.
  #
  # It is a local symlink package, not `pnpm_12.overrideAttrs`: nixpkgs builds
  # pnpm 12 from source with Cargo, and an override changes the derivation, so
  # every consumer would compile pnpm instead of fetching it from the binary
  # cache. `passthru` is copied from `pnpm_12`, so that code which reads
  # `pnpm.passthru` keeps working.
  pnpm =
    pkgs.runCommandLocal "pnpm-${pkgs.pnpm_12.version}"
      {
        inherit (pkgs.pnpm_12) version passthru;
        meta = pkgs.pnpm_12.meta // {
          mainProgram = "pnpm";
        };
      }
      ''
        mkdir -p "$out/bin"
        ln -s ${pkgs.pnpm_12}/bin/pnpm ${pkgs.pnpm_12}/bin/pn "$out/bin/"
      '';
in
{
  # nodejs-slim ships neither npm nor corepack.
  nodejs = pkgs.nodejs-slim_26;
  inherit pnpm;
  inherit (beamPackages) erlang;
  inherit elixir;

  # Hex built for the toolchain's Elixir. Its setup hook adds Hex to
  # ERL_LIBS, so `mix hex.info`, `mix deps.get` and `mix hex.audit` need no
  # download of the newest Hex into MIX_HOME.
  hex = beamPackages.hex.override { inherit elixir; };
  postgresql = pkgs.postgresql_18;
  inherit (pkgs) opentofu cosign;
}
