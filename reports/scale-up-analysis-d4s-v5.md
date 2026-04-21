# Node Scale-Up Time Analysis: Standard_D4s_v5 (Azure)

## Cluster
- **Cluster**: ci-ln-rm0x8pk-1d09d (OpenShift 4.22, Kubernetes 1.35.3)
- **Region**: eastus2, Zone 1
- **VM Type**: Standard_D4s_v5 (4 vCPU, 16 GB RAM)
- **Machine**: ci-ln-rm0x8pk-1d09d-vkpbd-worker-eastus21-v5-75rk2
- **MachineSet**: ci-ln-rm0x8pk-1d09d-vkpbd-worker-eastus21-v5

## Total Scale-Up Time: ~4 minutes 43 seconds
- MachineSet created: **19:45:12 UTC**
- Node Ready: **19:49:48 UTC** (NodeReady event in journal)
- Polling confirmed Ready: **19:49:55 UTC**

## Phase Breakdown

| Phase | Start | End | Duration | Notes |
|-------|-------|-----|----------|-------|
| **MachineSet create -> Machine created** | 19:45:12 | 19:45:12 | ~0s | Immediate |
| **Azure VM Provisioning** | 19:45:12 | 19:45:31 | ~19s | VM creating in Azure |
| **Boot 1: Kernel -> Ignition (all stages)** | 19:45:31 | 19:45:49 | ~18s | All Ignition stages |
| **Boot 1: Pivot to real root** | 19:45:49 | 19:45:54 | ~5s | sysroot transition |
| **Boot 1: MCD pull + rpm-ostree rebase** | 19:45:54 | 19:48:07 | ~2m 13sec | MCD image pull, rpm-ostree rebase, **LARGEST PHASE** |
| **Boot 1: Reboot** | 19:48:07 | 19:48:18 | ~11s | Shutdown + BIOS/bootloader |
| **Boot 2: Kernel + initrd** | 19:48:18 | 19:48:27 | ~9s | Second boot |
| **Boot 2: chrony-wait** | 19:48:27 | 19:48:51 | ~24s | NTP time sync |
| **Boot 2: OVS configuration** | 19:48:27 | 19:48:32 | ~5s | OVS setup (parallel with chrony) |
| **Boot 2: CRI-O + Kubelet start** | 19:48:51 | 19:48:52 | ~1s | Container runtime + kubelet |
| **Boot 2: Kubelet -> NodeReady** | 19:48:52 | 19:49:48 | ~56s | CSR, CNI, node registration |

## Time Spent Summary

| Category | Duration | % of Total |
|----------|----------|------------|
| Azure VM Provisioning | ~19s | 7% |
| Boot 1: Ignition + OS Setup | ~23s | 8% |
| Boot 1: MCD Firstboot (rpm-ostree) | **~2m 13sec** | **47%** |
| Reboot (shutdown + POST) | ~11s | 4% |
| Boot 2: Kernel/initrd | ~9s | 3% |
| Boot 2: chrony-wait (NTP sync) | ~24s | 8% |
| Boot 2: OVS configuration | ~5s | 2% |
| Boot 2: CRI-O + Kubelet start | ~1s | <1% |
| Boot 2: Kubelet to NodeReady | **~56s** | **20%** |

## rpm-ostree Rebase Details
- MCD pulled image: `quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:fd6fd30...` (~8s pull, 19:45:56 -> 19:46:04)
- rpm-ostree rebase started: 19:46:31 (to `sha256:e7f6b06...`)
- Staging deployment done: 19:47:60 (~89s for ostree rebase)
- Additional staging + SELinux policy refresh: ~6s
- Reboot initiated: 19:48:07

## Boot List
```
IDX  BOOT ID                           FIRST ENTRY                  LAST ENTRY
 -1  c5af595d0a9f462dbc1cb4a28a4e9af9   2026-04-17 19:45:31 UTC      2026-04-17 19:48:14 UTC
  0  b374b71b10a24010a4c4d03113e996c0   2026-04-17 19:48:18 UTC      2026-04-17 19:50:29 UTC
```

## systemd-analyze (Boot 2)
```
Startup finished in 905ms (kernel) + 2.995s (initrd) + 27.836s (userspace) = 31.737s
graphical.target reached after 27.708s in userspace.
```

## systemd-analyze critical-chain (Boot 2)
```
graphical.target @27.708s
└─multi-user.target @27.708s
  └─kubelet.service @27.472s +235ms
    └─crio.service @26.891s +572ms
      └─kubelet-dependencies.target @26.878s
        └─chrony-wait.service @2.807s +24.071s
```

