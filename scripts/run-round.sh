#!/bin/bash
# Run one round of a scale-up study.
# Discovers test MachineSets, scales them up, waits for Ready,
# collects all artifacts, then scales back down.
#
# Usage: STUDY_NAME=<name> KUBECONFIG=<path> scripts/run-round.sh <round> <study_suffix>
#   e.g.: STUDY_NAME=cni-baseline KUBECONFIG=kubeconfigs/aws-5.0 scripts/run-round.sh 2 5.0-m6a-baseline

set -euo pipefail
source "$(dirname "$0")/config.env"
check_kubeconfig
detect_machine_namespace
discover_test_machinesets

ROUND="${1:?Usage: $0 <round> <study_suffix>}"
STUDY_SUFFIX="${2:?Usage: $0 <round> <study_suffix>}"
SCRIPT_DIR="$(dirname "$0")"

mkdir -p "$DATA_DIR"

echo "=========================================="
echo "Round ${ROUND} | ${STUDY_SUFFIX}"
echo "Study: ${STUDY_NAME} | Namespace: ${MACHINE_NS}"
echo "MachineSets: ${TEST_MACHINESETS[*]}"
echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "=========================================="

# Safety check: verify all test MachineSets are at 0 replicas
for MS in "${TEST_MACHINESETS[@]}"; do
  REPLICAS=$(oc get machineset "$MS" -n "$MACHINE_NS" \
    -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "?")
  if [ "$REPLICAS" != "0" ]; then
    echo "ERROR: ${MS} has replicas=${REPLICAS}, expected 0. Scale down first." >&2
    exit 1
  fi
done

# Scale up all test MachineSets
echo "Scaling up ${#TEST_MACHINESETS[@]} MachineSets..."
SCALE_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
for MS in "${TEST_MACHINESETS[@]}"; do
  oc scale machineset "$MS" -n "$MACHINE_NS" --replicas=1
done
echo "Scale commands issued at $(date -u +%H:%M:%S) UTC"

# Wait for each to be Ready
declare -A NODES MACHINES
FAILED_ZONES=()

for MS in "${TEST_MACHINESETS[@]}"; do
  ZONE_ID=$(ms_to_zone_id "$MS")
  echo "Waiting for ${MS} (zone ${ZONE_ID})..."

  NODE=$("${SCRIPT_DIR}/wait-for-ready.sh" "$MS" 2>&1 | tee /dev/stderr | tail -1) || true

  if [ -n "$NODE" ] && [[ "$NODE" != TIMEOUT* ]] && [[ "$NODE" != FAILED* ]]; then
    NODES[$ZONE_ID]="$NODE"
    MACHINES[$ZONE_ID]=$(oc get machines -n "$MACHINE_NS" \
      -l "machine.openshift.io/cluster-api-machineset=${MS}" \
      -o jsonpath='{.items[0].metadata.name}')
  else
    echo "  WARN: ${MS} (zone ${ZONE_ID}) failed to reach Ready" >&2
    FAILED_ZONES+=("$ZONE_ID")
  fi
done

READY_COUNT=${#NODES[@]}
TOTAL_COUNT=${#TEST_MACHINESETS[@]}
echo "Nodes Ready: ${READY_COUNT}/${TOTAL_COUNT}"

if [ "$READY_COUNT" -eq 0 ]; then
  echo "ERROR: No nodes reached Ready. Scaling down and exiting." >&2
  for MS in "${TEST_MACHINESETS[@]}"; do
    oc scale machineset "$MS" -n "$MACHINE_NS" --replicas=0 2>/dev/null || true
  done
  exit 1
fi

# Collect artifacts from all ready nodes
echo "Collecting artifacts..."
for ZONE_ID in $(echo "${!NODES[@]}" | tr ' ' '\n' | sort); do
  SUFFIX="${STUDY_SUFFIX}-r${ROUND}-${ZONE_ID}"
  echo "--- Zone ${ZONE_ID}: ${NODES[$ZONE_ID]} (suffix: ${SUFFIX}) ---"
  "${SCRIPT_DIR}/collect-artifacts.sh" "${NODES[$ZONE_ID]}" "${MACHINES[$ZONE_ID]}" "$SUFFIX"
done

# CSR list (once per round, using first zone's suffix)
FIRST_ZONE=$(echo "${!NODES[@]}" | tr ' ' '\n' | sort | head -1)
oc get csr > "${DATA_DIR}/csr-list-${STUDY_SUFFIX}-r${ROUND}.txt" 2>/dev/null || true

# Scale down all test MachineSets
echo "Scaling down..."
for MS in "${TEST_MACHINESETS[@]}"; do
  oc scale machineset "$MS" -n "$MACHINE_NS" --replicas=0
done
echo "Scale-down commanded at $(date -u +%H:%M:%S) UTC"

# Wait for machine cleanup
echo "Waiting for machine cleanup..."
for i in $(seq 1 60); do
  if ! oc get machines -n "$MACHINE_NS" --no-headers 2>/dev/null \
    | grep -q "$MACHINESET_PATTERN"; then
    echo "Machines deleted."
    break
  fi
  sleep 10
done

echo ""
echo "Round ${ROUND} complete at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "  Ready: ${READY_COUNT}/${TOTAL_COUNT}"
if [ ${#FAILED_ZONES[@]} -gt 0 ]; then
  echo "  Failed zones: ${FAILED_ZONES[*]}"
fi
echo "Artifacts in: ${DATA_DIR}"
