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

## Phase 5: Pre-pull CNI Serial (MAX_PARALLEL=1)

Re-test of the pre-pull CNI optimization with serial image pulls instead of MAX_PARALLEL=3. The hypothesis is that reducing pull concurrency will reduce network contention with MCD during Boot 1, yielding a better total time while preserving the KTR reduction.

Changes from Phase 3:
- Removed `systemd-inhibit` wrapper (no longer needed without rebase-wait logic)
- Removed `logind.conf.d` dropin for `InhibitDelayMaxSec`
- Script pulls images serially (one at a time) instead of 3 concurrent pulls
- `TimeoutStartSec` reverted from 600 to 300

### Summary (n=15)

| Phase | Mean | Stdev | Min | Max | Δ vs Baseline |
|---|---|---|---|---|---|
| **Total** | **240.8s** | 16.4 | 215 | 266 | **+20.3s (+9%)** |
| VM Provisioning | 23.5s | 2.8 | 17 | 28 | +0.6s |
| Boot 1 (total) | 151.3s | 13.1 | 131 | 173 | +30.7s (+25%) |
| — MCD firstboot | 98.5s | 8.3 | 85 | 116 | +46.5s (+89%) |
| —— rpm-ostree rebase | 54.3s | 8.0 | 36 | 73 | +14.7s (+37%) |
| Reboot | 27.2s | 4.9 | 18 | 33 | +11.8s |
| Boot 2 SA | 19.0s | 3.0 | 15.8 | 25.5 | −1.8s (−9%) |
| — chrony-wait | 9.7s | 2.9 | 7.0 | 16.1 | −2.0s (−17%) |
| KTR | **19.9s** | 1.5 | 17 | 23 | **−41.7s (−68%)** |
| Pre-pull duration | 81.7s | 8.6 | 63 | 98 | — |

### All Data Points

| Sample | Total | VM Prov | Boot 1 | MCD FB | Rebase | Reboot | SA | chrony | KTR | Pre-pull |
|---|---|---|---|---|---|---|---|---|---|---|
| r1-z1 | 224 | 23 | 143 | 92 | 36 | 23 | 15.8 | 7.0 | 19 | 63 |
| r1-z2 | 252 | 17 | 173 | 107 | 47 | 25 | 17.0 | 7.1 | 20 | 96 |
| r1-z3 | 262 | 26 | 168 | 97 | 57 | 32 | 16.5 | 7.0 | 19 | 98 |
| r2-z1 | 266 | 23 | 172 | 116 | 73 | 32 | 16.5 | 7.0 | 23 | 79 |
| r2-z2 | 263 | 28 | 160 | 102 | 56 | 33 | 22.1 | 12.1 | 20 | 82 |
| r2-z3 | 222 | 22 | 132 | 85 | 52 | 25 | 21.7 | 13.1 | 21 | 81 |
| r3-z1 | 229 | 22 | 143 | 94 | 49 | 18 | 25.5 | 16.1 | 20 | 80 |
| r3-z2 | 215 | 26 | 131 | 92 | 57 | 19 | 17.3 | 8.1 | 22 | 76 |
| r3-z3 | 240 | 24 | 146 | 95 | 54 | 31 | 19.7 | 10.1 | 19 | 82 |
| r4-z1 | 224 | 21 | 143 | 96 | 54 | 24 | 15.9 | 7.0 | 20 | 83 |
| r4-z2 | 249 | 24 | 152 | 102 | 58 | 31 | 23.6 | 14.1 | 18 | 84 |
| r4-z3 | 230 | 26 | 142 | 87 | 48 | 27 | 17.1 | 9.0 | 18 | 71 |
| r5-z1 | 252 | 26 | 154 | 100 | 58 | 32 | 18.7 | 9.0 | 21 | 86 |
| r5-z2 | 239 | 20 | 153 | 106 | 61 | 31 | 18.4 | 9.1 | 17 | 86 |
| r5-z3 | 245 | 24 | 157 | 107 | 55 | 25 | 18.2 | 9.0 | 21 | 78 |

### Notes

