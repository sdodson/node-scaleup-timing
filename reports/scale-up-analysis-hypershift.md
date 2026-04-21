# Node Scale-Up Analysis: HyperShift / ROSA HCP (AWS, OCP 4.21)

## Cluster Setup
- **Cluster**: ROSA HCP (HyperShift) — `karpenter2`
- **OCP Version**: 4.21 (Kubernetes 1.34.2, CRI-O 1.34.3)
- **OS**: RHCOS 9.6.20260112-0 (Plow), kernel 5.14.0-570.78.1.el9_6
- **Region**: us-east-1, Zone us-east-1c
- **Control Plane**: Hosted (HyperShift) — no local API servers on worker nodes
- **Node Provisioning**: CAPI MachineSet (`karpenter2-workers-d44lt`) for m5.xlarge nodes; Karpenter NodePool (`ondemand-and-spot`) for t3.large node
- **Date**: 2026-02-12 (m5-1, m5-2), 2026-04-01 (t3), 2026-04-21 (m5-3, m5-4)

## Key Differences from Standalone OCP

1. **No Machine API** — HyperShift uses Cluster API (CAPI) MachineSet, not `openshift-machine-api`. VM creation timestamps come from CAPI Machine objects, not the Machine API.
2. **Hosted control plane** — kubelet connects to `api.karpenter2.hypershift.local` via `kube-apiserver-proxy` running on the node, rather than a local API server.
3. **No MCD firstboot** — Boot 1 runs Ignition and rpm-ostree rebase, but the MCD image pull and firstboot service are structured differently in HyperShift.
4. **Mixed provisioning** — This cluster has both CAPI MachineSet workers (m5.xlarge) and Karpenter-provisioned workers (t3.large).

## Results Summary

| Node | Instance Type | Provisioner | Date | Total | Boot 1 | Reboot | Boot2→Ready | KTR | systemd-analyze | chrony-wait |
|------|--------------|-------------|------|-------|--------|--------|-------------|-----|-----------------|-------------|
| m5-1 | m5.xlarge | CAPI MS | Feb 12 | **251s (4m 11sec)** | 176s | 11s | 64s | 45s | 19.2s | 9.1s |
| m5-2 | m5.xlarge | CAPI MS | Feb 12 | **296s (4m 56sec)** | 213s | 13s | 70s | 44s | 27.8s | 15.1s |
| m5-3 | m5.xlarge | CAPI MS | Apr 21 | **274s (4m 34sec)** | 179s | 12s | 83s | 55s | 30.0s | 18.3s |
| m5-4 | m5.xlarge | CAPI MS | Apr 21 | **274s (4m 34sec)** | 179s | 22s | 73s | 46s | 29.3s | 16.1s |
| t3 | t3.large | Karpenter | Apr 1 | **335s (5m 35sec)** | 215s | 22s | 98s | 74s | 26.2s | 7.1s |

## m5.xlarge Statistics (n=4)

| Metric | Mean | Stdev | Min | Max |
|--------|------|-------|-----|-----|
| **Total** | **274s (4m 34sec)** | 18.4s | 251s | 296s |
| Boot 1 | 187s | 18.2s | 176s | 213s |
| Reboot | 15s | 5.2s | 11s | 22s |
| Boot2→Ready | 73s | 8.0s | 64s | 83s |
| Kubelet to Ready | 48s | 5.1s | 44s | 55s |
| systemd-analyze | 26.6s | 4.8s | 19.2s | 30.0s |
| chrony-wait | 14.6s | 3.9s | 9.1s | 18.3s |

## t3.large vs m5.xlarge

| Metric | m5.xlarge (mean, n=4) | t3.large (n=1) | Delta |
|--------|----------------------|----------------|-------|
| **Total** | **274s** | **335s** | **+61s (22% slower)** |
| Boot 1 | 187s | 215s | +28s |
| Reboot | 15s | 22s | +7s |
| Boot2→Ready | 73s | 98s | +25s |
| Kubelet to Ready | 48s | 74s | +26s |
| chrony-wait | 14.6s | 7.1s | -7.5s |

The t3.large is 22% slower overall. Boot 1 takes 28s longer (burstable CPU throttling during rpm-ostree rebase). Kubelet-to-Ready takes 26s longer — the 2 vCPU / lower network bandwidth (512 Mbps vs 1.25 Gbps) significantly slows CNI image pulls. chrony-wait is actually faster on t3 (7s vs 15s avg), likely due to lower initial clock drift.

## Phase Breakdown: m5.xlarge Mean

| Phase | Duration | % of Total |
|-------|----------|------------|
| Boot 1 (Ignition + rpm-ostree rebase) | 187s | 68.2% |
| Reboot | 15s | 5.3% |
| Boot 2: chrony-wait | 14.6s | 5.3% |
| Boot 2: Other systemd (to kubelet start) | 12s | 4.4% |
| Boot 2: Kubelet to NodeReady | 48s | 17.3% |
| **Total** | **274s** | **100%** |

