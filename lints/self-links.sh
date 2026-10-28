#!/usr/bin/env bash
#
# Fails when a file holds an absolute link into this repository whose path is
# not in the tree.
#
# The default files of this repository link to each other with absolute
# `https://github.com/sealambda/.github/blob/main/` URLs, because GitHub shows
# a default file in the other repositories of the organization, where a
# relative link breaks. The offline run of lychee skips every absolute link,
# so it cannot catch a link to a renamed or deleted file, and only the weekly
# online run would.
#
# The lint checks the path of a link and not its query after `?` or its
# fragment after `#`: GitHub shows `doc.md?plain=1` as the file `doc.md`. It
# does not count a trailing `.`, `,`, `;` or `:` as part of the path, because
# prose ends a sentence with one. It reads the paths from the current
# directory, which treefmt sets to the tree root.
#
# Usage: self-links FILE...
#   treefmt passes the files.
#
# Exit status: 0 when every link points to a path of the tree, 1 when a link
# does not, 2 when a file cannot be read. An unreadable file is an error of
# the environment, not a finding, so the lint stops at the first one. Each
# finding is printed as `path: message` on standard output.

set -euo pipefail

# The prefix of the absolute links that the default files use for each other.
readonly LINK_PREFIX='https://github.com/sealambda/.github/blob/main/'

# A link: the prefix, then the path up to a character that ends a URL in
# Markdown or YAML (a closing bracket, `#`, a space, a quote or an angle
# bracket). The prefix is a fixed string with no regular expression
# character other than `.`, which matches itself here.
readonly LINK_REGEX="${LINK_PREFIX}[^])#[:space:]>\"'\`]+"

# The punctuation that ends a sentence and is not part of a path.
readonly TRAILING_PUNCTUATION='.,;:'

# The number of findings so far. Functions raise it instead of returning
# non-zero, so that a call stays a plain statement and `set -e` keeps its
# effect in the caller (ShellCheck SC2310).
findings=0

#######################################
# Prints a link without its prefix, without its query and without the
# punctuation that ends a sentence. The query is everything from the first
# `?`, so punctuation that follows a query goes with it.
# Arguments:
#   The link, with its prefix.
# Outputs:
#   Writes the path to stdout.
#######################################
link_path() {
  local path="${1#"${LINK_PREFIX}"}"
  path="${path%%\?*}"
  while [[ -n ${path} && ${TRAILING_PUNCTUATION} == *"${path: -1}"* ]]; do
    path="${path%?}"
  done
  echo "${path}"
}

#######################################
# Checks the links of one file.
# Globals:
#   findings
# Arguments:
#   The path of the file.
# Outputs:
#   Writes a `path: message` line to stdout for each link to a path that is
#   not in the tree, or that has no path after the prefix. Writes an error to
#   stderr and exits 2 when the file cannot be read.
#######################################
check_file() {
  local document="$1"
  local links
  local grep_status=0
  links="$(grep -o -E -e "${LINK_REGEX}" -- "${document}" 2>/dev/null)" || grep_status=$?
  if ((grep_status > 1)); then
    # grep exits 1 when no line matches; any other status is a read error.
    echo "${document}: cannot read the file" >&2
    exit 2
  fi
  local link path
  while IFS= read -r link; do
    if [[ -z ${link} ]]; then
      continue
    fi
    path="$(link_path "${link}")"
    if [[ -z ${path} ]]; then
      # The link is the prefix and punctuation only, so it names no file.
      echo "${document}: links to ${link}, which names no path in the tree"
      findings=$((findings + 1))
    elif [[ ! -e ${path} ]]; then
      echo "${document}: links to ${path}, which is not in the tree"
      findings=$((findings + 1))
    fi
  done <<<"${links}"
}

#######################################
# Checks every file that the command line names.
# Arguments:
#   The paths of the files.
# Returns:
#   Exits 0 when no link has a finding, 1 otherwise.
#######################################
main() {
  local document
  for document in "$@"; do
    check_file "${document}"
  done
  if ((findings > 0)); then
    exit 1
  fi
}

main "$@"
