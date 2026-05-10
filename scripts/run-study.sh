#!/bin/bash
# Top-level orchestrator for the boot image age study.
# Iterates through boot image versions and runs N rounds per version.
#
# Usage:
#   scripts/run-study.sh                              # run full study
#   scripts/run-study.sh --start-version 4.14.38      # resume from a specific version
#   scripts/run-study.sh --start-version 4.14.38 --start-round 3  # resume from version+round
#   scripts/run-study.sh --version 4.18.0             # run only one version

set -euo pipefail
source "$(dirname "$0")/config.env"
check_kubeconfig

SCRIPT_DIR="$(dirname "$0")"
START_VERSION=""
START_ROUND=1
SINGLE_VERSION=""

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --start-version) START_VERSION="$2"; shift 2 ;;
    --start-round) START_ROUND="$2"; shift 2 ;;
    --version) SINGLE_VERSION="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

mkdir -p "$DATA_DIR"

# Validate prerequisites
echo "=== Boot Image Age Study ==="
echo "Cluster version: ${CLUSTER_VERSION}"
echo "Region: ${REGION}"
echo "Instance type: ${INSTANCE_TYPE}"
echo "Rounds per version: ${ROUNDS}"
echo "Zones per round: ${#ZONE_LETTERS[@]}"
echo "Total samples per version: $(( ROUNDS * ${#ZONE_LETTERS[@]} ))"
echo ""

# Check cluster version
ACTUAL_VERSION=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || echo "unknown")
echo "Actual cluster version: ${ACTUAL_VERSION}"
if [[ "$ACTUAL_VERSION" != "${CLUSTER_VERSION}"* ]]; then
  echo "WARNING: Cluster version ${ACTUAL_VERSION} does not match expected ${CLUSTER_VERSION}" >&2
  read -p "Continue anyway? (y/N) " -r
  [[ $REPLY =~ ^[Yy]$ ]] || exit 1
fi

# Check AMIs are resolved
if [ ! -f "$AMI_FILE" ]; then
  echo "AMI file not found. Running lookup-ami.sh --all..."
  "${SCRIPT_DIR}/lookup-ami.sh" --all
fi

# Determine versions to test
if [ -n "$SINGLE_VERSION" ]; then
  VERSIONS=("$SINGLE_VERSION")
elif [ -n "$START_VERSION" ]; then
  VERSIONS=()
  FOUND=false
  for v in "${BOOT_VERSIONS[@]}"; do
    if [ "$v" = "$START_VERSION" ]; then
      FOUND=true
    fi
    if $FOUND; then
      VERSIONS+=("$v")
    fi
  done
  if ! $FOUND; then
    echo "ERROR: Start version ${START_VERSION} not found in BOOT_VERSIONS" >&2
    exit 1
  fi
else
  VERSIONS=("${BOOT_VERSIONS[@]}")
fi

echo ""
echo "Versions to test: ${VERSIONS[*]}"
echo "==========================================="
echo ""

STUDY_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TOTAL_VERSIONS=${#VERSIONS[@]}
VERSION_NUM=0

for VERSION in "${VERSIONS[@]}"; do
  VERSION_NUM=$((VERSION_NUM + 1))

  AMI=$(get_ami "$VERSION")
  if [ -z "$AMI" ]; then
    echo "ERROR: No AMI for ${VERSION}. Add it to ${AMI_FILE} and retry." >&2
    echo "  Format: $(version_to_var "$VERSION")=ami-xxxxxxxxxxxxxxxxx" >&2
    continue
  fi

  echo "===== [${VERSION_NUM}/${TOTAL_VERSIONS}] Boot image: ${VERSION} (AMI: ${AMI}) ====="

  FIRST_ROUND=1
  if [ "$VERSION" = "$START_VERSION" ] && [ -n "$START_VERSION" ]; then
    FIRST_ROUND=$START_ROUND
    START_VERSION=""  # only apply start_round to the first version
  fi

  for ROUND in $(seq "$FIRST_ROUND" "$ROUNDS"); do
    # Resume support: skip if this round already has data
    SUFFIX=$(make_suffix "$VERSION" "$ROUND" "a")
    if [ -f "${DATA_DIR}/timings-${SUFFIX}.json" ]; then
      echo "  Round ${ROUND} already complete, skipping"
      continue
    fi

    "${SCRIPT_DIR}/run-round.sh" "$VERSION" "$ROUND"

    # Cooldown between rounds
    if [ "$ROUND" -lt "$ROUNDS" ]; then
      echo "  Cooldown ${COOLDOWN}s..."
      sleep "$COOLDOWN"
    fi
  done

  echo ""
done

STUDY_END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "==========================================="
echo "Study complete: ${STUDY_START} -> ${STUDY_END}"
echo ""

# Aggregate results
echo "Aggregating results..."
"${SCRIPT_DIR}/aggregate-results.sh"
