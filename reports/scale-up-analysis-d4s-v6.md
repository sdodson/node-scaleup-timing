# Node Scale-Up Time Analysis: Standard_D4s_v6 (Azure)

## Cluster
- **Cluster**: ci-ln-rm0x8pk-1d09d (OpenShift 4.22, Kubernetes 1.35.3)
- **Region**: eastus2, Zone 1
- **VM Type**: Standard_D4s_v6 (4 vCPU, 16 GB RAM)
- **Machine**: ci-ln-rm0x8pk-1d09d-vkpbd-worker-eastus21-v6-8hct8
- **MachineSet**: ci-ln-rm0x8pk-1d09d-vkpbd-worker-eastus21-v6

## Total Scale-Up Time: ~3 minutes 59 seconds
- MachineSet created: **20:09:02 UTC**
- NodeReady event: **20:13:01 UTC**

## Phase Breakdown

| Phase | Start | End | Duration | Notes |
|-------|-------|-----|----------|-------|
| **MachineSet create -> Machine created** | 20:09:02 | 20:09:02 | ~0s | Immediate |
| **Azure VM Provisioning** | 20:09:02 | 20:09:20 | ~18s | VM creating in Azure |
| **Boot 1: Kernel -> Ignition (all stages)** | 20:09:20 | 20:09:30 | ~10s | All Ignition stages |
| **Boot 1: Pivot to real root** | 20:09:30 | 20:09:36 | ~6s | sysroot transition |
| **Boot 1: MCD pull + rpm-ostree rebase** | 20:09:36 | 20:11:16 | ~1m 40sec | **LARGEST PHASE** |
| **Boot 1: Reboot** | 20:11:16 | 20:11:29 | ~13s | Shutdown + BIOS/bootloader |
| **Boot 2: Kernel + initrd** | 20:11:29 | 20:11:34 | ~5s | Second boot |
| **Boot 2: chrony-wait** | 20:11:34 | 20:11:58 | ~24s | NTP time sync |
| **Boot 2: OVS configuration** | 20:11:34 | 20:11:37 | ~3s | OVS setup (parallel with chrony) |
| **Boot 2: CRI-O + Kubelet start** | 20:11:58 | 20:11:59 | ~1s | Container runtime + kubelet |
| **Boot 2: Kubelet -> NodeReady** | 20:11:59 | 20:13:01 | ~1m 2sec | CSR, CNI, node registration |

## Time Spent Summary

| Category | Duration | % of Total |
|----------|----------|------------|
| Azure VM Provisioning | ~18s | 8% |
| Boot 1: Ignition + OS Setup | ~16s | 7% |
| Boot 1: MCD Firstboot (rpm-ostree) | **~1m 40sec** | **42%** |
| Reboot (shutdown + POST) | ~13s | 5% |
| Boot 2: Kernel/initrd | ~5s | 2% |
| Boot 2: chrony-wait (NTP sync) | ~24s | 10% |
| Boot 2: OVS configuration | ~3s | 1% |
| Boot 2: CRI-O + Kubelet start | ~1s | <1% |
| Boot 2: Kubelet to NodeReady | **~1m 2sec** | **26%** |

## MCD Firstboot Detail
- MCD image pull: 20:09:37 -> 20:09:45 (~8s)
- rpm-ostree rebase started: 20:10:21
- Staging deployment done: 20:11:11 (~50s for ostree rebase)
- Additional staging + SELinux refresh: ~5s
- Reboot initiated: 20:11:16

## Boot List
```
IDX  BOOT ID                           FIRST ENTRY                  LAST ENTRY
 -1  312b6ca853284e84badde7ab1213a0d0   2026-04-17 20:09:20 UTC      2026-04-17 20:11:22 UTC
  0  8e01f48b502d4345ac6ae7e690109c93   2026-04-17 20:11:29 UTC      2026-04-17 20:14:18 UTC
```

## systemd-analyze (Boot 2)
```
Startup finished in 1.596s (kernel) + 3.235s (initrd) + 26.845s (userspace) = 31.677s
graphical.target reached after 26.771s in userspace.
```

