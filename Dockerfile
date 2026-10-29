# The build input of the `release-dry-run` job in .github/workflows/ci.yml.
# That job runs release-image.yml in dry-run mode on this repository, and the
# workflow builds the Dockerfile at the root of the commit. This repository
# ships no image: the file is a fixture that lets the dry run build something
# without a registry. It holds no instruction beyond the empty base image.
FROM scratch
