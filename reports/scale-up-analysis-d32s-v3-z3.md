# Node Scale-Up Time Analysis: Standard_D32s_v3 (Azure, Zone 3)

## Cluster
- **Cluster**: ci-ln-ikkmv7b-1d09d-lh6ms (OpenShift 4.20, Kubernetes 1.33.9)
- **Region**: eastus2, Zone 3
- **VM Type**: Standard_D32s_v3 (32 vCPU, 128 GB RAM)
- **Storage**: Premium_LRS, 128 GB OS disk
- **Accelerated Networking**: true
- **Machine**: ci-ln-ikkmv7b-1d09d-lh6ms-d32s-v3-z3-hzmdn
- **MachineSet**: ci-ln-ikkmv7b-1d09d-lh6ms-d32s-v3-z3
- **OS Image**: Red Hat Enterprise Linux CoreOS 9.6.20260414-0 (Plow)
- **Kernel (boot 1)**: 5.14.0-570.92.1.el9_6.x86_64
- **Kernel (boot 2)**: 5.14.0-570.107.1.el9_6.x86_64 (upgraded via rpm-ostree rebase)

## Total Scale-Up Time: ~6 minutes 42 seconds
- Machine created: **00:48:27 UTC**
- Node Ready: **00:55:09 UTC**

## Phase Breakdown

| Phase | Start | End | Duration | Notes |
|-------|-------|-----|----------|-------|
| **Cloud VM Provisioning** | 00:48:27 | 00:49:44 | **77s** | Machine created -> first kernel boot (boot -1) |
| **Boot 1: Kernel + initrd + network** | 00:49:44 | 00:49:48 | **~4s** | Kernel, dracut, DHCP (ip=auto) |
| **Boot 1: Ignition fetch-offline** | 00:49:48 | 00:49:48 | **<1s** | Config requires networking, deferred |
| **Boot 1: Ignition fetch (Azure IMDS + SR0)** | 00:49:49 | 00:49:50 | **~1s** | IMDS userdata + config from /dev/sr0 |
| **Boot 1: Ignition stages (kargs/disks/mount/files)** | 00:49:50 | 00:49:57 | **~7s** | Disk grow, write configs, systemd units, SELinux relabel |
| **Boot 1: Pivot to real root** | 00:49:59 | 00:50:12 | **~13s** | dracut pre-pivot, initrd-switch-root, sysroot transition |
| **Boot 1: First-boot services start** | 00:50:12 | 00:50:29 | **~17s** | systemd init, OVS, NM, sshd, chrony |
| **Boot 1: MCD pull (MCO image)** | 00:50:29 | 00:50:47 | **~18s** | Pulling machine-config-daemon container image |
| **Boot 1: MCD firstboot (rpm-ostree rebase)** | 00:50:47 | 00:53:05 | **~138s (2m 18sec)** | MCD re-exec, os-container pull, rpm-ostree rebase, kargs |
| **Boot 1: Shutdown + ostree finalize** | 00:53:05 | 00:53:29 | **~24s** | ostree finalize staged deployment, SELinux policy refresh, syncfs |
| **Reboot gap** | 00:53:29 | 00:53:36 | **~7s** | POST + bootloader |
| **Boot 2: Kernel + initrd + sysroot** | 00:53:36 | 00:53:43 | **~7s** | New kernel, dracut, switch-root |
| **Boot 2: chrony-wait** | 00:53:48 | 00:54:12 | **~24s** | Waiting for PHC0 time sync (Azure PTP) |
| **Boot 2: CRI-O start** | 00:54:12 | 00:54:15 | **~3s** | Container runtime startup |
| **Boot 2: Kubelet start** | 00:54:15 | 00:54:15 | **<1s** | Kubelet process started, CSR submitted |
| **Boot 2: CSR approval + node registration** | 00:54:15 | 00:54:16 | **~1s** | csr-gltzg approved, node registered |
| **Boot 2: Kubelet -> NodeReady** | 00:54:16 | 00:55:09 | **~53s** | CNI image pulls, OVN-Kubernetes readiness |

## Time Spent Summary

| Category | Duration | % of Total |
|----------|----------|------------|
| Cloud VM Provisioning | 77s | 19.1% |
| Boot 1: Ignition + OS Setup | ~25s | 6.2% |
| Boot 1: Pivot + first-boot services | ~30s | 7.5% |
| Boot 1: MCD Pull (MCO image) | 18s | 4.5% |
| Boot 1: MCD Firstboot (rpm-ostree rebase) | **138s (2m 18sec)** | **34.3%** |
| Boot 1: Shutdown + ostree finalize | 24s | 6.0% |
| Reboot gap (POST + bootloader) | 7s | 1.7% |
| Boot 2: Kernel + initrd + sysroot | 7s | 1.7% |
| Boot 2: chrony-wait (NTP sync) | **24s** | **6.0%** |
| Boot 2: CRI-O + Kubelet start | ~3s | 0.7% |
| Boot 2: Kubelet to NodeReady | **53s** | **13.2%** |

