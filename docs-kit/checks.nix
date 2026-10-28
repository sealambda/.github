# The checks of the docs kit for one system, as an attribute set of
# derivations (the `checks` output of the flake).
#
# The documents of the kit have no check here. Its README links to the pages
# in `docs/` of the repository, which are outside this flake's source, so the
# docs check of the repository root checks them (flake.nix of the root).
#
# Arguments:
#   pkgs      the package set of the system;
#   kit       the programs of kit.nix for that system.
{ pkgs, kit }:
let
  inherit (pkgs) lib;

  styleSource = ./vale/Sealambda/styles/Sealambda;

  # One fixture of the `docs-check-fixtures` check: a derivation that builds a
  # small tree of documents, runs `docs-check` on it, and fails unless the exit
  # status and the output are the expected ones. The expected values in the
  # cases below are written by hand, and none is read from the code under test.
  #
  # Arguments (an attribute set):
  #   name            the name of the derivation;
  #   files           an attribute set from a path in the tree to its text;
  #   git             whether the tree is a Git work tree (`git init` and
  #                   `git add -A`, so that `.gitignore` applies);
  #   args            the options of `docs-check`, a list of strings;
  #   environment     variables that `docs-check` gets, an attribute set from a
  #                   name to its text;
  #   status         the expected exit status;
  #   contains        strings that the output must contain;
  #   lacks           strings that the output must not contain;
  #   treeHas         paths in the tree that must exist after the run;
  #   treeLacks       paths in the tree that must not exist after the run.
  mkFixture =
    {
      name,
      files,
      git ? false,
      args ? [ ],
      environment ? { },
      status,
      contains ? [ ],
      lacks ? [ ],
      treeHas ? [ ],
      treeLacks ? [ ],
    }:
    let
      # The shell line that writes one file of the tree.
      installFile =
        path: text:
        "install -D -m 0644 ${pkgs.writeText "fixture" text} ${lib.escapeShellArg "tree/${path}"}";
      # The shell lines that fail the fixture unless the output has `text`.
      assertContains = text: ''
        grep -qF -e ${lib.escapeShellArg text} output \
          || { echo "FIXTURE: the output lacks: ${text}" >&2; exit 1; }
      '';
      # The shell lines that fail the fixture if the output has `text`.
      assertLacks = text: ''
        if grep -qF -e ${lib.escapeShellArg text} output; then
          echo "FIXTURE: the output has: ${text}" >&2
          exit 1
        fi
      '';
      # The shell lines that fail the fixture unless `path` exists in the tree.
      assertTreeHas = path: ''
        test -e ${lib.escapeShellArg "tree/${path}"} \
          || { echo "FIXTURE: the tree lacks: ${path}" >&2; exit 1; }
      '';
      # The shell lines that fail the fixture if `path` exists in the tree.
      assertTreeLacks = path: ''
        if test -e ${lib.escapeShellArg "tree/${path}"}; then
          echo "FIXTURE: the tree has: ${path}" >&2
          exit 1
        fi
      '';
    in
    pkgs.runCommandLocal "docs-check-fixture-${name}"
      {
        nativeBuildInputs = [ kit.docsCheck ] ++ lib.optional git pkgs.git;
      }
      ''
        export HOME="$TMPDIR"
        mkdir tree scratch
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList installFile files)}
        ${lib.optionalString git "git -C tree init -q && git -C tree add -A"}

        # `docs-check` writes its temporary files below `scratch`, which must
        # be empty when it ends, whatever its exit status.
        ${lib.concatStrings (
          lib.mapAttrsToList (name: text: "export ${name}=${lib.escapeShellArg text}\n") environment
        )}
        actual=0
        TMPDIR="$PWD/scratch" docs-check ${lib.escapeShellArgs args} tree >output 2>&1 || actual=$?
        cat output
        if [ "$actual" -ne ${toString status} ]; then
          echo "FIXTURE: expected exit status ${toString status}, got $actual" >&2
          exit 1
        fi
        if [ -n "$(ls -A scratch)" ]; then
          echo "FIXTURE: docs-check left temporary files:" >&2
          ls -A scratch >&2
          exit 1
        fi
        ${lib.concatMapStrings assertContains contains}
        ${lib.concatMapStrings assertLacks lacks}
        ${lib.concatMapStrings assertTreeHas treeHas}
        ${lib.concatMapStrings assertTreeLacks treeLacks}
        touch "$out"
      '';

  # A page that all three tools accept.
  cleanPage = "# Guide\n\nBuild the project.\n";

  # A page with a filler word (`Sealambda.Filler`).
  fillerPage = "# Guide\n\nSimply build the project.\n";

  # A page with a link to a file that does not exist.
  deadLinkPage = "# Guide\n\nRead [the missing guide](missing-guide.md).\n";

  # A page with a link to a host that never resolves: a name in the special-use
  # top-level domain `.onion` does not resolve (RFC 7686 tells software that is
  # not a Tor client to return an error for such a name), so the request fails
  # at once, whether or not the build has network access. The
  # domain `.invalid` (RFC 6761) would fit too, but lychee.toml excludes it.
  remoteLinkPage = "# Guide\n\nRead [the remote guide](http://docs-kit-fixture.onion/guide).\n";

  # A pull request template of GitHub: the first line is a level-2 heading, and
  # the text holds a filler word and a dead link, which are right in a template.
  placeholderTemplate = "## Why\n\nSimply say [why](missing-guide.md).\n";

  # The fixtures of the check `docs-check-fixtures`. Each one names the finding
  # or the rule that it covers.
  fixtureCases = [
    # A near miss of a template name is a page.
    (mkFixture {
      name = "near-miss-template-name";
      files."docs/email-templates.md" = "# Emails\n\nSimply send [the mail](missing-guide.md).\n";
      status = 1;
      contains = [
        "Sealambda.Filler"
        "missing-guide.md"
      ];
    })

    # A hidden directory is searched, with and without Git.
    (mkFixture {
      name = "dead-link-under-hidden-directory";
      files.".github/SECURITY.md" = deadLinkPage;
      status = 1;
      contains = [ "missing-guide.md" ];
    })
    (mkFixture {
      name = "dead-link-under-hidden-directory-git";
      git = true;
      files.".github/SECURITY.md" = deadLinkPage;
      status = 1;
      contains = [ "missing-guide.md" ];
    })

    # Each tool is wired in: one finding for each.
    (mkFixture {
      name = "vale-runs";
      files."guide.md" = fillerPage;
      status = 1;
      contains = [ "Sealambda.Filler" ];
    })
    (mkFixture {
      name = "markdownlint-runs";
      files."guide.md" = "# Guide\n\n### Skipped level\n";
      status = 1;
      contains = [ "MD001" ];
    })
    (mkFixture {
      name = "lychee-runs";
      files."guide.md" = deadLinkPage;
      status = 1;
      contains = [ "missing-guide.md" ];
    })
    (mkFixture {
      name = "lychee-checks-anchors";
      files = {
        "guide.md" = "# Guide\n\nRead [the section](other.md#no-such-section).\n";
        "other.md" = "# Other\n\nBuild the project.\n";
      };
      status = 1;
      contains = [ "no-such-section" ];
    })

    # A usage error is exit status 2, not 1.
    (mkFixture {
      name = "unknown-option";
      files."guide.md" = cleanPage;
      args = [ "--no-such-option" ];
      status = 2;
      contains = [ "unknown option: --no-such-option" ];
    })
    (mkFixture {
      name = "two-directories";
      files."guide.md" = cleanPage;
      args = [ "elsewhere" ];
      status = 2;
      contains = [ "more than one directory" ];
    })

    # A file name that starts with `-` is a file for Vale and for lychee, not
    # an option.
    (mkFixture {
      name = "dash-name-clean";
      files."-dash.md" = cleanPage;
      status = 0;
    })
    (mkFixture {
      name = "dash-name-vale";
      files."-dash.md" = fillerPage;
      status = 1;
      contains = [ "Sealambda.Filler" ];
      lacks = [ "unknown shorthand flag" ];
    })
    (mkFixture {
      name = "dash-name-lychee";
      files."-dash.md" = deadLinkPage;
      status = 1;
      contains = [ "missing-guide.md" ];
    })

    # Command words in lower case are not terms of the vocabulary.
    (mkFixture {
      name = "lowercase-command-words";
      files."guide.md" =
        "# Guide\n\nRun ssh to open a shell. Use cd to change the directory. Show the id of the process, and the os of the host.\n";
      status = 0;
    })

    # A path that Git does not track is not a document.
    (mkFixture {
      name = "ignored-path";
      git = true;
      files = {
        ".gitignore" = "deps/\n";
        "guide.md" = cleanPage;
        "deps/vendored.md" = "# Vendored\n\n### Skipped level\n\nSimply read [it](missing-guide.md).\n";
      };
      status = 0;
    })
    (mkFixture {
      name = "tracked-path-is-checked";
      git = true;
      files = {
        ".gitignore" = "deps/\n";
        "guide.md" = fillerPage;
      };
      status = 1;
      contains = [ "Sealambda.Filler" ];
    })

    # The templates that GitHub documents are not checked for prose and links,
    # and a first-line heading is not required, in every documented location and
    # in several spellings of the case. No two paths differ only
    # by case, because the build sandbox of macOS has a case-insensitive file
    # system.
    (mkFixture {
      name = "github-templates";
      files = {
        "guide.md" = cleanPage;
        "Pull_Request_Template.md" = placeholderTemplate;
        "docs/PULL_REQUEST_TEMPLATE.md" = placeholderTemplate;
        ".github/pull_request_template.md" = placeholderTemplate;
        ".github/PULL_REQUEST_TEMPLATE/release.md" = placeholderTemplate;
        "PULL_REQUEST_TEMPLATE/feature.md" = placeholderTemplate;
        "docs/pull_request_template/hotfix.md" = placeholderTemplate;
        ".github/Issue_Template/bug.md" = placeholderTemplate;
      };
      status = 0;
    })

    # GitHub documents issue templates only in `.github/ISSUE_TEMPLATE`, so the
    # same paths in the root and in `docs` are pages.
    (mkFixture {
      name = "undocumented-issue-template-locations-are-pages";
      files = {
        "docs/ISSUE_TEMPLATE/change.md" = fillerPage;
        "issue_template/question.md" = fillerPage;
      };
      status = 1;
      contains = [
        "change.md"
        "question.md"
        "Sealambda.Filler"
      ];
    })

    # A template of GitHub still gets the structure rules.
    (mkFixture {
      name = "github-template-structure";
      files = {
        ".github/ISSUE_TEMPLATE/bug.md" = "## Why\n\n#### Skipped level\n";
      };
      status = 1;
      contains = [ "MD001" ];
      lacks = [ "MD041" ];
    })

    # The option --template adds a pattern, and only the files that match it
    # are templates.
    (mkFixture {
      name = "template-option";
      files = {
        "guide.md" = cleanPage;
        "templates/page.md" = "# {Title}\n\nSimply say [it](missing-guide.md).\n";
      };
      args = [
        "--template"
        "templates/*"
      ];
      status = 0;
    })
    # A file of the option --template is a template like the GitHub ones: the
    # rule MD041 is off, and the other structure rules apply.
    (mkFixture {
      name = "template-option-skips-md041";
      files."templates/form.md" = "## Why\n\nSay why.\n";
      args = [
        "--template"
        "templates/*"
      ];
      status = 0;
    })
    (mkFixture {
      name = "template-option-checks-structure";
      files."templates/form.md" = "## Why\n\n#### Skipped level\n";
      args = [
        "--template"
        "templates/*"
      ];
      status = 1;
      contains = [ "MD001" ];
      lacks = [ "MD041" ];
    })
    # The `ignores` key of the repository applies to the run on the templates.
    (mkFixture {
      name = "repository-config-ignores-a-template";
      files = {
        "templates/form.md" = "## Why\n\n#### Skipped level\n";
        ".markdownlint-cli2.yaml" = ''
          ignores:
            - "templates/*.md"
        '';
      };
      args = [
        "--template"
        "templates/*"
      ];
      status = 0;
    })
    (mkFixture {
      name = "template-option-matches-only-its-pattern";
      files."docs/page.md" = fillerPage;
      args = [
        "--template"
        "templates/*"
      ];
      status = 1;
      contains = [ "Sealambda.Filler" ];
    })
    # The variable DOCS_CHECK_TEMPLATES holds one pattern on each line. The
    # empty line between the two patterns adds none, so it does not make the
    # pattern `` that would match nothing, or everything.
    (mkFixture {
      name = "template-environment-adds-patterns";
      files = {
        "guide.md" = cleanPage;
        "templates/page.md" = "# {Title}\n\nSimply say [it](missing-guide.md).\n";
        "forms/page.md" = "# {Title}\n\nSimply say [it](missing-guide.md).\n";
      };
      environment.DOCS_CHECK_TEMPLATES = "templates/*\n\nforms/*\n";
      status = 0;
    })
    (mkFixture {
      name = "template-environment-matches-only-its-patterns";
      files = {
        "templates/page.md" = "# {Title}\n\nSimply say [it](missing-guide.md).\n";
        "docs/page.md" = fillerPage;
      };
      environment.DOCS_CHECK_TEMPLATES = "templates/*\n\n";
      status = 1;
      contains = [ "Sealambda.Filler" ];
      # The dead link is in the template only, so lychee did not get the file.
      lacks = [ "missing-guide.md" ];
    })
    (mkFixture {
      name = "template-directory-without-option-is-a-page";
      files."templates/page.md" = fillerPage;
      status = 1;
      contains = [ "Sealambda.Filler" ];
    })

    # `--online` runs lychee only, with the cache. The page below has a filler
    # word and a skipped heading level, which Vale and markdownlint would
    # report, and only local links, so the run needs no network.
    (mkFixture {
      name = "online-runs-lychee-only";
      files."guide.md" = "# Guide\n\nSimply build the project.\n\n### Skipped level\n";
      args = [ "--online" ];
      status = 0;
      contains = [ "== lychee (all links), 1 files" ];
      lacks = [
        "== Vale"
        "== markdownlint"
        "Sealambda.Filler"
        "MD001"
      ];
      treeHas = [ ".lycheecache" ];
    })
    (mkFixture {
      name = "online-checks-local-links";
      files."guide.md" = deadLinkPage;
      args = [ "--online" ];
      status = 1;
      contains = [ "missing-guide.md" ];
    })
    # The page keeps lychee running, so that the template with a dead link
    # shows whether lychee gets it.
    (mkFixture {
      name = "online-skips-templates";
      files = {
        "guide.md" = cleanPage;
        ".github/pull_request_template.md" = placeholderTemplate;
      };
      args = [ "--online" ];
      status = 0;
      contains = [ "== lychee (all links), 1 files" ];
    })
    # The host of `remoteLinkPage` never resolves, so the request fails and the
    # output names the host.
    (mkFixture {
      name = "online-requests-remote-links";
      files."guide.md" = remoteLinkPage;
      args = [ "--online" ];
      status = 1;
      contains = [ "docs-kit-fixture.onion" ];
    })
    # Without `--online`, a link to another site is not requested, and the run
    # leaves no cache file in the checked tree.
    (mkFixture {
      name = "offline-skips-remote-links";
      files."guide.md" = remoteLinkPage;
      status = 0;
      lacks = [ "docs-kit-fixture.onion" ];
      treeLacks = [ ".lycheecache" ];
    })
  ];

  # The bare script, without the variables that the Nix wrapper sets, must end
  # with status 2 and an error message before it creates a temporary
  # directory, and it must leave no temporary file. A script that creates the
  # directory first and then stops on the unset variable leaves a temporary
  # copy of the configuration behind.
  missingEnvironment = pkgs.runCommandLocal "docs-check-fixture-missing-environment" { } ''
    mkdir tree scratch
    printf '# Guide\n\nBuild the project.\n' >tree/guide.md

    actual=0
    env -u DOCS_KIT_VALE_CONFIG -u DOCS_KIT_LYCHEE_CONFIG TMPDIR="$PWD/scratch" \
      ${pkgs.bash}/bin/bash ${./docs-check.sh} tree >output 2>&1 || actual=$?
    cat output
    test "$actual" -eq 2
    grep -qF 'DOCS_KIT_VALE_CONFIG' output
    test -z "$(ls -A scratch)"
    touch "$out"
  '';

  # A lychee that cannot run is a failure of the setup, exit status 2, and not
  # a broken link, exit status 1: the workflow `links.yml` opens its issue for
  # status 1 only. The bare script gets a lychee configuration that does not
  # exist, which makes lychee end with status 3 (lychee 0.24: 0 ok, 2 broken
  # links, 1 and 3 errors of the run or the configuration).
  lycheeCannotRun =
    pkgs.runCommandLocal "docs-check-fixture-lychee-cannot-run"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.findutils
          pkgs.lychee
        ];
      }
      ''
        mkdir tree scratch
        printf '# Guide\n\nBuild the project.\n' >tree/guide.md

        actual=0
        TMPDIR="$PWD/scratch" SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
          DOCS_KIT_VALE_CONFIG=unused DOCS_KIT_TEMPLATE_PATTERNS=unused \
          DOCS_KIT_LYCHEE_CONFIG="$PWD/no-such-lychee.toml" \
          bash ${./docs-check.sh} --online tree >output 2>&1 || actual=$?
        cat output
        test "$actual" -eq 2
        grep -qF 'lychee could not run (exit status 3)' output
        test -z "$(ls -A scratch)"
        touch "$out"
      '';

  # Vale that cannot run is a failure of the setup, exit status 2, and not a
  # finding, exit status 1. The bare script gets a Vale configuration whose
  # StylesPath does not exist, which makes Vale end with status 2 (Vale 3.25:
  # 0 no alert, 1 an alert at the level, 2 an error of the run).
  valeCannotRun =
    pkgs.runCommandLocal "docs-check-fixture-vale-cannot-run"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.findutils
          pkgs.vale
        ];
      }
      ''
        mkdir tree scratch
        printf '# Guide\n\nBuild the project.\n' >tree/guide.md
        printf 'StylesPath = %s/no-such-styles\n' "$PWD" >bad-vale.ini

        actual=0
        TMPDIR="$PWD/scratch" DOCS_KIT_VALE_CONFIG="$PWD/bad-vale.ini" \
          DOCS_KIT_LYCHEE_CONFIG=unused DOCS_KIT_TEMPLATE_PATTERNS=unused \
          bash ${./docs-check.sh} tree >output 2>&1 || actual=$?
        cat output
        test "$actual" -eq 2
        grep -qF 'vale could not run (exit status 2)' output
        test -z "$(ls -A scratch)"
        touch "$out"
      '';

  # markdownlint-cli2 that cannot run is a failure of the setup, exit status 2,
  # and not a finding, exit status 1. The stand-in `markdownlint-sealambda`
  # runs the real program with a configuration file that does not exist, which
  # makes it end with status 2 (markdownlint-cli2 0.23: 0 no error, 1 an error
  # in a document, 2 a problem or failure). Vale gets the configuration of the
  # kit and passes.
  #
  # Two runs cover the two calls of the check, the one for the pages and the
  # one for the templates. The tree has a page and a template. In the first run
  # both stand-ins fail, and the run for the pages ends the check. In the
  # second run the stand-in for the pages passes and records its call, so the
  # check reaches the run for the templates, whose stand-in fails. The second
  # run also shows that the check stops there: lychee, which comes next, does
  # not start.
  markdownlintCannotRun =
    pkgs.runCommandLocal "docs-check-fixture-markdownlint-cannot-run"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.findutils
          pkgs.vale
          pkgs.markdownlint-cli2
        ];
      }
      ''
        mkdir tree scratch bin-both bin-templates
        printf '# Guide\n\nBuild the project.\n' >tree/guide.md
        printf '## Form\n\nFill in the form.\n' >tree/form.md
        export HOME="$TMPDIR"

        # Writes the stand-in $1 into the directory $2: markdownlint-cli2 with
        # a configuration file that does not exist, which ends with status 2.
        write_failing_stand_in() {
          printf '#!%s\nexec markdownlint-cli2 --config "%s/no-such.yaml" "$@"\n' \
            ${pkgs.bash}/bin/bash "$PWD" >"$2/$1"
          chmod +x "$2/$1"
        }

        # Writes the stand-in $1 into the directory $2: a program that creates
        # the file `pages-called` and passes.
        write_passing_stand_in() {
          printf '#!%s\ntouch "%s/pages-called"\n' \
            ${pkgs.bash}/bin/bash "$PWD" >"$2/$1"
          chmod +x "$2/$1"
        }

        # Runs docs-check on the tree, with the stand-ins of the directory $1
        # first on the PATH and `form.md` as a template. Sets `actual` to the
        # exit status and writes the output to `output`.
        run_docs_check() {
          actual=0
          PATH="$PWD/$1:$PATH" TMPDIR="$PWD/scratch" \
            DOCS_KIT_VALE_CONFIG=${kit.valeConfig} \
            DOCS_KIT_LYCHEE_CONFIG=unused DOCS_KIT_TEMPLATE_PATTERNS=unused \
            bash ${./docs-check.sh} --template form.md tree >output 2>&1 || actual=$?
          cat output
        }

        write_failing_stand_in markdownlint-sealambda bin-both
        write_failing_stand_in markdownlint-sealambda-templates bin-both
        run_docs_check bin-both
        test "$actual" -eq 2
        grep -qF 'markdownlint-cli2 could not run (exit status 2)' output
        test -z "$(ls -A scratch)"

        write_passing_stand_in markdownlint-sealambda bin-templates
        write_failing_stand_in markdownlint-sealambda-templates bin-templates
        run_docs_check bin-templates
        test "$actual" -eq 2
        grep -qF 'markdownlint-cli2 could not run (exit status 2)' output
        test -e pages-called
        if grep -qF '== lychee' output; then exit 1; fi
        test -z "$(ls -A scratch)"
        touch "$out"
      '';

  # The reserved example domains (RFC 2606, RFC 6761) are not requested, and
  # the names that only look like them are. `lychee --dump` lists the links
  # that lychee would request after it applies the exclusions of lychee.toml,
  # and it requests none.
  exampleDomains =
    let
      reserved = [
        "https://api.example.com/v1"
        "https://example.com:8443/x"
        "http://example.org"
        "https://a.b.example.net/p?q=1"
        "https://foo.example/"
        "https://x.invalid/"
        "https://sub.localhost:3000/"
        "https://svc.test/path"
        "HTTPS://API.EXAMPLE.COM/upper"
      ];
      requested = [
        "https://notexample.com/"
        "https://example.com.evil.org/"
        "https://example.community/"
        "https://valid.invalidity.io/"
        "https://example.co.uk/"
      ];
      document = pkgs.writeText "example-domains.md" (
        "# Links\n\n" + lib.concatMapStrings (url: "- ${url}\n") (reserved ++ requested)
      );
      expected = pkgs.writeText "expected-links" (lib.concatMapStrings (url: "${url}\n") requested);
    in
    pkgs.runCommandLocal "docs-check-fixture-example-domains"
      {
        nativeBuildInputs = [ pkgs.lychee ];
        SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      }
      ''
        lychee --config ${./lychee.toml} --dump ${document} | sort >actual
        sort ${expected} >wanted
        diff -u wanted actual
        touch "$out"
      '';

  # A directory of files in the Nix store.
  # Arguments: the name of the directory, and an attribute set from the file
  # name to the text of the file.
  directory =
    name: files:
    pkgs.linkFarm name (
      lib.mapAttrsToList (path: text: {
        name = path;
        path = pkgs.writeText (baseNameOf path) text;
      }) files
    );

  # A commit SHA of 40 hexadecimal characters, written out by hand.
  commit = "0123456789abcdef0123456789abcdef01234567";

  # A decision record with the given status in its front matter.
  record = status: ''
    ---
    status: "${status}"
    ---

    # A decision
  '';

  # A row of the ledger of decision records. The permalink is a Markdown link.
  # Arguments: an attribute set with `number`, `status`, and optionally
  # `replaced` ("none" by default) and `sha` (a full commit SHA by default).
  ledgerRow =
    {
      number,
      status,
      replaced ? "none",
      sha ? commit,
    }:
    "| ${number} | A decision | ${status} | ${replaced} | The reason. | [permalink](https://github.com/example-org/example-repo/blob/${sha}/docs/decisions/${number}-a-decision.md) |\n";

  # The ledger file: the table header and the given rows.
  ledger = rows: ''
    # Decisions

    | Number | Title | Status | Replaced by | Reason | Permalink |
    | ------ | ----- | ------ | ----------- | ------ | --------- |
    ${lib.concatStrings rows}'';

  # The cases of the `decisions-ledger` program. Each case is a directory of
  # records and a ledger, the exit status that the program must return, and a
  # text that its message must hold. The expected values are written out by
  # hand and do not come from the program.
  ledgerCases = [
    {
      name = "valid tree and ledger";
      files = {
        "0001-first.md" = record "accepted";
        "0002-second.md" = record "proposed";
        "README.md" = ledger [
          (ledgerRow {
            number = "0003";
            status = "rejected";
          })
          (ledgerRow {
            number = "0004";
            status = "superseded";
            replaced = "0001";
          })
          (ledgerRow {
            number = "0005";
            status = "deprecated";
            replaced = "0002";
          })
          (ledgerRow {
            number = "0006";
            status = "superseded";
            replaced = "0004";
          })
        ];
      };
      exit = 0;
    }
    {
      name = "a record in the tree is superseded";
      files = {
        "0001-first.md" = record "superseded";
        "README.md" = ledger [ ];
      };
      exit = 1;
      message = "is not proposed or accepted";
    }
    {
      name = "a record has no status";
      files = {
        "0001-first.md" = "# A decision\n";
        "README.md" = ledger [ ];
      };
      exit = 1;
      message = "is not proposed or accepted";
    }
    {
      name = "a record has no number in its name";
      files = {
        "decision.md" = record "accepted";
        "README.md" = ledger [ ];
      };
      exit = 1;
      message = "NNNN-title.md";
    }
    {
      name = "a number is in the tree and in the ledger";
      files = {
        "0001-first.md" = record "accepted";
        "README.md" = ledger [
          (ledgerRow {
            number = "0001";
            status = "rejected";
          })
        ];
      };
      exit = 1;
      message = "used more than once";
    }
    {
      name = "two records in the tree have the same number";
      files = {
        "0001-first.md" = record "accepted";
        "0001-second.md" = record "proposed";
        "README.md" = ledger [ ];
      };
      exit = 1;
      message = "the number 0001 is also used by";
    }
    {
      name = "a record is replaced by itself";
      files = {
        "README.md" = ledger [
          (ledgerRow {
            number = "0001";
            status = "superseded";
            replaced = "0001";
          })
        ];
      };
      exit = 1;
      message = "a record cannot replace itself";
    }
    {
      name = "the replaced by cell is empty";
      files = {
        "README.md" = ledger [
          (ledgerRow {
            number = "0001";
            status = "deprecated";
            replaced = "";
          })
        ];
      };
      exit = 1;
      message = "'replaced by' needs a number or 'none'";
    }
    {
      name = "a number is twice in the ledger";
      files = {
        "README.md" = ledger [
          (ledgerRow {
            number = "0001";
            status = "rejected";
          })
          (ledgerRow {
            number = "0001";
            status = "deprecated";
          })
        ];
      };
      exit = 1;
      message = "used more than once";
    }
    {
      name = "the final status is not in the set";
      files = {
        "README.md" = ledger [
          (ledgerRow {
            number = "0001";
            status = "accepted";
          })
        ];
      };
      exit = 1;
      message = "is not rejected, deprecated or superseded";
    }
    {
      name = "a superseded record has no replacement";
      files = {
        "README.md" = ledger [
          (ledgerRow {
            number = "0001";
            status = "superseded";
          })
        ];
      };
      exit = 1;
      message = "needs the number of its replacement";
    }
    {
      name = "the replacement does not exist";
      files = {
        "README.md" = ledger [
          (ledgerRow {
            number = "0001";
            status = "superseded";
            replaced = "0099";
          })
        ];
      };
      exit = 1;
      message = "does not resolve";
    }
    {
      name = "the permalink has a short SHA";
      files = {
        "README.md" = ledger [
          (ledgerRow {
            number = "0001";
            status = "rejected";
            sha = "0123456";
          })
        ];
      };
      exit = 1;
      message = "40-character commit SHA";
    }
    {
      name = "the permalink names a branch";
      files = {
        "README.md" = ledger [
          (ledgerRow {
            number = "0001";
            status = "rejected";
            sha = "main";
          })
        ];
      };
      exit = 1;
      message = "40-character commit SHA";
    }
    {
      name = "there is no ledger";
      files = {
        "0001-first.md" = record "accepted";
      };
      exit = 2;
      message = "is missing";
    }
  ];

  # The shell that runs one case of `ledgerCases`. It records a failure in
  # `failed` and goes on, so that one run shows every wrong case.
  runLedgerCase =
    case:
    ''
      status=0
      decisions-ledger ${directory "decisions" case.files} 2> stderr || status=$?
      if [ "$status" -ne ${toString case.exit} ]; then
        echo "${case.name}: exit status $status, expected ${toString case.exit}" >&2
        cat stderr >&2
        failed=1
      fi
    ''
    + lib.optionalString (case ? message) ''
      if ! grep -qF -- ${lib.escapeShellArg case.message} stderr; then
        echo "${case.name}: the message lacks '${case.message}'" >&2
        cat stderr >&2
        failed=1
      fi
    '';
