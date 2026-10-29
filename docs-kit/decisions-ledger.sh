#!/usr/bin/env bash
#
# Checks the decision records of a directory and their ledger.
#
# The organization keeps only decisions in force in the tree. A record that is
# rejected, deprecated or superseded is deleted in the commit that records the
# change, and a row in the ledger keeps its number, its reason and a permalink
# to its last text (docs/explanation/docs-kit.md, "Decision records").
#
# Usage: decisions-ledger [DIRECTORY]
#   DIRECTORY defaults to docs/decisions. It holds the records, named
#   `NNNN-title.md` with four digits, and the ledger, `README.md`.
#
# A record has a front matter block with a `status:` line. The ledger is a
# Markdown table. Each row starts with the four-digit number of a record, and
# its cells are, in order:
#   number | title | final status | replaced by | reason | permalink
# The final status is `rejected`, `deprecated` or `superseded`. "Replaced by"
# is the number of another record, or `none`. The permalink is a Markdown link
# to the last text of the record at a commit: https://github.com/OWNER/REPO/
# blob/<40 hexadecimal characters>/PATH. A row whose first cell is not a
# four-digit number, such as the header, is not a record.
#
# The script checks these rules and prints every finding:
#   - the status of a record in the tree is `proposed` or `accepted`;
#   - a number is used once, in the tree or in the ledger;
#   - the final status in the ledger is in the closed set above;
#   - "replaced by" names a record of the tree or of the ledger, and a
#     superseded record names one;
#   - the permalink has a 40-character commit SHA.
# That a permalink resolves is left to the scheduled link check.
#
# Exit status: 0 when every rule holds, 1 when a rule fails, 2 when the check
# cannot run (a usage error, a missing directory or ledger).

set -euo pipefail

# The record files of the tree, by number.
declare -A tree_files=()
# The "replaced by" cell of each ledger row, by number.
declare -A ledger_replacements=()
# The final status of each ledger row, by number.
declare -A ledger_statuses=()
# The statuses that a record in the tree may have, and that a ledger row may have.
declare -rA tree_allowed=([proposed]=1 [accepted]=1)
declare -rA ledger_allowed=([rejected]=1 [deprecated]=1 [superseded]=1)
# The count of findings. A counter, not a function status, keeps `errexit` on.
findings=0
# The path of the ledger, for the findings. `main` sets it.
ledger=""

#######################################
# Prints a finding and counts it.
# Arguments:
#   The file or place of the finding.
#   The message.
# Outputs:
#   Writes the finding to stderr.
#######################################
report() {
  echo "decisions-ledger: $1: $2" >&2
  findings=$((findings + 1))
}

#######################################
# Prints a value without the white space at both ends.
# Arguments:
#   The value.
# Outputs:
#   Writes the trimmed value to stdout, without a newline.
#######################################
trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

#######################################
# Prints the value of the `status:` line in the front matter of a record, without
# quotation marks. It prints nothing when the file has no front matter or no
# status.
# Arguments:
#   The path of the record.
# Outputs:
#   Writes the status to stdout.
#######################################
front_matter_status() {
  awk '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    /^status:/ {
      sub(/^status:[[:space:]]*/, "")
      gsub(/^["\047]|["\047]$/, "")
      print
      exit
    }
  ' "$1"
}

#######################################
# Checks the records of the tree: the file name, the number and the status.
# Arguments:
#   The directory of the records.
# Globals:
#   tree_files, written.
#######################################
scan_records() {
  local file base number status
  for file in "$1"/*.md; do
    base="${file##*/}"
    if [[ ${base} == README.md ]]; then
      continue
    fi
    if [[ ! ${base} =~ ^[0-9]{4}-.+\.md$ ]]; then
      report "${file}" "the name must be four digits, a hyphen and a title: NNNN-title.md"
      continue
    fi
    number="${base:0:4}"
    if [[ -v tree_files[${number}] ]]; then
      report "${file}" "the number ${number} is also used by ${tree_files[${number}]}"
    fi
    tree_files[${number}]="${file}"
    status="$(front_matter_status "${file}")"
    if [[ -z ${status} || ! -v tree_allowed[${status}] ]]; then
      report "${file}" "the status '${status}' is not proposed or accepted; a record with another status is deleted and gets a row in the ledger"
    fi
  done
}

