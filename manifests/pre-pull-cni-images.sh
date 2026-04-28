#!/bin/bash
# Pre-pull NodeReady-blocking container images during firstboot.
# Runs in parallel with MCD firstboot (rpm-ostree rebase) with
# MAX_PARALLEL=1 to reduce network contention with MCD's OS image
# download. Serialized pulls still overlap with MCD's I/O-bound
# rebase work.
#
# Images are pulled via podman into /var/lib/containers/storage, which
# is the same graphroot CRI-O uses. After reboot, CRI-O finds them
# cached and skips re-pulling, saving 40-60s on KTR.
#
# Pullspecs are hardcoded for OCP 4.20.18. In production the MCO would
# populate this list from the release payload at render time.

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

# Ordered by NodeReady-blocking criticality (largest / most critical first).
# Digests from: oc adm release info 4.20.18 --pullspecs
IMAGES=(
    # ovn-kubernetes — ovnkube-node init + 5 containers, network-node-identity (largest)
    "quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:53ecbed423371b09c2867ebbc1ad10dbc259eb69a1dadb0162a491548a503d8a"
    # multus-cni — multus ds + multus-additional-cni-plugins container
    "quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:a42120a83db7cd7de76baf52c2336c60be42486a2025e305ab43e50000f3a671"
    # kube-rbac-proxy — sidecar in ovnkube-node, MCD, network-metrics, dns, node-exporter
    "quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:3366d391aaeff028defbc936ce86754c0d454f9fc89e9e126d1e961bbf66facc"
    # egress-router-cni — multus-additional-cni-plugins init
    "quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:7ae5539fae6028fff4d116d044a0fcb8cf2780d27093fa5e4cd821a59b7dd291"
    # container-networking-plugins — multus-additional-cni-plugins init
    "quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:e7ed1c517895be2df46c23ba8915d245bb3bea849f644d8f3e957a2fa2c4e454"
    # network-interface-bond-cni — multus-additional-cni-plugins init
    "quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:cfb8e5119fd8ee21c3cc8ae827d615ba2ecf8c1d588e5810be309878e4906d8a"
    # multus-route-override-cni — multus-additional-cni-plugins init
    "quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:27ed497875cf17231c74af201f20f9d0fa994e448c5d50416a43bbb03f0b2578"
    # multus-whereabouts-ipam-cni — multus-additional-cni-plugins init
    "quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:03b79ad962ab93a071a74331b6e9f164f48407c683ac2fe0508af19c0dd348cf"
    # network-metrics-daemon
    "quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:cb59e2bf4eefd02d7988c52633584f62c3f145563ffba8dc2bc0294554db1d46"
    # cluster-node-tuning-operator (tuned daemonset)
    "quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:9db35df4013bf4bd89bd2634dcff8450e0d10e52328635a67281e7f9e3042543"
)

log "Starting pre-pull of ${#IMAGES[@]} NodeReady-blocking images (serial)"

pull_image() {
    local image="$1"
    local short="${image##*@sha256:}"
    short="${short:0:12}"

    log "PULL ${short}"
    if podman pull --authfile "$PULL_SECRET" "$image" 2>&1; then
        log "OK   ${short}"
    else
        log "FAIL ${short} (non-fatal)"
    fi
}

for image in "${IMAGES[@]}"; do
    pull_image "$image"
done

log "Pre-pull complete ($(podman images --format '{{.Repository}}' 2>/dev/null | wc -l) images cached)"