## Container Images Pulled After Boot 2 (Post-NodeReady)
- First image pull: 19:48:53
- Last image pull: 19:50:16
- 31 container images pulled, totaling ~14.7 GB
- Image pull period: ~83 seconds (mostly after NodeReady at 19:49:48)

## Comparison: D4s_v3 vs D4s_v5

| Metric | Standard_D4s_v3 | Standard_D4s_v5 | Delta |
|--------|----------------|----------------|-------|
| **Total time** | **7m 3sec** | **4m 43sec** | **-2m 20sec (33% faster)** |
| Azure VM Provisioning | 32s | 19s | -13s |
| Boot 1 (Ignition + pivot) | 29s | 23s | -6s |
| MCD firstboot (rpm-ostree) | 2m 44sec | 2m 13sec | -31s |
| Reboot | 26s | 11s | -15s |
| Boot 2 kernel/initrd | 12s | 9s | -3s |
| chrony-wait | 24s | 24s | 0s |
| OVS configuration | 14s | 5s | -9s |
| CRI-O + Kubelet start | 1s | 1s | 0s |
| Kubelet to NodeReady | 2m 14sec | 56s | -1m 18sec |
| **systemd-analyze total** | **40.9s** | **31.7s** | **-9.2s** |

### Key Differences
1. **Kubelet to NodeReady is dramatically faster on v5** (56s vs 2m 14sec). This is likely due to
   faster I/O and CPU on the v5 generation improving CSR processing and CNI configuration.
2. **VM provisioning is faster** (19s vs 32s) — v5 instances launch quicker in Azure.
3. **MCD firstboot is ~30s faster** — the rpm-ostree rebase benefits from better I/O.
4. **Reboot is faster** (11s vs 26s) — faster POST and bootloader.
5. **OVS configuration is faster** (5s vs 14s) — faster CPU for OVS bridge setup.
6. **chrony-wait is identical** (~24s) — this is network/NTP latency, not hardware-bound.

## Saved Artifacts
- `node-journal-d4s-v5.log` — Full journal (all boots, 10,206 lines)
- `node-boot-list-d4s-v5.txt` — Boot list
- `node-systemd-analyze-d4s-v5.txt` — systemd-analyze output
- `node-systemd-blame-d4s-v5.txt` — systemd-analyze blame
- `node-systemd-critical-chain-d4s-v5.txt` — systemd critical chain
- `node-images-d4s-v5.txt` — Container images on node
- `node-images-detail-d4s-v5.json` — Detailed image info with digests
- `node-image-pulls-d4s-v5.txt` — Image pull log entries
- `node-rpm-ostree-status-v5.txt` — rpm-ostree status
- `node-rpm-ostree-status-v5.json` — rpm-ostree status (JSON)
- `new-machine-v5-final.yaml` — Machine object
- `new-node-v5.yaml` — Node object
- `csr-list-d4s-v5.txt` — CSR list
- `machineset-v5.json` — MachineSet definition used

## Pre-Pull Analysis

### Images Pulled to Node (31 images, ~14.7 GB total)
These are pulled by kubelet after the node becomes Ready and pods are scheduled:

| Image | Size | Source |
|-------|------|--------|
| quay.io/openshift-release-dev/ocp-v4.0-art-dev (28 images) | ~14.2 GB | OCP release payload |
| quay.io/openshift-logging/promtail:v2.9.8 | 478 MB | Logging stack |
| quay.io/observatorium/token-refresher:latest | 10.5 MB | Observability |
| registry.redhat.io/openshift4/ose-oauth-proxy-rhel9:latest | 305 MB | OAuth proxy |

### rpm-ostree Content (Pulled During Boot 1 MCD Phase)
The MCD pulls one container image during firstboot to rebase the OS:
- **MCD image**: `ocp-v4.0-art-dev@sha256:fd6fd30...` (machine-config-operator) — ~8s pull
- **OS rebase image**: `ocp-v4.0-art-dev@sha256:e7f6b06...` — pulled by rpm-ostree during rebase (~89s)

### Pre-Pull Opportunities

### Boot 1: MCD Phase Images (Blocks NodeReady)
These are pulled during the MCD firstboot provisioning phase and directly add to scale-up time:

| Component | Digest (short) | Size | Duration | Notes |
|-----------|---------------|------|----------|-------|
| machine-config-operator | sha256:fd6fd3... | 955 MB | ~8s | MCD container itself |
| machine-os (rhel-coreos) | sha256:e7f6b0... | N/A (rpm-ostree) | ~89s | rpm-ostree rebase target |

**Pre-pull opportunity**: If the machine-os container image could be pre-cached in the RHCOS
base image (e.g., baked into an Azure Shared Image Gallery image), the MCD firstboot phase
would drop by ~89s. This is release-specific and changes with every build. The MCD image
itself (~8s) is less impactful.

