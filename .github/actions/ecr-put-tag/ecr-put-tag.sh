#!/usr/bin/env bash
#
# The registry side of a release: the steps of the publish job that talk to ECR
# or report its result. One operation per run, chosen by OPERATION.
#
#   inspect  Assert that the repository is IMMUTABLE, then look for the tag.
#            Output digest: the digest of the image under the tag, or empty
#            when the tag does not exist yet.
#   put      Tag the image that was pushed by digest. The image keeps its
#            manifest and its media type. When the tag exists already (a run of
#            the same commit won the race), the tag is left alone.
#            Output digest: the digest of the image under the tag afterwards.
#   report   Check the digest and write it to the job summary.
#            Output digest: the checked digest.
#
# The tag is immutable while it exists. ECR refuses to move it, and a lifecycle
# policy may expire it. `put` is the point where two runs of the same commit are
# arbitrated: the first one wins, and the other one returns the winner's digest.
#
# Environment:
#   OPERATION        `inspect`, `put` or `report`. Required.
#   GITHUB_OUTPUT    The file of the step outputs. Required.
#   REPOSITORY       The ECR repository name. Required for inspect and put.
#   TAG              The tag, `build-<sha>`. Required for inspect, put, report.
#   DIGEST           The digest to tag (put), or to report (report).
#   IMAGE            The image without a tag (report; empty in a dry run).
#   DRY_RUN          `true` or `false` (report).
#   COMMIT_SHA       The commit (report).
#   GITHUB_STEP_SUMMARY  The file of the job summary (report).
#
# Exit status: 0 on success. 1 when an assertion fails. The status of the `aws`
# command, with its message on standard error, when ECR fails in any other way.
# A failure prints a `::error::` line or the message of `aws`.

# The inputs are environment variables, listed above and set by action.yml, so
# ShellCheck cannot see where they are assigned.
# shellcheck disable=SC2154
set -euo pipefail

readonly DIGEST_PATTERN='^sha256:[0-9a-f]{64}$'

# The manifest types that a build can produce: Docker v2 and OCI. Passing them
# to batch-get-image makes ECR return the manifest in its stored form.
readonly -a MEDIA_TYPES=(
  application/vnd.docker.distribution.manifest.v2+json
  application/vnd.oci.image.manifest.v1+json
)

# Scratch space for the messages and the manifest of one run.
work_dir="$(mktemp -d)"
readonly work_dir
trap 'rm -rf "${work_dir}"' EXIT

# The result of the last aws_capture.
aws_status=0
aws_output=''

# The digest under the tag, set by find_tag; empty when there is no such tag.
tag_digest=''

#######################################
# Prints an error and stops the run.
# Arguments:
#   The message.
# Outputs:
#   Writes a `::error::` workflow command to stdout.
#######################################
die() {
  echo "::error::$1"
  exit 1
}

#######################################
# Runs a command, keeping its output and status apart from its messages.
# Arguments:
#   The command and its arguments.
# Globals:
#   aws_status, aws_output: set. The messages of the command are in
#   ${work_dir}/aws.err.
#######################################
aws_capture() {
  aws_status=0
  aws_output="$("$@" 2>"${work_dir}/aws.err")" || aws_status=$?
}

#######################################
# Stops the run with the status and the message of the last failed command.
# Outputs:
#   Writes the message of the command to stderr.
#######################################
abort_with_aws_failure() {
  cat "${work_dir}/aws.err" >&2
  exit "${aws_status}"
}

#######################################
# Writes the digest to the step outputs.
# Arguments:
#   The digest, possibly empty.
#######################################
write_digest() {
  echo "digest=$1" >>"${GITHUB_OUTPUT}"
}

#######################################
# Stops the run unless the repository has IMMUTABLE tags. Any other setting lets
# a tag move, and then a re-run could return an image that is not the commit's.
# Globals:
#   REPOSITORY
#######################################
require_immutable_repository() {
  aws_capture aws ecr describe-repositories --repository-names "${REPOSITORY}" \
    --query 'repositories[0].imageTagMutability' --output text
  if ((aws_status != 0)); then
    abort_with_aws_failure
  fi
  if [[ ${aws_output} != IMMUTABLE ]]; then
    die "ECR repository ${REPOSITORY} has imageTagMutability ${aws_output}; a release needs IMMUTABLE."
  fi
}

#######################################
# Looks up the digest of the image under the tag.
# Globals:
#   REPOSITORY, TAG
#   tag_digest: set; empty when the tag does not exist.
# Returns:
#   Stops the run on any failure other than a missing tag.
#######################################
find_tag() {
  aws_capture aws ecr describe-images --repository-name "${REPOSITORY}" \
    --image-ids "imageTag=${TAG}" \
    --query 'imageDetails[0].imageDigest' --output text
  tag_digest=''
  if ((aws_status == 0)); then
    if [[ ! ${aws_output} =~ ${DIGEST_PATTERN} ]]; then
      die "ECR returned no image digest for ${TAG}: '${aws_output}'."
    fi
    tag_digest="${aws_output}"
  elif ! grep -q ImageNotFoundException "${work_dir}/aws.err"; then
    abort_with_aws_failure
  fi
}

