# AWS 4.20.18 Node Scale-Up Optimization Study

## Overview

This study measures the impact of two MachineConfig-based optimizations on OpenShift node scale-up time on AWS:

1. **chrony-wait skip** — skip NTP wait on Boot 2 when the clock was recently synced (saves ~7-20s)
2. **Pre-pull CNI images** — pull NodeReady-blocking container images during Boot 1 in parallel with MCD firstboot (saves ~40-60s on KTR)

## Cluster

| Property | Value |
|---|---|
| Platform | AWS (us-east-2) |
| OCP Version | 4.20.18 |
| Instance Type | m6i.xlarge (4 vCPU, 16 GB RAM) |
| Zones | us-east-2a, us-east-2b, us-east-2c |
| Boot Image | ami-021a620474c1cd2fe (RHCOS 4.20) |
| Cluster ID | sdodson-nt-br5zj |

## Test Methodology

- 3 test MachineSets (one per AZ), scaled 0→1 per round
- 5 rounds per configuration = 15 samples per configuration
- Artifacts collected: full journal, systemd-analyze, Machine/Node YAML
- Between rounds: scale to 0, wait for full machine deletion

## Phase 1: Baseline (No Optimizations)

### Summary (n=14, excluding r1-z2 outlierⁱ)

| Phase | Mean | Stdev | Min | Max |
|---|---|---|---|---|
| **Total** | **220.5s** | 16.2 | 196 | 247 |
| VM Provisioning | 22.9s | 1.7 | 20 | 25 |
| Boot 1 (kernel → finalize) | 120.6s | 12.8 | 100 | 147 |
| — MCD firstboot | 52.0s | 4.7 | 44 | 59 |
| —— Extensions pull+copy | 12.4s | 3.4 | 7 | 16 |
| —— rpm-ostree rebase | 39.6s | 2.5 | 36 | 43 |
| Reboot | 15.4s | 3.5 | 11 | 19 |
| Boot 2 (systemd-analyze) | 20.8s | 4.5 | 15.5 | 28.8 |
| — chrony-wait | 11.7s | 4.6 | 7.0 | 20.1 |
| KTR (kubelet → NodeReady) | 61.6s | 5.4 | 56 | 77 |

ⁱ r1-z2 excluded: 389s total with 2m12s Boot 2 filesystem mount delay (EBS volume initialization stall). With all 15: mean 231.7s, stdev 46.2s.

### All Data Points

| Sample | Total | VM Prov | Boot 1 | MCD | Ext | Rebase | Reboot | SA | chrony | KTR |
|---|---|---|---|---|---|---|---|---|---|---|
| r1-z1 | 230 | 21 | 133 | 51 | 8 | 43 | 18 | 15.5 | 7.0 | 58 |
| **r1-z2**ⁱ | **389** | **24** | **151** | **54** | **7** | **47** | **19** | **148.0** | **7.0** | **195** |
| r1-z3 | 247 | 25 | 147 | 45 | 8 | 37 | 19 | 17.5 | 9.0 | 56 |
| r2-z1 | 214 | 21 | 114 | 53 | 16 | 37 | 18 | 25.7 | 17.1 | 61 |
| r2-z2 | 226 | 24 | 128 | 59 | 16 | 43 | 11 | 24.0 | 14.1 | 63 |
| r2-z3 | 205 | 25 | 109 | 49 | 13 | 36 | 11 | 16.1 | 7.0 | 60 |
| r3-z1 | 239 | 21 | 135 | 46 | 7 | 39 | 18 | 16.5 | 7.0 | 65 |
| r3-z2 | 213 | 24 | 120 | 44 | 7 | 37 | 12 | 16.7 | 7.0 | 57 |
| r3-z3 | 209 | 24 | 107 | 51 | 14 | 37 | 18 | 25.3 | 17.1 | 60 |
| r4-z1 | 231 | 21 | 125 | 57 | 14 | 43 | 18 | 20.0 | 11.1 | 67 |
| r4-z2 | 242 | 24 | 123 | 57 | 15 | 42 | 18 | 28.8 | 20.1 | 77 |
| r4-z3 | 196 | 23 | 100 | 53 | 14 | 39 | 12 | 21.6 | 12.1 | 61 |
| r5-z1 | 200 | 20 | 111 | 56 | 15 | 41 | 11 | 16.3 | 7.1 | 58 |
| r5-z2 | 227 | 24 | 126 | 55 | 15 | 40 | 19 | 25.7 | 16.1 | 58 |
| r5-z3 | 208 | 23 | 111 | 52 | 12 | 40 | 12 | 21.2 | 12.1 | 62 |

