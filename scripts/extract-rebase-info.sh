#!/bin/bash
# Extract ostree chunk/layer data from Boot 1 journal during MCD firstboot.
#
# Usage: scripts/extract-rebase-info.sh <suffix>
#   e.g.: scripts/extract-rebase-info.sh 4.14.38-m6i-r3-z2
#
# Outputs: $DATA_DIR/rebase-info-<suffix>.json

set -euo pipefail
source "$(dirname "$0")/config.env"

SUFFIX="${1:?Usage: $0 <suffix>}"

JOURNAL="${DATA_DIR}/node-journal-${SUFFIX}.log"
OUTFILE="${DATA_DIR}/rebase-info-${SUFFIX}.json"

BOOT_VERSION=$(echo "$SUFFIX" | sed 's/-m6i-r[0-9]*-z[0-9]*//')

if [ ! -f "$JOURNAL" ]; then
  echo '{"suffix":"'"${SUFFIX}"'","boot_version":"'"${BOOT_VERSION}"'","error":"Journal not found"}' > "$OUTFILE"
  echo "  WARN: Journal file not found" >&2
  exit 0
fi

# Extract chunk summary lines (deduplicate podman vs container name lines)
# Note: journal may have '?' (0x3f) or non-breaking space between number and unit (e.g., "309.3?MB")
CHUNKS_PRESENT=$(grep -m1 "ostree chunk layers already present:" "$JOURNAL" \
  | grep -oP 'present: \K[0-9]+' || echo "")
CHUNKS_NEEDED=$(grep -m1 "ostree chunk layers needed:" "$JOURNAL" \
  | grep -oP 'needed: \K[0-9]+' || echo "")
CHUNKS_SIZE=$(grep -m1 "ostree chunk layers needed:" "$JOURNAL" \
  | grep -oP '\(([0-9.]+).?[GMKT]i?B\)' | tr -d '()' | sed 's/[^0-9.GMKTB]//g' || echo "")
CUSTOM_LAYERS=$(grep -m1 "custom layers needed:" "$JOURNAL" \
  | grep -oP 'needed: \K[0-9]+' || echo "")
CUSTOM_SIZE=$(grep -m1 "custom layers needed:" "$JOURNAL" \
  | grep -oP '\(([0-9.]+).?[GMKT]i?B\)' | tr -d '()' | sed 's/[^0-9.GMKTB]//g' || echo "")

# rpm-ostree summary line: "layers already present: N; layers needed: N (SIZE)"
RPM_OSTREE_SUMMARY=$(grep -m1 "layers already present:.*layers needed:" "$JOURNAL" || echo "")
TOTAL_FETCH_SIZE=""
if [ -n "$RPM_OSTREE_SUMMARY" ]; then
  TOTAL_FETCH_SIZE=$(echo "$RPM_OSTREE_SUMMARY" | grep -oP 'needed: \d+ \(\K[^)]+' \
    | sed 's/[^0-9.GMKTBgmktb ]//g; s/  */ /g; s/^ //; s/ $//' || echo "")
fi

# Extract individual fetch lines — deduplicate (podman/container/rpm-ostree all log)
# Format 1 (4.20): "[N/M] Fetching ostree chunk HASH (SIZE)...done"
# Format 2 (4.18): "Fetching ostree chunk sha256:HASH (SIZE)"
FETCH_LINES=$(grep -E "Fetching (ostree chunk|layer)" "$JOURNAL" \
  | grep -v "afterburn\|Fetching http" \
  | sort -u -t':' -k4 || true)
# Deduplicate: prefer rpm-ostree lines, fall back to podman
if echo "$FETCH_LINES" | grep -q "rpm-ostree\["; then
  FETCH_LINES=$(echo "$FETCH_LINES" | grep "rpm-ostree\[" || true)
elif echo "$FETCH_LINES" | grep -q "podman\["; then
  FETCH_LINES=$(echo "$FETCH_LINES" | grep "podman\[" || true)
fi

