#!/bin/bash
# Resolve RHCOS AMI IDs for OCP versions from release payloads.
#
# Usage:
#   scripts/lookup-ami.sh --all          # resolve all versions in BOOT_VERSIONS
#   scripts/lookup-ami.sh 4.18.24        # resolve a single version
#
# Results are appended to $DATA_DIR/amis.env as AMI_4_18_24=ami-xxx format.
# Already-resolved versions are skipped.

set -euo pipefail
source "$(dirname "$0")/config.env"

mkdir -p "$DATA_DIR"
touch "$AMI_FILE"

resolve_one() {
  local version="$1"
  local var
  var=$(version_to_var "$version")

  # Skip if already resolved
  if grep -q "^${var}=" "$AMI_FILE" 2>/dev/null; then
    local existing
    existing=$(grep "^${var}=" "$AMI_FILE" | head -1 | cut -d= -f2)
    echo "  SKIP ${version} -> ${existing} (already resolved)"
    return 0
  fi

  echo "  Resolving ${version}..."

  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" RETURN

  local release_image="quay.io/openshift-release-dev/ocp-release:${version}-x86_64"

  if ! oc adm release extract --tools "${release_image}" --to="${tmpdir}/" 2>"${tmpdir}/extract.err"; then
    echo "  ERROR: Failed to extract tools for ${version}:" >&2
    cat "${tmpdir}/extract.err" >&2
    return 1
  fi

  local installer_tar
  installer_tar=$(ls "${tmpdir}"/openshift-install-linux-*.tar.gz 2>/dev/null | head -1)
  if [ -z "$installer_tar" ]; then
    echo "  ERROR: No openshift-install tarball found for ${version}" >&2
    return 1
  fi

  tar xf "$installer_tar" -C "${tmpdir}/" 2>/dev/null

  if [ ! -x "${tmpdir}/openshift-install" ]; then
    echo "  ERROR: openshift-install binary not found or not executable for ${version}" >&2
    echo "  This may happen with RHEL 8-era releases (4.10-4.12) on a RHEL 9 host." >&2
    echo "  Manual lookup: find the RHCOS AMI for ${version} in ${REGION} and add to ${AMI_FILE}:" >&2
    echo "    ${var}=ami-xxxxxxxxxxxxxxxxx" >&2
    return 1
  fi

  local ami
  ami=$("${tmpdir}/openshift-install" coreos print-stream-json 2>/dev/null \
    | jq -r ".architectures.x86_64.images.aws.regions[\"${REGION}\"].image // empty") || true

  if [ -z "$ami" ]; then
    echo "  ERROR: No AMI found for ${version} in ${REGION}" >&2
    echo "  The release may not have AWS AMIs for this region, or the metadata format may differ." >&2
    echo "  Manual lookup: add to ${AMI_FILE}:" >&2
    echo "    ${var}=ami-xxxxxxxxxxxxxxxxx" >&2
    return 1
  fi

  echo "${var}=${ami}" >> "$AMI_FILE"
  echo "  OK   ${version} -> ${ami}"
}

if [ "${1:-}" = "--all" ]; then
  echo "Resolving AMIs for all ${#BOOT_VERSIONS[@]} versions in ${REGION}..."
  failed=()
  for version in "${BOOT_VERSIONS[@]}"; do
    if ! resolve_one "$version"; then
      failed+=("$version")
    fi
  done
  echo ""
  echo "Results saved to ${AMI_FILE}"
  if [ ${#failed[@]} -gt 0 ]; then
    echo "FAILED versions (need manual resolution): ${failed[*]}"
    exit 1
  fi
elif [ -n "${1:-}" ]; then
  resolve_one "$1"
else
  echo "Usage: $0 --all | <version>"
  echo "  --all       Resolve AMIs for all versions in BOOT_VERSIONS"
  echo "  <version>   Resolve AMI for a single version (e.g., 4.18.24)"
  exit 1
fi
