# SPDX-License-Identifier: MPL-2.0
#
# This repository's formatters and linters: the organization's set from the
# toolchain (toolchain/treefmt.nix), and markdownlint with the base of the docs
# kit (docs-kit/treefmt.nix), plus the schema check of the issue forms below.
{ lib, pkgs, ... }:
let
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

  # The form that SECURITY.md names as the fallback channel, and the documents
  # that quote its name. The name is typed in each of them, and nothing else
  # ties the text to the form.
  securityForm = ".github/ISSUE_TEMPLATE/security_contact.yml";
  securityFormReferences = [
    "SECURITY.md"
    "SUPPORT.md"
    "docs/decisions/0003-security-reporting-scope.md"
    "docs/explanation/default-files.md"
  ];

  # Fails when the security form is missing or has no `name:` line, or when a
  # document of `securityFormReferences` does not quote the name in bold. It
  # reads the fixed paths from the tree root, which is the working directory of
  # treefmt, and ignores the paths that treefmt passes: the form and the
  # documents are checked together, whichever of them changed. Exit status: 0
  # when every document quotes the name, 1 otherwise.
  securityFormNameCheck = pkgs.writeShellApplication {
    name = "security-form-name";
    runtimeInputs = [
      pkgs.gnugrep
      pkgs.gnused
    ];
    text = ''
      form=${lib.escapeShellArg securityForm}
      if [[ ! -f "''${form}" ]]; then
        echo "security-form-name: ''${form} is missing; SECURITY.md names it" >&2
        exit 1
      fi
      name="$(sed -n 's/^name: //p' "''${form}")"
      if [[ -z "''${name}" ]]; then
        echo "security-form-name: ''${form} has no 'name:' line" >&2
        exit 1
      fi
      status=0
      for document in ${lib.escapeShellArgs securityFormReferences}; do
        if ! grep -qF -- "**''${name}**" "''${document}"; then
          echo "security-form-name: ''${document} does not quote **''${name}**" >&2
          status=1
        fi
      done
      exit "''${status}"
    '';
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
    # The documents quote the name of the security form (see
    # `securityFormNameCheck`).
    security-form-name = {
      command = lib.getExe securityFormNameCheck;
      priority = 1;
      includes = [ securityForm ] ++ securityFormReferences;
    };
  };
}
