# SPDX-License-Identifier: MPL-2.0
#
# This repository's formatters and linters: the organization's set from the
# toolchain (toolchain/treefmt.nix), and markdownlint with the base of the docs
# kit (docs-kit/treefmt.nix), plus the checks below: the schema of the issue
# forms, the name of the security form, and the links between default files.
{ lib, pkgs, ... }:
let
  # This repository's own lints (lints/); lints/checks.nix tests them.
  lints = import ./lints/default.nix pkgs;

  # Validates files against a schema that check-jsonschema ships, so the check
  # needs no network. It lints and never writes, like the toolchain's linters.
  #
  # Arguments: `schema` is a built-in schema name (`check-jsonschema
  # --help` lists them), and `includes` and `excludes` select the files.
  builtinSchemaCheck =
    {
      schema,
      includes,
      excludes ? [ ],
    }:
    {
      command = lib.getExe pkgs.check-jsonschema;
      options = [
        "--builtin-schema"
        schema
      ];
      priority = 1;
      inherit includes excludes;
    };
in
{
  projectRootFile = "flake.nix";

  # The issue forms and the issue chooser configuration of GitHub have two
  # schemas. A wrong key, for example `validation` for `validations`, passes
  # every other check and makes GitHub ignore the form.
  settings.formatter = {
    issue-forms = builtinSchemaCheck {
      schema = "vendor.github-issue-forms";
      includes = [
        ".github/ISSUE_TEMPLATE/*.yml"
        ".github/ISSUE_TEMPLATE/*.yaml"
      ];
      excludes = [
        ".github/ISSUE_TEMPLATE/config.yml"
        ".github/ISSUE_TEMPLATE/config.yaml"
      ];
    };
    issue-config = builtinSchemaCheck {
      schema = "vendor.github-issue-config";
      includes = [
        ".github/ISSUE_TEMPLATE/config.yml"
        ".github/ISSUE_TEMPLATE/config.yaml"
      ];
    };
    # The documents quote the name of the security form. The lint names the
    # form and the documents itself and ignores the paths that treefmt passes,
    # so it runs when any Markdown file or issue form is in the run.
    security-form-name = {
      command = lib.getExe lints.securityFormName;
      priority = 1;
      includes = [
        "*.md"
        ".github/ISSUE_TEMPLATE/*.yml"
      ];
    };
    # The absolute links between the default files point to files of the tree.
    # The issue chooser configuration holds one.
    self-links = {
      command = lib.getExe lints.selfLinks;
      priority = 1;
      includes = [
        "*.md"
        ".github/ISSUE_TEMPLATE/config.yml"
      ];
    };
  };
}
