# Node Scale-Up Time Analysis: Standard_D32s_v3 (Azure, Zone 2)

## Cluster
- **Cluster**: ci-ln-ikkmv7b-1d09d-lh6ms (OpenShift 4.20, Kubernetes 1.33.9)
- **Region**: eastus2, Zone 2
- **VM Type**: Standard_D32s_v3 (32 vCPU, 128 GB RAM)
- **Disk**: 128 GB Premium_LRS, Accelerated Networking enabled
- **Machine**: ci-ln-ikkmv7b-1d09d-lh6ms-d32s-v3-z2-7qx66
- **MachineSet**: ci-ln-ikkmv7b-1d09d-lh6ms-d32s-v3-z2
- **OS Image**: RHCOS 9.6.20260414-0 (Plow), kernel 5.14.0-570.107.1.el9_6.x86_64

## Total Scale-Up Time: ~7 minutes 46 seconds
- Machine created: **00:48:27 UTC**
- Node Ready: **00:56:13 UTC**

## Phase Breakdown

| Phase | Start | End | Duration | Notes |
|-------|-------|-----|----------|-------|
| **Azure VM Provisioning** | 00:48:27 | 00:49:43 | **~76s** | Machine created -> first kernel boot |
| **Boot 1: Kernel + initrd + network** | 00:49:43 | 00:49:49 | ~6s | Kernel, initrd, DHCP, dracut |
| **Boot 1: Ignition fetch (Azure IMDS)** | 00:49:49 | 00:49:50 | ~1s | Config from IMDS userData + CD-ROM |
| **Boot 1: Ignition stages (kargs/disks/mount/files)** | 00:49:50 | 00:50:03 | ~13s | Disk ops, grow rootfs, write configs |
| **Boot 1: Pivot to real root** | 00:50:05 | 00:50:17 | ~12s | Switch root, sysroot transition |
| **Boot 1: First-boot services + networking** | 00:50:17 | 00:50:30 | ~13s | Systemd init, NetworkManager, OVS |
| **Boot 1: MCD pull** | 00:50:30 | 00:50:53 | ~23s | Pull MCD container image |
| **Boot 1: MCD firstboot (rpm-ostree rebase)** | 00:50:53 | 00:53:49 | **~2m 56sec** | rpm-ostree rebase + kargs + staged deployment, **LARGEST PHASE** |
| **Reboot (shutdown + POST + bootloader)** | 00:53:49 | 00:54:30 | ~41s | Shutdown services, OSTree finalize, kernel boot |
| **Boot 2: Kernel + initrd + switch root** | 00:54:30 | 00:54:37 | ~7s | Second boot initrd + sysroot pivot |
| **Boot 2: Userspace init -> chrony start** | 00:54:37 | 00:54:41 | ~4s | Basic system services |
| **Boot 2: chrony-wait** | 00:54:41 | 00:55:06 | **~25s** | PHC0 refclock sync (Azure Hyper-V TSC) |
| **Boot 2: CRI-O start** | 00:55:06 | 00:55:08 | ~2s | Container runtime |
| **Boot 2: Kubelet start + registration** | 00:55:08 | 00:55:09 | ~1s | Kubelet process, node registered |
| **Boot 2: Kubelet -> NodeReady** | 00:55:09 | 00:56:13 | **~64s** | CSR approval, CNI, OVN, pod scheduling |

## Time Spent Summary

| Category | Duration | % of Total |
|----------|----------|------------|
| Azure VM Provisioning | ~76s | 16% |
| Boot 1: Ignition + OS Setup | ~45s | 10% |
| Boot 1: MCD Firstboot (pull + rpm-ostree) | **~3m 19sec** | **43%** |
| Reboot (shutdown + POST) | ~41s | 9% |
| Boot 2: Kernel/initrd/sysroot | ~11s | 2% |
| Boot 2: chrony-wait (NTP sync) | ~25s | 5% |
| Boot 2: CRI-O + Kubelet start | ~3s | <1% |
| Boot 2: Kubelet to NodeReady | **~64s** | **14%** |

## Detailed Phase Timestamps

### Phase 1: Cloud VM Provisioning (76s)
- **00:48:27** Machine object created (creationTimestamp)
- **00:48:35** Azure VM creation succeeded (MachineCreated condition)
- **00:48:37** InstanceExists condition set
- **00:49:43** First kernel boot log entry (boot -1 starts)