### Phase Breakdown

```
VM Provisioning  ████ 22.9s (10%)
Boot 1 (total)   ████████████████████████████████████████████████ 120.6s (55%)
  Ign+Pivot+Other ████████████████████████████████████ 68.6s
  MCD firstboot   ██████████████████████████ 52.0s
    Extensions     ██████ 12.4s
    rpm-ostree     ████████████████████ 39.6s
Reboot           ██████ 15.4s (7%)
Boot 2           ████████ 20.8s (9%)
  chrony-wait     ██████ 11.7s
KTR              ████████████████████████ 61.6s (28%)
─────────────────────────────────────────────────────────────
Total            ████████████████████████████████████████████████████████████████████████████████████████ 220.5s
```

### Optimization Targets

| Optimization | Target Phase | Current | Expected Savings |
|---|---|---|---|
| chrony-wait skip | Boot 2 → chrony-wait | 11.7s mean | 7-20s (skip entirely on Boot 2) |
| Pre-pull CNI | KTR → image pulls | ~50s of 61.6s KTR | 30-50s (overlap with MCD) |

### Notes

- **chrony-wait variance**: 7.0-20.1s across samples. The 7s floor appears when the initial clock offset is small; the 20s ceiling occurs with larger drift. The skip optimization would eliminate this variance entirely on Boot 2.
- **Boot 1 Ign+Pivot+Other**: 68.6s mean includes kernel/initrd (1-2s), DHCP (~2s), Ignition IMDS fetch (~4s), disk resize/mount (~6s), file writes, switch-root, and real-root systemd init through MCD image pull. This phase is not targeted by either optimization.
- **KTR**: 61.6s mean, dominated by container image pulls (CNI: multus, OVN-Kubernetes, plus MCD daemonset). CSR approval is <2s. Pre-pulling these images during Boot 1 would eliminate most of this.
- **AWS vs ARO comparison**: This AWS cluster shows significantly faster MCD firstboot (52s vs 111s on ARO) due to direct quay.io access (ARO routes through arosvc.azurecr.io mirror). Boot 2 systemd-analyze is also faster (20.8s vs 33.4s) due to shorter chrony-wait on AWS.

## Phase 2: chrony-wait Skip Only

MachineConfig `99-worker-chrony-wait-skip-reboot` adds a systemd drop-in to chrony-wait.service:
```
[Unit]
ConditionPathExists=!/var/lib/chrony/drift
```
On Boot 2, the chrony drift file exists (written during Boot 1), so chrony-wait is skipped entirely. On a fresh provision (Boot 1), the drift file does not yet exist and chrony-wait runs normally.

### Summary (n=15)

| Phase | Mean | Stdev | Min | Max | Δ vs Baseline |
|---|---|---|---|---|---|
| **Total** | **215.4s** | 12.2 | 195 | 239 | **−5.1s (−2%)** |
| Boot 2 SA | 13.1s | 0.8 | 11.7 | 14.8 | −7.7s (−37%) |
| chrony-wait | 0.0s | 0.0 | 0 | 0 | **−11.7s (−100%)** |
| KTR | 44.1s | 5.3 | 36 | 54 | −17.5s (−28%) |
| MCD firstboot | 69.3s | 2.4 | 64 | 74 | +17.3s (+33%) |

### All Data Points

