# A treefmt-nix module that formats Elixir with `mix format` from the
# toolchain's Elixir, so the formatter and the build use one Elixir version.
# treefmt-nix's own mix-format program defaults to nixpkgs' unversioned
# `beamPackages.elixir`, which is another version.
#
# `mix format` reads the repository's .formatter.exs. A formatter plugin from
# a dependency needs the dependency fetched and compiled, which the build
# sandbox cannot do; such a repository runs this module outside the sandbox.
#
# Argument: `packagesFor`, a function from a system name to the toolchain's
# packages (packages.nix).
# Returns: the module.
{ packagesFor }:
{ pkgs, ... }:
{
  programs.mix-format = {
    enable = true;
    package = (packagesFor pkgs.stdenv.hostPlatform.system).elixir;
  };
}
