# Node Scale-Up Variance Analysis: Standard_D4s_v5 (ARO, OCP 4.20.15, brazilsouth)

## Test Setup
- **Cluster**: ARO (Azure Red Hat OpenShift) — `sdodsonbr-tghmp`
- **OCP Version**: 4.20.15 (Kubernetes 1.33.6, CRI-O 1.33.9)
- **OS**: RHCOS 9.6.20260217-1 (Plow), kernel 5.14.0-570.92.1.el9_6
- **Region**: brazilsouth, Zones 1/2/3
- **Date**: 2026-04-22
- **VM Type**: Standard_D4s_v5 (4 vCPU, 16 GB RAM)
- **Rounds**: 10 (all 3 zones per round, machinesets created simultaneously)
- **Total samples**: 30

## Results Summary

**Overall scale-up time:** Mean = **335s (5m 35sec)**, stdev = 40s, range 293-430s

## All 30 Data Points

| Round | Zone | Total | VM Prov | Boot 1 | Reboot | Boot2→Ready | KTR | systemd-analyze | chrony-wait |
|------:|-----:|------:|--------:|-------:|-------:|------------:|----:|----------------:|------------:|
| 1 | 1 | 329s | 23s | 196s | 8s | 102s | 72s | 28.2s | 24.06s |
| 1 | 2 | 327s | 21s | 172s | 7s | 127s | 96s | 28.1s | 24.07s |
| 1 | 3 | 327s | 24s | 187s | 8s | 108s | 76s | 28.6s | 24.07s |
| 2 | 1 | 327s | 25s | 183s | 13s | 106s | 71s | 28.6s | 24.07s |
| 2 | 2 | 326s | 25s | 189s | 8s | 104s | 73s | 28.6s | 24.06s |
| 2 | 3 | 332s | 22s | 198s | 7s | 105s | 71s | 28.4s | 24.06s |
| 3 | 1 | 323s | 24s | 194s | 4s | 101s | 68s | 28.0s | 24.06s |
| 3 | 2 | 321s | 21s | 188s | 4s | 108s | 75s | 28.0s | 24.07s |
| 3 | 3 | 322s | 20s | 183s | 4s | 115s | 81s | 28.2s | 24.07s |
| 4 | 1 | 311s | 21s | 168s | 4s | 118s | 84s | 28.0s | 24.08s |
| 4 | 2 | 316s | 23s | 193s | 6s | 94s | 60s | 28.5s | 24.07s |
| 4 | 3 | 308s | 21s | 190s | 5s | 92s | 59s | 28.5s | 24.07s |
| 5 | 1 | 314s | 23s | 176s | 5s | 110s | 78s | 28.1s | 24.07s |
| 5 | 2 | 315s | 23s | 191s | 8s | 93s | 62s | 28.5s | 24.07s |
| 5 | 3 | 312s | 21s | 187s | 5s | 99s | 66s | 28.6s | 24.07s |
| 6 | 1 | 298s | 20s | 155s | 5s | 118s | 85s | 28.7s | 24.06s |
| 6 | 2 | 297s | 22s | 173s | 5s | 97s | 63s | 29.0s | 24.09s |
| 6 | 3 | 301s | 23s | 181s | 5s | 92s | 58s | 28.6s | 24.06s |
| 7 | 1 | 343s | 23s | 213s | 5s | 102s | 68s | 29.2s | 24.07s |
| 7 | 2 | 340s | 20s | 169s | 4s | 147s | 113s | 28.4s | 24.08s |
| 7 | 3 | 338s | 21s | 191s | 4s | 122s | 88s | 28.6s | 24.07s |
| 8 | 1 | 294s | 21s | 165s | 8s | 100s | 70s | 28.1s | 24.06s |
| 8 | 2 | 293s | 23s | 160s | 5s | 105s | 72s | 28.3s | 24.07s |
| 8 | 3 | 297s | 21s | 168s | 5s | 103s | 69s | 28.4s | 24.08s |
| 9 | 1 | 430s | 20s | 279s | 6s | 125s | 93s | 28.2s | 24.07s |
| 9 | 2 | 428s | 19s | 266s | 5s | 138s | 105s | 28.2s | 24.08s |
| 9 | 3 | 427s | 22s | 283s | 7s | 115s | 83s | 28.6s | 24.07s |
| 10 | 1 | 387s | 22s | 253s | 10s | 102s | 72s | 28.0s | 24.07s |
| 10 | 2 | 382s | 20s | 260s | 6s | 96s | 64s | 28.2s | 24.07s |
| 10 | 3 | 387s | 19s | 259s | 7s | 102s | 71s | 28.3s | 24.07s |