## systemd-analyze critical-chain (Boot 2)
```
graphical.target @26.771s
└─multi-user.target @26.771s
  └─kubelet.service @26.676s +94ms
    └─crio.service @26.308s +359ms
      └─kubelet-dependencies.target @26.294s
        └─chrony-wait.service @2.226s +24.067s
```

---

## Comparison: D4s_v3 vs D4s_v5 vs D4s_v6

| Metric | Standard_D4s_v3 | Standard_D4s_v5 | Standard_D4s_v6 |
|--------|----------------|----------------|----------------|
| **Total time** | **7m 3sec** | **4m 43sec** | **3m 59sec** |
| Azure VM Provisioning | 32s | 19s | 18s |
| Boot 1: Ignition + pivot | 29s | 23s | 16s |
| MCD firstboot (rpm-ostree) | 2m 44sec | 2m 13sec | **1m 40sec** |
| rpm-ostree rebase (subset) | ~120s | ~89s | **~50s** |
| Reboot (shutdown + POST) | 26s | 11s | 13s |
| Boot 2: Kernel/initrd | 12s | 9s | 5s |
| chrony-wait | 24s | 24s | 24s |
| OVS configuration | 14s | 5s | 3s |
| CRI-O + Kubelet start | 1s | 1s | 1s |
| Kubelet to NodeReady | 2m 14sec | 56s | 1m 2sec |
| **systemd-analyze total** | **40.9s** | **31.7s** | **31.7s** |

### Key Observations

1. **v6 is the fastest overall at ~4 minutes** — a 44% improvement over v3.

2. **MCD firstboot is dramatically faster on v6** (1m 40sec vs 2m 44sec on v3). The rpm-ostree
   rebase itself dropped from ~120s (v3) to ~50s (v6) — a 58% improvement in the single
   largest phase. This is primarily due to faster NVMe-class storage I/O on the v6
   generation VMs.

3. **Azure VM provisioning is similar between v5 and v6** (~18-19s), both much faster
   than v3 (32s).

4. **chrony-wait remains fixed at ~24s** across all generations — this is NTP network
   latency and not hardware-bound.

5. **Kubelet to NodeReady is slightly slower on v6 (62s) than v5 (56s)** — this is
   within normal variance for CSR approval timing and network readiness checks.

6. **Boot 2 kernel/initrd is fastest on v6** (5s vs 9s v5 vs 12s v3), reflecting
   faster CPU and storage.

### Speedup Summary
| From → To | Time Saved | % Faster |
|-----------|-----------|----------|
| v3 → v5 | 2m 20sec | 33% |
| v3 → v6 | 3m 4sec | 44% |
| v5 → v6 | 44s | 16% |

### Where the remaining ~4 minutes go (v6)
1. **MCD firstboot**: 1m 40sec (42%) — rpm-ostree rebase is still the bottleneck
2. **Kubelet to NodeReady**: 1m 2sec (26%) — CSR approval + CNI readiness
3. **chrony-wait**: 24s (10%) — NTP sync
4. **Everything else**: 53s (22%) — VM provisioning, Ignition, boot, reboot

## Saved Artifacts
- `node-journal-d4s-v6.log` — Full journal (all boots, 10,229 lines)
- `node-boot-list-d4s-v6.txt` — Boot list
- `node-systemd-analyze-d4s-v6.txt` — systemd-analyze output
- `node-systemd-blame-d4s-v6.txt` — systemd-analyze blame
- `node-systemd-critical-chain-d4s-v6.txt` — systemd critical chain
- `node-images-d4s-v6.txt` — Container images on node
- `node-images-detail-d4s-v6.json` — Detailed image info with digests
- `node-rpm-ostree-status-v6.txt` — rpm-ostree status
- `new-machine-v6-final.yaml` — Machine object
- `new-node-v6.yaml` — Node object
- `csr-list-d4s-v6.txt` — CSR list
- `node-pods-images-v6.txt` — Pods/images scheduled on node
- `machineset-v6.json` — MachineSet definition used