## Detailed Phase Timeline

### Phase 1: Cloud VM Provisioning (77s)
- **00:48:27** Machine object created (creationTimestamp)
- **00:48:37** Azure VM created (MachineCreated condition)
- **00:48:38** InstanceExists condition set to True
- **00:49:44** First kernel boot log entry (boot -1)
- Cloud provisioning to first kernel boot: **77s**
- Note: Azure API responded "machine successfully created" in 10s, but VM took another ~67s to actually boot.

### Phase 2: Boot 1 - Ignition (00:49:44 - 00:49:59, ~15s)
- **00:49:44** Kernel 5.14.0-570.92.1 boots with `ignition.firstboot` and `ignition.platform.id=azure`
- **00:49:48** Ignition fetch-offline completes (no config URL, needs network)
- **00:49:49** Network available, Ignition fetch starts, reads IMDS + /dev/sr0 config
- **00:49:50** Ignition fetch complete, kargs/disks/mount stages
- **00:49:57** Ignition files stage complete (91 SELinux patterns relabeled)
- **00:49:59** Ignition Complete target reached

### Phase 3: Boot 1 - Pivot to Real Root (00:49:59 - 00:50:29, ~30s)
- **00:49:59** dracut pre-pivot, initrd cleanup
- **00:50:01** First switch-root into sysroot
- **00:50:12** Second switch-root (ostree sysroot)
- **00:50:27** chrony, NM, sshd, OVS starting
- **00:50:29** Multi-User System target reached, NetworkManager online

### Phase 4: Boot 1 - MCD Pull + Firstboot (00:50:29 - 00:53:05, ~156s / 2m 36sec)
- **00:50:29** Machine Config Daemon Pull service starts
- **00:50:36** MCD image pull begins (quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:9ff861...)
- **00:50:47** MCD image pulled, Machine Config Daemon Firstboot starts
- **00:50:48** MCD container launched (kind_curie), re-exec into machine-config-daemon
- **00:50:49** MCD detects changes from mco-empty-mc to rendered-worker-6d58a2ae...
- **00:50:49** machine-os-content image pull starts (via nice/ionice -c 3)
- **00:51:29** machine-os-content pulled, ostree-container-pivot created
- **00:51:37** rpm-ostree rebase begins (ostree-unverified-registry:quay.io/openshift-release-dev/...)
- **00:52:49** First staging deployment complete (checkout=1.5s, composefs=1.8s, etc=710ms)
- **00:52:54** Rebase transaction successful
- **00:52:58** rpm-ostree kargs append (cgroup_no_v1, psi=0)
- **00:53:03** Second staging deployment complete (kargs update)
- **00:53:05** MCD initiates reboot

#### MCD Firstboot sub-phases:
| Sub-phase | Duration |
|-----------|----------|
| MCD image pull | 18s |
| MCD container start + re-exec | ~2s |
| machine-os-content image pull | ~40s |
| rpm-ostree rebase (download + stage) | ~72s (1m 12sec) |
| rpm-ostree kargs update | ~7s |
| Reboot initiation | ~2s |

### Phase 5: Reboot (00:53:05 - 00:53:36, ~31s)
- **00:53:05** MCD triggers reboot, systemd shutdown begins
- **00:53:06** Services stopping (auditd, tmpfiles, etc.)
- **00:53:06 - 00:53:29** ostree-finalize-staged runs (copy /etc changes, refresh SELinux policy ~2.9s, syncfs)
- **00:53:29** Last journal entry of boot -1 (ostree finalize complete)
- **00:53:36** First journal entry of boot 0 (new kernel starts)
- POST + bootloader gap: **7s**

### Phase 6: Boot 2 - chrony-wait (00:53:48 - 00:54:12, ~24s)
- **00:53:36** New kernel 5.14.0-570.107.1 boots (upgraded kernel)
- **00:53:43** switch-root into sysroot
- **00:53:48** chronyd starts, chrony-wait.service begins
- **00:54:12** PHC0 source selected, chrony-wait completes
- chrony-wait is on the critical path (blocks kubelet-dependencies.target)

### Phase 7: Boot 2 - CRI-O + Kubelet (00:54:12 - 00:54:15, ~3s)
- **00:54:12** CRI-O starts (version 1.33.10-2.rhaos4.20)
- **00:54:15** CRI-O ready, kubelet starts (v1.33.9)
- **00:54:15** Kubelet "Started kubelet", CSR submitted (csr-gltzg)