## Overall Statistics (n=30)

| Metric | Mean | Stdev | Min | Max |
|:---|---:|---:|---:|---:|
| **Total Scale-up** | **335.1s** | 40.1s | 293s | 430s |
| VM Provisioning | 21.8s | 1.6s | 19s | 25s |
| Boot 1 Duration | 199.0s | 36.8s | 155s | 283s |
| Reboot Gap | 6.1s | 2.1s | 4s | 13s |
| Boot2 → NodeReady | 108.2s | 13.3s | 92s | 147s |
| Kubelet to NodeReady | 75.5s | 13.2s | 58s | 113s |
| systemd-analyze | 28.38s | 0.29s | 28.0s | 29.2s |
| chrony-wait | 24.069s | 0.007s | 24.06s | 24.09s |

## Per-Zone Statistics (n=10 per zone)

| Metric | Zone 1 Mean | Zone 1 SD | Zone 2 Mean | Zone 2 SD | Zone 3 Mean | Zone 3 SD |
|:---|---:|---:|---:|---:|---:|---:|
| **Total Scale-up** | **335.6s** | 42.3s | **334.5s** | 41.1s | **335.1s** | 41.2s |
| VM Provisioning | 22.2s | 1.6s | 21.7s | 1.9s | 21.4s | 1.3s |
| Boot 1 Duration | 197.7s | 40.6s | 196.1s | 35.4s | 203.0s | 38.1s |
| Boot2 → NodeReady | 110.2s | 9.3s | 110.9s | 18.5s | 103.5s | 9.9s |
| Kubelet to NodeReady | 76.1s | 8.5s | 78.3s | 18.2s | 72.2s | 9.5s |

**No statistically significant zonal differences.** Zone means differ by <1s in total time. Consistent with previous findings from the 4.20 eastus2 D4s_v5 study.

## Variance Analysis

**Boot 1 explains 90.4% of total variance** (R² = 0.904). This is consistent with the 4.20 eastus2 finding (R² = 0.966). MCD firstboot / rpm-ostree rebase variability dominates all other phases.

**KTR explains only 18.2% of total variance** (R² = 0.182). Image pull timing contributes some variance but is secondary to Boot 1.

**chrony-wait has near-zero variance** — 24.069s ± 0.007s across all 30 samples. Azure PHC refclock timing is deterministic.

**systemd-analyze is very stable** — 28.38s ± 0.29s. Boot 2 systemd services are highly consistent.

### Rounds 9 and 10 are outliers

Round 9 averaged 428s (2.3 SD above mean) and Round 10 averaged 385s (1.3 SD above mean). Both have dramatically elevated Boot 1 times:

| Round | Boot 1 Mean | Total Mean | vs Overall |
|------:|------------:|-----------:|:-----------|
| 1-8 | 182s | 317s | baseline |
| 9 | 276s | 428s | +94s Boot1, +111s total |
| 10 | 257s | 385s | +75s Boot1, +68s total |

The simplest explanation is transient I/O or network contention in the brazilsouth region affecting rpm-ostree image pulls during those rounds. All other phases (VM provisioning, chrony-wait, KTR) were normal.

**Excluding rounds 9+10 (n=24):** Mean = **317s (5m 17sec)**, stdev = 15.0s

## Normalized Phase Breakdown (Overall Mean)

| Phase | Duration | % of Total | Stdev |
|:---|---:|---:|---:|
| VM Provisioning | 21.8s | 6.5% | 1.6s |
| Boot 1 (Ignition + MCD firstboot) | 199.0s | 59.4% | 36.8s |
| Reboot | 6.1s | 1.8% | 2.1s |
| Boot 2: chrony-wait | 24.1s | 7.2% | 0.007s |
| Boot 2: Other systemd | 4.3s | 1.3% | — |
| Boot 2: Kubelet to NodeReady | 75.5s | 22.5% | 13.2s |
| **Total** | **335.1s** | **100%** | **40.1s** |

## Comparison with Other Clusters