#######################################
# Checks one row of the ledger and records its number, status and replacement.
# Arguments:
#   The cells of the row, trimmed: number, final status, replaced by, permalink.
# Globals:
#   ledger, read. tree_files, read. ledger_statuses and ledger_replacements,
#   written.
#######################################
check_ledger_row() {
  local number="$1" status="$2" replaced="$3" link="$4"
  local url=""
  if [[ -v tree_files[${number}] || -v ledger_statuses[${number}] ]]; then
    report "${ledger}" "the number ${number} is used more than once in the tree and the ledger"
  fi
  ledger_statuses[${number}]="${status}"
  ledger_replacements[${number}]="${replaced}"
  if [[ -z ${status} || ! -v ledger_allowed[${status}] ]]; then
    report "${ledger}" "${number}: the final status '${status}' is not rejected, deprecated or superseded"
  fi
  if [[ ${status} == superseded && ${replaced} == none ]]; then
    report "${ledger}" "${number}: a superseded record needs the number of its replacement"
  fi
  if [[ ${link} =~ \]\((https://[^\)[:space:]]+)\) ]]; then
    url="${BASH_REMATCH[1]}"
  fi
  if [[ ! ${url} =~ ^https://github\.com/[^/]+/[^/]+/blob/[0-9a-f]{40}/[^[:space:]]+$ ]]; then
    report "${ledger}" "${number}: the permalink must be a Markdown link to https://github.com/OWNER/REPO/blob/<40-character commit SHA>/PATH"
  fi
}

#######################################
# Reads the rows of the ledger table and checks each one.
# Arguments:
#   The ledger path.
#######################################
scan_ledger() {
  local line first number status replaced link
  # `read` returns a failure status on a last line without a newline, even
  # though it has read the line. The test `-n` keeps that line.
  while IFS= read -r line || [[ -n ${line} ]]; do
    # The cells of a row are separated by `|`. The text before the first `|` is
    # empty, and the title and the reason (the 2nd and 5th cells) are not read.
    IFS='|' read -r first number _ status replaced _ link _ <<<"${line}"
    number="$(trim "${number}")"
    if [[ -n ${first} || ! ${number} =~ ^[0-9]{4}$ ]]; then
      continue
    fi
    status="$(trim "${status}")"
    replaced="$(trim "${replaced}")"
    link="$(trim "${link}")"
    check_ledger_row "${number}" "${status}" "${replaced}" "${link}"
  done <"$1"
}

#######################################
# Checks that every "replaced by" value names a record that exists.
# Globals:
#   ledger, tree_files, ledger_statuses and ledger_replacements, read.
#######################################
check_replacements() {
  local number replaced
  for number in "${!ledger_replacements[@]}"; do
    replaced="${ledger_replacements[${number}]}"
    if [[ ${replaced} == none ]]; then
      continue
    fi
    if [[ -z ${replaced} ]]; then
      report "${ledger}" "${number}: 'replaced by' needs a number or 'none'"
    elif [[ ${replaced} == "${number}" ]]; then
      report "${ledger}" "${number}: a record cannot replace itself"
    elif [[ ! -v tree_files[${replaced}] && ! -v ledger_statuses[${replaced}] ]]; then
      report "${ledger}" "${number}: 'replaced by' ${replaced} does not resolve to a record of the tree or the ledger"
    fi
  done
}

#######################################
# Runs every check on the decision records of a directory.
# Arguments:
#   The directory, optional. See the usage at the top of the file.
# Globals:
#   ledger, written.
#######################################
main() {
  if (($# > 1)); then
    echo "usage: decisions-ledger [DIRECTORY]" >&2
    exit 2
  fi
  local directory="${1:-docs/decisions}"
  ledger="${directory}/README.md"
  if [[ ! -d ${directory} ]]; then
    echo "decisions-ledger: ${directory} is not a directory" >&2
    exit 2
  fi
  if [[ ! -f ${ledger} ]]; then
    echo "decisions-ledger: ${ledger} is missing; the ledger is a table in this file" >&2
    exit 2
  fi
  shopt -s nullglob
  scan_records "${directory}"
  scan_ledger "${ledger}"
  check_replacements
  if ((findings > 0)); then
    echo "decisions-ledger: ${findings} finding(s)" >&2
    exit 1
  fi
}

main "$@"
