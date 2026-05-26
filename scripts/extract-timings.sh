#!/bin/bash
# Extract phase timings from journal logs and Machine/Node YAML.
#
# Usage: scripts/extract-timings.sh <suffix>
#   e.g.: scripts/extract-timings.sh 4.14.38-m6i-r3-z2
#
# Outputs: $DATA_DIR/timings-<suffix>.json

set -euo pipefail
source "$(dirname "$0")/config.env"

SUFFIX="${1:?Usage: $0 <suffix>}"

JOURNAL="${DATA_DIR}/node-journal-${SUFFIX}.log"
MACHINE_YAML="${DATA_DIR}/new-machine-${SUFFIX}-final.yaml"
NODE_YAML="${DATA_DIR}/new-node-${SUFFIX}.yaml"
SA_FILE="${DATA_DIR}/node-systemd-analyze-${SUFFIX}.txt"
BLAME_FILE="${DATA_DIR}/node-systemd-blame-${SUFFIX}.txt"
BOOT_LIST="${DATA_DIR}/node-boot-list-${SUFFIX}.txt"
OUTFILE="${DATA_DIR}/timings-${SUFFIX}.json"

# Parse round number from suffix (e.g. "5.0-m6a-baseline-r2-2b" -> "2", "4.14.38-m6i-r3-z2" -> "3")
ROUND=$(echo "$SUFFIX" | grep -oP '(?<=-r)\d+(?=-|$)' | head -1)
ROUND="${ROUND:-0}"

# Convert journal timestamp "Mon DD HH:MM:SS" to epoch seconds (UTC).
# Requires YEAR to be set (derived from Machine YAML creation timestamp).
journal_to_epoch() {
  local ts="$1"
  date -u -d "${ts} ${YEAR}" +%s 2>/dev/null || echo ""
}

# Extract ISO timestamp and convert to epoch
iso_to_epoch() {
  date -d "$1" +%s 2>/dev/null || echo ""
}

emit_null() {
  cat > "$OUTFILE" <<EOF
{
  "suffix": "${SUFFIX}",
  "round": ${ROUND},
  "error": "$1"
}
EOF
  echo "  WARN: ${1}" >&2
  exit 0
}

if [ ! -f "$JOURNAL" ]; then
  emit_null "Journal file not found"
fi

# Get year from Machine creation timestamp
CREATED_ISO=""
if [ -f "$MACHINE_YAML" ]; then
  CREATED_ISO=$(grep "creationTimestamp:" "$MACHINE_YAML" | head -1 | awk '{print $2}' | tr -d '"')
fi
if [ -z "$CREATED_ISO" ]; then
  emit_null "Cannot determine creation timestamp from Machine YAML"
fi
YEAR=$(date -d "$CREATED_ISO" +%Y)
CREATED_EPOCH=$(iso_to_epoch "$CREATED_ISO")

