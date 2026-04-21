# Node Scale-Up Time Analysis: m6a.xlarge (AWS, OCP 4.21)

## Cluster
- **Cluster**: ci-ln-0mi9cpt-76ef8 (OpenShift 4.21.11)
- **Region**: us-west-2, Zone us-west-2a
- **Instance Type**: m6a.xlarge (AMD EPYC 3rd Gen, 4 vCPU, 16 GB RAM)
- **Machine**: ci-ln-0mi9cpt-76ef8-8g76q-worker-us-west-2a-m6a-ksbhx
- **Node**: ip-10-0-49-168.us-west-2.compute.internal

## Total Scale-Up Time: ~4 minutes 26 seconds
- MachineSet created: **02:27:08 UTC**
- Node Ready: **02:31:34 UTC** (NodeReady event in journal)
- Polling confirmed Ready: **02:32:00 UTC**

## Phase Breakdown

| Phase | Start | End | Duration | Notes |
|-------|-------|-----|----------|-------|
| **AWS Instance Provisioning** | 02:27:08 | 02:27:31 | ~23s | VM launch + first kernel |
| **Boot 1: Kernel + Ignition (all stages)** | 02:27:31 | 02:27:42 | ~11s | Ignition fetch, write files |
| **Boot 1: Pivot to real root** | 02:27:42 | 02:28:08 | ~26s | sysroot transition, systemd init |
| **Boot 1: MCD pull + rpm-ostree rebase** | 02:28:08 | 02:29:41 | ~1m 33sec | MCD image pull (10s), rpm-ostree rebase, **LARGEST PHASE** |
| **Boot 1: Reboot** | 02:29:41 | 02:30:16 | ~35s | Shutdown (16s) + POST/bootloader (19s) |
| **Boot 2: Kernel + initrd** | 02:30:16 | 02:30:23 | ~7s | Second boot startup |
| **Boot 2: chrony-wait** | 02:30:23 | 02:30:37 | ~14s | NTP time sync (AWS time service) |
| **Boot 2: CRI-O + Kubelet start** | 02:30:37 | 02:30:39 | ~2s | Container runtime + kubelet |
| **Boot 2: Kubelet -> NodeReady** | 02:30:39 | 02:31:34 | ~55s | CSR, CNI, node registration |

## Time Spent Summary

| Category | Duration | % of Total |
|----------|----------|------------|
| AWS Instance Provisioning | ~23s | 9% |
| Boot 1: Ignition + Pivot | ~37s | 14% |
| Boot 1: MCD Firstboot (rpm-ostree) | **~1m 33sec** | **35%** |
| Reboot (shutdown + POST) | ~35s | 13% |
| Boot 2: Kernel/initrd | ~7s | 3% |
| Boot 2: chrony-wait (NTP sync) | ~14s | 5% |
| Boot 2: CRI-O + Kubelet start | ~2s | <1% |
| Boot 2: Kubelet to NodeReady | **~55s** | **21%** |

## rpm-ostree Rebase Details
- MCD pull started: 02:28:08, finished: 02:28:18 (~10s)
- rpm-ostree rebase started: 02:28:44 (to `sha256:5f140840...`)
- Rebase target: `quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:5f140840c3308449da2a70ec39e47be6008bafd7019e56cdb828acd7e9e22cb3`
- MCD firstboot deactivated: 02:29:41
- Kernel upgrade: 5.14.0-570.74.1 -> 5.14.0-570.107.1

## Boot List
```
IDX BOOT ID                          FIRST ENTRY                 LAST ENTRY
 -1 4d8fb85e4b6e494486bb8f7e9fb4eb4d Sat 2026-04-18 02:27:31 UTC Sat 2026-04-18 02:29:57 UTC
  0 fa755946cc1b408b9e02816ffbb992ca Sat 2026-04-18 02:30:16 UTC Sat 2026-04-18 02:32:57 UTC
```

## systemd-analyze (Boot 2)
```
Startup finished in 1.744s (kernel) + 3.445s (initrd) + 20.407s (userspace) = 25.598s
graphical.target reached after 20.385s in userspace.
```

## systemd-analyze critical-chain (Boot 2)
```
graphical.target @20.385s
└─multi-user.target @20.385s
  └─kubelet.service @19.802s +583ms
    └─crio.service @18.210s +1.579s
      └─kubelet-dependencies.target @18.183s
        └─chrony-wait.service @4.050s +14.133s
```

## CSR Timeline
- Client CSR (csr-bffh2) approved: 02:30:40
- Serving CSR (csr-fdc8x) approved: 02:30:41

## AWS vs Azure Notes
- chrony-wait is ~14s on AWS vs ~24s on Azure (AWS uses NTP to 169.254.169.123, not PTP/PHC)
- No PHC refclock delay on AWS

## Saved Artifacts
- `node-journal-4.21-m6a.log` — Full journal (all boots, 10,307 lines)
- `node-boot-list-4.21-m6a.txt` — Boot list
- `node-systemd-analyze-4.21-m6a.txt` — systemd-analyze output
- `node-systemd-blame-4.21-m6a.txt` — systemd-analyze blame
- `node-systemd-critical-chain-4.21-m6a.txt` — systemd critical chain
- `node-images-4.21-m6a.txt` — Container images on node
- `new-machine-4.21-m6a-final.yaml` — Machine object
- `new-node-4.21-m6a.yaml` — Node object
- `csr-list-4.21-m6a.txt` — CSR list
- `machineset-4.21-m6a.json` — MachineSet definition used
