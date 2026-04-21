# Node Scale-Up Time Analysis: Standard_D32s_v5 (Azure Zone 3)

## Cluster
- **Cluster**: ci-ln-ikkmv7b-1d09d (OpenShift 4.20, Kubernetes 1.33.9)
- **Region**: eastus2, Zone 3
- **VM Type**: Standard_D32s_v5 (32 vCPU, 128 GB RAM)
- **Machine**: ci-ln-ikkmv7b-1d09d-lh6ms-d32s-v5-z3-8gmzx
- **MachineSet**: ci-ln-ikkmv7b-1d09d-lh6ms-d32s-v5-z3

## Total Scale-Up Time: ~5 minutes 28 seconds (328s)
- MachineSet created: **00:33:32 UTC**
- Node Ready: **00:39:00 UTC**

## Phase Breakdown

| Phase | Start | End | Duration | Notes |
|-------|-------|-----|----------|-------|
| **Cloud VM Provisioning** | 00:33:32 | 00:34:23 | ~51s | MachineCreationSucceeded at 00:33:41, InstanceExists at 00:33:42 |
| **Boot 1: Ignition** | 00:34:23 | 00:34:35 | ~12s | Kernel, initrd, Ignition fetch + apply |
| **Boot 1: Pivot to real root** | 00:34:35 | 00:34:50 | ~15s | Switch root, systemd reinit |
| **Boot 1: MCD firstboot** | 00:35:06 | 00:37:15 | ~129s | MCD pull (~16s), machine-os pull (~41s), rpm-ostree rebase (~54s), finalize (~10s) |
| **Reboot** | 00:37:15 | 00:37:41 | ~26s | ostree finalize during shutdown + POST + bootloader |
| **Boot 2: Kernel + initrd + pivot** | 00:37:41 | 00:37:47 | ~6s | Second boot init |
| **Boot 2: chrony-wait** | 00:37:47 | 00:38:11 | ~24s | PHC0 (Hyper-V PTP) refclock sync |
| **Boot 2: CRI-O + Kubelet start** | 00:38:11 | 00:38:13 | ~2s | CRI-O 1.807s, kubelet 199ms |
| **Boot 2: Kubelet -> NodeReady** | 00:38:13 | 00:39:00 | ~47s | CSR approval <1s, CNI image pulls dominate |

## Time Spent Summary

| Category | Duration | % of Total |
|----------|----------|------------|
| Cloud VM Provisioning | ~51s | 15.5% |
| Boot 1: Ignition | ~12s | 3.7% |
| Boot 1: Pivot to real root | ~15s | 4.6% |
| Boot 1: MCD Firstboot (rpm-ostree) | **~129s** | **39.3%** |
| Reboot (shutdown + POST) | ~26s | 7.9% |
| Boot 2: Kernel/initrd | ~6s | 1.8% |
| Boot 2: chrony-wait (NTP sync) | ~24s | 7.3% |
| Boot 2: CRI-O + Kubelet start | ~2s | 0.6% |
| Boot 2: Kubelet to NodeReady | **~47s** | **14.3%** |
| Gap: real root init to MCD start | ~16s | 4.9% |

## MCD Firstboot Details
- MCD image pull: 00:35:06 to 00:35:22 (~16s)
- Machine-os-content image pull (podman): 00:35:23 to 00:36:04 (~41s)
- rpm-ostree rebase: 00:36:11 to 00:37:05 (~54s)
- ostree finalize + kernel args: 00:37:05 to 00:37:15 (~10s)
- rpm-ostreed consumed 28.758s CPU time
- machine-config-daemon-pull consumed 21.112s CPU time
- ostree finalize-staged ran during shutdown: 00:37:16 to 00:37:35 (~19s)

## Boot List
```
IDX BOOT ID                          FIRST ENTRY                 LAST ENTRY
 -1 9ef8cb4e090345e69f66b26bf7a0aa44 Tue 2026-04-21 00:34:23 UTC Tue 2026-04-21 00:37:35 UTC
  0 50758c99d66144748c388ae40bfc4f08 Tue 2026-04-21 00:37:41 UTC Tue 2026-04-21 00:46:10 UTC
```

## systemd-analyze (Boot 2)
```
Startup finished in 938ms (kernel) + 3.391s (initrd) + 30.145s (userspace) = 34.474s
graphical.target reached after 29.202s in userspace.
```

## Top 10 systemd-analyze blame (Boot 2)

| Rank | Duration | Service |
|------|----------|---------|
| 1 | 24.063s | chrony-wait.service |
| 2 | 3.706s | sys-module-fuse.device |
| 3 | 3.619s | dev-ttyS3.device |
| 4 | 3.618s | dev-ttyS1.device |
| 5 | 3.605s | dev-ttyS2.device |
| 6 | 3.604s | dev-ttyS0.device |
| 7 | 3.603s | sys-module-configfs.device |
| 8 | 3.436s | dev-sda.device |
| 9 | 2.671s | ovs-configuration.service |
| 10 | 1.807s | crio.service |

## Saved Artifacts
- `node-journal-d32s-v5-z3.log` — Full journal (all boots, 10,047 lines)
- `node-boot-list-d32s-v5-z3.txt` — Boot list
- `node-systemd-analyze-d32s-v5-z3.txt` — systemd-analyze output
- `node-systemd-blame-d32s-v5-z3.txt` — systemd-analyze blame
- `node-systemd-critical-chain-d32s-v5-z3.txt` — systemd critical chain
- `node-images-d32s-v5-z3.txt` — Container images on node
- `new-machine-d32s-v5-z3-final.yaml` — Machine object
- `new-node-d32s-v5-z3.yaml` — Node object
- `machineset-d32s-v5-z3.json` — MachineSet definition used