# Get NodeReady timestamp from Node YAML
NODE_READY_ISO=""
if [ -f "$NODE_YAML" ]; then
  NODE_READY_ISO=$(python3 -c "
import yaml, sys
with open('${NODE_YAML}') as f:
    node = yaml.safe_load(f)
for c in node.get('status', {}).get('conditions', []):
    if c.get('type') == 'Ready' and c.get('status') == 'True':
        print(c.get('lastTransitionTime', ''))
        break
" 2>/dev/null || true)
fi
NODE_READY_EPOCH=""
if [ -n "$NODE_READY_ISO" ]; then
  NODE_READY_EPOCH=$(iso_to_epoch "$NODE_READY_ISO")
fi

# Find Boot 1 and Boot 2 boundaries from boot list
# Format: " -1 BOOTID DayOfWeek YYYY-MM-DD HH:MM:SS TZ DayOfWeek YYYY-MM-DD HH:MM:SS TZ"
#   e.g.: " -1 4e51fd7274fc... Tue 2026-04-28 18:49:30 UTC Tue 2026-04-28 18:50:57 UTC"
BOOT1_FIRST=""
BOOT1_LAST=""
BOOT2_FIRST=""

# Helper to parse boot list timestamp (YYYY-MM-DD HH:MM:SS UTC) to epoch
bootlist_to_epoch() {
  date -u -d "$1" +%s 2>/dev/null || echo ""
}

if [ -f "$BOOT_LIST" ]; then
  NBOOTS=$(grep -cP '^\s+-?\d+\s+' "$BOOT_LIST" || true)

  if [ "$NBOOTS" -ge 2 ]; then
    # The second-to-last boot is MCD firstboot (Boot 1), last is Boot 2
    BOOT1_LINE=$(grep -P '^\s+-?\d+\s+' "$BOOT_LIST" | tail -2 | head -1)
    BOOT2_LINE=$(grep -P '^\s+-?\d+\s+' "$BOOT_LIST" | tail -1)

    # Fields: $1=IDX $2=BOOTID $3=DayOfWeek $4=YYYY-MM-DD $5=HH:MM:SS $6=TZ $7=DayOfWeek $8=YYYY-MM-DD $9=HH:MM:SS $10=TZ
    BOOT1_FIRST=$(echo "$BOOT1_LINE" | awk '{print $4, $5}')
    BOOT1_LAST=$(echo "$BOOT1_LINE" | awk '{print $8, $9}')
    BOOT2_FIRST=$(echo "$BOOT2_LINE" | awk '{print $4, $5}')
  fi
fi

# Parse key timestamps from journal
# All greps use || true to avoid set -e abort on no match

# First kernel boot (Boot 1)
BOOT1_KERNEL_TS=$(grep -m1 "kernel: Linux version" "$JOURNAL" | awk '{print $1, $2, $3}' || true)
BOOT1_KERNEL_EPOCH=""
if [ -n "$BOOT1_KERNEL_TS" ]; then
  BOOT1_KERNEL_EPOCH=$(journal_to_epoch "$BOOT1_KERNEL_TS")
fi

# MCD start: look for machine-config-daemon-pull or MCD container pull
MCD_START_TS=$(grep -m1 "machine-config-daemon-pull.service\|Starting Machine Config Daemon Pull" "$JOURNAL" \
  | grep "Starting\|Started" | head -1 | awk '{print $1, $2, $3}' || true)
if [ -z "$MCD_START_TS" ]; then
  MCD_START_TS=$(grep -m1 "podman.*pull.*machine-config-daemon" "$JOURNAL" | awk '{print $1, $2, $3}' || true)
fi

# rpm-ostree rebase initiation
REBASE_START_TS=$(grep -m1 "Initiated txn Rebase" "$JOURNAL" | awk '{print $1, $2, $3}' || true)
REBASE_START_EPOCH=""
if [ -n "$REBASE_START_TS" ]; then
  REBASE_START_EPOCH=$(journal_to_epoch "$REBASE_START_TS")
fi

# First ostree chunk fetch
FIRST_FETCH_TS=$(grep -m1 "Fetching ostree chunk\|Fetching layer" "$JOURNAL" | awk '{print $1, $2, $3}' || true)
FIRST_FETCH_EPOCH=""
if [ -n "$FIRST_FETCH_TS" ]; then
  FIRST_FETCH_EPOCH=$(journal_to_epoch "$FIRST_FETCH_TS")
fi

# rpm-ostree rebase completion: "Created deployment" or "Created new deployment"
REBASE_DONE_TS=$(grep "Created.*deployment" "$JOURNAL" | grep -v "KernelArgs" | head -1 | awk '{print $1, $2, $3}' || true)
REBASE_DONE_EPOCH=""
if [ -n "$REBASE_DONE_TS" ]; then
  REBASE_DONE_EPOCH=$(journal_to_epoch "$REBASE_DONE_TS")
fi

# Reboot trigger
REBOOT_TS=$(grep -m1 '"Rebooting node"' "$JOURNAL" | awk '{print $1, $2, $3}' || true)
REBOOT_EPOCH=""
if [ -n "$REBOOT_TS" ]; then
  REBOOT_EPOCH=$(journal_to_epoch "$REBOOT_TS")
fi

# Boot 2 kernel (from boot list: ISO format "YYYY-MM-DD HH:MM:SS")
BOOT2_KERNEL_EPOCH=""
if [ -n "$BOOT2_FIRST" ]; then
  BOOT2_KERNEL_EPOCH=$(bootlist_to_epoch "$BOOT2_FIRST")
fi

# Boot 1 epoch from boot list (more reliable than first kernel line for multi-boot)
BOOT1_EPOCH=""
if [ -n "$BOOT1_FIRST" ]; then
  BOOT1_EPOCH=$(bootlist_to_epoch "$BOOT1_FIRST")
elif [ -n "$BOOT1_KERNEL_EPOCH" ]; then
  BOOT1_EPOCH="$BOOT1_KERNEL_EPOCH"
fi

BOOT1_END_EPOCH=""
if [ -n "$BOOT1_LAST" ]; then
  BOOT1_END_EPOCH=$(bootlist_to_epoch "$BOOT1_LAST")
elif [ -n "$REBOOT_EPOCH" ]; then
  BOOT1_END_EPOCH="$REBOOT_EPOCH"
fi

# Compute durations (use jq for null-safe arithmetic)
# systemd-analyze total from the text file
SA_TOTAL=""
if [ -f "$SA_FILE" ]; then
  SA_TOTAL=$(grep -oP '= \K[0-9.]+s' "$SA_FILE" | head -1 | tr -d 's' || true)
fi

# chrony-wait from blame file
CHRONY_WAIT=""
if [ -f "$BLAME_FILE" ]; then
  CHRONY_WAIT=$(grep "chrony-wait.service" "$BLAME_FILE" | head -1 | awk '{print $1}' | tr -d 's' || true)
fi

# Apply subtasks from "Created deployment" line
APPLY_SUBTASKS=$(grep "Created deployment; subtasks:" "$JOURNAL" | tail -1 \
  | sed 's/.*subtasks: //' || true)

# Build JSON output
python3 -c "
import json, sys

def safe_int(v):
    try: return int(v) if v else None
    except: return None

def safe_float(v):
    try: return float(v) if v else None
    except: return None

def delta(a, b):
    a, b = safe_int(a), safe_int(b)
    if a is not None and b is not None and b >= a:
        return b - a
    return None

created = safe_int('${CREATED_EPOCH}')
boot1 = safe_int('${BOOT1_EPOCH}')
boot1_end = safe_int('${BOOT1_END_EPOCH}')
boot2 = safe_int('${BOOT2_KERNEL_EPOCH}')
rebase_start = safe_int('${REBASE_START_EPOCH}')
first_fetch = safe_int('${FIRST_FETCH_EPOCH}')
rebase_done = safe_int('${REBASE_DONE_EPOCH}')
reboot = safe_int('${REBOOT_EPOCH}')
node_ready = safe_int('${NODE_READY_EPOCH}')

result = {
    'suffix': '${SUFFIX}',
    'round': ${ROUND},
    'machineset_created': '${CREATED_ISO}',
    'node_ready_time': '${NODE_READY_ISO}' or None,
    'vm_provisioning_s': delta(created, boot1),
    'boot1_total_s': delta(boot1, boot1_end),
    'rebase_start_s': delta(rebase_start, first_fetch) if rebase_start and first_fetch else None,
    'rebase_fetch_s': delta(first_fetch, rebase_done),
    'rebase_total_s': delta(rebase_start, rebase_done),
    'reboot_gap_s': delta(boot1_end, boot2),
    'boot2_systemd_analyze_s': safe_float('${SA_TOTAL}'),
    'chrony_wait_s': safe_float('${CHRONY_WAIT}'),
    'ktr_s': delta(boot2, node_ready),
    'total_s': delta(created, node_ready),
    'apply_subtasks': '${APPLY_SUBTASKS}' or None,
}

json.dump(result, sys.stdout, indent=2)
print()
" > "$OUTFILE"

echo "  Timings extracted -> ${OUTFILE}"