# Parse fetch lines into JSON array via python
CHUNKS_JSON=$(echo "$FETCH_LINES" | python3 -c "
import sys, re, json

chunks = []
seen = set()
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue

    # Extract timestamp
    ts_match = re.match(r'(\w+ \d+ [\d:]+)', line)
    ts = ts_match.group(1) if ts_match else ''

    # Determine type and extract hash
    if 'Fetching ostree chunk' in line:
        chunk_type = 'ostree_chunk'
        hash_match = re.search(r'Fetching ostree chunk (?:sha256:)?(\S+)', line)
    elif 'Fetching layer' in line:
        chunk_type = 'custom_layer'
        hash_match = re.search(r'Fetching layer (?:sha256:)?(\S+)', line)
    else:
        continue

    chunk_hash = hash_match.group(1) if hash_match else ''
    # Normalize: strip trailing punctuation from hash
    chunk_hash = chunk_hash.rstrip('.')

    # Deduplicate by hash
    if chunk_hash in seen:
        continue
    seen.add(chunk_hash)

    # Extract size (handle '?' or non-breaking space between number and unit)
    size_match = re.search(r'\(([0-9.]+).?([GMKT]i?B)\)', line)
    size_str = ''
    size_mb = None
    if size_match:
        val = float(size_match.group(1))
        unit = size_match.group(2)
        size_str = f'{val} {unit}'
        if 'GB' in unit:
            size_mb = val * 1024
        elif 'MB' in unit:
            size_mb = val
        elif 'kB' in unit or 'KB' in unit:
            size_mb = val / 1024
        elif 'B' == unit:
            size_mb = val / (1024*1024)

    chunks.append({
        'hash': chunk_hash,
        'type': chunk_type,
        'size': size_str,
        'size_mb': round(size_mb, 2) if size_mb is not None else None,
        'timestamp': ts,
    })

json.dump(chunks, sys.stdout)
" 2>/dev/null || echo "[]")

# Apply subtasks (4.20 format: "Created deployment; subtasks: ...", may not exist in 4.18)
APPLY_SUBTASKS=$(grep "Created deployment; subtasks:" "$JOURNAL" | tail -1 \
  | sed 's/.*subtasks: //' || true)
# If no subtasks line, note the "Created new deployment" variant (4.18)
if [ -z "$APPLY_SUBTASKS" ]; then
  APPLY_SUBTASKS=$(grep "Created new deployment" "$JOURNAL" | head -1 | sed 's/.*Created new //' || true)
fi

# Rebase target image
REBASE_TARGET=$(grep -m1 "Fetching ostree-unverified-registry:" "$JOURNAL" \
  | grep -oP 'registry:\K\S+' || echo "")

# Build final JSON
python3 -c "
import json, sys

def safe_int(v):
    try: return int(v) if v else None
    except: return None

def safe_float(v):
    try: return float(v) if v else None
    except: return None

chunks = json.loads('''${CHUNKS_JSON}''')

# Compute totals from individual chunks
ostree_chunks = [c for c in chunks if c['type'] == 'ostree_chunk']
custom_layers = [c for c in chunks if c['type'] == 'custom_layer']
ostree_total_mb = sum(c['size_mb'] for c in ostree_chunks if c['size_mb']) if ostree_chunks else None
custom_total_mb = sum(c['size_mb'] for c in custom_layers if c['size_mb']) if custom_layers else None

result = {
    'suffix': '${SUFFIX}',
    'boot_version': '${BOOT_VERSION}',
    'rebase_target': '${REBASE_TARGET}' or None,
    'chunks_present': safe_int('${CHUNKS_PRESENT}'),
    'chunks_needed': safe_int('${CHUNKS_NEEDED}'),
    'chunks_needed_size': '${CHUNKS_SIZE}' or None,
    'custom_layers_needed': safe_int('${CUSTOM_LAYERS}'),
    'custom_layers_size': '${CUSTOM_SIZE}' or None,
    'total_fetch_size': '${TOTAL_FETCH_SIZE}' or None,
    'ostree_total_mb': round(ostree_total_mb, 1) if ostree_total_mb else None,
    'custom_total_mb': round(custom_total_mb, 1) if custom_total_mb else None,
    'apply_subtasks': '${APPLY_SUBTASKS}' or None,
    'chunks': chunks,
}

json.dump(result, sys.stdout, indent=2)
print()
" > "$OUTFILE"

echo "  Rebase info extracted -> ${OUTFILE}"
