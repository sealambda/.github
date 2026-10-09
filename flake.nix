# The shell for this repository's checks: `nix develop` (CI runs the same).
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      # Calls `mkOutput pkgs` for every system, as an attribute set.
      forSystems =
        mkOutput: nixpkgs.lib.genAttrs systems (system: mkOutput nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = with pkgs; [
            actionlint
            gh
            jq
            nixfmt
            shellcheck
          ];
        };
      });

      formatter = forSystems (pkgs: pkgs.nixfmt-tree);
    };
}