### Phase 8: Boot 2 - Kubelet to NodeReady (00:54:15 - 00:55:09, ~54s)
- **00:54:15** CSR csr-gltzg approved (kube-apiserver-client-kubelet)
- **00:54:16** Node registered successfully
- **00:54:17** Second CSR csr-jpj97 approved (kubelet-serving)
- **00:54:17** Container image pulls begin (multus, OVN-Kubernetes, etc.)
- **00:54:47** Bulk of initial image pulls complete (~30s of pulling)
- **00:54:59** OVN-Kubernetes ovnkube-node pod becomes ready
- **00:55:09** kubelet records "NodeReady" event
- Node object Ready condition lastTransitionTime: **00:55:09**

## systemd-analyze Top 10 (Boot 2)

```
Startup finished in 312ms (firmware) + 4.050s (loader) + 1.379s (kernel) + 4.938s (initrd) + 32.342s (userspace) = 43.022s
graphical.target reached after 32.219s in userspace.
```

| Rank | Service | Duration |
|------|---------|----------|
| 1 | chrony-wait.service | 24.085s |
| 2 | sys-module-fuse.device | 5.828s |
| 3 | dev-ttyS3.device (serial devices) | 5.666s |
| 4 | ovs-configuration.service | 3.909s |
| 5 | crio.service | 3.102s |
| 6 | systemd-udev-settle.service | 1.888s |
| 7 | coreos-update-ca-trust.service | 1.429s |
| 8 | initrd-switch-root.service | 1.049s |
| 9 | dracut-cmdline.service | 788ms |
| 10 | systemd-hwdb-update.service | 683ms |

## Critical Chain (Boot 2)
```
graphical.target @32.219s
 -> kubelet.service @31.779s +438ms
   -> crio.service @28.665s +3.102s
     -> kubelet-dependencies.target @28.650s
       -> chrony-wait.service @4.564s +24.085s
```

## Key Observations

1. **MCD firstboot is the largest single phase at ~2m 36sec (including pull), 38.8% of total time.**
   The Standard_D32s_v3 with 32 vCPUs and Premium_LRS storage handles the rpm-ostree rebase
   somewhat faster than the D4s_v3 (2m 36sec vs 2m 44sec), though the difference is modest because
   the rebase is largely I/O and network bound rather than CPU bound.

2. **Cloud VM provisioning is the second largest phase at 77s (19.1%).** The Azure API marks
   MachineCreated at 00:48:37 (10s after creation), but the VM does not boot until 00:49:44.
   This 67s delay is Azure-side VM allocation and booting.

3. **Kubelet to NodeReady is fast at ~53s (13.2%)**, significantly faster than the D4s_v3
   result of ~2m 14sec. The 32 vCPUs allow faster parallel container image pulls. Bulk image
   pulls complete in ~30s (00:54:17 to 00:54:47). OVN-Kubernetes readiness at 00:54:59.

4. **chrony-wait adds ~24s** on the critical path, blocking CRI-O and kubelet start.
   This uses PHC0 (Azure PTP hardware clock) as the time source.

5. **CSR approval is near-instant (<1s)** from kubelet start to approved+registered.

6. **Reboot is fast at ~31s total** (24s shutdown/ostree-finalize + 7s POST/bootloader).
   The ostree finalize phase includes a 2.9s SELinux policy refresh.

7. **The 32 vCPU advantage** is most visible in the kubelet-to-NodeReady phase where
   parallel image pulls benefit from more CPU cores. The MCD rebase phase benefits less
   because it is I/O bound.

## Boot List
```
IDX BOOT ID                          FIRST ENTRY                 LAST ENTRY
 -1 f4587ba2d14d452b9001ed532734bc2c Tue 2026-04-21 00:49:44 UTC Tue 2026-04-21 00:53:29 UTC
  0 4feb95f761894532bcf7559d54c3ea4e Tue 2026-04-21 00:53:36 UTC Tue 2026-04-21 01:01:55 UTC
```

## Machine Info
- **providerID**: azure:///subscriptions/72e3a972-58b0-4afc-bd4f-da89b39ccebd/resourceGroups/ci-ln-ikkmv7b-1d09d-lh6ms-rg/providers/Microsoft.Compute/virtualMachines/ci-ln-ikkmv7b-1d09d-lh6ms-d32s-v3-z3-hzmdn
- **Internal IP**: 10.0.128.12
- **CRI-O version**: 1.33.10-2.rhaos4.20.gita4d0894.el9
- **MCD image consumed**: 33.868s CPU time (machine-config-daemon-pull.service)
