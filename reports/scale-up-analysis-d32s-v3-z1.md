# Node Scale-Up Time Analysis: Standard_D32s_v3 (Azure, Zone 1)

## Cluster
- **Cluster**: ci-ln-ikkmv7b-1d09d (OpenShift 4.20, Kubernetes 1.33.9)
- **Region**: eastus2, Zone 1
- **VM Type**: Standard_D32s_v3 (32 vCPU, 128 GB RAM)
- **Machine**: ci-ln-ikkmv7b-1d09d-lh6ms-d32s-v3-z1-x4wt2
- **MachineSet**: ci-ln-ikkmv7b-1d09d-lh6ms-d32s-v3-z1
- **OS**: Red Hat Enterprise Linux CoreOS 9.6.20260414-0 (Plow)
- **Kernel**: 5.14.0-570.107.1.el9_6.x86_64 (boot 2), 5.14.0-570.92.1.el9_6.x86_64 (boot 1)

## Total Scale-Up Time: ~5 minutes 5 seconds
- Machine created: **00:48:27 UTC**
- Node Ready: **00:53:32 UTC** (NodeReady condition lastTransitionTime)
- Node object created: **00:52:29 UTC**

## Phase Breakdown

| Phase | Start | End | Duration | Notes |
|-------|-------|-----|----------|-------|
| **1. Cloud VM Provisioning** | 00:48:27 | 00:49:08 | **~41s** | Machine create to first kernel boot |
| **2. Boot 1: Ignition** | 00:49:08 | 00:49:19 | **~11s** | Kernel, initrd, network, Ignition fetch+apply |
| **3. Boot 1: Pivot to real root** | 00:49:19 | 00:49:24 | **~5s** | initrd-switch-root, sysroot transition |
| **4. Boot 1: MCD pull + firstboot** | 00:49:31 | 00:51:37 | **~2m 6sec** | MCD image pull + rpm-ostree rebase, **LARGEST PHASE** |
| **5. Reboot** | 00:51:48 | 00:51:55 | **~7s** | Shutdown + POST + bootloader |
| **6. Boot 2: Kernel + initrd** | 00:51:55 | 00:52:00 | **~5s** | Second boot kernel + initrd (1.2s + 4.1s) |
| **7. Boot 2: chrony-wait** | 00:52:03 | 00:52:27 | **~24s** | NTP time sync (PHC0 refclock) |
| **8. Boot 2: CRI-O + Kubelet start** | 00:52:27 | 00:52:29 | **~2s** | CRI-O 1.0s + kubelet 0.4s |
| **9. Boot 2: Kubelet to NodeReady** | 00:52:29 | 00:53:32 | **~63s** | CSR approval, CNI image pulls, registration |

## Time Spent Summary

| Category | Duration | % of Total |
|----------|----------|------------|
| Cloud VM Provisioning | ~41s | 13% |
| Boot 1: Ignition + Pivot | ~16s | 5% |
| Boot 1: MCD Firstboot (rpm-ostree) | **~2m 6sec** | **41%** |
| Reboot (shutdown + POST) | ~7s | 2% |
| Boot 2: Kernel/initrd | ~5s | 2% |
| Boot 2: chrony-wait (NTP sync) | ~24s | 8% |
| Boot 2: CRI-O + Kubelet start | ~2s | <1% |
| Boot 2: Kubelet to NodeReady | **~63s** | **21%** |
| **Miscellaneous gaps** | ~6s | 2% |

## Detailed Phase Analysis

### Phase 1: Cloud VM Provisioning (41s)
- Machine object created: 00:48:27
- Azure reports MachineCreated: 00:48:34 (~7s for Azure API call)
- InstanceExists condition: 00:48:36
- First kernel boot in journal: 00:49:08 (~32s from Azure create to boot)

### Phase 2: Boot 1 - Ignition (11s)
- Kernel boot: 00:49:08
- Ignition (fetch-offline): 00:49:11
- Ignition (fetch) -- config from MCS via IMDS: 00:49:12
- Ignition (kargs): 00:49:13
- Ignition (disks): 00:49:13
- Ignition (mount): 00:49:16 (includes root filesystem grow: ~3s)
- Ignition (files): 00:49:17-00:49:18 (writes all MachineConfig files, units, etc.)
- Ignition Complete target: 00:49:19

### Phase 3: Boot 1 - Pivot to Real Root (5s)
- initrd-switch-root: 00:49:19 -> 00:49:24
- systemd init in real root, udev, local filesystems: 00:49:24-00:49:30

