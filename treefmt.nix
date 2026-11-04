# The organization's treefmt module. `flake.nix` exports it through
# `lib.mkTreefmt`. Every program here either formats a file or fails the check.
{
  projectRootFile = "flake.nix";

  programs = {
    actionlint.enable = true;
    nixfmt.enable = true;
    shellcheck.enable = true;
    shfmt.enable = true;
    typos.enable = true;
    zizmor.enable = true;
  };

  # Run zizmor with its strictest persona.
  settings.formatter.zizmor.options = [ "--persona=pedantic" ];
}