### Phase 2: Boot 1 - Ignition (00:49:43 -> 00:50:06)
- **00:49:43** Kernel boot (5.14.0-570.92.1.el9_6.x86_64, firstboot kernel)
- **00:49:44** systemd targets reached, udevd started
- **00:49:47** Local file systems ready, Basic System reached
- **00:49:48** Ignition fetch-offline completed
- **00:49:49** Network up (DHCP on eth0), Ignition (fetch) started
- **00:49:50** Ignition (fetch) finished - config from Azure IMDS/CD-ROM
- **00:49:50** Ignition (kargs) finished, Ignition (disks) finished
- **00:49:55** Ignition OSTree: Grow Root Filesystem finished
- **00:50:00** Ignition (mount) finished, root filesystem check
- **00:50:02** Ignition (files) started
- **00:50:03** Ignition (files) finished - all configs/units written
- **00:50:04** Ignition Boot Disk Setup reached
- **00:50:05** Ignition Complete reached

### Phase 3: Boot 1 - Pivot to Real Root + First Boot Services (00:50:05 -> 00:50:30)
- **00:50:05** dracut pre-pivot
- **00:50:06** initrd cleanup
- **00:50:08** Switch Root target reached (initrd)
- **00:50:17** Switch Root complete (real root systemd)
- **00:50:28** System Initialization reached, Basic System reached
- **00:50:29** chronyd started, NetworkManager started
- **00:50:30** Network Manager Wait Online finished
- **00:50:30** Machine Config Daemon Pull started

### Phase 4: Boot 1 - MCD Firstboot (00:50:30 -> 00:53:49)
- **00:50:30** MCD pull service started
- **00:50:37** Pulling MCD image (4 blobs)
- **00:50:53** MCD pull finished (23s), MCD firstboot service started
- **00:50:54** MCD container started (re-exec machine-config-daemon)
- **00:50:56** rpm-ostree started, changes detected (osUpdate + kargs)
- **00:50:56** Starting update from mco-empty-mc to rendered-worker
- **00:51:31** Pulling machine-os container image for rebase
- **00:51:40** rpm-ostree rebase started (ostree-unverified-registry)
- **00:53:20** OSTree Finalize Staged Deployment started
- **00:53:28** First staging deployment done
- **00:53:37** Changes queued for next boot
- **00:53:46** Second staging deployment done
- **00:53:49** MCD initiates reboot

### Phase 5: Reboot (00:53:49 -> 00:54:30)
- **00:53:49** systemd-logind: "System is rebooting"
- **00:54:18** OSTree finalize completed, all services stopped
- **00:54:30** Boot 2 kernel starts (5.14.0-570.107.1, new kernel)

### Phase 6: Boot 2 - chrony-wait (00:54:41 -> 00:55:06)
- **00:54:30** Kernel boot (boot 0 starts)
- **00:54:37** Switch root completed
- **00:54:41** chrony-wait started
- **00:55:05** chronyd selected source PHC0
- **00:55:06** chrony-wait finished (24.1s from systemd-analyze blame)

### Phase 7: Boot 2 - CRI-O + Kubelet (00:55:06 -> 00:55:09)
- **00:55:06** CRI-O starting
- **00:55:08** CRI-O started (2.4s)
- **00:55:08** Kubelet process started (kubenswrapper)
- **00:55:09** Node registered, Startup finished (42.6s total boot 2)

### Phase 8: Boot 2 - Kubelet to NodeReady (00:55:09 -> 00:56:13)
- **00:55:09** Node registered successfully
- **00:55:09** Node creation timestamp in API
- **00:55:11** DaemonSet pods starting (kube-rbac-proxy, node-resolver, tuned, etc.)
- **00:55:12** CNI pods starting (multus, OVN-kubernetes)
- **00:55:51** Second wave of container starts (image pulls complete)
- **00:55:52** OVN-kubernetes containers all started (6 containers)
- **00:56:13** NodeReady event recorded
- **00:56:13** Machine lastUpdated (machine controller confirms)

## Top 10 Services by Time (systemd-analyze blame, Boot 2)

