# Node Scale-Up Time Analysis: Standard_D32s_v5 (Azure Zone 1)

## Cluster
- **Cluster**: ci-ln-ikkmv7b-1d09d (OpenShift 4.20, Kubernetes 1.33.9)
- **Region**: eastus2, Zone 1
- **VM Type**: Standard_D32s_v5 (32 vCPU, 128 GB RAM)
- **Machine**: ci-ln-ikkmv7b-1d09d-lh6ms-d32s-v5-z1-2wtmq
- **MachineSet**: ci-ln-ikkmv7b-1d09d-lh6ms-d32s-v5-z1

## Total Scale-Up Time: ~3 minutes 57 seconds (237s)
- MachineSet created: **00:33:32 UTC**
- Node Ready: **00:37:29 UTC**

## Phase Breakdown

| Phase | Start | End | Duration | Notes |
|-------|-------|-----|----------|-------|
| **Cloud VM Provisioning** | 00:33:32 | 00:34:01 | ~29s | MachineCreationSucceeded at 00:33:40, InstanceExists at 00:33:41 |
| **Boot 1: Ignition** | 00:34:01 | 00:34:12 | ~11s | Kernel, initrd, network, Ignition fetch + apply |
| **Boot 1: Pivot + MCD firstboot** | 00:34:12 | 00:35:52 | ~100s | Switch root (~5s), MCD pull (~12s), rpm-ostree rebase (~39s), ostree finalize (~8s) |
| **Reboot** | 00:35:52 | 00:36:04 | ~12s | Shutdown + POST + bootloader |
| **Boot 2: Kernel + initrd** | 00:36:04 | 00:36:13 | ~9s | Second boot init |
| **Boot 2: chrony-wait** | 00:36:13 | 00:36:37 | ~24s | PHC0 (Hyper-V PTP) refclock sync |
| **Boot 2: CRI-O + Kubelet start** | 00:36:37 | 00:36:38 | ~1s | CRI-O 858ms, kubelet 227ms |
| **Boot 2: Kubelet -> NodeReady** | 00:36:38 | 00:37:29 | ~51s | CSR approval <1s, CNI image pulls dominate |

## Time Spent Summary

| Category | Duration | % of Total |
|----------|----------|------------|
| Cloud VM Provisioning | ~29s | 12.2% |
| Boot 1: Ignition | ~11s | 4.6% |
| Boot 1: MCD Firstboot (rpm-ostree) | **~100s** | **42.2%** |
| Reboot (shutdown + POST) | ~12s | 5.1% |
| Boot 2: Kernel/initrd | ~9s | 3.8% |
| Boot 2: chrony-wait (NTP sync) | ~24s | 10.1% |
| Boot 2: CRI-O + Kubelet start | ~1s | 0.4% |
| Boot 2: Kubelet to NodeReady | **~51s** | **21.5%** |

## MCD Firstboot Details
- MCD image pull: 00:34:21 to 00:34:33 (~12s)
- MCD daemon init: 00:34:34 to 00:34:35 (~1s)
- rpm-ostree rebase: 00:35:07 to 00:35:46 (~39s)
- Second staging pass + kargs: 00:35:46 to 00:35:52 (~6s)
- ostree finalize staged: 00:35:53 to 00:36:01 (~8s)

## Boot List
```
IDX BOOT ID                          FIRST ENTRY                 LAST ENTRY
 -1 a97f51f9931c408590d22908e0355201 Tue 2026-04-21 00:34:01 UTC Tue 2026-04-21 00:36:01 UTC
  0 05271512ab6f4ac9b3cf9c3368d6d3ef Tue 2026-04-21 00:36:04 UTC Tue 2026-04-21 00:45:12 UTC
```

## systemd-analyze (Boot 2)
```
Startup finished in 799ms (kernel) + 3.105s (initrd) + 28.478s (userspace) = 32.384s
graphical.target reached after 28.125s in userspace.
```

## Top 10 systemd-analyze blame (Boot 2)

| Rank | Duration | Service |
|------|----------|---------|
| 1 | 24.056s | chrony-wait.service |
| 2 | 5.510s | ovs-configuration.service |
| 3 | 3.731s | sys-module-fuse.device |
| 4 | 3.630s | dev-ttyS3.device |
| 5 | 3.629s | dev-ttyS0.device |
| 6 | 3.621s | sys-module-configfs.device |
| 7 | 3.495s | dev-sda.device |
| 8 | 2.829s | mlx5_0 infiniband device |
| 9 | 2.256s | dev-loop0.device |
| 10 | 1.257s | systemd-udev-settle.service |

## Saved Artifacts
- `node-journal-d32s-v5-z1.log` — Full journal (all boots, 10,017 lines)
- `node-boot-list-d32s-v5-z1.txt` — Boot list
- `node-systemd-analyze-d32s-v5-z1.txt` — systemd-analyze output
- `node-systemd-blame-d32s-v5-z1.txt` — systemd-analyze blame
- `node-systemd-critical-chain-d32s-v5-z1.txt` — systemd critical chain
- `node-images-d32s-v5-z1.txt` — Container images on node
- `new-machine-d32s-v5-z1-final.yaml` — Machine object
- `new-node-d32s-v5-z1.yaml` — Node object
- `machineset-d32s-v5-z1.json` — MachineSet definition used