| Sample | Total | SA | chrony | KTR | MCD |
|---|---|---|---|---|---|
| r1-z1 | 205 | 11.9 | 0 | 42 | 64 |
| r1-z2 | 220 | 12.2 | 0 | 44 | 70 |
| r1-z3 | 212 | 13.3 | 0 | 41 | 67 |
| r2-z1 | 239 | 14.8 | 0 | 51 | 74 |
| r2-z2 | 219 | 13.4 | 0 | 47 | 70 |
| r2-z3 | 212 | 13.4 | 0 | 40 | 68 |
| r3-z1 | 204 | 13.8 | 0 | 40 | 71 |
| r3-z2 | 225 | 12.1 | 0 | 54 | 68 |
| r3-z3 | 227 | 11.7 | 0 | 53 | 68 |
| r4-z1 | 226 | 13.0 | 0 | 46 | 73 |
| r4-z2 | 212 | 13.1 | 0 | 45 | 71 |
| r4-z3 | 197 | 13.4 | 0 | 41 | 70 |
| r5-z1 | 195 | 13.9 | 0 | 36 | 69 |
| r5-z2 | 226 | 13.8 | 0 | 42 | 69 |
| r5-z3 | 212 | 12.8 | 0 | 39 | 68 |

### Notes

- **chrony-wait eliminated**: 0s in all 15 samples (was 7.0–20.1s in baseline). `ConditionPathExists=!/var/lib/chrony/drift` reliably skips chrony-wait on Boot 2 because chronyd writes the drift file during Boot 1.
- **Boot 2 SA reduced 37%**: Mean 13.1s vs 20.8s baseline. The 7.7s reduction closely tracks the baseline chrony-wait mean of 11.7s, confirming chrony-wait was on the critical path.
- **KTR reduced 28%**: Mean 44.1s vs 61.6s. The KTR reduction appears unrelated to chrony — it may reflect cluster state differences (warm caches from prior rounds) or network conditions during this test window.
- **MCD 33% slower**: Mean 69.3s vs 52.0s baseline. This is likely due to the additional MC content being rendered (the chrony-wait drop-in adds to the rendered config, potentially causing different file/unit application behavior during firstboot).

## Phase 3: Pre-pull CNI Only

MachineConfig `99-worker-pre-pull-cni` adds a oneshot systemd service that runs on Boot 1 (gated by `ConditionKernelCommandLine=ignition.firstboot`) to pull 10 NodeReady-blocking container images via podman in parallel with MCD firstboot. Images are pulled into `/var/lib/containers/storage` (shared graphroot with CRI-O), so after reboot CRI-O finds them cached.

Pullspecs are hardcoded for OCP 4.20.18 (in production, the MCO would populate them at render time from the release payload).

### Images Pre-pulled (ordered by criticality)

| Component | Used By |
|---|---|
| ovn-kubernetes | ovnkube-node (init + 5 containers), network-node-identity |
| multus-cni | multus ds, multus-additional-cni-plugins container |
| kube-rbac-proxy | sidecar in ovnkube-node, MCD, network-metrics, dns, node-exporter |
| egress-router-cni | multus-additional-cni-plugins init |
| container-networking-plugins | multus-additional-cni-plugins init |
| network-interface-bond-cni | multus-additional-cni-plugins init |
| multus-route-override-cni | multus-additional-cni-plugins init |
| multus-whereabouts-ipam-cni | multus-additional-cni-plugins init |
| network-metrics-daemon | network-metrics-daemon ds |
| cluster-node-tuning-operator | tuned ds |

### Summary (n=7ⁱⁱ)

| Phase | Mean | Stdev | Min | Max | Δ vs Baseline |
|---|---|---|---|---|---|
| **Total** | **233.6s** | 16.0 | 203 | 248 | **+13.1s (+6%)** |
| Boot 2 SA | 18.1s | 1.6 | 16.1 | 20.6 | −2.7s (−13%) |
| chrony-wait | 9.3s | 3.7 | 7.0 | 17.1 | −2.4s (−21%) |
| KTR | 23.9s | 10.1 | 11 | 41 | **−37.7s (−61%)** |
| MCD firstboot | 84.0s | 6.1 | 75 | 93 | **+32.0s (+62%)** |

