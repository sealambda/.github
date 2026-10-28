#!/usr/bin/env bash
#
# Fails when the security form is missing or has no name, or when a document
# does not quote the name of the form in bold.
#
# SECURITY.md names the security contact request form as the fallback channel
# for a private report. The documents below type the name of the form, and
# nothing else ties the text to the form, so a renamed form leaves the
# documents wrong.
#
# The lint reads the fixed paths below from the current directory, which
# treefmt sets to the tree root, and ignores the paths that treefmt passes:
# the form and the documents are checked together, whichever of them changed.
#
# Usage: security-form-name [FILE...]
#   The arguments are ignored.
#
# Exit status: 0 when every document quotes the name, 1 otherwise. Each
# finding is printed as `security-form-name: message` on standard output.

set -euo pipefail

# The form that SECURITY.md names as the fallback channel.
readonly FORM='.github/ISSUE_TEMPLATE/security_contact.yml'

# The documents that quote the name of the form.
readonly REFERENCES=(
  SECURITY.md
  SUPPORT.md
  docs/decisions/0003-security-reporting-scope.md
  docs/explanation/default-files.md
)

#######################################
# Prints the name of the form, which is its `name:` line.
# Outputs:
#   Writes the name to stdout. Writes nothing when the line is missing.
#######################################
form_name() {
  sed -n 's/^name: //p' "${FORM}"
}

#######################################
# Checks that every document quotes the name of the form in bold.
# Arguments:
#   The name of the form.
# Outputs:
#   Writes a message to stdout for each document that does not quote it.
# Returns:
#   Exits 0 when every document quotes the name, 1 otherwise.
#######################################
check_references() {
  local name="$1"
  local status=0
  local document
  for document in "${REFERENCES[@]}"; do
    if ! grep -qF -- "**${name}**" "${document}"; then
      echo "security-form-name: ${document} does not quote **${name}**"
      status=1
    fi
  done
  exit "${status}"
}

#######################################
# Checks the form, then the documents that quote its name.
# Outputs:
#   Writes a message to stdout for each finding.
# Returns:
#   Exits 0 when every document quotes the name, 1 otherwise.
#######################################
main() {
  if [[ ! -f ${FORM} ]]; then
    echo "security-form-name: ${FORM} is missing; SECURITY.md names it"
    exit 1
  fi
  local name
  name="$(form_name)"
  if [[ -z ${name} ]]; then
    echo "security-form-name: ${FORM} has no 'name:' line"
    exit 1
  fi
  check_references "${name}"
}

main
