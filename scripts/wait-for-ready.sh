#!/bin/bash
# Wait for a MachineSet's node to reach Ready status.
#
# Usage: scripts/wait-for-ready.sh <machineset_name>
#
# Prints the node name on success (stdout). Progress goes to stderr.
# Exit code 0 on success, 1 on timeout or failure.

set -euo pipefail
source "$(dirname "$0")/config.env"
check_kubeconfig

MS_NAME="${1:?Usage: $0 <machineset_name>}"

START=$(date +%s)

while true; do
  ELAPSED=$(( $(date +%s) - START ))

  # Check for Machine in Failed phase (early exit)
  PHASE=$(oc get machines -n openshift-machine-api \
    -l "machine.openshift.io/cluster-api-machineset=${MS_NAME}" \
    -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)

  if [ "$PHASE" = "Failed" ]; then
    ERROR_MSG=$(oc get machines -n openshift-machine-api \
      -l "machine.openshift.io/cluster-api-machineset=${MS_NAME}" \
      -o jsonpath='{.items[0].status.errorMessage}' 2>/dev/null || true)
    echo "FAILED: Machine entered Failed phase after ${ELAPSED}s: ${ERROR_MSG}" >&2
    exit 1
  fi

  # Check for Ready
  READY=$(oc get machineset "$MS_NAME" -n openshift-machine-api \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)

  if [ "$READY" = "1" ]; then
    MACHINE=$(oc get machines -n openshift-machine-api \
      -l "machine.openshift.io/cluster-api-machineset=${MS_NAME}" \
      -o jsonpath='{.items[0].metadata.name}')
    NODE=$(oc get machine "$MACHINE" -n openshift-machine-api \
      -o jsonpath='{.status.nodeRef.name}')
    echo "  Ready after ${ELAPSED}s: ${NODE}" >&2
    echo "$NODE"
    exit 0
  fi

  if [ $ELAPSED -ge $WAIT_TIMEOUT ]; then
    echo "TIMEOUT: ${MS_NAME} not ready after ${ELAPSED}s (phase: ${PHASE:-unknown})" >&2
    exit 1
  fi

  echo "  ${ELAPSED}s - phase: ${PHASE:-pending}, waiting..." >&2
  sleep "$POLL_INTERVAL"
done