### Phase 4: Boot 1 - MCD Firstboot (2m 6sec)
This is the largest single phase, consisting of:

| Sub-Phase | Start | End | Duration |
|-----------|-------|-----|----------|
| MCD Pull (MCD container image) | 00:49:31 | 00:49:42 | ~11s |
| MCD Firstboot start | 00:49:42 | 00:49:43 | ~1s |
| MCD re-exec + detect changes | 00:49:43 | 00:49:44 | ~1s |
| Pull machine-os container image | 00:49:44 | 00:49:59 | ~15s |
| Copy extensions content | 00:49:59 | 00:50:17 | ~18s |
| rpm-ostree rebase (fetch 30 layers, 643.8 MB) | 00:50:18 | 00:51:06 | ~48s |
| Staging deployment | 00:51:06 | 00:51:27 | ~21s |
| Additional staging + SELinux policy refresh | 00:51:27 | 00:51:37 | ~10s |
| ostree finalize staged deployment | 00:51:37 | 00:51:48 | ~11s |

- rpm-ostree rebase target: `quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:df15dd8834fda81c18b0c1373c1f93258b033efb40d8b94f2a7a78bd2b7e3b58`
- ostree chunk layers already present: 23, layers needed: 30 (643.8 MB)
- rpm-ostreed consumed 48.740s CPU time
- machine-config-daemon-pull consumed 28.218s CPU time

### Phase 5: Reboot (7s)
- Last boot -1 journal entry: 00:51:48 (ostree finalize complete)
- First boot 0 kernel entry: 00:51:55
- Very fast reboot -- D32s_v3 has 32 vCPUs, POST is quick

### Phase 6: Boot 2 - Kernel + initrd (5s)
- systemd-analyze reports: kernel 1.230s + initrd 4.129s
- New kernel version: 5.14.0-570.107.1.el9_6.x86_64 (upgraded from 570.92.1)

### Phase 7: Boot 2 - chrony-wait (24s)
- chrony-wait.service started: 00:52:03
- chrony-wait.service finished: 00:52:27
- chronyd selected source PHC0 (Azure PTP Hardware Clock)
- Duration: 24.075s per systemd-analyze blame
- This is on the critical path (blocks kubelet-dependencies.target)

### Phase 8: Boot 2 - CRI-O + Kubelet (2s)
- CRI-O started: 00:52:27 (1.025s startup)
- Kubelet started: 00:52:29 (0.362s startup)
- Both are fast; CRI-O is the gating service after chrony-wait

### Phase 9: Boot 2 - Kubelet to NodeReady (63s)
- Kubelet start: 00:52:29
- CSR csr-kj9n2 approved + issued: 00:52:29 (<1s)
- CSR csr-svhfz (serving) approved + issued: 00:52:30 (~1s)
- NodeReady event: 00:53:32
- Node Ready condition lastTransitionTime: 00:53:32
- The majority of this time (~62s) is spent on container image pulls for CNI plugins
  (multus, OVN-Kubernetes, container-networking-plugins, etc.)

## Boot List
```
IDX BOOT ID                          FIRST ENTRY                 LAST ENTRY
 -1 493955e6b28c4683a0803528b77c93a1 Tue 2026-04-21 00:49:08 UTC Tue 2026-04-21 00:51:48 UTC
  0 3f1c8a552cb14e4f80b783d19f5c431d Tue 2026-04-21 00:51:55 UTC Tue 2026-04-21 01:00:33 UTC
```

## systemd-analyze (Boot 2)
```
Startup finished in 1.230s (kernel) + 4.129s (initrd) + 29.989s (userspace) = 35.349s
graphical.target reached after 29.664s in userspace.
```

## systemd-analyze critical-chain (Boot 2)
```
graphical.target @29.664s
 └─multi-user.target @29.664s
   └─kubelet.service @29.301s +362ms
     └─crio.service @28.265s +1.025s
       └─kubelet-dependencies.target @28.248s
         └─chrony-wait.service @4.171s +24.075s
           └─chronyd.service @4.113s +51ms
             └─coreos-platform-chrony-config.service @4.031s +67ms
               └─basic.target @4.011s
```

## systemd-analyze blame -- Top 10 Services (Boot 2)

| Rank | Duration | Service |
|------|----------|---------|
| 1 | 24.075s | chrony-wait.service |
| 2 | 4.768s | sys-module-fuse.device |
| 3 | 4.622s | dev-ttyS0.device (and other serial devices) |
| 4 | 4.521s | dev-sda4.device (root partition) |
| 5 | 3.552s | enP19341s1.device (accelerated NIC) |
| 6 | 2.993s | ovs-configuration.service |
| 7 | 2.757s | dev-loop0.device |
| 8 | 2.191s | systemd-udev-settle.service |
| 9 | 1.192s | coreos-update-ca-trust.service |
| 10 | 1.025s | crio.service |