| Rank | Service | Duration |
|------|---------|----------|
| 1 | chrony-wait.service | 24.119s |
| 2 | dev-disk-by-partuuid-*.device (disk devices) | 7.970s |
| 3 | sys-subsystem-net-devices-enP15920s1.device | 5.862s |
| 4 | ovs-configuration.service | 5.459s |
| 5 | crio.service | 2.368s |
| 6 | coreos-update-ca-trust.service | 2.363s |
| 7 | systemd-udev-settle.service | 2.350s |
| 8 | initrd-switch-root.service | 1.260s |
| 9 | dracut-cmdline.service | 1.155s |
| 10 | systemd-hwdb-update.service | 1.079s |

## systemd-analyze Critical Chain (Boot 2)
```
graphical.target @32.677s
 -> multi-user.target @32.677s
    -> kubelet.service @32.203s +473ms
       -> crio.service @29.819s +2.368s
          -> kubelet-dependencies.target @29.796s
             -> chrony-wait.service @5.675s +24.119s
```

## Boot List
```
IDX  BOOT ID                           FIRST ENTRY                  LAST ENTRY
 -1  eb443891f3f6447babbba3e1362a3760   2026-04-21 00:49:43 UTC      2026-04-21 00:54:18 UTC
  0  41aa3717390843258b0dcb1b35035194   2026-04-21 00:54:30 UTC      2026-04-21 01:01:24 UTC
```

## systemd-analyze (Boot 2)
```
Startup finished in 2.135s (kernel) + 6.813s (initrd) + 33.686s (userspace) = 42.635s
graphical.target reached after 32.677s in userspace.
```

## Key Observations

1. **MCD firstboot is the single largest phase (~3m 19sec, 43%)** including the MCD image pull (23s)
   and rpm-ostree rebase (~2m 56sec). The 32-vCPU VM does not significantly speed this up vs. 4-vCPU
   D4s_v3 (~2m 44sec) because this phase is I/O-bound (container image pulls and ostree operations),
   not CPU-bound.

2. **Azure VM provisioning is notably slower at ~76s (16%)** compared to ~32s for D4s_v3.
   The larger VM (32 vCPU, 128GB RAM) takes longer to allocate and boot in Azure.

3. **Kubelet to NodeReady is significantly faster at ~64s (14%)** compared to ~2m 14sec for D4s_v3.
   The 32-vCPU VM has much more bandwidth for parallel container image pulls (CNI, OVN, multus).
   All DaemonSet pods were started within 4 seconds of kubelet start, and NodeReady was achieved
   in ~64s vs. ~134s on D4s_v3.

4. **chrony-wait adds ~25s** on the critical path, using Azure's PHC0 (PTP Hardware Clock) refclock.
   This is consistent with the ~24s observed on D4s_v3.

5. **Boot 2 systemd startup is 42.6s** (kernel 2.1s + initrd 6.8s + userspace 33.7s), similar to
   D4s_v3 at 40.9s. The critical chain is dominated by chrony-wait (24s).

6. **Reboot takes ~41s** (shutdown at 00:53:49, kernel at 00:54:30), longer than D4s_v3's ~26s.
   This may be due to the OSTree finalize staged deployment taking significant time at 00:54:18.

7. **The node reboots once** after MCD firstboot provisioning, which is the standard OpenShift
   first-boot flow (applying rendered-worker config via rpm-ostree rebase).

## Comparison with D4s_v3 (4 vCPU)

| Phase | D4s_v3 (4 vCPU) | D32s_v3 (32 vCPU) | Delta |
|-------|-----------------|-------------------|-------|
| Azure VM Provisioning | ~32s | ~76s | +44s (larger VM) |
| Boot 1: Ignition + Setup | ~29s | ~45s | +16s |
| MCD Firstboot (pull + rebase) | ~2m 44sec | ~3m 19sec | +35s |
| Reboot | ~26s | ~41s | +15s |
| Boot 2: chrony-wait | ~24s | ~25s | ~same |
| Boot 2: CRI-O + Kubelet | ~1s | ~3s | +2s |
| Kubelet -> NodeReady | **~2m 14sec** | **~64s** | **-70s** |
| **Total** | **~7m 03sec** | **~7m 46sec** | **+43s** |

The 32-vCPU D32s_v3 saves significant time on the Kubelet-to-NodeReady phase (image pulls are
faster with more bandwidth/CPU), but this is offset by longer Azure VM provisioning and MCD
firstboot phases. Overall scale-up time is ~43s longer.
