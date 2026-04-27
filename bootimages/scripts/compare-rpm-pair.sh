#!/bin/bash
# Compare two sorted RPM list files and report statistics.
#
# Usage: compare-rpm-pair.sh <rpms-start.txt> <rpms-end.txt> [--detail]
#
# Without --detail: prints a single pipe-delimited summary line:
#   start_label|end_label|total_start|total_end|identical|updated|added|removed|unchanged%|updated%
#
# With --detail: prints the full breakdown including added, removed,
#   and updated package lists.
#
# Examples:
#   ./compare-rpm-pair.sh rpms-4.16.0.txt rpms-4.16.60.txt
#   ./compare-rpm-pair.sh rpms-4.16.0.txt rpms-4.18.38.txt --detail

set -euo pipefail

FILE_S="${1:?Usage: $0 <rpms-start.txt> <rpms-end.txt> [--detail]}"
FILE_E="${2:?Usage: $0 <rpms-start.txt> <rpms-end.txt> [--detail]}"
DETAIL="${3:-}"

# Derive labels from filenames (rpms-4.16.0.txt → 4.16.0)
LABEL_S=$(basename "$FILE_S" .txt | sed 's/^rpms-//')
LABEL_E=$(basename "$FILE_E" .txt | sed 's/^rpms-//')

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

TOTAL_S=$(wc -l < "$FILE_S")
TOTAL_E=$(wc -l < "$FILE_E")
IDENTICAL=$(comm -12 "$FILE_S" "$FILE_E" | wc -l)

# Extract package names (strip version-release.arch)
extract_name() { sed 's/\(.*\)-[^-]*-[^-]*$/\1/'; }

extract_name < "$FILE_S" | sort -u > "${TMPDIR}/names-s.txt"
extract_name < "$FILE_E" | sort -u > "${TMPDIR}/names-e.txt"

ADDED=$(comm -23 "${TMPDIR}/names-e.txt" "${TMPDIR}/names-s.txt" | wc -l)
REMOVED=$(comm -23 "${TMPDIR}/names-s.txt" "${TMPDIR}/names-e.txt" | wc -l)

# Build name→NEVRA maps
build_map() {
    while IFS= read -r nevra; do
        name=$(echo "$nevra" | extract_name)
        printf '%s\t%s\n' "$name" "$nevra"
    done | sort -t$'\t' -k1,1
}

build_map < "$FILE_S" > "${TMPDIR}/map-s.txt"
build_map < "$FILE_E" > "${TMPDIR}/map-e.txt"

VERSION_CHANGED=$(join -t$'\t' "${TMPDIR}/map-s.txt" "${TMPDIR}/map-e.txt" 2>/dev/null \
    | awk -F'\t' '$2 != $3' | wc -l)

UNCHANGED_PCT=$((IDENTICAL * 100 / TOTAL_S))
CHANGED_PCT=$((VERSION_CHANGED * 100 / TOTAL_S))

if [[ "$DETAIL" == "--detail" ]]; then
    echo "================================================================"
    echo "  ${LABEL_S} → ${LABEL_E}: Package Comparison"
    echo "================================================================"
    echo ""
    printf "%-14s %d packages\n" "${LABEL_S}:" "$TOTAL_S"
    printf "%-14s %d packages\n" "${LABEL_E}:" "$TOTAL_E"
    echo ""
    printf "Identical (same NEVRA): %d (%d%%)\n" "$IDENTICAL" "$UNCHANGED_PCT"
    printf "Updated (same name):    %d (%d%%)\n" "$VERSION_CHANGED" "$CHANGED_PCT"
    printf "Added:                  %d\n" "$ADDED"
    printf "Removed:                %d\n" "$REMOVED"

    ADDED_LIST=$(comm -23 "${TMPDIR}/names-e.txt" "${TMPDIR}/names-s.txt")
    if [[ -n "$ADDED_LIST" ]]; then
        echo ""
        echo "--- ADDED packages ---"
        echo "$ADDED_LIST" | while read -r pkg; do
            ver=$(grep "^${pkg}-" "$FILE_E" | head -1)
            echo "  + $ver"
        done
    fi

    REMOVED_LIST=$(comm -23 "${TMPDIR}/names-s.txt" "${TMPDIR}/names-e.txt")
    if [[ -n "$REMOVED_LIST" ]]; then
        echo ""
        echo "--- REMOVED packages ---"
        echo "$REMOVED_LIST" | while read -r pkg; do
            ver=$(grep "^${pkg}-" "$FILE_S" | head -1)
            echo "  - $ver"
        done
    fi

    echo ""
    echo "--- UPDATED packages ---"
    join -t$'\t' "${TMPDIR}/map-s.txt" "${TMPDIR}/map-e.txt" 2>/dev/null \
        | awk -F'\t' '$2 != $3 {printf "  %-55s → %s\n", $2, $3}'
else
    echo "${LABEL_S}|${LABEL_E}|${TOTAL_S}|${TOTAL_E}|${IDENTICAL}|${VERSION_CHANGED}|${ADDED}|${REMOVED}|${UNCHANGED_PCT}|${CHANGED_PCT}"
fi
