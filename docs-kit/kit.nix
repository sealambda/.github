# The programs and files of the docs kit for one system.
#
# Argument: `pkgs`, the package set of the system. Returns an attribute set:
#   markdownlint  markdownlint-cli2 with the base configuration
#                 (`markdownlint-sealambda`);
#   markdownlintTemplates
#                 markdownlint-cli2 for template files, the base configuration
#                 with MD041 off (`markdownlint-sealambda-templates`);
#   markdownlintConfigs
#                 the directory of the two configuration files;
#   githubTemplatePatterns
#                 the patterns of the template locations that GitHub documents;
#   valeStyles    the Google and Microsoft styles of nixpkgs and the Sealambda
#                 style, joined in one directory;
#   valeConfig    the Vale configuration of the kit (see below);
#   docsCheck     the `docs-check` program (docs-check.sh);
#   valePackage   the Vale package, `Sealambda.zip`, for a release.
{ pkgs }:
let
  inherit (pkgs) lib;

  # The markdownlint configuration files in one store directory, because
  # templates.markdownlint.yaml extends base.markdownlint.yaml by a relative
  # path.
  markdownlintConfigs = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./base.markdownlint.yaml
      ./templates.markdownlint.yaml
    ];
  };

  # A program that runs markdownlint-cli2 with a configuration file of the kit.
  # markdownlint-cli2 reads the `.markdownlint-cli2.yaml` of the checked tree
  # after that file and merges the two.
  # Arguments: the name of the program and the file name of the configuration.
  mkMarkdownlint =
    name: configFile:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [ pkgs.markdownlint-cli2 ];
      text = ''
        exec markdownlint-cli2 --config ${markdownlintConfigs}/${configFile} "$@"
      '';
    };

  # markdownlint-cli2 with the base configuration, for the pages.
  markdownlint = mkMarkdownlint "markdownlint-sealambda" "base.markdownlint.yaml";

  # markdownlint-cli2 with the configuration for template files, which is the
  # base with MD041 off.
  markdownlintTemplates = mkMarkdownlint "markdownlint-sealambda-templates" "templates.markdownlint.yaml";

  # The locations of the templates that GitHub documents, as patterns for a
  # path relative to the root of the repository. This list is the only one: the
  # `docs-check` program reads it (DOCS_KIT_TEMPLATE_PATTERNS) and the treefmt
  # module (treefmt.nix) uses it. A pattern uses only literal text, `[xX]`
  # classes and one `*` for a file name. Bash (`[[ == ]]`) and treefmt 2.6 read
  # such a pattern in the same way, and in both `*` also matches `/`, so
  # `.github/ISSUE_TEMPLATE/sub/x.md` is a template for both (checked with
  # treefmt 2.6.0 on that path).
  #
  # GitHub does not document whether it matches the case of the names, so each
  # letter accepts both cases. Pull request templates: one file in the root, in
  # `docs` or in `.github`, or a directory of files with the name
  # PULL_REQUEST_TEMPLATE in one of the three. Issue templates: only the
  # directory `.github/ISSUE_TEMPLATE`; GitHub does not document the root or
  # `docs` for them. See
  # https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests
  githubTemplatePatterns =
    let
      # A pattern for a name that matches in any case: `ab_c` gives `[aA][bB]_[cC]`.
      anyCase =
        name:
        lib.concatMapStrings (
          char:
          if lib.toLower char == lib.toUpper char then char else "[${lib.toLower char}${lib.toUpper char}]"
        ) (lib.stringToCharacters name);
      pullRequestTemplate = anyCase "pull_request_template";
      issueTemplate = anyCase "issue_template";
    in
    [
      "${pullRequestTemplate}.md"
      "docs/${pullRequestTemplate}.md"
      ".github/${pullRequestTemplate}.md"
      "${pullRequestTemplate}/*.md"
      "docs/${pullRequestTemplate}/*.md"
      ".github/${pullRequestTemplate}/*.md"
      ".github/${issueTemplate}/*.md"
    ];

  # The styles that the Sealambda style needs: Google and Microsoft come from
  # nixpkgs, so that no check needs the network, and Sealambda comes from the
  # package source (vale/Sealambda/styles). The style `Sealambda` extends rules
  # of the other two.
  valeStyles =
    let
      # The Sealambda style alone, in the layout of a Vale styles directory
      # (`share/vale/styles/Sealambda`).
      sealambda = pkgs.runCommandLocal "vale-style-sealambda" { } ''
        mkdir -p "$out/share/vale/styles"
        cp -r ${./vale/Sealambda/styles}/. "$out/share/vale/styles"
      '';
    in
    pkgs.symlinkJoin {
      name = "vale-styles-sealambda";
      paths = [
        pkgs.valeStyles.google
        pkgs.valeStyles.microsoft
        sealambda
      ];
    };

  # The package configuration of the Sealambda package with one addition: the
  # StylesPath of the styles above. The source file has no Packages line, so
  # Vale fetches nothing from the network.
  valeConfig = pkgs.writeText "vale.ini" (
    "StylesPath = ${valeStyles}/share/vale/styles\n" + builtins.readFile ./vale/Sealambda/.vale.ini
  );

  # The `Packages` line of the release asset: the release of a Vale style
  # package of the vale-cli organization, at the version of nixpkgs. This is
  # the only place that names the versions, so the asset and the Nix check lint
  # with the same Google and Microsoft rules.
  # Arguments: the name of the style ("Google") and its nixpkgs package.
  styleRelease =
    name: package:
    "https://github.com/vale-cli/${name}/releases/download/v${package.version}/${name}.zip";
  packagesLine = "Packages = ${
    lib.concatStringsSep ", " [
      (styleRelease "Google" pkgs.valeStyles.google)
      (styleRelease "Microsoft" pkgs.valeStyles.microsoft)
    ]
  }";

  # The `docs-check` program.
  docsCheck = pkgs.writeShellApplication {
    name = "docs-check";
    runtimeInputs = [
      markdownlint
      markdownlintTemplates
      pkgs.coreutils
      pkgs.findutils
      # `git ls-files` selects the documents in a Git work tree.
      pkgs.git
      pkgs.lychee
      pkgs.vale
    ];
    runtimeEnv = {
      # lychee builds its HTTP client before it reads a document, even with
      # `--offline`, and the client needs CA certificates. The Linux build
      # sandbox sets SSL_CERT_FILE to a missing file, so lychee would fail
      # there. The bundle comes from nixpkgs.
      SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      DOCS_KIT_VALE_CONFIG = valeConfig;
      DOCS_KIT_LYCHEE_CONFIG = ./lychee.toml;
      DOCS_KIT_TEMPLATE_PATTERNS = lib.concatStringsSep "\n" githubTemplatePatterns;
    };
    text = builtins.readFile ./docs-check.sh;
  };

  # `Sealambda.zip`: one folder, Sealambda, with the package configuration
  # (with the Packages line added) and the styles. A consumer does not need the
  # `*.test.yml` files, so they stay out. The archive is reproducible: the file
  # list is sorted, every time stamp is the same and in UTC, and `-X` drops the
  # extra attributes.
  valePackage = pkgs.runCommandLocal "vale-package" { nativeBuildInputs = [ pkgs.zip ]; } ''
    export TZ=UTC LC_ALL=C
    mkdir -p "$out" package
    cp -r ${./vale}/. package
    chmod -R u+w package
    {
      printf '# Added by the docs kit (kit.nix) when it builds this asset.\n%s\n\n' \
        ${lib.escapeShellArg packagesLine}
      cat ${./vale/Sealambda/.vale.ini}
    } > package/Sealambda/.vale.ini
    find package -exec touch -h -d @1 {} +
    cd package
    find Sealambda -type f ! -name '*.test.yml' | sort | zip -X -q "$out/Sealambda.zip" -@
  '';
in
{
  inherit
    docsCheck
    githubTemplatePatterns
    markdownlint
    markdownlintConfigs
    markdownlintTemplates
    valeConfig
    valePackage
    valeStyles
    ;
}