in
{
  # The cases of every rule of the Sealambda style (`*.test.yml`). `--coverage`
  # fails when a rule produces no alert in any case. Every rule also has an
  # absolute link, because an editor and a pull request comment show the link
  # of the rule outside the repository.
  vale-rules = pkgs.runCommandLocal "vale-rules" { nativeBuildInputs = [ pkgs.vale ]; } ''
    vale test --no-global --config ${kit.valeConfig} --coverage ${styleSource}

    status=0
    for rule in ${styleSource}/*.yml; do
      case "$rule" in
        *.test.yml) continue ;;
      esac
      if ! grep -q '^link: https://' "$rule"; then
        echo "$rule: the key link must be an absolute URL (https://...)" >&2
        status=1
      fi
    done
    test "$status" -eq 0
    touch "$out"
  '';

  # The vocabulary fixes the case of the words it lists (`Vale.Terms`). A
  # command or an ordinary word in lower case, such as `ssh`, `cd`, `gpg`,
  # `id`, `ip`, `os`, `prettier`, `elixir`, `markdown` and `vale`, must pass,
  # and a word of the list in another case must fail, so that the first test
  # cannot pass because the vocabulary is not loaded.
  vale-vocabulary =
    pkgs.runCommandLocal "vale-vocabulary"
      {
        nativeBuildInputs = [ pkgs.vale ];
        lowerCase = ''
          Use ssh to connect to the host. Run the cd command in the shell.
          The id of a user and the os of a host are plain words.
          Run gpg to sign a tag. Run ip to show the address of a host.
          A prettier layout, an elixir, plain markdown and the vale are words.
        '';
        wrongCase = ''
          Open the github page.
        '';
        passAsFile = [
          "lowerCase"
          "wrongCase"
        ];
      }
      ''
        lint() {
          vale --no-global --config ${kit.valeConfig} --minAlertLevel=error --output=line "$1"
        }
        cp "$lowerCasePath" lower-case.md
        cp "$wrongCasePath" wrong-case.md

        lint lower-case.md
        if lint wrong-case.md > alerts; then
          echo "Vale.Terms did not flag 'github'; the vocabulary may not be loaded." >&2
          exit 1
        fi
        grep -q "Use 'GitHub' instead of 'github'" alerts
        touch "$out"
      '';

  # The release asset has one folder, Sealambda, with the package
  # configuration and the styles (https://docs.vale.sh/packages). It has no
  # rule test, because a consumer does not need it. Its `Packages` line is the
  # only one in the file, and names Google and Microsoft by a release URL. A
  # comment of the file must not say that it has no such line, because the
  # asset has one.
  vale-package = pkgs.runCommandLocal "vale-package" { nativeBuildInputs = [ pkgs.unzip ]; } ''
    zip=${kit.valePackage}/Sealambda.zip
    test "$(unzip -Z1 "$zip" | cut -d/ -f1 | sort -u)" = Sealambda
    unzip -Z1 "$zip" | grep -qx 'Sealambda/.vale.ini'
    unzip -Z1 "$zip" | grep -qx 'Sealambda/styles/Sealambda/Filler.yml'
    unzip -Z1 "$zip" | grep -qx 'Sealambda/styles/config/vocabularies/Sealambda/accept.txt'
    if unzip -Z1 "$zip" | grep -q '\.test\.yml$'; then
      echo "The asset holds a rule test (*.test.yml)." >&2
      exit 1
    fi
    unzip -p "$zip" Sealambda/.vale.ini > vale.ini
    test "$(grep -c '^Packages = ' vale.ini)" -eq 1
    if grep -q 'file has no Packages line' vale.ini; then
      echo "A comment of the asset says that it has no Packages line." >&2
      exit 1
    fi
    grep -qE '^Packages = https://github.com/vale-cli/Google/releases/download/v[0-9.]+/Google.zip, https://github.com/vale-cli/Microsoft/releases/download/v[0-9.]+/Microsoft.zip$' vale.ini
    touch "$out"
  '';

  # The fixtures of `docs-check`: trees of documents that it must reject, and
  # trees that it must accept, so that a refactor cannot drop a tool, a
  # document or a rule without a failure. Each fixture is its own derivation, so
  # that a failure shows its name and its output.
  docs-check-fixtures = pkgs.linkFarm "docs-check-fixtures" (
    lib.listToAttrs (
      map (fixture: lib.nameValuePair fixture.name fixture) (
        fixtureCases
        ++ [
          missingEnvironment
          lycheeCannotRun
          valeCannotRun
          markdownlintCannotRun
          exampleDomains
        ]
      )
    )
  );

  # The cases of the `decisions-ledger` program (`ledgerCases`).
  decisions-ledger =
    pkgs.runCommandLocal "decisions-ledger" { nativeBuildInputs = [ kit.decisionsLedger ]; }
      ''
        failed=0
        ${lib.concatMapStrings runLedgerCase ledgerCases}
        test "$failed" -eq 0
        touch "$out"
      '';
}