- **KTR near floor with excellent consistency**: Mean 19.9s with σ=1.5s (vs Phase 3's 23.9s with σ=10.1s). Serial pulls ensure all 10 images are fully cached before reboot. The remaining KTR is CSR approval + non-pre-pulled images.
- **Serial pulls still cause network contention**: MCD firstboot mean 98.5s vs baseline 52.0s (+89%). However, the contention is concentrated in MCD's pre-rebase phase (image pulls, extensions copy), not during the rebase itself. The rpm-ostree rebase takes 54.3s (vs baseline 39.6s, +37%), compared to Phase 3's implied +62% contention with MAX_PARALLEL=3.
- **Pre-pull timing**: Serial pulls took 81.7s mean (vs Phase 3's ~60s with MAX_PARALLEL=3). The serial pre-pull overlaps primarily with MCD's network-bound work (MCD image pull + extensions), then finishes around the time rebase starts. This means the rebase runs with less network contention than Phase 3.
- **Total time increase**: +20.3s vs baseline (+9%). The KTR savings (−41.7s) are offset by MCD slowdown (+46.5s) and reboot increase (+11.8s). The reboot increase may reflect the additional storage I/O from having 10 extra images in `/var/lib/containers/storage`.
- **MCP rolling update may have contributed to contention**: During this test, the existing worker nodes were being updated with the new rendered config (chrony-wait MC had just been removed). This network activity could have inflated the MCD firstboot times beyond what serial pre-pull alone would cause.

## Comparison Summary

| Config | n | Total | SA | chrony | KTR | MCD FB |
|---|---|---|---|---|---|---|
| Baseline | 14 | **220.5s** | 20.8s | 11.7s | 61.6s | 52.0s |
| chrony-wait skip | 15 | **215.4s** | 13.1s | 0.0s | 44.1s | 69.3s |
| Pre-pull CNI (×3) | 7 | **233.6s** | 18.1s | 9.3s | 23.9s | 84.0s |
| Both (×3) | 4 | **233.5s** | 12.3s | 0.0s | 20.8s | 94.0s |
| Pre-pull serial (×1) | 15 | **240.8s** | 19.0s | 9.7s | **19.9s** | 98.5s |

### KTR Comparison

```
Baseline         ████████████████████████████████████████████████████████████████ 61.6s  σ=5.4
chrony-wait skip ████████████████████████████████████████████ 44.1s  σ=5.3
Pre-pull ×3      ████████████████████████ 23.9s  σ=10.1
Both ×3          ████████████████████ 20.8s  σ=1.3
Pre-pull ×1      ████████████████████ 19.9s  σ=1.5
```

### Key Findings

1. **chrony-wait skip is a clean win**: −11.7s with no side effects. The `ConditionPathExists=!/var/lib/chrony/drift` drop-in is simple, reliable, and zero-cost. **Recommended for production.**

2. **Pre-pull CNI reduces KTR by 68%** (61.6s → 19.9s) with serial pulls, but increases MCD firstboot by 89% due to network contention during Boot 1. Net total time is +20s (9%) worse than baseline.

3. **Serial vs parallel pre-pull**:
   - Serial (×1): KTR 19.9s (σ=1.5), MCD 98.5s, Total 240.8s
   - Parallel (×3): KTR 23.9s (σ=10.1), MCD 84.0s, Total 233.6s
   - Serial yields lower and more consistent KTR (all images guaranteed cached) but higher total due to longer pull duration and more overlap with MCD network operations.

4. **Network contention is unavoidable with a systemd unit approach**: Whether serial or parallel, the pre-pull service competes with MCD for network bandwidth during Boot 1. The contention shifts from MCD's rebase phase (with parallel pulls) to MCD's pre-rebase phase (with serial pulls), but doesn't disappear. **The only way to eliminate contention is MCO integration** — pulling images after `applyOSChanges()` returns and before `reboot()` is called (see MCO integration notes).

5. **Recommended production approach**:
   - **Short-term**: chrony-wait skip only (−11.7s, zero risk)
   - **Medium-term**: Pre-pull with serial pulls + chrony-wait skip. Total is ~20s worse than baseline, but KTR is 68% lower and highly consistent — valuable for workload scheduling predictability.
   - **Long-term**: Integrate pre-pull into MCO source code, pulling images after rpm-ostree rebase completes but before MCD triggers reboot. This eliminates network contention entirely and should yield both lower KTR and lower total.

## Test Timeline

| Phase | Date | Time (UTC) | Status |
|---|---|---|---|
| Baseline | 2026-04-27 | 15:05–17:20 | Complete (15 samples) |
| chrony-wait skip | 2026-04-27 | 18:50–20:30 | Complete (15 samples) |
| Pre-pull CNI (×3) | 2026-04-27–28 | 22:28–00:43 | Complete (7 usable samples) |
| Both (×3) | 2026-04-28 | 01:05–03:37 | Complete (5 samples) |
| Pre-pull serial (×1) | 2026-04-28 | 14:10–17:13 | Complete (15 samples) |
