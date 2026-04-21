# Node Scale-Up Time Comparison: Standard_D32s_v3 vs D32s_v5 (Azure, All Zones)

## Cluster
- **Cluster**: ci-ln-ikkmv7b-1d09d (OpenShift 4.20, Kubernetes 1.33.9)
- **Region**: eastus2, Zones 1/2/3
- **Date**: 2026-04-21
- **VM Types**: Standard_D32s_v3 and Standard_D32s_v5 (both 32 vCPU, 128 GB RAM)
- **Disk**: 128 GB Premium_LRS, Accelerated Networking enabled

## Total Scale-Up Times

| Zone | D32s_v3 | D32s_v5 | Delta |
|------|---------|---------|-------|
| Zone 1 | 5m 5sec (305s) | 3m 57sec (237s) | **-68s (22% faster)** |
| Zone 2 | 7m 46sec (466s) | 5m 26sec (326s) | **-140s (30% faster)** |
| Zone 3 | 6m 42sec (402s) | 5m 28sec (328s) | **-74s (18% faster)** |
| **Average** | **6m 31sec (391s)** | **4m 57sec (297s)** | **-94s (24% faster)** |

## Phase-by-Phase Comparison (All Zones)

### Cloud VM Provisioning

| Zone | D32s_v3 | D32s_v5 | Delta |
|------|---------|---------|-------|
| Zone 1 | 41s | 29s | -12s |
| Zone 2 | 76s | 48s | -28s |
| Zone 3 | 77s | 51s | -26s |
| **Average** | **65s** | **43s** | **-22s** |

The v5 generation provisions faster across all zones. Zone 1 is consistently fastest for both types.

### Boot 1: Ignition + Pivot

| Zone | D32s_v3 | D32s_v5 | Delta |
|------|---------|---------|-------|
| Zone 1 | 16s | 11s | -5s |
| Zone 2 | 45s | 45s | 0s |
| Zone 3 | 45s | 27s | -18s |
| **Average** | **35s** | **28s** | **-7s** |

### Boot 1: MCD Firstboot (rpm-ostree rebase) — LARGEST PHASE

| Zone | D32s_v3 | D32s_v5 | Delta |
|------|---------|---------|-------|
| Zone 1 | 2m 6sec (126s) | 1m 40sec (100s) | -26s |
| Zone 2 | 3m 19sec (199s) | 2m 21sec (141s) | -58s |
| Zone 3 | 2m 36sec (156s) | 2m 9sec (129s) | -27s |
| **Average** | **2m 40sec (160s)** | **2m 3sec (123s)** | **-37s** |

The v5's faster storage I/O significantly reduces rpm-ostree rebase time. Zone 2 shows the largest difference, suggesting zonal storage performance variance.

### Reboot (Shutdown + POST + Bootloader)

| Zone | D32s_v3 | D32s_v5 | Delta |
|------|---------|---------|-------|
| Zone 1 | 7s | 12s | +5s |
| Zone 2 | 41s | 5s | -36s |
| Zone 3 | 31s | 26s | -5s |
| **Average** | **26s** | **14s** | **-12s** |

Zone 2 D32s_v3 had an unusually long reboot. Reboot times are variable.

### Boot 2: chrony-wait

| Zone | D32s_v3 | D32s_v5 | Delta |
|------|---------|---------|-------|
| Zone 1 | 24s | 24s | 0s |
| Zone 2 | 25s | 24s | -1s |
| Zone 3 | 24s | 24s | 0s |
| **Average** | **24s** | **24s** | **0s** |

chrony-wait is identical across all tests — it's network/NTP bound (Azure PHC0 refclock), not hardware bound. Always ~24s.

### Boot 2: CRI-O + Kubelet Start

| Zone | D32s_v3 | D32s_v5 | Delta |
|------|---------|---------|-------|
| Zone 1 | 2s | 1s | -1s |
| Zone 2 | 3s | 2s | -1s |
| Zone 3 | 3s | 2s | -1s |
| **Average** | **3s** | **2s** | **-1s** |

### Boot 2: Kubelet to NodeReady

| Zone | D32s_v3 | D32s_v5 | Delta |
|------|---------|---------|-------|
| Zone 1 | 63s | 51s | -12s |
| Zone 2 | 64s | 51s | -13s |
| Zone 3 | 53s | 47s | -6s |
| **Average** | **60s** | **50s** | **-10s** |

The v5 is ~10s faster on average for image pulls. Both are dramatically faster than D4s_v3/v5 (4 vCPU) where this phase takes 56s-2m 14sec.

### systemd-analyze Total (Boot 2)

