# Node Scale-Up Time Analysis: Standard_D32s_v5 (Azure Zone 2)

## Cluster
- **Cluster**: ci-ln-ikkmv7b-1d09d (OpenShift 4.20, Kubernetes 1.33.9)
- **Region**: eastus2, Zone 2
- **VM Type**: Standard_D32s_v5 (32 vCPU, 128 GB RAM)
- **Machine**: ci-ln-ikkmv7b-1d09d-lh6ms-d32s-v5-z2-bwzs9
- **MachineSet**: ci-ln-ikkmv7b-1d09d-lh6ms-d32s-v5-z2

## Total Scale-Up Time: ~5 minutes 26 seconds (326s)
- MachineSet created: **00:33:32 UTC**
- Node Ready: **00:38:58 UTC**

## Phase Breakdown

| Phase | Start | End | Duration | Notes |
|-------|-------|-----|----------|-------|
| **Cloud VM Provisioning** | 00:33:32 | 00:34:20 | ~48s | MachineCreationSucceeded at 00:33:40, InstanceExists at 00:33:41 |
| **Boot 1: Ignition** | 00:34:20 | 00:34:39 | ~19s | Kernel, initrd, Ignition fetch + apply, disk UUID regen (~9s) |
| **Boot 1: Pivot to real root** | 00:34:39 | 00:35:05 | ~26s | Switch root, systemd reinit, ldconfig (~8s) |
| **Boot 1: MCD firstboot** | 00:35:06 | 00:37:27 | ~141s | MCD pull (~15s), rpm-ostree rebase, ostree finalize (~24s) |
| **Reboot** | 00:37:27 | 00:37:32 | ~5s | Shutdown + POST + bootloader |
| **Boot 2: Kernel + initrd + pivot** | 00:37:32 | 00:37:41 | ~9s | Second boot init |
| **Boot 2: chrony-wait** | 00:37:41 | 00:38:05 | ~24s | PHC0 (Hyper-V PTP) refclock sync |
| **Boot 2: CRI-O + Kubelet start** | 00:38:05 | 00:38:07 | ~2s | CRI-O 2.277s, kubelet 342ms |
| **Boot 2: Kubelet -> NodeReady** | 00:38:07 | 00:38:58 | ~51s | CSR approval <1s, CNI image pulls dominate |

## Time Spent Summary

| Category | Duration | % of Total |
|----------|----------|------------|
| Cloud VM Provisioning | ~48s | 14.7% |
| Boot 1: Ignition | ~19s | 5.8% |
| Boot 1: Pivot to real root | ~26s | 8.0% |
| Boot 1: MCD Firstboot (rpm-ostree) | **~141s** | **43.3%** |
| Reboot (shutdown + POST) | ~5s | 1.5% |
| Boot 2: Kernel/initrd | ~9s | 2.8% |
| Boot 2: chrony-wait (NTP sync) | ~24s | 7.4% |
| Boot 2: CRI-O + Kubelet start | ~2s | 0.6% |
| Boot 2: Kubelet to NodeReady | **~51s** | **15.6%** |

## MCD Firstboot Details
- MCD image pull: 00:35:06 to 00:35:21 (~15s)
- MCD firstboot / rpm-ostree rebase: 00:35:21 to 00:37:03 (~102s)
- ostree finalize staged + SELinux + bootloader: 00:37:03 to 00:37:27 (~24s)
- rpm-ostreed consumed 28.1s CPU time
- machine-config-daemon-pull consumed 17.6s CPU time

## Boot List
```
IDX BOOT ID                          FIRST ENTRY                 LAST ENTRY
 -1 2ee45461422e46bba0e34af7da17ecbe Tue 2026-04-21 00:34:20 UTC Tue 2026-04-21 00:37:27 UTC
  0 3ec80aea0b694d34b64c8cd679e91295 Tue 2026-04-21 00:37:32 UTC Tue 2026-04-21 00:45:47 UTC
```

## systemd-analyze (Boot 2)
```
Startup finished in 803ms (kernel) + 3.200s (initrd) + 29.919s (userspace) = 33.924s
graphical.target reached after 29.835s in userspace.
```

## Top 10 systemd-analyze blame (Boot 2)

| Rank | Duration | Service |
|------|----------|---------|
| 1 | 24.059s | chrony-wait.service |
| 2 | 3.855s | sys-module-fuse.device |
| 3 | 3.759s | dev-ttyS2.device |
| 4 | 3.758s | dev-ttyS0.device |
| 5 | 3.758s | dev-ttyS3.device |
| 6 | 3.746s | dev-ttyS1.device |
| 7 | 3.737s | sys-module-configfs.device |
| 8 | 3.594s | dev-sda.device |
| 9 | 3.566s | sys-subsystem-net-devices-eth0.device |
| 10 | 2.968s | sys-subsystem-net-devices-enP22310s1.device |

## Saved Artifacts
- `node-journal-d32s-v5-z2.log` — Full journal (all boots, 10,045 lines)
- `node-boot-list-d32s-v5-z2.txt` — Boot list
- `node-systemd-analyze-d32s-v5-z2.txt` — systemd-analyze output
- `node-systemd-blame-d32s-v5-z2.txt` — systemd-analyze blame
- `node-systemd-critical-chain-d32s-v5-z2.txt` — systemd critical chain
- `node-images-d32s-v5-z2.txt` — Container images on node
- `new-machine-d32s-v5-z2-final.yaml` — Machine object
- `new-node-d32s-v5-z2.yaml` — Node object
- `machineset-d32s-v5-z2.json` — MachineSet definition used
