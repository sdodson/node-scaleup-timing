#!/bin/bash
# Extract container images needed for NodeReady, with names and sizes.
#
# Usage: scripts/extract-nodeready-images.sh <suffix>
#   e.g.: scripts/extract-nodeready-images.sh 4.14.38-m6i-r3-z2
#
# Combines crictl images JSON (sizes) with CRI-O pull events from Boot 2
# journal (pull timing). Outputs: $DATA_DIR/nodeready-images-<suffix>.json

set -euo pipefail
source "$(dirname "$0")/config.env"

SUFFIX="${1:?Usage: $0 <suffix>}"

JOURNAL="${DATA_DIR}/node-journal-${SUFFIX}.log"
IMAGES_JSON="${DATA_DIR}/node-images-detail-${SUFFIX}.json"
IMAGES_TXT="${DATA_DIR}/node-images-${SUFFIX}.txt"
BOOT_LIST="${DATA_DIR}/node-boot-list-${SUFFIX}.txt"
OUTFILE="${DATA_DIR}/nodeready-images-${SUFFIX}.json"

BOOT_VERSION="$SUFFIX"

if [ ! -f "$JOURNAL" ]; then
  echo '{"suffix":"'"${SUFFIX}"'","boot_version":"'"${BOOT_VERSION}"'","error":"Journal not found"}' > "$OUTFILE"
  exit 0
fi

# Get year from journal for timestamp parsing
YEAR=$(grep -m1 "kernel: Linux version" "$JOURNAL" | awk '{print $1}' || echo "2026")
# The journal timestamp doesn't include year — get it from Machine YAML if available
MACHINE_YAML="${DATA_DIR}/new-machine-${SUFFIX}-final.yaml"
if [ -f "$MACHINE_YAML" ]; then
  YEAR=$(grep "creationTimestamp:" "$MACHINE_YAML" | head -1 | awk '{print $2}' | cut -d- -f1 | tr -d '"')
fi

# Find Boot 2 start timestamp from boot list
# Format: " 0 BOOTID DayOfWeek YYYY-MM-DD HH:MM:SS TZ ..."
BOOT2_START=""
if [ -f "$BOOT_LIST" ]; then
  BOOT2_LINE=$(grep -P '^\s+-?\d+\s+' "$BOOT_LIST" | tail -1)
  BOOT2_START=$(echo "$BOOT2_LINE" | awk '{print $4, $5}')
fi

python3 -c "
import json, sys, re
from datetime import datetime

suffix = '${SUFFIX}'
boot_version = '${BOOT_VERSION}'
journal_path = '${JOURNAL}'
images_json_path = '${IMAGES_JSON}'
images_txt_path = '${IMAGES_TXT}'
boot2_start = '${BOOT2_START}'
year = '${YEAR}'

# Parse CRI-O pull events from journal (Boot 2 only)
pulls = {}  # digest -> {pull_start, pull_end}
request_ids = {}  # request_id -> digest (maps Pulled back to Pulling)

def parse_journal_ts(ts_str):
    try:
        return datetime.strptime(f'{year} {ts_str}', '%Y %b %d %H:%M:%S')
    except:
        return None

def parse_bootlist_ts(ts_str):
    try:
        return datetime.strptime(ts_str, '%Y-%m-%d %H:%M:%S')
    except:
        return None

# Find Boot 2 boundary
boot2_ts = None
if boot2_start:
    boot2_ts = parse_bootlist_ts(boot2_start)

