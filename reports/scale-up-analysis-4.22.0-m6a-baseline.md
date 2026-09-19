# Node Scale-Up Analysis: OCP 4.22.0 Baseline (AWS)

## Cluster

- **Cluster**: sdods-scl-rngn9
- **OCP version**: 4.22.0 (GA), release image `quay.io/openshift-release-dev/ocp-release@sha256:283887f...`
- **Region**: us-east-2 (zones: us-east-2a, us-east-2b, us-east-2c — all 3 zones)
- **Instance type**: m6a.xlarge (AMD EPYC, 4 vCPU, 16 GB RAM)
- **OS**: Red Hat Enterprise Linux CoreOS 9.8.20260520-0 (Plow, RHEL 9)
- **Kernel**: 5.14.0-687.11.1.el9_8.x86_64
- **Kubelet**: v1.35.5, CRI-O: 1.35.3-13.rhaos4.22.git5a749ba.el9
- **Boot AMI**: ami-0f87100a0927b4e1e
- **API**: Legacy MAPI (openshift-machine-api)
- **Rounds**: 10 rounds × 3 zones = **n=30 samples**

### Purpose

Establish a baseline for OCP 4.22.0 node scale-up timing on AWS before upgrading this
cluster to the latest 4.22 nightly, to measure any improvement/regression from
nightly-vs-GA changes.

### Test infrastructure

Test MachineSets `sdods-scl-rngn9-worker-test-2a/2b/2c` remain in the cluster at 0
replicas. To run the next study on the same cluster after upgrading to nightly:

```bash
export KUBECONFIG=aws/auth/kubeconfig
export STUDY_NAME=4.22-nightly-vs-4.22.0
scripts/run-study.sh 10 4.22-nightly
```

---

## Summary (p90, n=30)

Per CLAUDE.md convention, p90 (linear-interpolated, nearest-rank equivalent for n=30) is
used as the headline statistic instead of the mean.

| Phase | p90 | Median | Min | Max | Mean |
|---|---:|---:|---:|---:|---:|
| Cloud VM Provisioning | 26.0s | 23.0s | 18s | 34s | 22.9s |
| Boot 1 total (Ignition → end of MCD firstboot) | 142.2s | 122.5s | 97s | 167s | 125.6s |
| ⤷ Boot 1: Ignition + pivot (derived) | 103.4s | 87.0s | 61s | 111s | — |
| ⤷ Boot 1: MCD firstboot (rpm-ostree rebase) | 40.1s | 36.0s | 34s | 58s | 37.4s |
| Reboot (shutdown + POST + bootloader) | 17.1s | 11.0s | 10s | 18s | 12.6s |
| Boot 2: systemd startup (kernel → boot complete) | 27.5s | 21.1s | 16.3s | 28.3s | 21.3s |
| ⤷ Boot 2: chrony-wait | 17.3s | 11.1s | 7.1s | 18.2s | 11.4s |
| ⤷ Boot 2: CRI-O + Kubelet start (derived, non-chrony) | 10.3s | 9.9s | 9.2s | 10.4s | — |
| Boot 2: kubelet → NodeReady (total) | 97.4s | 87.5s | 75s | 111s | 88.1s |
| ⤷ post-systemd-startup portion (image pulls, derived) | 75.1s | 66.2s | 52.2s | 82.8s | — |
| **Total (MachineSet create → NodeReady)** | **270.0s** | **248.0s** | **215s** | **289s** | **249.1s** |

**Boot 1** = kernel start through the last journal entry of boot 1 (Ignition fetch/apply,
pivot to real root, MCD image pull, rpm-ostree rebase). **MCD firstboot / rebase** is a
sub-phase within Boot 1 and is the single largest contributor (~15% of total at p90).
**Boot 2: kubelet → NodeReady** starts at boot 2 kernel and ends at the NodeReady condition
timestamp; it subsumes the systemd startup phase (including chrony-wait) plus the
subsequent kubelet/CRI-O image-pull period.

### Bottleneck share of total (at p90)

1. **Boot 1: Ignition + pivot** — 103.4s / 270.0s = **38%**
2. **Boot 2: kubelet → NodeReady (post-systemd, image pulls)** — 75.1s / 270.0s = **28%**
3. **Boot 1: MCD firstboot rebase** — 40.1s / 270.0s = **15%**
4. **Cloud VM Provisioning** — 26.0s / 270.0s = **10%**
5. **Boot 2: chrony-wait** — 17.3s / 270.0s = **6%**
6. **Reboot** — 17.1s / 270.0s = **6%**
7. **Boot 2: CRI-O + Kubelet start (non-chrony)** — 10.3s / 270.0s = **4%**

