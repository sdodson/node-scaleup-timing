# Node Scale-Up Variance Analysis: Standard_D4s_v5 (Azure, 8 Rounds x 3 Zones)

## Test Setup
- **Cluster**: ci-ln-ikkmv7b-1d09d (OpenShift 4.20, Kubernetes 1.33.9)
- **Region**: eastus2, Zones 1/2/3
- **Date**: 2026-04-21
- **VM Type**: Standard_D4s_v5 (4 vCPU, 16 GB RAM)
- **Rounds**: 8 (all 3 zones per round, machinesets created simultaneously)
- **Total samples**: 24

## Results Summary

**Overall scale-up time:** Mean = **293.5s (4m 53.5s)**, stdev = 49.0s, range 229-415s

## All 24 Data Points

| Round | Zone | Total | VM Prov | Boot 1 | Reboot | Boot2->Ready | systemd-analyze | chrony-wait |
|------:|-----:|------:|--------:|-------:|-------:|-------------:|----------------:|------------:|
| 1 | 1 | 326s | 44s | 176s | 4s | 102s | 34.6s | 24.07s |
| 1 | 2 | 327s | 51s | 183s | 5s | 88s | 33.8s | 24.06s |
| 1 | 3 | 332s | 46s | 187s | 7s | 92s | 33.5s | 24.07s |
| 2 | 1 | 321s | 44s | 187s | 8s | 82s | 33.0s | 24.07s |
| 2 | 2 | 341s | 45s | 202s | 8s | 86s | 32.9s | 24.06s |
| 2 | 3 | 356s | 45s | 213s | 7s | 91s | 34.5s | 24.07s |
| 3 | 1 | 285s | 43s | 155s | 5s | 82s | 33.2s | 24.07s |
| 3 | 2 | 279s | 42s | 137s | 3s | 97s | 36.7s | 24.08s |
| 3 | 3 | 304s | 51s | 161s | 5s | 87s | 34.4s | 24.06s |
| 4 | 1 | 293s | 43s | 158s | 4s | 88s | 33.8s | 24.07s |
| 4 | 2 | 239s | 27s | 116s | 6s | 90s | 35.7s | 24.06s |
| 4 | 3 | 306s | 43s | 165s | 3s | 95s | 33.6s | 24.07s |
| 5 | 1 | 235s | 29s | 108s | 6s | 92s | 32.3s | 24.07s |
| 5 | 2 | 246s | 31s | 126s | 3s | 86s | 36.5s | 24.07s |
| 5 | 3 | 312s | 29s | 187s | 8s | 88s | 32.7s | 24.07s |
| 6 | 1 | 355s | 42s | 206s | 5s | 102s | 34.2s | 24.08s |
| 6 | 2 | 246s | 25s | 117s | 6s | 98s | 36.2s | 24.08s |
| 6 | 3 | 238s | 29s | 112s | 11s | 86s | 33.2s | 24.07s |
| 7 | 1 | 315s | 45s | 178s | 7s | 85s | 33.1s | 24.07s |
| 7 | 2 | 239s | 26s | 119s | 5s | 89s | 36.8s | 24.09s |
| 7 | 3 | 243s | 32s | 106s | 10s | 95s | 33.3s | 24.07s |
| 8 | 1 | 415s | 82s | 234s | 6s | 93s | 37.0s | 24.06s |
| 8 | 2 | 261s | 29s | 136s | 8s | 88s | 35.6s | 24.08s |
| 8 | 3 | 229s | 28s | 107s | 7s | 87s | 32.6s | 24.08s |

## Per-Zone Statistics (n=8 per zone)

| Metric | Zone 1 Mean | Zone 1 SD | Zone 2 Mean | Zone 2 SD | Zone 3 Mean | Zone 3 SD | Overall Mean | Overall SD |
|:---|---:|---:|---:|---:|---:|---:|---:|---:|
| **Total Scale-up** | **318.1s** | 52.7s | **272.2s** | 40.5s | **290.0s** | 47.3s | **293.5s** | 49.0s |
| VM Provisioning | 46.5s | 15.2s | 34.5s | 10.0s | 37.9s | 9.3s | 39.6s | 12.4s |
| Boot 1 Duration | 175.2s | 37.4s | 142.0s | 32.6s | 154.8s | 41.6s | 157.3s | 38.3s |
| Reboot Gap | 5.6s | 1.4s | 5.5s | 1.9s | 7.2s | 2.5s | 6.1s | 2.1s |
| Boot2 -> NodeReady | 90.8s | 8.0s | 90.2s | 4.7s | 90.1s | 3.6s | 90.4s | 5.5s |
| systemd-analyze | 33.9s | 1.4s | 35.5s | 1.4s | 33.5s | 0.7s | 34.3s | 1.5s |
| chrony-wait | 24.07s | 0.007s | 24.07s | 0.010s | 24.07s | 0.006s | 24.07s | 0.008s |

