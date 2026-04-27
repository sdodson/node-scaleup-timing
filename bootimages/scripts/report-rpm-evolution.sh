#!/bin/bash
# Generate a full RHCOS RPM evolution report across multiple release pairs.
#
# Usage: report-rpm-evolution.sh <rpms-dir> <pair1_start> <pair1_end> [<pair2_start> <pair2_end> ...]
#
# Expects rpms-<version>.txt files to already exist in <rpms-dir>.
# Use extract-rpms-from-release.sh to create them first.
#
# Examples:
#   # Generate RPM lists first
#   for v in 4.16.0 4.16.60 4.18.0 4.18.38; do
#     ./scripts/extract-rpms-from-release.sh $v .
#   done
#
#   # Then produce the report
#   ./scripts/report-rpm-evolution.sh . \
#     4.16.0 4.16.60 \
#     4.18.0 4.18.38
#
#   # Cross-major comparison
#   ./scripts/report-rpm-evolution.sh . \
#     4.16.0 4.16.60 \
#     4.18.0 4.18.38 \
#     4.16.0 4.18.38

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RPMS_DIR="${1:?Usage: $0 <rpms-dir> <start1> <end1> [<start2> <end2> ...]}"
shift

if (( $# < 2 )) || (( $# % 2 != 0 )); then
    echo "ERROR: Provide pairs of versions (start end start end ...)" >&2
    exit 1
fi

echo "================================================================"
echo "  RHCOS Package Evolution Report"
echo "  Generated: $(date +%Y-%m-%d)"
echo "================================================================"
echo ""

printf "%-20s | %5s | %5s | %9s | %7s | %5s | %7s | %10s | %8s\n" \
    "Release Pair" "Start" "End" "Identical" "Updated" "Added" "Removed" "Unchanged%" "Updated%"
printf "%-20s-+-%5s-+-%5s-+-%9s-+-%7s-+-%5s-+-%7s-+-%10s-+-%8s\n" \
    "--------------------" "-----" "-----" "---------" "-------" "-----" "-------" "----------" "--------"

while (( $# >= 2 )); do
    START="$1"; END="$2"; shift 2

    FILE_S="${RPMS_DIR}/rpms-${START}.txt"
    FILE_E="${RPMS_DIR}/rpms-${END}.txt"

    if [[ ! -f "$FILE_S" ]]; then
        echo "WARNING: ${FILE_S} not found, skipping pair" >&2
        continue
    fi
    if [[ ! -f "$FILE_E" ]]; then
        echo "WARNING: ${FILE_E} not found, skipping pair" >&2
        continue
    fi

    LINE=$("${SCRIPT_DIR}/compare-rpm-pair.sh" "$FILE_S" "$FILE_E")
    IFS='|' read -r ls le ts te ident vc added removed upct cpct <<< "$LINE"

    printf "%-8s→ %-9s | %5s | %5s | %9s | %7s | %5s | %7s | %9s%% | %7s%%\n" \
        "$ls" "$le" "$ts" "$te" "$ident" "$vc" "$added" "$removed" "$upct" "$cpct"
done

echo ""
echo "Use compare-rpm-pair.sh --detail for per-pair package diffs."
