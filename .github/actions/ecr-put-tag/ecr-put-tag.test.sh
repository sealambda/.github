#!/usr/bin/env bash
#
# Tests .github/actions/ecr-put-tag/ecr-put-tag.sh against a fake `aws`: the
# three operations, every answer of ECR that the script must tell apart, and
# the arguments that it sends. The error texts of the fake are the texts of the
# AWS CLI v2: `An error occurred (Name) when calling the Operation operation`.
#
# Usage: ecr-put-tag.test.sh [REPOSITORY_ROOT]
#   REPOSITORY_ROOT defaults to the root of the tree that holds this file.
#
# Exit status: 0 when every case passes, 1 otherwise.

set -euo pipefail

root="${1:-$(dirname "${BASH_SOURCE[0]}")/../../..}"
# shellcheck disable=SC2034 # read by run_script in lib.sh
readonly SCRIPT="${root}/.github/actions/ecr-put-tag/ecr-put-tag.sh"
# shellcheck source=../../../scripts/ci/release/lib.sh
source "${root}/scripts/ci/release/lib.sh"

readonly COMMIT=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
readonly TAG=build-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
readonly PUSHED=sha256:1111111111111111111111111111111111111111111111111111111111111111
readonly WINNER=sha256:2222222222222222222222222222222222222222222222222222222222222222
readonly UPPER_CASE=sha256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
readonly OCI=application/vnd.oci.image.manifest.v1+json
readonly DOCKER=application/vnd.docker.distribution.manifest.v2+json

# The manifest ends with a newline on purpose: the script must keep the bytes.
readonly MANIFEST=$'{"schemaVersion":2,"config":{"digest":"sha256:cc"}}\n'

# shellcheck disable=SC2034 # read by run_script in lib.sh
readonly -a BASE_ENV=(
  REPOSITORY=billing_api
  "TAG=${TAG}"
  "COMMIT_SHA=${COMMIT}"
)

#######################################
# Makes the fake aws answer batch-get-image with one image.
# Arguments:
#   The manifest.
#   The media type.
#######################################
fake_batch_image() {
  local answer
  answer="$(jq -nc --arg manifest "$1" --arg type "$2" \
    '{images: [{imageManifest: $manifest, imageManifestMediaType: $type}], failures: []}')"
  fake_response batch-get-image 0 "${answer}" ""
}

#######################################
# The inspect operation: the repository must be IMMUTABLE, then the tag is
# looked up.
#######################################
test_inspect() {
  reset_case
  fake_response describe-repositories 0 $'IMMUTABLE\n' ""
  fake_response describe-images 0 "${WINNER}"$'\n' ""
  expect_success "inspect returns the digest under the tag" "digest=${WINNER}" OPERATION=inspect
  expect_flag_value "inspect asks for the repository" aws.log --repository-names billing_api
  expect_flag_value "inspect asks for the tag" aws.log --image-ids "imageTag=${TAG}"

  reset_case
  fake_response describe-repositories 0 $'IMMUTABLE\n' ""
  fake_aws_error describe-images 254 ImageNotFoundException DescribeImages
  expect_success "inspect returns an empty digest for a free tag" "digest=" OPERATION=inspect

  reset_case
  fake_response describe-repositories 0 $'MUTABLE\n' ""
  expect_failure "inspect refuses MUTABLE" 1 "imageTagMutability MUTABLE; a release needs IMMUTABLE" OPERATION=inspect
  expect_log_line "inspect looks up no tag in a mutable repository" lacks aws.log describe-images
  fake_response describe-repositories 0 $'IMMUTABLE_WITH_EXCLUSION\n' ""
  expect_failure "inspect refuses IMMUTABLE_WITH_EXCLUSION" 1 "imageTagMutability IMMUTABLE_WITH_EXCLUSION" OPERATION=inspect
  fake_response describe-repositories 0 $'MUTABLE_WITH_EXCLUSION\n' ""
  expect_failure "inspect refuses MUTABLE_WITH_EXCLUSION" 1 "imageTagMutability MUTABLE_WITH_EXCLUSION" OPERATION=inspect
  fake_aws_error describe-repositories 254 RepositoryNotFoundException DescribeRepositories
  expect_failure "inspect passes on the status of aws" 254 "RepositoryNotFoundException" OPERATION=inspect

  reset_case
  fake_response describe-repositories 0 $'IMMUTABLE\n' ""
  fake_aws_error describe-images 255 AccessDeniedException DescribeImages
  expect_failure "inspect stops on an error other than a missing tag" 255 "AccessDeniedException" OPERATION=inspect
  fake_response describe-images 0 $'None\n' ""
  expect_failure "inspect refuses a digest that is not one" 1 "ECR returned no image digest" OPERATION=inspect
}

