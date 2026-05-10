#!/bin/bash
# Run one round of the boot image age study: create 3 MachineSets (one per zone),
# wait for all to become Ready, collect artifacts, run extraction, delete MachineSets.
#
# Usage: scripts/run-round.sh <boot_version> <round>
#   e.g.: scripts/run-round.sh 4.14.38 3

set -euo pipefail
source "$(dirname "$0")/config.env"
check_kubeconfig

BOOT_VERSION="${1:?Usage: $0 <boot_version> <round>}"
ROUND="${2:?Usage: $0 <boot_version> <round>}"
SCRIPT_DIR="$(dirname "$0")"

echo "=========================================="
echo "ROUND ${ROUND} | Boot image: ${BOOT_VERSION}"
echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "=========================================="

# Get cluster prefix for MachineSet naming
BASE_MS=$(oc get machinesets -n openshift-machine-api -o name \
  | sed 's|machineset.machine.openshift.io/||' \
  | grep "worker" | head -1)
CLUSTER_PREFIX=$(echo "$BASE_MS" | sed "s/-worker-.*//")

# Phase 1: Create MachineSets for all 3 zones
echo "Creating MachineSets..."
for ZONE in "${ZONE_LETTERS[@]}"; do
  "${SCRIPT_DIR}/create-machineset.sh" "$BOOT_VERSION" "$ROUND" "$ZONE"
done

CREATE_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "All MachineSets created at ${CREATE_TIME}"

# Phase 2: Wait for all 3 nodes to reach Ready
echo "Waiting for nodes to become Ready..."
declare -A NODES MACHINES
FAILED_ZONES=()

for ZONE in "${ZONE_LETTERS[@]}"; do
  SUFFIX=$(make_suffix "$BOOT_VERSION" "$ROUND" "$ZONE")
  MS_NAME="${CLUSTER_PREFIX}-${SUFFIX}"

  NODE=$("${SCRIPT_DIR}/wait-for-ready.sh" "$MS_NAME" 2>&1 | tee /dev/stderr | tail -1) || true

  if [ -n "$NODE" ] && [[ "$NODE" != TIMEOUT* ]] && [[ "$NODE" != FAILED* ]]; then
    NODES[$ZONE]="$NODE"
    MACHINES[$ZONE]=$(oc get machines -n openshift-machine-api \
      -l "machine.openshift.io/cluster-api-machineset=${MS_NAME}" \
      -o jsonpath='{.items[0].metadata.name}')
  else
    echo "  WARN: Zone ${ZONE} failed to reach Ready" >&2
    FAILED_ZONES+=("$ZONE")
  fi
done

READY_COUNT=$(( ${#ZONE_LETTERS[@]} - ${#FAILED_ZONES[@]} ))
echo "Nodes Ready: ${READY_COUNT}/${#ZONE_LETTERS[@]}"

# Phase 3: Collect artifacts from all ready nodes
echo "Collecting artifacts..."
for ZONE in "${ZONE_LETTERS[@]}"; do
  if [[ -v "NODES[$ZONE]" ]]; then
    SUFFIX=$(make_suffix "$BOOT_VERSION" "$ROUND" "$ZONE")
    echo "  Zone ${ZONE}: ${NODES[$ZONE]}"
    "${SCRIPT_DIR}/collect-artifacts.sh" "${NODES[$ZONE]}" "${MACHINES[$ZONE]}" "$SUFFIX"
  fi
done

# CSR list (per-round, shared across zones)
oc get csr > "${DATA_DIR}/csr-list-${BOOT_VERSION}-m6i-r${ROUND}.txt" 2>/dev/null || true

# Phase 4: Run extraction scripts
echo "Extracting data..."
for ZONE in "${ZONE_LETTERS[@]}"; do
  if [[ -v "NODES[$ZONE]" ]]; then
    SUFFIX=$(make_suffix "$BOOT_VERSION" "$ROUND" "$ZONE")
    "${SCRIPT_DIR}/extract-timings.sh" "$SUFFIX"
    "${SCRIPT_DIR}/extract-rebase-info.sh" "$SUFFIX"
    "${SCRIPT_DIR}/extract-nodeready-images.sh" "$SUFFIX"
  fi
done

# Phase 5: Delete MachineSets
echo "Deleting MachineSets..."
for ZONE in "${ZONE_LETTERS[@]}"; do
  SUFFIX=$(make_suffix "$BOOT_VERSION" "$ROUND" "$ZONE")
  MS_NAME="${CLUSTER_PREFIX}-${SUFFIX}"
  oc delete machineset "$MS_NAME" -n openshift-machine-api --wait=false 2>/dev/null &
done
wait

# Wait for machines to be fully deleted before returning
echo "Waiting for machine cleanup..."
for i in $(seq 1 30); do
  REMAINING=$(oc get machines -n openshift-machine-api -o name 2>/dev/null \
    | grep -c "${BOOT_VERSION}.*r${ROUND}" || true)
  if [ "${REMAINING:-0}" -eq 0 ]; then
    break
  fi
  sleep 10
done

echo "Round ${ROUND} complete at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [ ${#FAILED_ZONES[@]} -gt 0 ]; then
  echo "  Failed zones: ${FAILED_ZONES[*]}"
fi
echo ""
