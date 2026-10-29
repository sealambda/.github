# Tests of this repository's lints (default.nix), for one system. `nix flake
# check` builds them.
#
# A case builds a small tree, runs a lint there and compares the exit status
# and the output with values written here by hand. No value is read from a lint
# or from its source, so a lint cannot make its own test pass. The layout and
# the helpers follow toolchain/lints/checks.nix.
#
# Argument: the nixpkgs package set of one system.
# Returns: an attribute set of check derivations.
pkgs:
let
  inherit (pkgs) lib;

  # The lints under test, built as in treefmt.nix.
  lints = import ./default.nix pkgs;

  # The prefix of the absolute links that the default files use for each other.
  # It is written out here, apart from the lint.
  prefix = "https://github.com/sealambda/.github/blob/main/";

  # Builds a check: runs `script` (test-helpers.sh calls) with `lint` on PATH.
  # The check fails when a case fails.
  mkCheck =
    name: lint: script:
    pkgs.runCommandLocal name { nativeBuildInputs = [ lint ]; } ''
      source ${./test-helpers.sh}
      ${script}
      finish
      touch "$out"
    '';

  # A file of a case: `path` relative to the tree, `mode` for chmod and
  # `content`.
  file = path: content: {
    inherit path content;
    mode = "644";
  };

  # The shell script of one case of a lint.
  #   lintName  the program name of the lint on PATH, as `mkCheck` provides it;
  #   c         the case, an attribute set with these attributes:
  #     name    the case name, for the failure message;
  #     files   the files of the tree, as made by `file`;
  #     args    the arguments of the lint, the files that treefmt would pass;
  #     status  the expected exit status;
  #     output  the expected output, standard output and standard error
  #             together.
  treeCase = lintName: c: ''
    new_tree
    ${lib.concatMapStrings (f: ''
      write_file ${
        lib.escapeShellArgs [
          f.path
          f.mode
          f.content
        ]
      }
    '') c.files}
    run_tree_case ${
      lib.escapeShellArgs (
        [
          lintName
          c.name
          (toString c.status)
          c.output
        ]
        ++ c.args
      )
    }
  '';

  # The `run_tree_case` calls of a list of cases, as one shell script.
  treeCases = lintName: cases: lib.concatMapStrings (treeCase lintName) cases;

  # A case for `self-links` that checks `doc.md` with the given content.
  selfLinkCase =
    {
      name,
      content,
      status,
      output,
      mode ? "644",
    }:
    {
      inherit name status output;
      files = [
        ((file "doc.md" content) // { inherit mode; })
      ];
      args = [ "doc.md" ];
    };

  # The cases of `self-links`.
  selfLinksCases = [
    (selfLinkCase {
      name = "clean tree";
      content = "[this file](${prefix}doc.md)\n";
      status = 0;
      output = "";
    })
    (selfLinkCase {
      name = "link with a fragment";
      content = "[a heading](${prefix}doc.md#a-heading)\n";
      status = 0;
      output = "";
    })
    (selfLinkCase {
      name = "link with a query";
      content = "[source](${prefix}doc.md?plain=1)\n";
      status = 0;
      output = "";
    })
    (selfLinkCase {
      name = "dead link with a query";
      content = "[gone](${prefix}missing.md?plain=1)\n";
      status = 1;
      output = "doc.md: links to missing.md, which is not in the tree";
    })
    (selfLinkCase {
      name = "no link";
      content = "No link here.\n";
      status = 0;
      output = "";
    })
    (selfLinkCase {
      name = "dead self-link";
      content = "[gone](${prefix}missing.md)\n";
      status = 1;
      output = "doc.md: links to missing.md, which is not in the tree";
    })
    (selfLinkCase {
      name = "link followed by a full stop";
      content = "See ${prefix}doc.md.\n";
      status = 0;
      output = "";
    })
    (selfLinkCase {
      name = "link followed by a comma, a semicolon and a colon";
      content = "${prefix}doc.md, ${prefix}doc.md; ${prefix}doc.md: end\n";
      status = 0;
      output = "";
    })
    (selfLinkCase {
      name = "dead link followed by a full stop";
      content = "See ${prefix}missing.md.\n";
      status = 1;
      output = "doc.md: links to missing.md, which is not in the tree";
    })
    (selfLinkCase {
      name = "link of the prefix and a full stop only";
      content = "See ${prefix}.\n";
      status = 1;
      output = "doc.md: links to ${prefix}., which names no path in the tree";
    })
    (selfLinkCase {
      # Mode 311: the owner may execute but not read the file. The case needs a
      # build user that is not root, because root reads every file; `write_file`
      # fails the check when the user can read the file.
      name = "file that cannot be read";
      content = "[this file](${prefix}doc.md)\n";
      mode = "311";
      status = 2;
      output = "doc.md: cannot read the file";
    })
    {
      name = "file that does not exist";
      files = [ ];
      args = [ "doc.md" ];
      status = 2;
      output = "doc.md: cannot read the file";
    }
  ];

  # The name of the security form in the tree of the cases below, and the
  # documents that quote it. Written out by hand, apart from the lint.
  formPath = ".github/ISSUE_TEMPLATE/security_contact.yml";
  formName = "Security contact request";
  referencePaths = [
    "SECURITY.md"
    "SUPPORT.md"
    "docs/decisions/0003-security-reporting-scope.md"
    "docs/explanation/default-files.md"
  ];

  # The documents of the tree; each quotes `name` in bold.
  referencesQuoting = name: map (path: file path "Use the form **${name}**.\n") referencePaths;

  # A case for `security-form-name`. The lint ignores its arguments, so the
  # case passes the form, as treefmt does.
  securityCase =
    {
      name,
      files,
      status,
      output,
    }:
    {
      inherit
        name
        files
        status
        output
        ;
      args = [ formPath ];
    };

  # The cases of `security-form-name`.
  securityFormNameCases = [
    (securityCase {
      name = "clean tree";
      files = [ (file formPath "name: ${formName}\n") ] ++ referencesQuoting formName;
      status = 0;
      output = "";
    })
    (securityCase {
      name = "renamed security form";
      files = [ (file formPath "name: Private report\n") ] ++ referencesQuoting formName;
      status = 1;
      output = lib.concatMapStringsSep "\n" (
        path: "security-form-name: ${path} does not quote **Private report**"
      ) referencePaths;
    })
    (securityCase {
      name = "one document that does not quote the name";
      files = [
        (file formPath "name: ${formName}\n")
        (file "SECURITY.md" "Use the form **${formName}**.\n")
        (file "SUPPORT.md" "Use the form Security contact request.\n")
        (file "docs/decisions/0003-security-reporting-scope.md" "Use the form **${formName}**.\n")
        (file "docs/explanation/default-files.md" "Use the form **${formName}**.\n")
      ];
      status = 1;
      output = "security-form-name: SUPPORT.md does not quote **${formName}**";
    })
    (securityCase {
      name = "form without a name line";
      files = [ (file formPath "description: no name\n") ] ++ referencesQuoting formName;
      status = 1;
      output = "security-form-name: ${formPath} has no 'name:' line";
    })
    (securityCase {
      name = "missing security form";
      files = referencesQuoting formName;
      status = 1;
      output = "security-form-name: ${formPath} is missing; SECURITY.md names it";
    })
  ];
in
{
  # `self-links` accepts links to paths of the tree, and flags the others.
  self-links = mkCheck "self-links-cases" lints.selfLinks (treeCases "self-links" selfLinksCases);

  # `security-form-name` flags a form without a name and documents that do not
  # quote it.
  security-form-name = mkCheck "security-form-name-cases" lints.securityFormName (
    treeCases "security-form-name" securityFormNameCases
  );
}
