# Node Scale-Up Time Analysis: m7a.xlarge (AWS, OCP 4.21)

## Cluster
- **Cluster**: ci-ln-0mi9cpt-76ef8 (OpenShift 4.21.11)
- **Region**: us-west-2, Zone us-west-2a
- **Instance Type**: m7a.xlarge (AMD EPYC 4th Gen, 4 vCPU, 16 GB RAM)
- **Machine**: ci-ln-0mi9cpt-76ef8-8g76q-worker-us-west-2a-m7a-9s2sr
- **Node**: ip-10-0-49-250.us-west-2.compute.internal

## Total Scale-Up Time: ~4 minutes 19 seconds
- MachineSet created: **02:33:16 UTC**
- Node Ready: **02:37:35 UTC** (NodeReady event in journal)
- Polling confirmed Ready: **02:37:42 UTC**

## Phase Breakdown

| Phase | Start | End | Duration | Notes |
|-------|-------|-----|----------|-------|
| **AWS Instance Provisioning** | 02:33:16 | 02:33:41 | ~25s | VM launch + first kernel |
| **Boot 1: Kernel + Ignition (all stages)** | 02:33:41 | 02:33:51 | ~10s | Ignition fetch, write files |
| **Boot 1: Pivot to real root** | 02:33:51 | 02:34:17 | ~26s | sysroot transition, systemd init |
| **Boot 1: MCD pull + rpm-ostree rebase** | 02:34:17 | 02:35:46 | ~1m29s | MCD image pull (10s), rpm-ostree rebase, **LARGEST PHASE** |
| **Boot 1: Reboot** | 02:35:46 | 02:36:25 | ~39s | Shutdown (16s) + POST/bootloader (23s) |
| **Boot 2: Kernel + initrd** | 02:36:25 | 02:36:32 | ~7s | Second boot startup |
| **Boot 2: chrony-wait** | 02:36:32 | 02:36:45 | ~13s | NTP time sync (AWS time service) |
| **Boot 2: CRI-O + Kubelet start** | 02:36:45 | 02:36:47 | ~2s | Container runtime + kubelet |
| **Boot 2: Kubelet -> NodeReady** | 02:36:47 | 02:37:35 | ~48s | CSR, CNI, node registration |

## Time Spent Summary

| Category | Duration | % of Total |
|----------|----------|------------|
| AWS Instance Provisioning | ~25s | 10% |
| Boot 1: Ignition + Pivot | ~36s | 14% |
| Boot 1: MCD Firstboot (rpm-ostree) | **~1m29s** | **34%** |
| Reboot (shutdown + POST) | ~39s | 15% |
| Boot 2: Kernel/initrd | ~7s | 3% |
| Boot 2: chrony-wait (NTP sync) | ~13s | 5% |
| Boot 2: CRI-O + Kubelet start | ~2s | <1% |
| Boot 2: Kubelet to NodeReady | **~48s** | **19%** |

## rpm-ostree Rebase Details
- MCD pull started: 02:34:17, finished: 02:34:27 (~10s)
- rpm-ostree rebase started: 02:34:51 (to `sha256:5f140840...`)
- Rebase target: `quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:5f140840c3308449da2a70ec39e47be6008bafd7019e56cdb828acd7e9e22cb3`
- MCD firstboot deactivated: 02:35:46
- Kernel upgrade: 5.14.0-570.74.1 -> 5.14.0-570.107.1

## Boot List
```
IDX BOOT ID                          FIRST ENTRY                 LAST ENTRY
 -1 9af41ce251a547c48d427847fcbe3d4c Sat 2026-04-18 02:33:41 UTC Sat 2026-04-18 02:36:02 UTC
  0 7559e27257e74fb1a1c03384389d474d Sat 2026-04-18 02:36:25 UTC Sat 2026-04-18 02:38:17 UTC
```

## systemd-analyze (Boot 2)
```
Startup finished in 4.409s (kernel) + 3.641s (initrd) + 18.839s (userspace) = 26.891s
graphical.target reached after 18.823s in userspace.
```

## systemd-analyze critical-chain (Boot 2)
```
graphical.target @18.823s
└─multi-user.target @18.823s
  └─kubelet.service @18.352s +470ms
    └─crio.service @16.736s +1.599s
      └─kubelet-dependencies.target @16.724s
        └─chrony-wait.service @3.645s +13.078s
```

## CSR Timeline
- Client CSR (csr-k2dn5) approved: 02:36:47
- Serving CSR (csr-rcw6k) approved: 02:36:49

## Saved Artifacts
- `node-journal-4.21-m7a.log` — Full journal (all boots, 11,204 lines)
- `node-boot-list-4.21-m7a.txt` — Boot list
- `node-systemd-analyze-4.21-m7a.txt` — systemd-analyze output
- `node-systemd-blame-4.21-m7a.txt` — systemd-analyze blame
- `node-systemd-critical-chain-4.21-m7a.txt` — systemd critical chain
- `node-images-4.21-m7a.txt` — Container images on node
- `new-machine-4.21-m7a-final.yaml` — Machine object
- `new-node-4.21-m7a.yaml` — Node object
- `csr-list-4.21-m7a.txt` — CSR list
- `machineset-4.21-m7a.json` — MachineSet definition used
