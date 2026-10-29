# markdownlint-cli2 with the base configuration of the docs kit, as a
# treefmt-nix module. Import it next to the toolchain's module
# (toolchain/treefmt.nix): the toolchain's Prettier formats Markdown first
# (priority 0), and markdownlint checks the result (priority 1).
#
# A repository that imports this module has no `.markdownlint-cli2.yaml` of
# its own, unless it needs an exception (docs-kit/README.md, "Markdown lint").
#
# The template files of the GitHub locations (`kit.githubTemplatePatterns`) get
# their own formatter, because they are exempt from MD041, as in `docs-check`.
# A file that `docs-check --template` selects is not known here: a repository
# adds its glob to `settings.formatter.markdownlint-templates.includes` and to
# `settings.formatter.markdownlint.excludes`.
{ lib, pkgs, ... }:
let
  # The programs of the docs kit (kit.nix) for the system of `pkgs`.
  kit = import ./kit.nix { inherit pkgs; };
in
{
  settings.formatter.markdownlint = {
    command = lib.getExe kit.markdownlint;
    includes = [ "*.md" ];
    excludes = kit.githubTemplatePatterns;
    priority = 1;
  };

  settings.formatter.markdownlint-templates = {
    command = lib.getExe kit.markdownlintTemplates;
    includes = kit.githubTemplatePatterns;
    priority = 1;
  };
}