#######################################
# The put operation: the pushed image gets the tag with its own manifest, and
# the answers "the tag exists" lead to the digest under the tag.
#######################################
test_put() {
  reset_case
  fake_batch_image "${MANIFEST}" "${OCI}"
  fake_response put-image 0 "{}" ""
  fake_response describe-images 0 "${PUSHED}"$'\n' ""
  expect_success "put returns the digest under the tag" "digest=${PUSHED}" OPERATION=put "DIGEST=${PUSHED}"
  expect_flag_value "put reads the pushed image" aws.log --image-ids "imageDigest=${PUSHED}"
  expect_log_line "put accepts Docker manifests" has aws.log "${DOCKER}"
  expect_log_line "put accepts OCI manifests" has aws.log "${OCI}"
  expect_flag_value "put passes the media type through" aws.log --image-manifest-media-type "${OCI}"
  expect_flag_value "put passes the digest, so ECR checks the manifest" aws.log --image-digest "${PUSHED}"
  expect_flag_value "put sets the tag" aws.log --image-tag "${TAG}"
  expect_file "put sends the manifest byte for byte" fake/manifest.copy "${MANIFEST}"

  reset_case
  fake_batch_image "${MANIFEST}" "${DOCKER}"
  fake_response put-image 0 "{}" ""
  fake_response describe-images 0 "${PUSHED}"$'\n' ""
  expect_success "put works for a Docker manifest" "digest=${PUSHED}" OPERATION=put "DIGEST=${PUSHED}"
  expect_flag_value "put passes a Docker media type through" aws.log --image-manifest-media-type "${DOCKER}"

  local exception
  for exception in ImageTagAlreadyExistsException ImageAlreadyExistsException; do
    reset_case
    fake_batch_image "${MANIFEST}" "${OCI}"
    fake_aws_error put-image 254 "${exception}" PutImage
    fake_response describe-images 0 "${WINNER}"$'\n' ""
    expect_success "put returns the winner's digest after ${exception}" "digest=${WINNER}" OPERATION=put "DIGEST=${PUSHED}"
    expect_output_contains "put says that the tag exists after ${exception}" "exists already"
  done

  reset_case
  fake_batch_image "${MANIFEST}" "${OCI}"
  fake_aws_error put-image 255 ImageDigestDoesNotMatchException PutImage
  expect_failure "put stops on any other error of put-image" 255 "ImageDigestDoesNotMatchException" OPERATION=put "DIGEST=${PUSHED}"
  expect_log_line "put looks up no tag after that error" lacks aws.log describe-images
}

#######################################
# The put operation when the image cannot be tagged for another reason.
#######################################
test_put_failures() {
  reset_case
  fake_response batch-get-image 0 '{"images":[],"failures":[{"failureCode":"ImageNotFound"}]}' ""
  expect_failure "put refuses a digest that ECR does not hold" 1 "holds no manifest for ${PUSHED}" OPERATION=put "DIGEST=${PUSHED}"
  expect_log_line "put does not put without a manifest" lacks aws.log put-image
  fake_aws_error batch-get-image 254 RepositoryNotFoundException BatchGetImage
  expect_failure "put passes on the status of batch-get-image" 254 "RepositoryNotFoundException" OPERATION=put "DIGEST=${PUSHED}"
  fake_batch_image "${MANIFEST}" "${OCI}"
  fake_response put-image 0 "{}" ""
  fake_aws_error describe-images 254 ImageNotFoundException DescribeImages
  expect_failure "put refuses a tag that is missing after the put" 1 "is not in billing_api after the tag was put" OPERATION=put "DIGEST=${PUSHED}"
  expect_failure "put refuses an empty digest" 1 "No image digest to tag: ''" OPERATION=put DIGEST=
  expect_failure "put refuses a short digest" 1 "No image digest to tag: 'sha256:abc'" OPERATION=put DIGEST=sha256:abc
}

#######################################
# The report operation: only a well-formed digest is reported.
#######################################
test_report() {
  local image=1.dkr.ecr.r.amazonaws.com/billing_api
  reset_case
  expect_success "report returns the digest" "digest=${PUSHED}" \
    OPERATION=report "DIGEST=${PUSHED}" "IMAGE=${image}" DRY_RUN=false
  expect_file "report writes the summary of a release" step-summary \
    "## Image

- Image: \`${image}@${PUSHED}\`
- Tag: \`${TAG}\`
- Commit: \`${COMMIT}\`
"
  expect_success "report returns the digest of a dry run" "digest=${PUSHED}" \
    OPERATION=report "DIGEST=${PUSHED}" IMAGE= DRY_RUN=true
  expect_file "report writes the summary of a dry run" step-summary \
    "## Image

Dry run: built and not pushed.

- Digest: \`${PUSHED}\`
- Commit: \`${COMMIT}\`
"
  expect_failure "report refuses an empty digest" 1 "No image digest: ''" \
    OPERATION=report DIGEST= IMAGE= DRY_RUN=false
  expect_failure "report refuses a short digest" 1 "No image digest: 'sha256:abc'" \
    OPERATION=report DIGEST=sha256:abc IMAGE= DRY_RUN=false
  expect_failure "report refuses upper case hex" 1 "No image digest" \
    OPERATION=report "DIGEST=${UPPER_CASE}" IMAGE= DRY_RUN=false
  expect_failure "report refuses a digest followed by a newline" 1 "No image digest" \
    OPERATION=report "DIGEST=${PUSHED}"$'\n' IMAGE= DRY_RUN=false
  expect_failure "an unknown operation is refused" 1 "Unknown operation 'delete'" OPERATION=delete
}

#######################################
# Runs every case.
#######################################
main() {
  init_sandbox
  test_inspect
  test_put
  test_put_failures
  test_report
  finish_tests
}

main
