# Node Scale-Up Time Analysis: m8a.xlarge (AWS, OCP 4.21)

## Cluster
- **Cluster**: ci-ln-0mi9cpt-76ef8 (OpenShift 4.21.11)
- **Region**: us-west-2, Zone us-west-2a
- **Instance Type**: m8a.xlarge (AMD EPYC 5th Gen, 4 vCPU, 16 GB RAM)
- **Machine**: ci-ln-0mi9cpt-76ef8-8g76q-worker-us-west-2a-m8a-lxzns
- **Node**: ip-10-0-46-98.us-west-2.compute.internal

## Total Scale-Up Time: ~3 minutes 32 seconds
- MachineSet created: **02:38:33 UTC**
- Node Ready: **02:42:05 UTC** (NodeReady event in journal)
- Polling confirmed Ready: **02:42:26 UTC**

## Phase Breakdown

| Phase | Start | End | Duration | Notes |
|-------|-------|-----|----------|-------|
| **AWS Instance Provisioning** | 02:38:33 | 02:38:53 | ~20s | VM launch + first kernel |
| **Boot 1: Kernel + Ignition (all stages)** | 02:38:53 | 02:39:03 | ~10s | Ignition fetch, write files |
| **Boot 1: Pivot to real root** | 02:39:03 | 02:39:27 | ~24s | sysroot transition, systemd init |
| **Boot 1: MCD pull + rpm-ostree rebase** | 02:39:27 | 02:40:37 | ~1m 10sec | MCD image pull (8s), rpm-ostree rebase, **LARGEST PHASE** |
| **Boot 1: Reboot** | 02:40:37 | 02:41:09 | ~32s | Shutdown (14s) + POST/bootloader (18s) |
| **Boot 2: Kernel + initrd** | 02:41:09 | 02:41:14 | ~5s | Second boot startup |
| **Boot 2: chrony-wait** | 02:41:14 | 02:41:27 | ~13s | NTP time sync (AWS time service) |
| **Boot 2: CRI-O + Kubelet start** | 02:41:27 | 02:41:30 | ~3s | Container runtime + kubelet |
| **Boot 2: Kubelet -> NodeReady** | 02:41:30 | 02:42:05 | ~35s | CSR, CNI, node registration |

## Time Spent Summary

| Category | Duration | % of Total |
|----------|----------|------------|
| AWS Instance Provisioning | ~20s | 9% |
| Boot 1: Ignition + Pivot | ~34s | 16% |
| Boot 1: MCD Firstboot (rpm-ostree) | **~1m 10sec** | **33%** |
| Reboot (shutdown + POST) | ~32s | 15% |
| Boot 2: Kernel/initrd | ~5s | 2% |
| Boot 2: chrony-wait (NTP sync) | ~13s | 6% |
| Boot 2: CRI-O + Kubelet start | ~3s | 1% |
| Boot 2: Kubelet to NodeReady | **~35s** | **17%** |

## rpm-ostree Rebase Details
- MCD pull started: 02:39:27, finished: 02:39:35 (~8s)
- rpm-ostree rebase started: 02:39:58 (to `sha256:5f140840...`)
- Rebase target: `quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:5f140840c3308449da2a70ec39e47be6008bafd7019e56cdb828acd7e9e22cb3`
- MCD firstboot deactivated: 02:40:37
- Kernel upgrade: 5.14.0-570.74.1 -> 5.14.0-570.107.1

## Boot List
```
IDX BOOT ID                          FIRST ENTRY                 LAST ENTRY
 -1 5433c64802034ccea6df64d3ce18f481 Sat 2026-04-18 02:38:53 UTC Sat 2026-04-18 02:40:51 UTC
  0 3b57a0a1f7bb4af8a880ee7706a36c8c Sat 2026-04-18 02:41:09 UTC Sat 2026-04-18 02:43:14 UTC
```

## systemd-analyze (Boot 2)
```
Startup finished in 2.407s (kernel) + 2.402s (initrd) + 17.922s (userspace) = 22.732s
graphical.target reached after 17.913s in userspace.
```

## systemd-analyze critical-chain (Boot 2)
```
graphical.target @17.913s
└─multi-user.target @17.913s
  └─kubelet.service @17.436s +476ms
    └─crio.service @15.895s +1.533s
      └─kubelet-dependencies.target @15.883s
        └─chrony-wait.service @2.749s +13.134s
```

## CSR Timeline
- Client CSR (csr-9tdt2) approved: 02:41:30
- Serving CSR (csr-f2fsk) approved: 02:41:31

## Comparison: m6a vs m7a vs m8a

| Metric | m6a.xlarge | m7a.xlarge | m8a.xlarge |
|--------|-----------|-----------|-----------|
| **Total time** | **4m 26sec** | **4m 19sec** | **3m 32sec** |
| AWS Instance Provisioning | 23s | 25s | 20s |
| Boot 1 (Ignition + pivot) | 37s | 36s | 34s |
| MCD firstboot (rpm-ostree) | 1m 33sec | 1m 29sec | 1m 10sec |
| Reboot | 35s | 39s | 32s |
| Boot 2 kernel/initrd | 7s | 7s | 5s |
| chrony-wait | 14s | 13s | 13s |
| CRI-O + Kubelet start | 2s | 2s | 3s |
| Kubelet to NodeReady | 55s | 48s | 35s |
| **systemd-analyze total** | **25.6s** | **26.9s** | **22.7s** |

### Key Differences
1. **m8a is 54s faster than m6a** overall (20% improvement). The biggest gains are in MCD firstboot (-23s) and Kubelet to NodeReady (-20s).
2. **MCD firstboot scales with I/O performance** — m8a's faster NVMe completes the rpm-ostree rebase 23s quicker than m6a.
3. **Kubelet to NodeReady is dramatically faster on m8a** (35s vs 55s) — faster CPU and I/O speed up CNI image pulls and pod startup.
4. **chrony-wait is nearly identical** (~13-14s) — NTP sync is network-latency-bound, not hardware.
5. **AWS provisioning time is consistent** (20-25s) — slight variance, not generation-dependent.

## Saved Artifacts
- `node-journal-4.21-m8a.log` — Full journal (all boots, 11,317 lines)
- `node-boot-list-4.21-m8a.txt` — Boot list
- `node-systemd-analyze-4.21-m8a.txt` — systemd-analyze output
- `node-systemd-blame-4.21-m8a.txt` — systemd-analyze blame
- `node-systemd-critical-chain-4.21-m8a.txt` — systemd critical chain
- `node-images-4.21-m8a.txt` — Container images on node
- `new-machine-4.21-m8a-final.yaml` — Machine object
- `new-node-4.21-m8a.yaml` — Node object
- `csr-list-4.21-m8a.txt` — CSR list
- `machineset-4.21-m8a.json` — MachineSet definition used