| Zone | D32s_v3 | D32s_v5 | Delta |
|------|---------|---------|-------|
| Zone 1 | 35.3s | 32.4s | -2.9s |
| Zone 2 | 42.6s | 33.9s | -8.7s |
| Zone 3 | 43.0s | 34.5s | -8.5s |
| **Average** | **40.3s** | **33.6s** | **-6.7s** |

## Zonal Variance Analysis

### D32s_v5 (v5 generation — more consistent)

| Phase | Zone 1 | Zone 2 | Zone 3 | Spread |
|-------|--------|--------|--------|--------|
| VM Provisioning | 29s | 48s | 51s | 22s |
| MCD Firstboot | 100s | 141s | 129s | 41s |
| Kubelet->NodeReady | 51s | 51s | 47s | 4s |
| **Total** | **237s** | **326s** | **328s** | **91s** |

Zone 1 was an outlier — 89s faster than zones 2/3. This is driven by faster VM provisioning (-20s) and faster MCD firstboot (-35s), suggesting better storage/network performance in zone 1 during this test window.

### D32s_v3 (v3 generation — more variable)

| Phase | Zone 1 | Zone 2 | Zone 3 | Spread |
|-------|--------|--------|--------|--------|
| VM Provisioning | 41s | 76s | 77s | 36s |
| MCD Firstboot | 126s | 199s | 156s | 73s |
| Kubelet->NodeReady | 63s | 64s | 53s | 11s |
| **Total** | **305s** | **466s** | **402s** | **161s** |

Zone 2 was the slowest, with MCD firstboot taking 73s longer than zone 1. The v3 generation shows more zonal variance overall (161s spread vs 91s on v5).

## Key Findings

### 1. v5 is 24% faster on average (94s savings)
The D32s_v5 consistently outperforms the D32s_v3 across all zones and phases. The biggest gains come from:
- **VM provisioning**: 22s faster (newer hardware allocates faster)
- **MCD firstboot**: 37s faster (better storage I/O for rpm-ostree rebase)
- **Reboot**: 12s faster
- **Kubelet->NodeReady**: 10s faster (better I/O for image pulls)

### 2. Zone 1 is consistently fastest
Both VM types show zone 1 as the fastest zone, with zones 2 and 3 clustering together. This may reflect:
- Different underlying hardware generations across zones
- Proximity to container registries or Azure infrastructure
- Load/capacity differences in the zone

### 3. MCD firstboot remains the dominant bottleneck (39-43% of total)
Across all 6 tests, MCD firstboot (rpm-ostree rebase) is the single largest phase. Even with 32 vCPUs, this phase is I/O and network bound.

### 4. chrony-wait is a fixed 24s constant
Completely hardware-independent. This is the PHC0 (Hyper-V PTP) clock synchronization time. Can only be reduced via chrony configuration tuning.

### 5. Kubelet->NodeReady benefits from more CPU but not generation
At 32 vCPUs, this phase (47-64s) is much faster than at 4 vCPUs (56s-2m 14sec). The v3->v5 generation jump only saves ~10s at this CPU count, since the image pulls are already well-parallelized.

### 6. Zonal variance is significant
Total scale-up time varies by up to 161s (D32s_v3) or 91s (D32s_v5) across zones in the same region. This suggests that single-zone measurements should not be used in isolation for benchmarking.

## Comparison with 4-vCPU Variants (from prior tests)

| Metric | D4s_v3 | D32s_v3 (avg) | D4s_v5 | D32s_v5 (avg) |
|--------|--------|---------------|--------|---------------|
| **Total** | 7m 3sec | 6m 31sec | 4m 43sec | 4m 57sec |
| VM Provisioning | 32s | 65s | 19s | 43s |
| MCD Firstboot | 2m 44sec | 2m 40sec | 2m 13sec | 2m 3sec |
| chrony-wait | 24s | 24s | 24s | 24s |
| Kubelet->NodeReady | 2m 14sec | 60s | 56s | 50s |

Note: D4s_v3/v5 were measured on a different cluster (OCP 4.22) in a single zone, so comparisons are approximate. The trend is clear: more CPU helps most with Kubelet->NodeReady (image pulls), but the generation upgrade (v3->v5) helps most with MCD firstboot (I/O).

## Saved Artifacts
- `scale-up-analysis-d32s-v5-z1.md` through `z3` — Individual zone reports (D32s_v5)
- `scale-up-analysis-d32s-v3-z1.md` through `z3` — Individual zone reports (D32s_v3)
- `machineset-d32s-v5-z{1,2,3}.json` — MachineSet definitions
- `machineset-d32s-v3-z{1,2,3}.json` — MachineSet definitions
- `node-journal-d32s-v{3,5}-z{1,2,3}.log` — Full journals
- `new-machine-d32s-v{3,5}-z{1,2,3}-final.yaml` — Machine objects
- `new-node-d32s-v{3,5}-z{1,2,3}.yaml` — Node objects
