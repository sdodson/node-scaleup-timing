#!/bin/bash
# Extract a sorted RPM list from an RHCOS VMDK (or .vmdk.gz) image.
#
# Requires: guestfish (guestfs-tools), rpm, sqlite3
#
# Usage: extract-rpms-from-vmdk.sh <image.vmdk[.gz]> [output-file]
#
# Examples:
#   ./extract-rpms-from-vmdk.sh rhcos-aws.x86_64.vmdk.gz
#   ./extract-rpms-from-vmdk.sh rhcos-aws.x86_64.vmdk rpms-vmdk.txt

set -euo pipefail

INPUT="${1:?Usage: $0 <image.vmdk[.gz]> [output-file]}"
OUTFILE="${2:-rpms-vmdk.txt}"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

VMDK="$INPUT"
if [[ "$INPUT" == *.gz ]]; then
    echo "Decompressing ${INPUT}..." >&2
    VMDK="${TMPDIR}/$(basename "$INPUT" .gz)"
    gunzip -c "$INPUT" > "$VMDK"
fi

echo "Inspecting filesystems..." >&2
ROOT_DEV=$(virt-filesystems -a "$VMDK" --filesystems 2>/dev/null \
    | grep -E 'sda[34]$' | tail -1)

if [[ -z "$ROOT_DEV" ]]; then
    echo "ERROR: Could not find root filesystem in ${INPUT}" >&2
    exit 1
fi

echo "Looking for OSTree deployment on ${ROOT_DEV}..." >&2
DEPLOY_DIR=$(guestfish --ro -a "$VMDK" -m "$ROOT_DEV" -- \
    glob-expand '/ostree/deploy/*/deploy/*.0' 2>/dev/null | head -1)

if [[ -z "$DEPLOY_DIR" ]]; then
    echo "ERROR: Could not find OSTree deployment" >&2
    exit 1
fi

RPMDB_PATH="${DEPLOY_DIR}/usr/lib/sysimage/rpm/rpmdb.sqlite"
echo "Extracting rpmdb from ${RPMDB_PATH}..." >&2

RPMDB_LOCAL="${TMPDIR}/var/lib/rpm/rpmdb.sqlite"
mkdir -p "$(dirname "$RPMDB_LOCAL")"
guestfish --ro -a "$VMDK" -m "$ROOT_DEV" -- \
    download "$RPMDB_PATH" "$RPMDB_LOCAL" 2>/dev/null

rpm --dbpath "${TMPDIR}/var/lib/rpm" -qa 2>/dev/null | sort > "$OUTFILE"

COUNT=$(wc -l < "$OUTFILE")
echo "Extracted ${COUNT} packages → ${OUTFILE}" >&2