with open(journal_path) as f:
    in_boot2 = False
    for line in f:
        # Detect boot boundary
        if '-- Boot' in line:
            continue

        if not in_boot2:
            if boot2_ts:
                ts_match = re.match(r'(\w+ \d+ [\d:]+)', line)
                if ts_match:
                    line_ts = parse_journal_ts(ts_match.group(1))
                    if line_ts and line_ts >= boot2_ts:
                        in_boot2 = True
            elif 'kernel: Linux version' in line:
                # If no boot list, use second kernel line as Boot 2 start
                if not boot2_ts:
                    ts_match = re.match(r'(\w+ \d+ [\d:]+)', line)
                    if ts_match:
                        boot2_ts = parse_journal_ts(ts_match.group(1))
                        in_boot2 = True

        if not in_boot2:
            continue

        if 'crio' not in line:
            continue

        # Parse CRI-O Pulling/Pulled events, matched by request ID.
        # Pulling format: msg="Pulling image: PULLSPEC" id=REQUEST_ID
        # Pulled format:  msg="Pulled image: CONTAINER_ID" id=REQUEST_ID
        pull_match = re.search(r'time=\"([^\"]+)\".*msg=\"Pulling image: (\S+)\".*id=([a-f0-9-]+)', line)
        if pull_match:
            iso_ts = pull_match.group(1)
            pullspec = pull_match.group(2)
            req_id = pull_match.group(3)
            digest = ''
            sha_match = re.search(r'@sha256:([a-f0-9]+)', pullspec)
            if sha_match:
                digest = 'sha256:' + sha_match.group(1)
            else:
                digest = pullspec
            try:
                ts = datetime.fromisoformat(iso_ts.rstrip('Z'))
            except:
                continue
            if req_id not in request_ids:
                request_ids[req_id] = digest
            if digest not in pulls:
                pulls[digest] = {'pullspec': pullspec, 'pull_start': None, 'pull_end': None}
            if pulls[digest]['pull_start'] is None or ts < pulls[digest]['pull_start']:
                pulls[digest]['pull_start'] = ts
            continue

        pulled_match = re.search(r'time=\"([^\"]+)\".*msg=\"Pulled image: \S+\".*id=([a-f0-9-]+)', line)
        if pulled_match:
            iso_ts = pulled_match.group(1)
            req_id = pulled_match.group(2)
            digest = request_ids.get(req_id)
            if not digest:
                continue
            try:
                ts = datetime.fromisoformat(iso_ts.rstrip('Z'))
            except:
                continue
            if digest in pulls:
                if pulls[digest]['pull_end'] is None or ts > pulls[digest]['pull_end']:
                    pulls[digest]['pull_end'] = ts

# Parse image sizes from crictl images JSON
image_sizes = {}  # digest -> size_bytes
try:
    with open(images_json_path) as f:
        data = json.load(f)
        for img in data.get('images', []):
            for digest in img.get('repoDigests', []):
                d = digest.split('@')[-1] if '@' in digest else digest
                image_sizes[d] = img.get('size', '0')
            # Also index by ID
            img_id = img.get('id', '')
            if img_id:
                image_sizes[img_id] = img.get('size', '0')
except (FileNotFoundError, json.JSONDecodeError):
    # Fall back to text format
    try:
        with open(images_txt_path) as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 4 and parts[0] != 'IMAGE':
                    # SIZE column is the last, parse it
                    size_str = parts[-1]
                    multiplier = 1
                    if 'GB' in size_str:
                        multiplier = 1024*1024*1024
                    elif 'MB' in size_str:
                        multiplier = 1024*1024
                    elif 'kB' in size_str:
                        multiplier = 1024
                    try:
                        val = float(re.sub(r'[A-Za-z]', '', size_str))
                        image_sizes[parts[2]] = str(int(val * multiplier))
                    except:
                        pass
    except FileNotFoundError:
        pass

# Build results
images = []
total_size = 0
for digest, info in sorted(pulls.items(), key=lambda x: x[1].get('pull_start') or datetime.max):
    size_bytes = int(image_sizes.get(digest, 0))
    size_mb = round(size_bytes / (1024*1024), 1) if size_bytes else None
    total_size += size_bytes

    duration_s = None
    if info['pull_start'] and info['pull_end']:
        duration_s = round((info['pull_end'] - info['pull_start']).total_seconds(), 1)

    images.append({
        'pullspec': info['pullspec'],
        'digest': digest,
        'size_bytes': size_bytes if size_bytes else None,
        'size_mb': size_mb,
        'pull_duration_s': duration_s,
    })

result = {
    'suffix': suffix,
    'boot_version': boot_version,
    'boot2_images_count': len(images),
    'boot2_images_total_mb': round(total_size / (1024*1024), 1) if total_size else None,
    'images': images,
}

json.dump(result, sys.stdout, indent=2)
print()
" > "$OUTFILE"

echo "  NodeReady images extracted -> ${OUTFILE}"
