#!/bin/bash
# Create a MachineSet with a specific boot image AMI override.
#
# Usage: scripts/create-machineset.sh <boot_version> <round> <zone_letter>
#   e.g.: scripts/create-machineset.sh 4.14.38 3 b
#
# Creates a MachineSet cloned from the existing worker MachineSet for the
# target zone, overrides the AMI ID to use the specified boot image version,
# saves the JSON, and applies it to the cluster.

set -euo pipefail
source "$(dirname "$0")/config.env"
check_kubeconfig

BOOT_VERSION="${1:?Usage: $0 <boot_version> <round> <zone_letter>}"
ROUND="${2:?Usage: $0 <boot_version> <round> <zone_letter>}"
ZONE="${3:?Usage: $0 <boot_version> <round> <zone_letter>}"

SUFFIX=$(make_suffix "$BOOT_VERSION" "$ROUND" "$ZONE")
AMI_ID=$(get_ami "$BOOT_VERSION")

if [ -z "$AMI_ID" ]; then
  echo "ERROR: No AMI found for ${BOOT_VERSION}. Run lookup-ami.sh first." >&2
  exit 1
fi

# Find the base worker MachineSet for this zone
BASE_MS=$(oc get machinesets -n openshift-machine-api -o name \
  | sed 's|machineset.machine.openshift.io/||' \
  | grep "worker.*${REGION}${ZONE}" \
  | head -1)

if [ -z "$BASE_MS" ]; then
  echo "ERROR: No worker MachineSet found for zone ${REGION}${ZONE}" >&2
  exit 1
fi

# Derive the cluster prefix (everything before -worker-)
CLUSTER_PREFIX=$(echo "$BASE_MS" | sed "s/-worker-.*//")
MS_NAME="${CLUSTER_PREFIX}-${SUFFIX}"

# Check for naming collision
if oc get machineset "$MS_NAME" -n openshift-machine-api &>/dev/null; then
  echo "ERROR: MachineSet ${MS_NAME} already exists" >&2
  exit 1
fi

mkdir -p "$DATA_DIR"

oc get machineset "$BASE_MS" -n openshift-machine-api -o json | jq "
  del(.metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp,
      .metadata.generation, .status, .metadata.annotations) |
  .metadata.name = \"${MS_NAME}\" |
  .spec.selector.matchLabels[\"machine.openshift.io/cluster-api-machineset\"] = \"${MS_NAME}\" |
  .spec.template.metadata.labels[\"machine.openshift.io/cluster-api-machineset\"] = \"${MS_NAME}\" |
  .spec.replicas = 1 |
  .spec.template.spec.providerSpec.value.ami.id = \"${AMI_ID}\" |
  .spec.template.spec.providerSpec.value.instanceType = \"${INSTANCE_TYPE}\"
" > "${DATA_DIR}/machineset-${SUFFIX}.json"

oc create -f "${DATA_DIR}/machineset-${SUFFIX}.json"
echo "Created MachineSet ${MS_NAME} (AMI: ${AMI_ID}, boot image: ${BOOT_VERSION})"