| Metric | ARO brazilsouth 4.20 (n=30) | OCP Standalone eastus2 4.20 (n=24) | OCP Standalone eastus 4.22 (n=12) |
|:---|---:|---:|---:|
| **Total** | **335s (5m 35sec)** | **294s (4m 54sec)** | **247s (4m 07sec)** |
| VM Provisioning | 21.8s | 39.6s | 20.5s |
| Boot 1 | 199.0s | 157.3s | 128.3s |
| Reboot | 6.1s | 6.1s | 5.4s |
| chrony-wait | 24.07s | 24.07s | 24.07s |
| systemd-analyze | 28.4s | 34.3s | 33.1s |
| Kubelet to NodeReady | 75.5s | 56.1s | 60.6s |
| **Total stdev** | **40.1s** | **49.0s** | **11.3s** |

### Key differences

1. **ARO brazilsouth is 41s slower than OCP standalone eastus2** (335s vs 294s, same OCP version 4.20, same VM type). The increase comes from:
   - **Boot 1**: +42s (199s vs 157s) — brazilsouth has slower I/O throughput or longer rpm-ostree image pulls from the release registry
   - **KTR**: +19s (76s vs 56s) — CNI image pulls are slower from Brazil, likely due to registry distance

2. **VM provisioning is faster on ARO** — 22s vs 40s on standalone eastus2. ARO's managed infrastructure provisions VMs faster than standalone OCP's Machine API.

3. **systemd-analyze is faster on ARO** — 28.4s vs 34.3s. ARO may have fewer systemd services to start compared to standalone OCP.

4. **chrony-wait is identical** — 24.07s across all Azure clusters regardless of region, OCP version, or deployment model (ARO vs standalone). The PHC refclock behavior is deterministic.

5. **Boot 1 is the dominant bottleneck** — 59% of total time in ARO brazilsouth vs 54% in standalone eastus2. The Brazil region amplifies the I/O-bound phases (image pulls, rpm-ostree rebase) due to greater distance from container registries.

## ARO-Specific Observations

1. **ARO uses the same node bootstrap path as standalone OCP** — same Ignition → MCD firstboot → reboot → chrony-wait → kubelet sequence. The managed control plane doesn't change the worker node boot process.

2. **VM provisioning is consistently fast** — 22s ± 1.6s with no outliers. ARO's Azure infrastructure provisioning is both faster and more consistent than standalone OCP's Machine API (which showed 40s ± 12s on eastus2).

3. **Regional impact on image pulls is significant** — the ~40s increase in total time vs eastus2 is almost entirely in I/O-bound phases (Boot 1 and KTR). Nodes in Brazil must pull container images from registries likely hosted in US regions, adding network latency.

4. **Run-to-run variance pattern matches standalone OCP** — Boot 1 drives >90% of variance, zones are statistically identical, chrony is deterministic. The same variance structure holds across deployment models.

## Key Conclusions

1. **ARO D4s_v5 brazilsouth averages 5m 35sec** — 41s (14%) slower than standalone OCP 4.20 in eastus2 (4m 54sec), and 88s (36%) slower than standalone OCP 4.22 in eastus (4m 07sec).

2. **The Brazil region penalty is ~40s**, split between slower rpm-ostree rebase (+42s) and slower CNI image pulls (+19s). Both are network-bound operations affected by registry distance.

3. **ARO doesn't add overhead** — VM provisioning is actually faster (22s vs 40s). The managed control plane imposes no penalty on worker node bootstrap.

4. **30 samples confirm the variance pattern**: Boot 1 explains 90% of total variance, zones are identical, chrony-wait is a fixed 24.07s cost.

5. **For ARO in distant regions**, the optimization opportunities are the same as standalone OCP, but with higher impact: pre-caching the machine-os image and CNI images would save more time in distant regions where pulls are slower.

## Saved Artifacts

Per round/zone (r1-r10, z1-z3):
- `new-machine-aro-d4s-v5-r{R}-z{Z}-final.yaml`
- `new-node-aro-d4s-v5-r{R}-z{Z}.yaml`
- `machineset-aro-d4s-v5-r{R}-z{Z}.json`
- `node-boot-list-aro-d4s-v5-r{R}-z{Z}.txt`
- `node-systemd-analyze-aro-d4s-v5-r{R}-z{Z}.txt`
- `node-systemd-blame-aro-d4s-v5-r{R}-z{Z}.txt`
- `node-systemd-critical-chain-aro-d4s-v5-r{R}-z{Z}.txt`
- `node-images-aro-d4s-v5-r{R}-z{Z}.txt`
- `csr-list-aro-r{R}.txt`
