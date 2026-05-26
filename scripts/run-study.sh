#!/bin/bash
# Run a complete scale-up study: N rounds of scale-up/collect/scale-down.
#
# Usage: STUDY_NAME=<name> KUBECONFIG=<path> scripts/run-study.sh <rounds> <study_suffix>
#   e.g.: STUDY_NAME=cni-baseline KUBECONFIG=kubeconfigs/aws-5.0 scripts/run-study.sh 4 5.0-m6a-baseline
#
# Options:
#   --start-round N   Resume from round N (skips earlier rounds)

set -euo pipefail
source "$(dirname "$0")/config.env"
check_kubeconfig
detect_machine_namespace
discover_test_machinesets

SCRIPT_DIR="$(dirname "$0")"
START_ROUND=1

# Parse positional args first, then options
ROUNDS=""
STUDY_SUFFIX=""
while [ $# -gt 0 ]; do
  case "$1" in
    --start-round) START_ROUND="$2"; shift 2 ;;
    -*)  echo "Unknown option: $1" >&2; exit 1 ;;
    *)
      if [ -z "$ROUNDS" ]; then
        ROUNDS="$1"
      elif [ -z "$STUDY_SUFFIX" ]; then
        STUDY_SUFFIX="$1"
      else
        echo "Unexpected argument: $1" >&2; exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "$ROUNDS" ] || [ -z "$STUDY_SUFFIX" ]; then
  echo "Usage: $0 <rounds> <study_suffix> [--start-round N]" >&2
  exit 1
fi

mkdir -p "$DATA_DIR"

echo "==========================================="
echo "Scale-Up Study: ${STUDY_NAME}"
echo "Suffix: ${STUDY_SUFFIX}"
echo "Rounds: ${START_ROUND}–${ROUNDS}"
echo "Namespace: ${MACHINE_NS}"
echo "Test MachineSets (${#TEST_MACHINESETS[@]}):"
for MS in "${TEST_MACHINESETS[@]}"; do
  echo "  - ${MS}"
done
echo "Data dir: ${DATA_DIR}"
echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "==========================================="
echo ""

STUDY_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)

for ROUND in $(seq "$START_ROUND" "$ROUNDS"); do
  "${SCRIPT_DIR}/run-round.sh" "$ROUND" "$STUDY_SUFFIX"

  # Cooldown between rounds (skip after last)
  if [ "$ROUND" -lt "$ROUNDS" ]; then
    echo "Cooldown ${COOLDOWN}s..."
    sleep "$COOLDOWN"
  fi
done

STUDY_END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo ""
echo "==========================================="
echo "Study complete: ${STUDY_START} -> ${STUDY_END}"
echo "Data in: ${DATA_DIR}"
echo "==========================================="