## Comparison with Standalone OCP

| Metric | HyperShift m5.xlarge (n=4) | Standalone 4.22 D4s_v5 Azure (n=12) | Standalone 4.21 m8a AWS (n=1) |
|--------|---------------------------|-------------------------------------|-------------------------------|
| **Total** | **274s (4m 34sec)** | **247s (4m 07sec)** | **212s (3m 32sec)** |
| VM Provisioning* | N/A | 21s | ~30s |
| Boot 1 | 187s | 128s | ~130s |
| Reboot | 15s | 5s | ~5s |
| chrony-wait | 14.6s | 24.1s | 13s |
| Kubelet to Ready | 48s | 61s | 35s |
| systemd-analyze (Boot 2) | 26.6s | 33.1s | ~30s |

\* VM provisioning is not separately measurable in HyperShift — no Machine object creation timestamp before boot. Boot 1 starts when the VM first boots, so cloud provisioning time is not captured.

### Notable differences

1. **Boot 1 is longer in HyperShift** — 187s vs 128s (standalone 4.22 Azure). This may reflect the m5.xlarge's older CPU/storage generation vs D4s_v5, or differences in the HyperShift Ignition config size.

2. **chrony-wait is shorter** — 14.6s (AWS NTP) vs 24.1s (Azure PHC refclock). AWS Time Sync Service (`169.254.169.123`) syncs faster than Azure's `ptp_hyperv` with its fixed 3-poll-interval cadence. But chrony-wait on AWS shows more variance (7-18s) than Azure (24.07s ± 0.005s).

3. **Boot 2 systemd is faster** — 26.6s vs 33.1s. HyperShift workers have fewer systemd services to start (no local etcd, API server, or controller-manager).

4. **Kubelet-to-Ready is faster** — 48s vs 61s (Azure 4.22). Despite being on an older instance type, HyperShift KTR is quicker. This could reflect differences in CNI image sizes or CSR approval path through the hosted control plane.

5. **Reboot is slower** — 15s vs 5s. The m5.xlarge (Nitro) has a longer POST/boot cycle than the D4s_v5 (Hyper-V). The t3.large reboot is even slower at 22s.

## chrony-wait on AWS: Variable

| Node | chrony-wait |
|------|-------------|
| m5-1 | 9.1s |
| m5-2 | 15.1s |
| m5-3 | 18.3s |
| m5-4 | 16.1s |
| t3 | 7.1s |

AWS chrony-wait ranges 7-18s across all 5 samples (vs fixed 24.07s on Azure). The variance depends on initial clock drift magnitude at boot, which varies per VM instance. Unlike Azure's deterministic PHC polling, AWS NTP sync time is opportunistic.

## Observations

1. **m5-3 and m5-4 were provisioned simultaneously** (boot1 start 3s apart) and produced identical total times (274s). Boot 1 duration is also identical (179s). This suggests that when VMs boot at the same time from the same AMI, the rpm-ostree rebase phase is very consistent — variance comes from other factors (chrony, image pull contention).

2. **m5-1 was the fastest** at 251s, with the shortest Boot 1 (176s) and chrony-wait (9.1s). m5-2 was slowest at 296s despite booting at the same time as m5-1 on Feb 12 — its Boot 1 was 37s longer (213s vs 176s), suggesting I/O contention or different placement.

3. **Karpenter vs CAPI provisioning** doesn't affect boot timing — the VM and OS bootstrap are identical regardless of which controller created the Machine/NodeClaim. The t3.large is slower due to hardware (burstable CPU, lower bandwidth), not the provisioning path.

4. **No VM provisioning measurement** — Unlike standalone OCP where Machine object `creationTimestamp` marks when the cloud API call was made, HyperShift's CAPI Machine objects are created differently. The first journal entry (Boot 1 start) is the earliest timing we can capture.

## Saved Artifacts

Per node:
- `new-node-hypershift-{m5-1,m5-2,m5-3,m5-4,t3}.yaml`
- `node-journal-hypershift-{m5-1,m5-2,m5-3,m5-4,t3}.log`
- `node-boot-list-hypershift-{m5-1,m5-2,m5-3,m5-4,t3}.txt`
- `node-systemd-analyze-hypershift-{m5-1,m5-2,m5-3,m5-4,t3}.txt`
- `node-systemd-blame-hypershift-{m5-1,m5-2,m5-3,m5-4,t3}.txt`
- `node-systemd-critical-chain-hypershift-{m5-1,m5-2,m5-3,m5-4,t3}.txt`
- `node-images-hypershift-{m5-1,m5-2,m5-3,m5-4,t3}.txt`

Cluster-level:
- `nodeclaims-hypershift.yaml`
- `nodepools-hypershift.yaml`
- `csr-list-hypershift.txt`