This matches known bottlenecks documented in CLAUDE.md: Boot 1 (Ignition+pivot+MCD
firstboot combined) and kubelet→NodeReady image pulls dominate, with chrony-wait a
consistent ~6% tax on Azure-comparable AWS NTP sync.

---

## Chrony-wait bimodality

`chrony_wait_s` is clearly bimodal across the 30 samples: roughly half the runs land
near ~7s and the other half near ~13-18s, rather than clustering around a single value.
This is consistent with prior AWS NTP chrony-wait behavior (~7-20s range noted in
CLAUDE.md) — worth keeping in mind when comparing against the nightly run, since a shift
in this bimodal split (not just the p90) could itself explain part of any delta.

---

## Per-run raw data

| Round | Zone | VM Prov | Boot 1 | Rebase | Reboot | Sysd | Chrony | KTR | Total |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 2a | 22 | 118 | 35 | 17 | 27.03 | 17.18 | 107 | 264 |
| 1 | 2b | 23 | 113 | 35 | 11 | 16.78 | 7.06 | 83 | 230 |
| 1 | 2c | 24 | 110 | 36 | 10 | 17.37 | 7.05 | 76 | 220 |
| 2 | 2a | 20 | 123 | 36 | 12 | 23.05 | 13.11 | 82 | 237 |
| 2 | 2b | 23 | 140 | 39 | 18 | 24.57 | 14.17 | 92 | 273 |
| 2 | 2c | 25 | 134 | 36 | 16 | 16.33 | 7.05 | 93 | 268 |
| 3 | 2a | 20 | 122 | 35 | 10 | 16.98 | 7.06 | 85 | 237 |
| 3 | 2b | 24 | 111 | 36 | 11 | 28.34 | 18.12 | 93 | 239 |
| 3 | 2c | 26 | 128 | 36 | 10 | 17.12 | 7.05 | 85 | 249 |
| 4 | 2a | 21 | 130 | 37 | 17 | 21.99 | 12.08 | 88 | 256 |
| 4 | 2b | 23 | 137 | 34 | 17 | 24.34 | 15.10 | 93 | 270 |
| 4 | 2c | 25 | 126 | 36 | 11 | 24.67 | 15.09 | 97 | 259 |
| 5 | 2a | 21 | 115 | 36 | 12 | 26.10 | 16.25 | 101 | 249 |
| 5 | 2b | 24 | 122 | 36 | 11 | 21.87 | 12.08 | 88 | 245 |
| 5 | 2c | 25 | 167 | 58 | 11 | 16.82 | 7.05 | 86 | 289 |
| 6 | 2a | 19 | 97 | 36 | 11 | 16.87 | 7.05 | 88 | 215 |
| 6 | 2b | 23 | 115 | 34 | 18 | 19.30 | 10.06 | 86 | 242 |
| 6 | 2c | 20 | 106 | 34 | 11 | 26.42 | 16.08 | 89 | 226 |
| 7 | 2a | 21 | 116 | 36 | 17 | 27.51 | 18.22 | 93 | 247 |
| 7 | 2b | 21 | 138 | 45 | 10 | 17.31 | 7.05 | 87 | 256 |
| 7 | 2c | 26 | 121 | 41 | 12 | 28.23 | 18.19 | 111 | 270 |
| 8 | 2a | 21 | 142 | 40 | 10 | 17.21 | 7.05 | 81 | 254 |
| 8 | 2b | 34 | 125 | 35 | 10 | 17.13 | 7.05 | 75 | 244 |
| 8 | 2c | 26 | 131 | 35 | 11 | 18.79 | 9.08 | 93 | 261 |
| 9 | 2a | 22 | 116 | 37 | 11 | 27.54 | 17.17 | 85 | 234 |
| 9 | 2b | 18 | 116 | 36 | 12 | 23.00 | 13.13 | 88 | 234 |
| 9 | 2c | 25 | 117 | 34 | 11 | 16.88 | 7.06 | 83 | 236 |
| 10 | 2a | 21 | 144 | 37 | 11 | 16.99 | 7.06 | 82 | 258 |
| 10 | 2b | 23 | 151 | 40 | 18 | 20.26 | 10.11 | 77 | 269 |
| 10 | 2c | 20 | 136 | 40 | 11 | 22.78 | 13.11 | 75 | 242 |

Raw artifacts for all 30 samples live in `data/4.22.0-m6a-baseline/` (gitignored).
`data/4.22.0-m6a-baseline/summary.csv` has the machine-readable aggregate.
