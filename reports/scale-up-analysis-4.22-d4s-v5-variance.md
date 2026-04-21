# Node Scale-Up Variance Analysis: Standard_D4s_v5 (Azure, OCP 4.22.0-rc.0)

## Test Setup
- **Cluster**: ci-ln-h0hn4xb-1d09d (OpenShift 4.22.0-rc.0, Kubernetes 1.35.3)
- **Region**: eastus, Zones 1/2/3
- **Date**: 2026-04-21
- **VM Type**: Standard_D4s_v5 (4 vCPU, 16 GB RAM)
- **Rounds**: 4 (all 3 zones per round, machinesets created simultaneously)
- **Total samples**: 12

## Results Summary

**Overall scale-up time:** Mean = **246.7s (4m 07sec)**, stdev = 11.3s, range 233-274s

## All 12 Data Points

| Round | Zone | Total | VM Prov | Boot 1 | Reboot | Boot2->Ready | KTR | systemd-analyze | chrony-wait |
|------:|-----:|------:|--------:|-------:|-------:|-------------:|----:|----------------:|------------:|
| 1 | 1 | 245s | 20s | 129s | 8s | 88s | 58s | 35.6s | 24.06s |
| 1 | 2 | 261s | 26s | 139s | 6s | 90s | 59s | 32.1s | 24.07s |
| 1 | 3 | 251s | 17s | 134s | 4s | 96s | 63s | 32.2s | 24.08s |
| 2 | 1 | 238s | 20s | 127s | 7s | 84s | 53s | 31.9s | 24.07s |
| 2 | 2 | 274s | 19s | 129s | 4s | 122s | 89s | 35.3s | 24.08s |
| 2 | 3 | 241s | 19s | 130s | 4s | 88s | 55s | 31.7s | 24.09s |
| 3 | 1 | 241s | 22s | 129s | 5s | 85s | 52s | 32.1s | 24.07s |
| 3 | 2 | 244s | 21s | 124s | 5s | 94s | 62s | 34.6s | 24.07s |
| 3 | 3 | 233s | 20s | 124s | 7s | 82s | 52s | 31.8s | 24.07s |
| 4 | 1 | 244s | 20s | 122s | 7s | 95s | 65s | 31.9s | 24.07s |
| 4 | 2 | 249s | 23s | 124s | 4s | 98s | 65s | 35.0s | 24.08s |
| 4 | 3 | 239s | 19s | 128s | 4s | 88s | 54s | 32.1s | 24.08s |

## Per-Zone Statistics (n=4 per zone)

| Metric | Zone 1 Mean | Zone 1 SD | Zone 2 Mean | Zone 2 SD | Zone 3 Mean | Zone 3 SD | Overall Mean | Overall SD |
|:---|---:|---:|---:|---:|---:|---:|---:|---:|
| **Total Scale-up** | **242.0s** | 3.2s | **257.0s** | 13.0s | **241.0s** | 7.5s | **246.7s** | 11.3s |
| VM Provisioning | 20.5s | 1.0s | 22.2s | 2.9s | 18.8s | 1.3s | 20.5s | 2.3s |
| Boot 1 Duration | 126.8s | 3.3s | 129.0s | 6.3s | 129.0s | 4.2s | 128.3s | 4.5s |
| Reboot Gap | 6.8s | 1.3s | 4.8s | 0.8s | 4.8s | 1.5s | 5.4s | 1.6s |
| Boot2 -> NodeReady | 88.0s | 4.8s | 101.0s | 14.3s | 88.5s | 5.8s | 92.5s | 10.8s |
| Kubelet to NodeReady | 57.0s | 5.7s | 68.8s | 13.4s | 56.0s | 4.8s | 60.6s | 10.1s |
| systemd-analyze | 32.9s | 1.8s | 34.4s | 1.2s | 32.0s | 0.2s | 33.1s | 1.5s |
| chrony-wait | 24.07s | 0.003s | 24.07s | 0.006s | 24.08s | 0.005s | 24.07s | 0.005s |

## Comparison with OCP 4.20 (same VM type, different cluster/region)