## Machine Object Timestamps

| Event | Timestamp |
|-------|-----------|
| Machine creationTimestamp | 00:48:27 |
| Drainable condition | 00:48:27 |
| Terminable condition | 00:48:27 |
| MachineCreationSucceeded | 00:48:34 |
| InstanceExists | 00:48:36 |
| Machine lastUpdated (nodeRef set) | 00:53:32 |

## Node Object Timestamps

| Event | Timestamp |
|-------|-----------|
| Node creationTimestamp | 00:52:29 |
| KubeletReady lastTransitionTime | 00:53:32 |
| MemoryPressure/DiskPressure/PIDPressure lastTransitionTime | 00:52:29 |

## D32s_v3 vs D4s_v3 Comparison

| Metric | Standard_D4s_v3 | Standard_D32s_v3 | Delta |
|--------|----------------|-------------------|-------|
| **vCPU** | 4 | 32 | 8x |
| **RAM** | 16 GB | 128 GB | 8x |
| **Total time** | ~7m 3sec | ~5m 5sec | **-1m 58sec (28% faster)** |
| VM Provisioning | ~32s | ~41s | +9s (larger VM) |
| Boot 1: Ignition+Pivot | ~29s | ~16s | -13s |
| MCD firstboot | ~2m 44sec | ~2m 6sec | **-38s** |
| Reboot | ~26s | ~7s | **-19s** |
| Boot 2 kernel/initrd | ~12s | ~5s | -7s |
| chrony-wait | ~24s | ~24s | 0s |
| CRI-O + Kubelet | ~1s | ~2s | +1s |
| Kubelet to NodeReady | ~2m 14sec | ~63s | **-1m 11sec** |
| systemd-analyze total | ~40.9s | ~35.3s | -5.6s |

### Key Differences
1. **Kubelet to NodeReady is much faster on D32s_v3** (63s vs 2m 14sec) -- 8x more CPU and
   better I/O bandwidth dramatically accelerates container image pulls for CNI plugins.
2. **Reboot is much faster** (7s vs 26s) -- more CPU cores mean faster shutdown and POST.
3. **MCD firstboot is ~38s faster** -- the rpm-ostree rebase benefits from more CPU cores
   for decompression and I/O parallelism, and faster I/O for the 643.8 MB of layers.
4. **VM provisioning is slightly slower** (+9s) -- larger VMs take slightly longer to allocate.
5. **chrony-wait is identical** (~24s) -- this is network/NTP latency, not hardware-bound.
6. **Boot 2 kernel/initrd is faster** (5s vs 12s) -- more cores means faster kernel/initrd
   initialization.

## Bottleneck Analysis

### 1. MCD Firstboot / rpm-ostree rebase (41% of total)
The single largest phase. The rpm-ostree rebase fetches 30 layers (643.8 MB) and stages a
new deployment. With 32 vCPUs, the fetch and decompression is faster than D4s_v3 (~2m 6sec
vs ~2m 44sec), but still dominates the timeline.

### 2. Kubelet to NodeReady (21% of total)
Second largest phase. 63s is spent primarily on container image pulls for CNI plugins
(multus, OVN-Kubernetes). CSR approval is <1s. The D32s_v3's additional bandwidth and
CPU significantly reduces this vs the D4s_v3 (63s vs 2m 14sec).

### 3. chrony-wait (8% of total)
24s on the critical path waiting for NTP time synchronization via PHC0 (Azure PTP Hardware
Clock). This is a constant across all Azure VM types tested and is tunable via chrony
configuration.

### 4. VM Provisioning (13% of total)
41s to provision the D32s_v3 VM in Azure. This is ~9s slower than the D4s_v3, likely due
to the larger VM requiring more resource allocation.

## Saved Artifacts
- `node-journal-d32s-v3-z1.log` -- Full journal (all boots)
- `node-boot-list-d32s-v3-z1.txt` -- Boot list
- `node-systemd-analyze-d32s-v3-z1.txt` -- systemd-analyze output
- `node-systemd-blame-d32s-v3-z1.txt` -- systemd-analyze blame
- `node-systemd-critical-chain-d32s-v3-z1.txt` -- systemd critical chain
- `new-machine-d32s-v3-z1-final.yaml` -- Machine object
- `new-node-d32s-v3-z1.yaml` -- Node object
