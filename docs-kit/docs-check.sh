#!/usr/bin/env bash
#
# Checks the Markdown documents of a directory with the docs kit of the
# organization: the prose with Vale, the structure with markdownlint-cli2, and
# the links with lychee.
#
# Usage: docs-check [--online] [--template GLOB]... [DIRECTORY]
#   DIRECTORY defaults to the current directory.
#   --online        Run lychee only, and request the links to other sites. The
#                   result of a request is cached in `.lycheecache` (see
#                   lychee.toml). Without this option, the check runs all three
#                   tools, and lychee tests the links to local files and their
#                   anchors, offline.
#   --template GLOB Treat the files that match GLOB as templates. Repeat the
#                   option for more than one pattern. See "Templates".
#
# Environment:
#   DOCS_CHECK_TEMPLATES  GLOBs for --template, one on each line. An empty line
#                         is ignored. The reusable workflow docs.yml passes its
#                         input `templates` this way. The patterns add to those
#                         of the option --template.
#
# The Nix wrapper of the kit (kit.nix) puts vale, lychee,
# markdownlint-sealambda (markdownlint-cli2 with the base configuration) and
# markdownlint-sealambda-templates (the same with MD041 off) on the PATH, and
# sets three variables:
#   DOCS_KIT_VALE_CONFIG       the Vale configuration of the Sealambda style;
#   DOCS_KIT_LYCHEE_CONFIG     the lychee configuration;
#   DOCS_KIT_TEMPLATE_PATTERNS the Bash patterns of the template locations that
#                              GitHub documents, one on each line.
#
# Documents: the check reads the Markdown files that Git tracks below
# DIRECTORY (`git ls-files`). Outside a Git work tree, or without `git` on the
# PATH, it reads every `.md` file below DIRECTORY, except in `.git` and
# `node_modules`. A file that Git ignores or does not track is not a document,
# so a local run and a run in CI read the same files. A hidden directory, such
# as `.github`, is searched like any other, because the check gives lychee the
# file list and not the directory. markdownlint-cli2 can skip a tracked file
# with the `ignores` key of the `.markdownlint-cli2.yaml` of the repository.
#
# Templates: a template is form text with placeholders. Vale and lychee skip
# it. markdownlint-cli2 checks it in a second run, with the configuration of
# templates.markdownlint.yaml: the base configuration with MD041 (the first line
# is a level-1 heading) off, because a template often starts with a lower level.
# A file is a template when its path matches a location that GitHub documents
# for issue and pull request templates (DOCS_KIT_TEMPLATE_PATTERNS), or a GLOB
# of the option --template or of DOCS_CHECK_TEMPLATES. A GLOB is a Bash pattern
# for the path relative to DIRECTORY, and `*` also matches `/`. A file name
# that only contains `template`, such as `email-templates.md`, is a page and not
# a template. The `ignores` key of the `.markdownlint-cli2.yaml` of the
# repository applies to both runs.
#
# Code of the checked tree: markdownlint-cli2 loads the files
# `.markdownlint-cli2.{cjs,mjs}` and `.markdownlint.{cjs,mjs}` of the checked
# tree and runs them as JavaScript. Do not run this check, without --online, on
# a tree that you do not trust and in an environment that holds a credential.
# --online runs lychee only, and lychee runs no code of the tree.
#
# Vale reads the kit configuration as its user-level file, which Vale lays
# under the file of the repository (`.vale.ini` in DIRECTORY or above it). The
# repository file adds a vocabulary, a rule level or a path section, and the
# kit rules stay on. This script puts the kit file in a temporary home
# directory, so a user-level file of the person who runs it has no effect.
#
# The script needs Bash 4.4 or later; the Nix wrapper provides it.
#
# Exit status: 0 when every check passes, 1 when a check finds a problem, 2 when
# the check cannot run (a usage error, a file list that Git cannot give, or a
# tool that fails for a reason other than a finding). Every check runs, so one
# run shows all findings.

set -euo pipefail

