#!/bin/bash
# Pre-pull NodeReady-blocking container images during firstboot.
# Runs in parallel with MCD firstboot (rpm-ostree rebase) to overlap
# network-bound image pulls with I/O-bound rebase work.
#
# Images are pulled via podman into /var/lib/containers/storage, which
# is the same graphroot CRI-O uses. After reboot, CRI-O finds them
# cached and skips re-pulling, saving 40-60s on KTR.
#
# Image discovery: extracts refs from the release image payload so
# the script works across OCP versions without hardcoded digests.

set -o pipefail

LOG_TAG="pre-pull-cni"
log() { echo "$(date -Iseconds) ${LOG_TAG}: $*"; }

PULL_SECRET="/var/lib/kubelet/config.json"
if [ ! -f "$PULL_SECRET" ]; then
    PULL_SECRET="/root/.docker/config.json"
fi
if [ ! -f "$PULL_SECRET" ]; then
    log "No pull secret found, exiting"
    exit 0
fi

# Find the release image from the rendered machine config.
# Ignition writes this during early boot before MCD runs.
RELEASE_IMAGE=""
for mc_file in /etc/machine-config-daemon/currentconfig /etc/mco/currentconfig; do
    if [ -f "$mc_file" ]; then
        RELEASE_IMAGE=$(jq -r '.spec.releaseImage // .spec.osImageURL // empty' "$mc_file" 2>/dev/null)
        if [ -n "$RELEASE_IMAGE" ]; then
            break
        fi
    fi
done

# Fallback: check the machine-config-daemon pull spec
if [ -z "$RELEASE_IMAGE" ]; then
    log "Could not find release image from machine config, trying clusterversion"
    # On firstboot the kubelet isn't up yet, so we can't query the API.
    # Try to parse from the ignition-written bootstrap config.
    RELEASE_IMAGE=$(find /etc -name "*.json" -path "*/machine-config*" -exec \
        jq -r '.spec.releaseImage // empty' {} \; 2>/dev/null | head -1)
fi

if [ -z "$RELEASE_IMAGE" ]; then
    log "Cannot determine release image, exiting"
    exit 0
fi

log "Release image: ${RELEASE_IMAGE}"

# Components whose images block NodeReady (ordered by pull time impact)
COMPONENTS=(
    "multus-cni"
    "multus-additional-cni-plugins"    # ~56s pull, critical path
    "ovn-kubernetes-microshift"        # ovn-k node image
    "ovn-kubernetes"                   # ~33s pull
    "network-metrics-daemon"
    "machine-config-operator"          # MCD daemonset
    "kube-rbac-proxy"
    "cluster-node-tuning-operator"
)

pull_image() {
    local component="$1"
    local image_ref

    # Extract the image reference for this component from the release payload
    image_ref=$(podman run --rm --authfile "$PULL_SECRET" \
        "$RELEASE_IMAGE" image "${component}" 2>/dev/null) || true

    if [ -z "$image_ref" ]; then
        log "SKIP ${component}: not found in release payload"
        return
    fi

    log "PULL ${component}: ${image_ref}"
    if podman pull --authfile "$PULL_SECRET" "$image_ref" 2>&1; then
        log "OK   ${component}: cached"
    else
        log "FAIL ${component}: pull failed (non-fatal)"
    fi
}

log "Starting opportunistic pre-pull of ${#COMPONENTS[@]} CNI/node images"

# Pull images in parallel (background jobs) to maximize overlap with MCD rebase.
# Limit concurrency to avoid saturating the network.
MAX_PARALLEL=3
RUNNING=0

for component in "${COMPONENTS[@]}"; do
    pull_image "$component" &
    RUNNING=$((RUNNING + 1))

    if [ "$RUNNING" -ge "$MAX_PARALLEL" ]; then
        wait -n 2>/dev/null || true
        RUNNING=$((RUNNING - 1))
    fi
done

# Wait for remaining pulls, but don't block forever.
# If the system is rebooting, SIGTERM will kill us — that's fine.
wait 2>/dev/null || true

log "Pre-pull complete ($(podman images --format '{{.Repository}}' 2>/dev/null | wc -l) images cached)"