#######################################
# The inspect operation: asserts the repository, then looks for the tag.
# Globals:
#   TAG, GITHUB_OUTPUT
# Outputs:
#   Writes the digest output; empty when the tag is free.
#######################################
inspect_repository() {
  require_immutable_repository
  find_tag
  if [[ -n ${tag_digest} ]]; then
    echo "::notice::${TAG} exists already: ${tag_digest}. Nothing to build."
  else
    echo "No image under ${TAG} yet; building it."
  fi
  write_digest "${tag_digest}"
}

#######################################
# Fetches the stored manifest of the image and its media type.
# Globals:
#   REPOSITORY, DIGEST
#   Writes ${work_dir}/manifest.json, byte for byte, and
#   ${work_dir}/media-type.
#######################################
fetch_manifest() {
  aws_capture aws ecr batch-get-image --repository-name "${REPOSITORY}" \
    --image-ids "imageDigest=${DIGEST}" \
    --accepted-media-types "${MEDIA_TYPES[@]}" --output json
  if ((aws_status != 0)); then
    abort_with_aws_failure
  fi
  # A missing image is a `failures` entry with exit status 0.
  if ! jq -e '(.images | length) == 1' <<<"${aws_output}" >/dev/null; then
    die "ECR holds no manifest for ${DIGEST} in ${REPOSITORY}: ${aws_output}"
  fi
  # -j: no trailing newline, so the manifest keeps the bytes that ECR stored.
  jq -j '.images[0].imageManifest' <<<"${aws_output}" >"${work_dir}/manifest.json"
  jq -j '.images[0].imageManifestMediaType' <<<"${aws_output}" >"${work_dir}/media-type"
}

#######################################
# The put operation: tags the pushed image, or returns the winner's digest when
# the tag exists.
# Globals:
#   REPOSITORY, TAG, DIGEST, GITHUB_OUTPUT
# Outputs:
#   Writes the digest of the image under the tag.
#######################################
put_tag() {
  if [[ ! ${DIGEST} =~ ${DIGEST_PATTERN} ]]; then
    die "No image digest to tag: '${DIGEST}'."
  fi
  fetch_manifest
  local media_type
  media_type="$(<"${work_dir}/media-type")"
  # --image-digest makes ECR refuse a manifest that differs from the pushed one.
  aws_capture aws ecr put-image --repository-name "${REPOSITORY}" \
    --image-manifest "file://${work_dir}/manifest.json" \
    --image-manifest-media-type "${media_type}" \
    --image-digest "${DIGEST}" \
    --image-tag "${TAG}"
  if ((aws_status == 0)); then
    echo "Tagged ${DIGEST} as ${TAG}."
  elif grep -qE 'ImageTagAlreadyExistsException|ImageAlreadyExistsException' "${work_dir}/aws.err"; then
    echo "::notice::${TAG} exists already; returning the image under it."
  else
    abort_with_aws_failure
  fi
  find_tag
  if [[ -z ${tag_digest} ]]; then
    die "${TAG} is not in ${REPOSITORY} after the tag was put."
  fi
  write_digest "${tag_digest}"
}

#######################################
# The report operation: checks the digest and writes the job summary.
# Globals:
#   DIGEST, IMAGE, TAG, DRY_RUN, COMMIT_SHA, GITHUB_OUTPUT, GITHUB_STEP_SUMMARY
# Outputs:
#   Writes the digest output and the summary.
#######################################
report_digest() {
  if [[ ! ${DIGEST} =~ ${DIGEST_PATTERN} ]]; then
    die "No image digest: '${DIGEST}'."
  fi
  write_digest "${DIGEST}"
  {
    echo "## Image"
    echo
    if [[ ${DRY_RUN} == true ]]; then
      echo "Dry run: built and not pushed."
      echo
      echo "- Digest: \`${DIGEST}\`"
    else
      echo "- Image: \`${IMAGE}@${DIGEST}\`"
      echo "- Tag: \`${TAG}\`"
    fi
    echo "- Commit: \`${COMMIT_SHA}\`"
  } >>"${GITHUB_STEP_SUMMARY}"
}

#######################################
# Runs the operation that OPERATION names.
# Globals:
#   OPERATION and the variables of the operation.
# Outputs:
#   Whatever the operation writes. An unknown operation prints a `::error::`
#   line and exits with status 1.
#######################################
main() {
  case "${OPERATION}" in
    inspect) inspect_repository ;;
    put) put_tag ;;
    report) report_digest ;;
    *)
      die "Unknown operation '${OPERATION}'; use inspect, put or report."
      ;;
  esac
}

main