# The options and the state of the run. The functions below read and write
# them, and `main` sets them in this order.
ONLINE=0
TEMPLATE_GLOBS=()
DIRECTORY="."
WORK_DIR=""
VALE_CONFIG=""
LYCHEE_CONFIG=""
GITHUB_TEMPLATE_PATTERNS=() # the Bash patterns of DOCS_KIT_TEMPLATE_PATTERNS
USE_GIT=0
DOCUMENTS=()   # every document, relative to DIRECTORY
PAGES=()       # the documents that are not templates, relative to DIRECTORY
TEMPLATES=()   # the documents that are templates, relative to DIRECTORY
PROSE_PATHS=() # the pages, as `./<path>`
FAILED=0       # 1 when a check found a problem

#######################################
# Prints a usage error and ends the script.
# Arguments:
#   The message.
# Outputs:
#   Writes the message and the usage line to stderr.
#######################################
usage_error() {
  echo "docs-check: $1" >&2
  echo "usage: docs-check [--online] [--template GLOB]... [DIRECTORY]" >&2
  exit 2
}

#######################################
# Reads the command line into ONLINE, TEMPLATE_GLOBS and DIRECTORY.
# Arguments:
#   The arguments of the script.
# Globals:
#   ONLINE, TEMPLATE_GLOBS, DIRECTORY
#######################################
parse_arguments() {
  while (($# > 0)); do
    case "$1" in
      --online)
        ONLINE=1
        shift
        ;;
      --template)
        if (($# < 2)); then
          usage_error "--template needs a GLOB"
        fi
        TEMPLATE_GLOBS+=("$2")
        shift 2
        ;;
      --)
        shift
        break
        ;;
      -*)
        usage_error "unknown option: $1"
        ;;
      *)
        break
        ;;
    esac
  done
  if (($# > 1)); then
    usage_error "more than one directory"
  fi
  DIRECTORY="${1:-.}"
}

#######################################
# Adds the patterns of the variable DOCS_CHECK_TEMPLATES to TEMPLATE_GLOBS. The
# variable holds one pattern on each line; an empty line adds nothing. Each line
# is taken literally, so the shell does not expand a pattern.
# Globals:
#   DOCS_CHECK_TEMPLATES (read; may be unset), TEMPLATE_GLOBS
#######################################
read_template_environment() {
  local -a lines
  local line
  mapfile -t lines <<<"${DOCS_CHECK_TEMPLATES:-}"
  for line in "${lines[@]}"; do
    if [[ -n ${line} ]]; then
      TEMPLATE_GLOBS+=("${line}")
    fi
  done
}

#######################################
# Reads the three variables that the Nix wrapper sets.
# Globals:
#   VALE_CONFIG, LYCHEE_CONFIG, GITHUB_TEMPLATE_PATTERNS
# Outputs:
#   Writes an error message to stderr when a variable is missing.
# Returns:
#   Ends the script with status 2 when a variable is missing.
#######################################
read_environment() {
  VALE_CONFIG="${DOCS_KIT_VALE_CONFIG-}"
  LYCHEE_CONFIG="${DOCS_KIT_LYCHEE_CONFIG-}"
  local patterns="${DOCS_KIT_TEMPLATE_PATTERNS-}"
  if [[ -z ${VALE_CONFIG} || -z ${LYCHEE_CONFIG} || -z ${patterns} ]]; then
    echo "docs-check: DOCS_KIT_VALE_CONFIG, DOCS_KIT_LYCHEE_CONFIG and" \
      "DOCS_KIT_TEMPLATE_PATTERNS must be set; the Nix wrapper of the kit" \
      "sets them" >&2
    exit 2
  fi
  mapfile -t GITHUB_TEMPLATE_PATTERNS <<<"${patterns}"
}

#######################################
# Sets USE_GIT to 1 when the working directory is in a Git work tree and `git`
# is available, and to 0 otherwise.
# Globals:
#   USE_GIT
#######################################
detect_git() {
  USE_GIT=0
  if command -v git >/dev/null 2>&1 \
    && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    USE_GIT=1
  fi
}

#######################################
# Writes the Markdown files of the working directory to a file, as paths
# relative to the working directory, each ended by a null character.
# Arguments:
#   The path of the output file.
# Globals:
#   USE_GIT
# Outputs:
#   Writes an error message to stderr when the listing fails.
# Returns:
#   Ends the script with status 2 when the listing fails.
#######################################
list_documents() {
  local listing="$1"
  if ((USE_GIT == 1)); then
    if ! git ls-files -z -- '*.md' >"${listing}"; then
      echo "docs-check: git ls-files failed" >&2
      exit 2
    fi
  else
    if ! find . -type d \( -name .git -o -name node_modules \) -prune \
      -o -type f -name '*.md' -print0 >"${listing}"; then
      echo "docs-check: find failed" >&2
      exit 2
    fi
  fi
}

#######################################
# Records a document, as a template when its path matches a template pattern
# and as a page otherwise. A tracked file that no longer exists in the work tree
# is not a document.
# Arguments:
#   The path of the file, relative to the working directory, with no `./`.
# Globals:
#   TEMPLATE_GLOBS, GITHUB_TEMPLATE_PATTERNS, DOCUMENTS, PAGES, TEMPLATES,
#   PROSE_PATHS
#######################################
record_document() {
  local path="$1"
  if [[ ! -f ${path} ]]; then
    return 0
  fi
  DOCUMENTS+=("${path}")

  # Bash patterns match `a/b` with `*`.
  local pattern
  for pattern in "${GITHUB_TEMPLATE_PATTERNS[@]}" "${TEMPLATE_GLOBS[@]}"; do
    # The unquoted right side is the point: it is a pattern.
    # shellcheck disable=SC2053
    if [[ ${path} == ${pattern} ]]; then
      TEMPLATES+=("${path}")
      return 0
    fi
  done
  PAGES+=("${path}")
  # A leading `./` keeps a name that starts with `-` from being an option.
  PROSE_PATHS+=("./${path}")
}

#######################################
# Fills DOCUMENTS and PROSE_PATHS from the files of the working directory.
# Globals:
#   WORK_DIR, DOCUMENTS, PROSE_PATHS
#######################################
collect_documents() {
  local listing="${WORK_DIR}/documents"
  detect_git
  list_documents "${listing}"
  local path
  while IFS= read -r -d '' path; do
    record_document "${path#./}"
  done <"${listing}"
}

#######################################
# Records the exit status of Vale or markdownlint-cli2. Both tools end with
# status 0 when they find nothing, 1 when they find a problem in a document,
# and 2 when they cannot run (Vale 3.25 stops with status 2 on an invalid
# configuration; the README of markdownlint-cli2 lists 2 as "a problem or
# failure", "Exit Codes"). Status 1 is a finding. Any other status ends the
# script with status 2: it is a problem of the setup, and not a finding.
# Arguments:
#   The name of the tool, and its exit status.
# Globals:
#   FAILED
# Outputs:
#   Writes an error message to stderr when the tool could not run.
#######################################
record_tool_status() {
  local tool="$1" status="$2"
  if ((status == 1)); then
    FAILED=1
  elif ((status != 0)); then
    echo "docs-check: ${tool} could not run (exit status ${status})" >&2
    exit 2
  fi
}

#######################################
# Runs Vale on the pages, with the kit configuration as the user-level file.
# Globals:
#   WORK_DIR, VALE_CONFIG, PROSE_PATHS, FAILED
#######################################
run_vale() {
  local home="${WORK_DIR}/home"
  # Vale reads the user-level file from the configuration directory of the
  # operating system: Library/Application Support on macOS, and
  # XDG_CONFIG_HOME elsewhere.
  install -D -m 0644 "${VALE_CONFIG}" \
    "${home}/Library/Application Support/vale/.vale.ini"
  install -D -m 0644 "${VALE_CONFIG}" "${home}/.config/vale/.vale.ini"
  local status=0
  HOME="${home}" XDG_CONFIG_HOME="${home}/.config" \
    vale --minAlertLevel=error "${PROSE_PATHS[@]}" || status=$?
  record_tool_status vale "${status}"
}

#######################################
# Runs markdownlint-cli2 on the pages with the base configuration, and on the
# templates with the configuration for templates. A run with no file is
# skipped.
# Globals:
#   PAGES, TEMPLATES, FAILED
#######################################
run_markdownlint() {
  local status=0
  # `:` marks a literal path, not a glob.
  if ((${#PAGES[@]} > 0)); then
    markdownlint-sealambda "${PAGES[@]/#/:}" || status=$?
    record_tool_status markdownlint-cli2 "${status}"
  fi
  if ((${#TEMPLATES[@]} > 0)); then
    status=0
    markdownlint-sealambda-templates "${TEMPLATES[@]/#/:}" || status=$?
    record_tool_status markdownlint-cli2 "${status}"
  fi
}

#######################################
# Runs lychee on the pages: offline, or online with the cache. The exit status
# of lychee is 0 when every link works, 2 when a link fails, and 1 or 3 when
# lychee cannot run (an input it cannot read, or a configuration error;
# https://github.com/lycheeverse/lychee#exit-codes). Status 2 is a finding.
# Any other failure ends the script with status 2: it is a problem of the
# setup, and not a broken link.
# Globals:
#   ONLINE, LYCHEE_CONFIG, PROSE_PATHS, FAILED
# Outputs:
#   Writes an error message to stderr when lychee cannot run.
#######################################
run_lychee() {
  local -a mode=(--offline --cache=false)
  if ((ONLINE == 1)); then
    mode=()
  fi
  # The files come from the list and not from a directory walk, because lychee
  # skips hidden directories and the files that `.gitignore` names when it
  # walks, and does not skip a file that it gets by name.
  local status=0
  lychee --config "${LYCHEE_CONFIG}" "${mode[@]}" \
    --no-progress --root-dir "${PWD}" -- "${PROSE_PATHS[@]}" || status=$?
  if ((status == 2)); then
    FAILED=1
  elif ((status != 0)); then
    echo "docs-check: lychee could not run (exit status ${status})" >&2
    exit 2
  fi
}

#######################################
# Runs the checks of the mode and prints a heading before each one. Every
# check runs, whatever the result of the others.
# Globals:
#   ONLINE, DOCUMENTS, PROSE_PATHS
#######################################
run_checks() {
  if ((ONLINE == 0)); then
    echo "== Vale (prose), ${#PROSE_PATHS[@]} files"
    if ((${#PROSE_PATHS[@]} > 0)); then
      run_vale
    fi

    echo "== markdownlint-cli2 (structure), ${#DOCUMENTS[@]} files"
    run_markdownlint
  fi

  if ((ONLINE == 1)); then
    echo "== lychee (all links), ${#PROSE_PATHS[@]} files"
  else
    echo "== lychee (local links)"
  fi
  if ((${#PROSE_PATHS[@]} > 0)); then
    run_lychee
  fi
}

#######################################
# Runs the whole check and ends the script with its exit status.
# Arguments:
#   The arguments of the script.
#######################################
main() {
  parse_arguments "$@"
  read_template_environment
  read_environment
  if [[ ! -d ${DIRECTORY} ]]; then
    echo "docs-check: ${DIRECTORY} is not a directory" >&2
    exit 2
  fi
  cd -- "${DIRECTORY}"

  # The EXIT trap removes the temporary directory after a normal end, an error
  # and an interrupt alike (a RETURN trap would miss the signals).
  WORK_DIR="$(mktemp -d)"
  trap 'rm -rf -- "${WORK_DIR}"' EXIT

  collect_documents
  if ((${#DOCUMENTS[@]} == 0)); then
    echo "docs-check: no Markdown file in ${DIRECTORY}" >&2
    exit 0
  fi

  run_checks
  exit "${FAILED}"
}

main "$@"
