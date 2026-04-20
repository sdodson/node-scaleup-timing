# Node Scale-Up Time Analysis: Standard_D4s_v3 (Azure)

## Cluster
- **Cluster**: ci-ln-rm0x8pk-1d09d (OpenShift 4.22, Kubernetes 1.35.3)
- **Region**: eastus2, Zone 1
- **VM Type**: Standard_D4s_v3 (4 vCPU, 16 GB RAM)
- **Machine**: ci-ln-rm0x8pk-1d09d-vkpbd-worker-eastus21-jdpdv
- **MachineSet**: ci-ln-rm0x8pk-1d09d-vkpbd-worker-eastus21

## Total Scale-Up Time: ~7 minutes 3 seconds
- Scale command issued: **19:34:39 UTC**
- Node Ready: **19:41:42 UTC**

## Phase Breakdown

| Phase | Start | End | Duration | Notes |
|-------|-------|-----|----------|-------|
| **MachineSet scale -> Machine created** | 19:34:39 | 19:34:39 | ~0s | Immediate |
| **Azure VM Provisioning** | 19:34:39 | 19:35:11 | ~32s | VM creating in Azure |
| **Boot 1: Kernel -> Ignition fetch-offline** | 19:35:11 | 19:35:15 | ~4s | Kernel + initrd |
| **Boot 1: Network setup (DHCP)** | 19:35:16 | 19:35:17 | ~1s | NetworkManager, eth0 DHCP |
| **Boot 1: Ignition fetch (from Azure IMDS)** | 19:35:17 | 19:35:18 | ~1s | Config from custom data / SR0 |
| **Boot 1: Ignition stages (kargs/disks/mount/files)** | 19:35:18 | 19:35:26 | ~8s | Write configs, systemd units |
| **Boot 1: Pivot to real root + first-boot services** | 19:35:26 | 19:35:40 | ~14s | ostree setup, sysroot transition |
| **Boot 1: MCD firstboot provisioning** | 19:35:40 | 19:38:24 | ~2m44s | machine-config-daemon applying rendered config, rpm-ostree layering, **LARGEST PHASE** |
| **Boot 1: Reboot initiated** | 19:38:24 | 19:38:50 | ~26s | Shutdown + BIOS/bootloader |
| **Boot 2: Kernel + initrd + sysroot** | 19:38:50 | 19:39:02 | ~12s | Second boot, faster (no ignition) |
| **Boot 2: chrony-wait** | 19:39:02 | 19:39:27 | ~24s | Waiting for NTP time sync |
| **Boot 2: OVS configuration** | 19:39:04 | 19:39:18 | ~14s | Open vSwitch setup (parallel with chrony) |
| **Boot 2: CRI-O start** | 19:39:27 | 19:39:28 | ~1s | Container runtime |
| **Boot 2: Kubelet start** | 19:39:28 | 19:39:28 | <1s | Kubelet process started |
| **Boot 2: Kubelet -> NodeReady** | 19:39:28 | 19:41:42 | ~2m14s | CSR approval, CNI setup, node registration |

## Time Spent Summary

| Category | Duration | % of Total |
|----------|----------|------------|
| Azure VM Provisioning | ~32s | 8% |
| Boot 1: Ignition + OS Setup | ~29s | 7% |
| Boot 1: MCD Firstboot (rpm-ostree) | **~2m44s** | **39%** |
| Reboot (shutdown + POST) | ~26s | 6% |
| Boot 2: Kernel/initrd/sysroot | ~12s | 3% |
| Boot 2: chrony-wait (NTP sync) | ~24s | 6% |
| Boot 2: OVS configuration | ~14s | 3% |
| Boot 2: CRI-O + Kubelet start | ~1s | <1% |
| Boot 2: Kubelet to NodeReady | **~2m14s** | **31%** |

## Key Observations

1. **MCD firstboot provisioning is the single largest phase (~2m44s, 39%)**. This includes
   machine-config-daemon applying the rendered worker config, running rpm-ostree operations,
   and preparing for the mandatory reboot.

2. **Kubelet to NodeReady takes ~2m14s (31%)**. This time is spent on:
   - CSR generation and approval (~30s from kubelet start to CSR issued at 19:39:59)
   - CNI/network plugin readiness
   - Node condition reporting cycle (kubelet logs "Node not becoming ready in time" at 19:41:28)
   - NodeReady finally recorded at 19:41:42

3. **chrony-wait adds ~24s** waiting for NTP time synchronization. This blocks CRI-O and
   kubelet from starting (it's on the critical path via kubelet-dependencies.target).

4. **Azure VM provisioning is relatively fast at ~32s** — the cloud infrastructure is not the
   bottleneck.

5. **The node reboots once** after MCD firstboot provisioning (applying the rendered-worker config).

## Boot List
```
IDX  BOOT ID                           FIRST ENTRY                  LAST ENTRY
 -1  f39b2ea681954313a423214ca516c47e   2026-04-17 19:35:11 UTC      2026-04-17 19:38:37 UTC
  0  9c106b0d86f2402ea58a1bb012b97849   2026-04-17 19:38:50 UTC      2026-04-17 19:42:38 UTC
```

## systemd-analyze (Boot 2)
```
Startup finished in 2.065s (kernel) + 7.013s (initrd) + 31.849s (userspace) = 40.928s
graphical.target reached after 31.649s in userspace.
```

## systemd-analyze critical-chain (Boot 2)
```
graphical.target @31.649s
└─multi-user.target @31.649s
  └─kubelet.service @31.167s +480ms
    └─crio.service @30.198s +953ms
      └─kubelet-dependencies.target @30.182s
        └─chrony-wait.service @6.050s +24.131s
          └─chronyd.service @5.894s +124ms
```

## Saved Artifacts
- `node-journal-d4s-v3.log` — Full journal (all boots, 10,491 lines)
- `node-boot-list-d4s-v3.txt` — Boot list
- `node-systemd-analyze-d4s-v3.txt` — systemd-analyze output
- `node-systemd-blame-d4s-v3.txt` — systemd-analyze blame
- `node-systemd-critical-chain-d4s-v3.txt` — systemd critical chain
- `new-machine-initial.yaml` — Machine object at creation
- `new-machine-final.yaml` — Machine object when Running
- `new-node.yaml` — Node object
- `machine-api-events.txt` — Machine API events
- `csr-list-d4s-v3.txt` — CSR list
