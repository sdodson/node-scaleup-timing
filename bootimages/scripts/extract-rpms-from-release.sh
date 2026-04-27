#!/bin/bash
# Extract a sorted RPM list from an OCP release's rhel-coreos image.
#
# Usage: extract-rpms-from-release.sh <version> [output-dir]
#
# Examples:
#   ./extract-rpms-from-release.sh 4.19.0
#   ./extract-rpms-from-release.sh 4.12.87 /tmp/rpmlists
#
# Output: <output-dir>/rpms-<version>.txt (sorted NEVRA, one per line)

set -euo pipefail

VERSION="${1:?Usage: $0 <version> [output-dir]}"
OUTDIR="${2:-.}"

OUTFILE="${OUTDIR}/rpms-${VERSION}.txt"

if [[ -f "$OUTFILE" ]]; then
    echo "Already exists: ${OUTFILE} ($(wc -l < "$OUTFILE") packages)" >&2
    exit 0
fi

MAJOR_MINOR="${VERSION%.*}"

# Determine the correct image name — 4.12.x uses rhel-coreos-8, later uses rhel-coreos
IMAGE_TAG="rhel-coreos"
if [[ "$MAJOR_MINOR" == "4.12" || "$MAJOR_MINOR" == "4.11" || "$MAJOR_MINOR" == "4.10" ]]; then
    IMAGE_TAG="rhel-coreos-8"
fi

echo "Resolving ${IMAGE_TAG} image for ${VERSION}..." >&2

# Try short form first, fall back to explicit registry path
IMAGE=$(oc adm release info "${VERSION}" --image-for "${IMAGE_TAG}" 2>/dev/null) || \
IMAGE=$(oc adm release info "quay.io/openshift-release-dev/ocp-release:${VERSION}-x86_64" --image-for "${IMAGE_TAG}" 2>/dev/null) || {
    echo "ERROR: Could not resolve ${IMAGE_TAG} image for ${VERSION}" >&2
    exit 1
}

echo "Pulling RPM list from ${IMAGE}..." >&2
podman run --rm --entrypoint rpm "${IMAGE}" -qa 2>/dev/null | sort > "${OUTFILE}"

COUNT=$(wc -l < "${OUTFILE}")
echo "${VERSION}: ${COUNT} packages → ${OUTFILE}" >&2
