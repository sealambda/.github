# This repository's formatters and linters: the organization's set from the
# toolchain (toolchain/treefmt.nix), plus markdownlint for the documentation.
{ lib, pkgs, ... }:
{
  projectRootFile = "flake.nix";

  settings.formatter.markdownlint = {
    command = lib.getExe pkgs.markdownlint-cli2;
    includes = [ "*.md" ];
    priority = 1;
  };
}