| Metric | 4.20 (eastus2, n=24) | 4.22 (eastus, n=12) | Delta |
|:---|---:|---:|---:|
| **Total Scale-up** | **293.5s (4m 54sec)** | **246.7s (4m 07sec)** | **-46.8s (16% faster)** |
| VM Provisioning | 39.6s | 20.5s | -19.1s |
| Boot 1 Duration | 157.3s | 128.3s | -29.0s |
| Reboot | 6.1s | 5.4s | -0.7s |
| Boot2 -> NodeReady | 90.4s | 92.5s | +2.1s |
| Kubelet to NodeReady | 56.1s | 60.6s | +4.5s |
| systemd-analyze | 34.3s | 33.1s | -1.2s |
| chrony-wait | 24.07s | 24.07s | 0s |

The 4.22 cluster is 47s faster overall. The improvement comes from:
- **VM provisioning**: 19s faster (eastus vs eastus2 — likely regional, not OCP version)
- **Boot 1 (MCD firstboot)**: 29s faster (smaller OS image delta or faster rpm-ostree in 4.22)
- **Boot2->NodeReady** is nearly identical (chrony and image pulls are unchanged)

**Note**: Different regions (eastus vs eastus2) make it hard to attribute improvements to OCP version vs regional infrastructure.

## Variance Analysis

**Much lower variance than 4.20**: stdev 11.3s (4.22) vs 49.0s (4.20). The 4.22 data has a 41s range (233-274s) vs 186s range on 4.20.

**R2Z2 is an outlier** at 274s (2.4 SD above mean), driven by an unusually slow Boot2->NodeReady (122s vs 88-96s typical). This suggests a one-off image pull delay.

## Normalized Phase Breakdown (Overall Mean)

| Phase | Duration | % of Total | Stdev |
|:---|---:|---:|---:|
| VM Provisioning | 20.5s | 8.3% | 2.3s |
| Boot 1 (Ignition + MCD firstboot) | 128.3s | 52.0% | 4.5s |
| Reboot | 5.4s | 2.2% | 1.6s |
| Boot 2: chrony-wait | 24.1s | 9.8% | 0.005s |
| Boot 2: Other systemd | 8.0s | 3.2% | 1.5s |
| Boot 2: Kubelet to NodeReady | 60.6s | 24.6% | 10.1s |
| **Total** | **246.7s** | **100%** | **11.3s** |

## Key Conclusions

1. **OCP 4.22 D4s_v5 averages 4m 07sec** — 47s (16%) faster than the 4.20 measurement (4m 54sec). Most of the improvement is in VM provisioning and MCD firstboot, which may be partially due to the different region (eastus vs eastus2).

2. **MCD firstboot is still the largest phase** at 128.3s (52%), but with dramatically lower variance (4.5s stdev) compared to 4.20 (38.3s stdev).

3. **chrony-wait remains a fixed 24.07s** — identical to 4.20 across all hardware and OCP versions.

4. **Run-to-run variance is much lower on this cluster** — 11.3s stdev vs 49.0s on 4.20. This could reflect regional infrastructure differences or generally less I/O contention.

5. **Zone 2 tends to be slightly slower** — mean 257s vs 241-242s for zones 1/3, driven by occasional Boot2->NodeReady spikes. With only 4 samples per zone, this is not statistically significant.

## Saved Artifacts

Per round/zone (r1-r4, z1-z3):
- `new-machine-4.22-d4s-v5-r{R}-z{Z}-final.yaml`
- `new-node-4.22-d4s-v5-r{R}-z{Z}.yaml`
- `node-journal-4.22-d4s-v5-r{R}-z{Z}.log`
- `node-boot-list-4.22-d4s-v5-r{R}-z{Z}.txt`
- `node-systemd-analyze-4.22-d4s-v5-r{R}-z{Z}.txt`
- `node-systemd-blame-4.22-d4s-v5-r{R}-z{Z}.txt`
- `node-systemd-critical-chain-4.22-d4s-v5-r{R}-z{Z}.txt`
- `node-images-4.22-d4s-v5-r{R}-z{Z}.txt`
- `machineset-4.22-d4s-v5-r{R}-z{Z}.json`