### Boot 2: DaemonSet Images (Pulled After Kubelet Starts)
These are pulled after CRI-O/kubelet start. Some are needed before NodeReady (CNI plugins),
while others are pulled after. Total: ~14.7 GB across 31 images, ~83s.

| # | Component | Digest (short) | Size | Critical Path? |
|---|-----------|---------------|------|----------------|
| 1 | **multus-cni** | sha256:047bc6... | 1,453 MB | Yes - CNI plugin, blocks NodeReady |
| 2 | **ovn-kubernetes** | sha256:965564... | 1,424 MB | Yes - CNI, blocks NodeReady |
| 3 | rhel-coreos-extensions | sha256:abab92... | 960 MB | No |
| 4 | machine-config-operator | sha256:fd6fd3... | 955 MB | No (already cached from boot 1) |
| 5 | tools | sha256:4f6b34... | 737 MB | No |
| 6 | multus-whereabouts-ipam-cni | sha256:808495... | 636 MB | Yes - CNI init container |
| 7 | cluster-node-tuning-operator | sha256:99d587... | 633 MB | No |
| 8 | container-networking-plugins | sha256:3cc959... | 600 MB | Yes - CNI init container |
| 9 | cluster-network-operator | sha256:909303... | 509 MB | No |
| 10 | azure-file-csi-driver | sha256:eb3908... | 493 MB | No |
| 11 | cli | sha256:9d581a... | 483 MB | No |
| 12 | cluster-ingress-operator | sha256:125b54... | 473 MB | No |
| 13 | cluster-cloud-controller-manager-operator | sha256:f2fecf... | 472 MB | No |
| 14 | promtail | quay.io/openshift-logging/promtail:v2.9.8 | 456 MB | No (e2e test) |
| 15 | azure-disk-csi-driver | sha256:1fe26d... | 412 MB | No |
| 16 | egress-router-cni | sha256:cb1656... | 409 MB | Yes - CNI init container |
| 17 | docker-registry (node-ca) | sha256:3d4a40... | 405 MB | No |
| 18 | azure-cloud-node-manager | sha256:3fb7c7... | 387 MB | No |
| 19 | coredns | sha256:ba6380... | 385 MB | No |
| 20 | insights-runtime-extractor | sha256:78863b... | 350 MB | No |
| 21 | kube-rbac-proxy | sha256:dee202... | 349 MB | No (used by many pods) |
| 22 | network-metrics-daemon | sha256:c49102... | 319 MB | No |
| 23 | prometheus-node-exporter | sha256:cc84f1... | 318 MB | No |
| 24 | csi-livenessprobe | sha256:69035a... | 305 MB | No |
| 25 | csi-node-driver-registrar | sha256:ffdb03... | 305 MB | No |
| 26 | network-interface-bond-cni | sha256:fa12cc... | 294 MB | Yes - CNI init container |
| 27 | ose-oauth-proxy-rhel9 | registry.redhat.io/...ose-oauth-proxy | 290 MB | No (e2e test) |
| 28 | multus-route-override-cni | sha256:ca1c53... | 290 MB | Yes - CNI init container |
| 29 | insights-runtime-exporter | sha256:6592f4... | 287 MB | No |
| 30 | pod (pause) | sha256:c244a9... | 278 MB | Yes - all pods need this |
| 31 | token-refresher | quay.io/observatorium/token-refresher | 10 MB | No (e2e test) |

### Pre-Pull Recommendations

**High-impact pre-pulls (CNI critical path, blocks NodeReady)**:
1. **multus-cni** (1,453 MB) — largest image, CNI plugin
2. **ovn-kubernetes** (1,424 MB) — OVN CNI
3. **container-networking-plugins** (600 MB) — CNI init container
4. **multus-whereabouts-ipam-cni** (636 MB) — CNI init container
5. **pod (pause)** (278 MB) — needed by all sandbox containers
6. **kube-rbac-proxy** (349 MB) — sidecar used by many daemonsets

Pre-pulling just the top 6 CNI-critical images (~4.7 GB) would eliminate the bulk of
the kubelet-to-NodeReady wait time, which is currently the second-largest phase.

**rpm-ostree content**: The machine-os container (`sha256:e7f6b06...`) is the target for
rpm-ostree rebase during MCD firstboot. It is fetched by rpm-ostree (not CRI-O), so it
would need to be pre-cached in the rpm-ostree image store or the base OS image itself.
This is the single largest optimization opportunity (~89s).

**chrony-wait (~24s)**: Not image-related but on the critical path. Could potentially be
tuned with chrony configuration (makestep, server selection).
