#!/bin/bash
# Aggregate all timing and rebase data into a single summary CSV.
#
# Usage: scripts/aggregate-results.sh
#
# Reads all timings-*.json and rebase-info-*.json files from $DATA_DIR,
# joins them, and produces summary.csv with one row per sample.

set -euo pipefail
source "$(dirname "$0")/config.env"

OUTFILE="${DATA_DIR}/summary.csv"

# CSV header
echo "boot_version,round,zone,total_s,vm_prov_s,boot1_s,rebase_total_s,rebase_fetch_s,reboot_s,systemd_analyze_s,chrony_wait_s,ktr_s,chunks_present,chunks_needed,chunks_needed_size,custom_layers,custom_layers_size,total_fetch_size,ostree_total_mb,custom_total_mb,boot2_images_count,boot2_images_total_mb" > "$OUTFILE"

ROWS=0

for timing_file in "${DATA_DIR}"/timings-*.json; do
  [ -f "$timing_file" ] || continue

  SUFFIX=$(basename "$timing_file" | sed 's/^timings-//; s/\.json$//')
  REBASE_FILE="${DATA_DIR}/rebase-info-${SUFFIX}.json"
  IMAGES_FILE="${DATA_DIR}/nodeready-images-${SUFFIX}.json"

  python3 -c "
import json, sys

try:
    with open('${timing_file}') as f:
        t = json.load(f)
except:
    sys.exit(0)

if 'error' in t:
    sys.exit(0)

r = {}
try:
    with open('${REBASE_FILE}') as f:
        r = json.load(f)
except:
    pass

img = {}
try:
    with open('${IMAGES_FILE}') as f:
        img = json.load(f)
except:
    pass

def v(d, k):
    val = d.get(k)
    return '' if val is None else str(val)

fields = [
    v(t, 'boot_version'),
    v(t, 'round'),
    v(t, 'zone'),
    v(t, 'total_s'),
    v(t, 'vm_provisioning_s'),
    v(t, 'boot1_total_s'),
    v(t, 'rebase_total_s'),
    v(t, 'rebase_fetch_s'),
    v(t, 'reboot_gap_s'),
    v(t, 'boot2_systemd_analyze_s'),
    v(t, 'chrony_wait_s'),
    v(t, 'ktr_s'),
    v(r, 'chunks_present'),
    v(r, 'chunks_needed'),
    v(r, 'chunks_needed_size'),
    v(r, 'custom_layers_needed'),
    v(r, 'custom_layers_size'),
    v(r, 'total_fetch_size'),
    v(r, 'ostree_total_mb'),
    v(r, 'custom_total_mb'),
    v(img, 'boot2_images_count'),
    v(img, 'boot2_images_total_mb'),
]

print(','.join(fields))
" >> "$OUTFILE" 2>/dev/null && ROWS=$((ROWS + 1))
done

echo "Aggregated ${ROWS} samples -> ${OUTFILE}"
