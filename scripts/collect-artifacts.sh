#!/bin/bash
# Collect all standard artifacts from a node.
#
# Usage: scripts/collect-artifacts.sh <node_name> <machine_name> <suffix>
#   e.g.: scripts/collect-artifacts.sh ip-10-0-29-15.us-east-2.compute.internal sdodson-xxx-4.14.38-m6i-r3-z2 4.14.38-m6i-r3-z2
#
# Requires: STUDY_NAME, KUBECONFIG set in environment.
# Uses MACHINE_NS from environment or auto-detects.

set -euo pipefail
source "$(dirname "$0")/config.env"
check_kubeconfig
detect_machine_namespace

NODE="${1:?Usage: $0 <node_name> <machine_name> <suffix>}"
MACHINE="${2:?Usage: $0 <node_name> <machine_name> <suffix>}"
SUFFIX="${3:?Usage: $0 <node_name> <machine_name> <suffix>}"

mkdir -p "$DATA_DIR"
COLLECTED=0
FAILED=0

collect() {
  local desc="$1" outfile="$2"
  shift 2
  echo "  Collecting ${desc}..."
  if "$@" > "$outfile" 2>/dev/null; then
    COLLECTED=$((COLLECTED + 1))
  else
    echo "    WARN: Failed to collect ${desc}" >&2
    FAILED=$((FAILED + 1))
  fi
}

# Journal (all boots) — largest artifact, collect first
collect "journal" \
  "${DATA_DIR}/node-journal-${SUFFIX}.log" \
  oc debug "node/${NODE}" -- chroot /host journalctl --no-pager

# Boot list
collect "boot list" \
  "${DATA_DIR}/node-boot-list-${SUFFIX}.txt" \
  oc debug "node/${NODE}" -- chroot /host journalctl --list-boots

# systemd-analyze (3 variants)
collect "systemd-analyze" \
  "${DATA_DIR}/node-systemd-analyze-${SUFFIX}.txt" \
  oc debug "node/${NODE}" -- chroot /host systemd-analyze

collect "systemd-analyze blame" \
  "${DATA_DIR}/node-systemd-blame-${SUFFIX}.txt" \
  oc debug "node/${NODE}" -- chroot /host systemd-analyze blame

collect "systemd-analyze critical-chain" \
  "${DATA_DIR}/node-systemd-critical-chain-${SUFFIX}.txt" \
  oc debug "node/${NODE}" -- chroot /host systemd-analyze critical-chain

# Machine and Node YAML
collect "Machine YAML" \
  "${DATA_DIR}/new-machine-${SUFFIX}-final.yaml" \
  oc get machine "$MACHINE" -n "$MACHINE_NS" -o yaml

collect "Node YAML" \
  "${DATA_DIR}/new-node-${SUFFIX}.yaml" \
  oc get node "$NODE" -o yaml

# CAPI: also collect AWSMachine object
if [ "$MACHINE_NS" = "openshift-cluster-api" ]; then
  collect "AWSMachine YAML" \
    "${DATA_DIR}/new-awsmachine-${SUFFIX}.yaml" \
    oc get awsmachine "$MACHINE" -n "$MACHINE_NS" -o yaml
fi

# Container images (text format)
collect "crictl images" \
  "${DATA_DIR}/node-images-${SUFFIX}.txt" \
  oc debug "node/${NODE}" -- chroot /host crictl images

# Container images (JSON with sizes)
collect "crictl images JSON" \
  "${DATA_DIR}/node-images-detail-${SUFFIX}.json" \
  oc debug "node/${NODE}" -- chroot /host crictl images -o json

echo "  Done: ${COLLECTED} collected, ${FAILED} failed"