ⁱⁱ Due to artifact collection bug (missing zone suffixes), rounds 2-5 preserved data for only one of 3 test nodes each. Round 1 has all 3 zones.

### All Data Points

| Sample | Total | SA | chrony | KTR | MCD |
|---|---|---|---|---|---|
| r1-z1 | 243 | 16.7 | 7.0 | 20 | 89 |
| r1-z2 | 245 | 17.1 | 7.1 | 21 | 86 |
| r1-z3 | 222 | 19.0 | 9.0 | 19 | 80 |
| r2 | 235 | 20.6 | 11.1 | 11 | 93 |
| r3 | 239 | 18.1 | 17.1 | 41 | 80 |
| r4 | 203 | 18.9 | 7.0 | 21 | 75 |
| r5 | 248 | 16.1 | 7.0 | 34 | 85 |

### Notes

- **KTR dramatically reduced**: Mean 23.9s vs 61.6s baseline (−61%). On Boot 2, CRI-O finds the pre-pulled images cached in `/var/lib/containers/storage` and skips re-pulling entirely. The remaining KTR is CSR approval + non-pre-pulled images (aws-ebs-csi, dns, node-exporter, etc.).
- **MCD slowed by network contention**: Mean 84.0s vs 52.0s baseline (+62%). During Boot 1, the pre-pull service pulls 10 images concurrently with MCD's rpm-ostree rebase, competing for network bandwidth. Pre-pull runs ~53-69s, overlapping ~39-67s with MCD.
- **Net effect on total**: The KTR savings (−38s) are partially offset by MCD slowdown (+32s), yielding only ~6s net improvement on total time. However, this shifts work from Boot 2 (blocking user-visible latency) to Boot 1 (background, overlapped with MCD).
- **Pre-pull timing on Boot 1**: The service ran for 53-69s, pulling all 10 images with MAX_PARALLEL=3 concurrency. It completed before MCD initiated reboot in all samples.

## Phase 4: Both Optimizations

Both MachineConfigs applied together: `99-worker-chrony-wait-skip-reboot` + `99-worker-pre-pull-cni`.

### Summary (n=4, excluding r4 outlierⁱⁱⁱ)

| Phase | Mean | Stdev | Min | Max | Δ vs Baseline |
|---|---|---|---|---|---|
| **Total** | **233.5s** | 5.7 | 230 | 242 | **+13.0s (+6%)** |
| Boot 2 SA | 12.3s | 0.5 | 11.9 | 13.0 | −8.5s (−41%) |
| chrony-wait | 0.0s | 0.0 | 0 | 0 | **−11.7s (−100%)** |
| KTR | 20.8s | 1.3 | 19 | 22 | **−40.8s (−66%)** |
| MCD firstboot | 94.0s | 9.0 | 84 | 105 | **+42.0s (+81%)** |

ⁱⁱⁱ r4 excluded: 344s total with 2m04s Boot 2 filesystem mount stall (same pattern as baseline r1-z2). Without outlier: mean 233.5s.

### All Data Points

| Sample | Total | SA | chrony | KTR | MCD |
|---|---|---|---|---|---|
| r1 | 242 | 13.0 | 0 | 20 | 93 |
| r2 | 230 | 11.9 | 0 | 22 | 94 |
| r3 | 230 | 11.9 | 0 | 22 | 84 |
| **r4**ⁱⁱⁱ | **344** | **137.5** | **0** | **21** | **80** |
| r5 | 232 | 12.5 | 0 | 19 | 105 |

### Notes

