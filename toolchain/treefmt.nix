# The organization's formatters and linters, as one treefmt-nix module.
#
# treefmt is the single entry point: `nix fmt` formats and lints the tree,
# and a repository's `formatting` check can run the same programs in the build
# sandbox and fail on any finding or change. Each program selects its files
# here, once.
#
# A consumer imports this module and adds its own settings; the module system
# merges them (for example a longer `excludes` list, or more yamllint rules).
# Repository files that the tools read on their own stay in each repository:
# .editorconfig (shfmt, Prettier, editorconfig-checker), and optional
# _typos.toml, .github/zizmor.yml and .github/actionlint.yaml.
#
# Order on a file: priority 0 fixes formatting, priority 1 lints the result.
{ lib, pkgs, ... }:
let
  # A program that lints and never writes. treefmt fails when it exits
  # non-zero.
  linter = attrs: { priority = 1; } // attrs;

  # statix checks one path per call, so a wrapper loops over the files.
  statixCheck = pkgs.writeShellApplication {
    name = "statix-check";
    runtimeInputs = [ pkgs.statix ];
    text = ''
      status=0
      for path in "$@"; do
        statix check -- "''${path}" || status=1
      done
      exit "''${status}"
    '';
  };

  # check-executables-have-shebangs reads every path it gets as executable:
  # pre-commit, its usual caller, passes only executable files. treefmt
  # selects by name, so this wrapper drops the files that are not executable.
  executablesHaveShebangs = pkgs.writeShellApplication {
    name = "executables-have-shebangs";
    runtimeInputs = [ pkgs.python3Packages.pre-commit-hooks ];
    text = ''
      executables=()
      for path in "$@"; do
        if [[ -x "''${path}" ]]; then
          executables+=("''${path}")
        fi
      done
      if ((''${#executables[@]} > 0)); then
        check-executables-have-shebangs "''${executables[@]}"
      fi
    '';
  };

  # The organization's own shell lints (lints/default.nix): they run as
  # `shell-script-names` and `bash-strict-mode` below.
  inherit (import ./lints pkgs) shellScriptNames bashStrictMode;
in
{
  # Lock files are generated.
  settings.global.excludes = [
    "*.lock"
    "pnpm-lock.yaml"
  ];

  programs = {
    # Formatters.
    nixfmt.enable = true;
    prettier = {
      enable = true;
      # Prettier owns Markdown, YAML and JSON; its defaults apply, and it
      # reads indentation and line endings from .editorconfig.
      includes = lib.mkDefault [
        "*.json"
        "*.md"
        "*.yaml"
        "*.yml"
      ];
    };
    shfmt = {
      enable = true;
      # Any printer flag makes shfmt ignore .editorconfig, which holds the
      # Google Shell Style Guide settings for editors and for this hook.
      useEditorConfig = true;
    };

    # Linters.
    shellcheck = {
      enable = true;
      priority = 1;
      external-sources = true;
      source-path = "SCRIPTDIR";
      # The optional checks that the Google Shell Style Guide asks for:
      # "${var}" braces, [[ ]] tests, quoted variables, explicit -n tests,
      # no masked return values, a default case, `command -v` over `which`.
      # `check-set-e-suppressed` is the organization's addition: `set -e` has
      # no effect inside a function that runs as an `if` condition or before
      # `||`, so a function there must not rely on it (SC2310, SC2311).
      extra-checks = [
        "add-default-case"
        "avoid-nullary-conditions"
        "check-extra-masked-returns"
        "check-set-e-suppressed"
        "deprecate-which"
        "quote-safe-variables"
        "require-double-brackets"
        "require-variable-braces"
      ];
    };
    actionlint = {
      enable = true;
      priority = 1;
    };
    zizmor = {
      enable = true;
      priority = 1;
      includes = [
        ".github/workflows/*.yml"
        ".github/workflows/*.yaml"
        ".github/actions/**/action.yml"
        ".github/actions/**/action.yaml"
        ".github/dependabot.yml"
        ".github/dependabot.yaml"
      ];
    };
    yamllint = {
      enable = true;
      priority = 1;
      # The default rules, changed only where Prettier prints otherwise and
      # has no option, and with every finding an error.
      settings = {
        extends = "default";
        rules = {
          braces = {
            min-spaces-inside = 1;
            max-spaces-inside = 1;
            min-spaces-inside-empty = 0;
            max-spaces-inside-empty = 0;
          };
          comments = {
            level = "error";
            min-spaces-from-content = 1;
          };
          comments-indentation.level = "error";
          # A workflow or a config file does not need `---`.
          document-start = "disable";
          # Prettier keeps one blank line after a final comment.
          empty-lines.max-end = 1;
          # Prettier does not wrap long scalars, so no tool could fix a
          # finding.
          line-length = "disable";
          # GitHub's `on:` key is not a boolean.
          truthy = {
            level = "error";
            check-keys = false;
          };
        };
      };
    };
    typos = {
      enable = true;
      priority = 1;
      # Report only: a correction needs a human eye.
      autoFix = false;
    };
  };

  settings.formatter = {
    zizmor.options = [
      # Pedantic adds the code-quality audits; auditor adds likely false
      # positives, so it is no gate. The sandbox has no network, so this
      # leaves out the four online audits (impostor-commit,
      # known-vulnerable-actions, ref-confusion, stale-action-refs); only a
      # CI job with a GitHub token can run them.
      "--persona=pedantic"
      "--offline"
    ];

    statix = linter {
      command = lib.getExe statixCheck;
      includes = [ "*.nix" ];
    };
    deadnix = linter {
      command = lib.getExe pkgs.deadnix;
      # Report unused code instead of deleting it (the module passes --edit).
      options = [ "--fail" ];
      includes = [ "*.nix" ];
    };
    editorconfig-checker = linter {
      command = lib.getExe pkgs.editorconfig-checker;
      # The formatters own indentation and line length; this checks the rest
      # of .editorconfig (charset, line endings, final newline, trailing
      # whitespace) on every file, including files no formatter reads.
      options = [
        "-disable-indentation"
        "-disable-indent-size"
        "-disable-max-line-length"
      ];
      includes = [ "*" ];
    };
    # pre-commit-hooks' two checks: an executable file starts with a shebang,
    # and a file with a shebang is executable (it reads the Git index mode).
    executables-have-shebangs = linter {
      command = lib.getExe executablesHaveShebangs;
      includes = [ "*" ];
    };
    shebang-scripts-are-executable = linter {
      command = "${pkgs.python3Packages.pre-commit-hooks}/bin/check-shebang-scripts-are-executable";
      includes = [ "*" ];
    };
    # A script with a shell shebang has a name that the shell programs above
    # select (`*.sh`, `*.bash`); otherwise none of them would read it.
    shell-script-names = linter {
      command = lib.getExe shellScriptNames;
      includes = [ "*" ];
    };
    bash-strict-mode = linter {
      command = lib.getExe bashStrictMode;
      includes = [
        "*.sh"
        "*.bash"
      ];
    };
  };
}