## Zonal Differences: NOT Statistically Significant

ANOVA results (F critical at p<0.05, df=2,21 = 3.467):

| Metric | F statistic | Significant? |
|:---|---:|:---:|
| Total Scale-up | 1.928 | NO |
| VM Provisioning | 2.195 | NO |
| Boot 1 Duration | 1.613 | NO |
| Reboot Gap | 1.876 | NO |
| Boot2 -> NodeReady | 0.026 | NO |
| systemd-analyze | 6.224 | YES (but only ~2s effect) |
| chrony-wait | 0.752 | NO |

The only statistically significant zonal difference is systemd-analyze (Zone 2 averages 35.5s vs Zone 1/3 at ~33.5s). This is operationally insignificant.

## Variance Decomposition

| Phase | Correlation with Total (r) | R-squared | Stdev |
|:---|---:|---:|---:|
| **Boot 1 Duration** | **0.983** | **96.6%** | 38.3s |
| VM Provisioning | 0.859 | 73.8% | 12.4s |
| Boot2 -> NodeReady | 0.158 | 2.5% | 5.5s |
| Reboot Gap | -0.109 | 1.2% | 2.1s |
| chrony-wait | ~0 | ~0% | 0.008s |

**Boot 1 (MCD firstboot / rpm-ostree rebase) explains 96.6% of total scale-up time variance.**

## Normalized Phase Breakdown (Overall Mean)

| Phase | Duration | % of Total | Stdev |
|:---|---:|---:|---:|
| VM Provisioning | 39.6s | 13.5% | 12.4s |
| Boot 1 (Ignition + MCD firstboot) | 157.3s | 53.6% | 38.3s |
| Reboot | 6.1s | 2.1% | 2.1s |
| Boot 2: chrony-wait | 24.1s | 8.2% | 0.008s |
| Boot 2: Other systemd (kernel/initrd/OVS) | 10.2s | 3.5% | 1.5s |
| Boot 2: Kubelet to NodeReady | 56.1s | 19.1% | 5.5s |
| **Total** | **293.5s** | **100%** | **49.0s** |

## Key Conclusions

1. **No zonal bias in Azure eastus2.** All three zones perform equivalently. The zone 1 "advantage" seen in single-round D32s tests was run-to-run noise. Within-zone variance (stdev 40-53s) exceeds between-zone differences (45.9s range of means).

2. **MCD firstboot is both the largest phase and the largest source of variance.** It averages 157.3s (53.6% of total) with 38.3s stdev, and explains 96.6% of total time variance. This phase is I/O and network bound (pulling container images, running rpm-ostree rebase).

3. **Boot 2 is remarkably stable.** The Boot2->NodeReady phase averages 90.4s with only 5.5s stdev (CV = 6.1%). chrony-wait is essentially a constant at 24.07s with 8ms stdev across 24 samples.

4. **Run-to-run variance is large and unpredictable.** Total scale-up time ranges from 229s to 415s (1.8x spread). This is driven almost entirely by MCD firstboot variance, likely reflecting Azure storage/network contention.

5. **For benchmarking, report the mean with confidence interval.** With 24 samples: 293.5s +/- 20.7s (95% CI). For a single zone, 8 samples gives roughly +/- 40s CI. Single-run measurements are unreliable.

## Saved Artifacts

Per round/zone (r1-r8, z1-z3):
- `new-machine-d4s-v5-r{R}-z{Z}-final.yaml`
- `new-node-d4s-v5-r{R}-z{Z}.yaml`
- `node-journal-d4s-v5-r{R}-z{Z}.log`
- `node-boot-list-d4s-v5-r{R}-z{Z}.txt`
- `node-systemd-analyze-d4s-v5-r{R}-z{Z}.txt`
- `node-systemd-blame-d4s-v5-r{R}-z{Z}.txt`
- `node-systemd-critical-chain-d4s-v5-r{R}-z{Z}.txt`
- `machineset-d4s-v5-r{R}-z{Z}.json`