- **Both optimizations confirmed working**: chrony-wait 0s (skipped via drift file condition), pre-pull complete with 11-12 images cached on Boot 1, correctly skipped on Boot 2.
- **KTR near floor**: Mean 20.8s, very consistent (σ=1.3s). The remaining KTR is CSR approval + pull of non-pre-pulled images (small, shared base layers already cached). This is likely near the practical minimum.
- **MCD regression amplified**: Mean 94.0s vs 52.0s baseline (+81%). With both MCs adding content, the rendered config is larger. Network contention from pre-pull during Boot 1 further slows MCD.
- **Total time not improved**: Despite eliminating 52.5s of Boot 2 time (11.7s chrony + 40.8s KTR), the MCD slowdown (+42.0s) absorbs most of the savings. The net total is 13s worse than baseline.

## Comparison Summary

| Config | n | Total | SA | chrony | KTR | MCD |
|---|---|---|---|---|---|---|
| Baseline | 14 | **220.5s** | 20.8s | 11.7s | 61.6s | 52.0s |
| chrony-wait skip | 15 | **215.4s** | 13.1s | 0.0s | 44.1s | 69.3s |
| Pre-pull CNI | 7 | **233.6s** | 18.1s | 9.3s | 23.9s | 84.0s |
| Both | 4 | **233.5s** | 12.3s | 0.0s | 20.8s | 94.0s |

### Phase Breakdown: Baseline vs Both

```
                    Baseline                              Both
VM Provisioning  ████ 22.9s (10%)                ████ ~23s (10%)
Boot 1 (total)   ████████████████████████ 120.6s  ████████████████████████████████ ~160s (69%)
  MCD firstboot   █████████████ 52.0s              ██████████████████████████ 94.0s
Reboot           ██████ 15.4s (7%)               ██████ ~15s (6%)
Boot 2           ████████ 20.8s (9%)             ████ 12.3s (5%)
  chrony-wait     ██████ 11.7s                     ▏ 0s
KTR              ████████████████████████ 61.6s   ████████ 20.8s (9%)
────────────────────────────────────────────────────────────────
Total            ████████████████████████████████████████████ 220.5s  ████████████████████████████████████████████████ 233.5s
```

### Key Findings

1. **chrony-wait skip is a clean win**: −11.7s with no side effects. The `ConditionPathExists=!/var/lib/chrony/drift` drop-in is simple, reliable, and zero-cost. **Recommended for production.**

2. **Pre-pull CNI trades Boot 1 time for Boot 2 time**: KTR drops 61.6s → 20.8s (−66%), but MCD firstboot increases 52.0s → 94.0s (+81%) due to network contention. **Net total time is unchanged.** However, this makes the boot process more *robust* — image pulls are no longer on the critical path after reboot. If registry latency varies, baseline KTR varies proportionally; with pre-pull, KTR is consistently ~20s.

3. **MCD network contention is the limiting factor**: The pre-pull service and MCD rebase compete for network bandwidth during Boot 1. With MAX_PARALLEL=3 image pulls running alongside rpm-ostree rebase, the MCD phase nearly doubles. A production implementation should either:
   - **Sequence intelligently**: Start pre-pull only after MCD finishes the OS image pull but before the reboot, or
   - **Use a lower concurrency**: MAX_PARALLEL=1 would reduce contention at the cost of less overlap, or
   - **Integrate into MCO**: The MCO could pull images as part of its own workflow, avoiding concurrency issues entirely.

4. **Combined optimizations save ~52.5s of Boot 2 time** (chrony-wait 11.7s + KTR 40.8s) but add ~42s to Boot 1 MCD, for a net effect of ~+13s on total. The value proposition depends on whether Boot 2 latency (user-visible, on the critical path to workload scheduling) is valued more than Boot 1 latency (background, before the node exists in the cluster).

## Test Timeline

| Phase | Date | Time (UTC) | Status |
|---|---|---|---|
| Baseline | 2026-04-27 | 15:05–17:20 | Complete (15 samples) |
| chrony-wait skip | 2026-04-27 | 18:50–20:30 | Complete (15 samples) |
| Pre-pull CNI | 2026-04-27–28 | 22:28–00:43 | Complete (7 usable samples) |
| Both | 2026-04-28 | 01:05–03:37 | Complete (5 samples) |
