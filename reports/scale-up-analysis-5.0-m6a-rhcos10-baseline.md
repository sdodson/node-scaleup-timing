# Node Scale-Up Analysis: OCP 5.0.0-ec.4 RHCOS10 Baseline (us-east-2)

## Cluster

- **Cluster**: sdods-el10-m4lm6 (OCP 5.0.0-ec.4)
- **Region**: us-east-2 (zones: us-east-2a, us-east-2b)
- **Instance type**: m6a.xlarge (AMD EPYC 3rd Gen, 4 vCPU, 16 GB RAM)
- **OS**: Red Hat Enterprise Linux CoreOS 10.2.20260627-0 (Coughlan, RHEL 10)
- **Kernel**: 6.12.0-211.28.1.el10_2.x86_64
- **Kubelet**: v1.35.3, CRI-O: 1.36.1-2.rhaos5.0.git5d8e346.el10
- **Boot image (AMI)**: ami-0df81851781a7c7c7
- **API**: Legacy MAPI (openshift-machine-api)
- **Rounds**: 10 (n=20 samples: 2 zones × 10 rounds)
- **Date**: 2026-07-14, 17:40–19:17 UTC

### Purpose

RHCOS10 experiment on OCP 5.0.0-ec.4 on the same cluster as the RHCOS9 baseline
study (`scale-up-analysis-5.0-m6a-rhcos9-baseline.md`). Direct comparison: same
cluster, same instance type, same region, same OCP version. Test MachineSets used
ami-0df81851781a7c7c7 (RHCOS10 AMI). The cluster has the chrony-wait skip
MachineConfig active, same as the RHCOS9 baseline.

---

## Summary: All 20 Runs

| Run      | Zone | VM Prov | Boot 1 | Reboot | Boot2→Ready | Total |
|----------|------|---------|--------|--------|-------------|-------|
| r1 2a    | 2a   | 21s     | 130s   | 17s    | 60s         | 228s  |
| r1 2b    | 2b   | 23s     | 108s   | 17s    | 58s         | 206s  |
| r2 2a    | 2a   | 20s     | 164s   | 11s    | 51s         | **246s** |
| r2 2b    | 2b   | 23s     | 159s   | 10s    | 55s         | **247s** |
| r3 2a    | 2a   | 21s     | 113s   | 18s    | 56s         | 208s  |
| r3 2b    | 2b   | 24s     | 107s   | 18s    | 55s         | 204s  |
| r4 2a    | 2a   | 20s     | 94s    | 11s    | 51s         | 176s  |
| r4 2b    | 2b   | 22s     | 107s   | 16s    | 57s         | 202s  |
| r5 2a    | 2a   | 16s     | 100s   | 12s    | 55s         | 183s  |
| r5 2b    | 2b   | 24s     | 96s    | 10s    | 56s         | 186s  |
| r6 2a    | 2a   | 20s     | 107s   | 18s    | 57s         | 202s  |
| r6 2b    | 2b   | 22s     | 98s    | 16s    | 56s         | 192s  |
| r7 2a    | 2a   | 20s     | 97s    | 17s    | 56s         | 190s  |
| r7 2b    | 2b   | 23s     | 102s   | 18s    | 60s         | 203s  |
| r8 2a    | 2a   | 21s     | 95s    | 11s    | 58s         | 185s  |
| r8 2b    | 2b   | 24s     | 93s    | 11s    | 59s         | 187s  |
| r9 2a    | 2a   | 21s     | 107s   | 17s    | 54s         | 199s  |
| r9 2b    | 2b   | 23s     | 107s   | 17s    | 61s         | 208s  |
| r10 2a   | 2a   | 21s     | 134s   | 17s    | 61s         | 233s  |
| r10 2b   | 2b   | 23s     | 104s   | 11s    | 59s         | 197s  |
| **p90**  |      | **24s** | **134s** | **18s** | **60s** | **233s** |
| Median   |      | 21.5s   | 107s   | 16.5s  | 56.5s       | 202s  |
| Min      |      | 16s     | 93s    | 10s    | 51s         | 176s  |
| Max      |      | 24s     | 164s   | 18s    | 61s         | 247s  |

**Boot 1** = kernel start through end of MCD firstboot (Ignition, pivot, MCD pull, rpm-ostree rebase, shutdown).
**Reboot** = gap between Boot 1 last journal entry and Boot 2 first kernel entry.
**Boot2→Ready** = Boot 2 kernel to NodeReady condition timestamp.

Round 2 produced the two highest Boot 1 values (164s, 159s) and overall totals (246s,
247s). These are EC2/registry placement outliers — all other rounds show Boot 1 ≤ 134s.
With n=20 these outliers no longer affect p90 (p90 = 18th of 20 sorted values = 233s).

---

## Phase Detail

### Boot 1: MCD Firstboot

Boot 1 breaks down into three sub-phases (measured from journal timestamps):

| Sub-phase | Median | p90 |
|-----------|--------|-----|
| Pre-rebase (Ignition + pivot + MCD setup) | 40s | ~55s |
| MCD rebase (fetch + apply) | 47.5s | 70s |
| — rebase fetch only | 40s | 52s |
| Post-rebase shutdown | 9.5s | 12s |
| **Boot 1 total** | **107s** | **134s** |

The rebase uses the chunked native container format with identical composition
across all 20 runs:

- **51 ostree chunks** needed, 14 present in boot image (37 pulled fresh)
- **3 custom layers** (MachineConfig-derived), 209 MB
- **Total fetch**: 885.9 MB

**Post-rebase shutdown** (from "changes queued" to last boot1 journal entry)
is 9.5s median, dramatically shorter than RHCOS9's ~23s. RHCOS10 eliminates
the OSTree finalize overhead present in RHCOS9.

### Boot 2: systemd startup

| | Kernel | Initrd | Userspace | Total |
|--|--------|--------|-----------|-------|
| Median | 1.93s | 3.74s | 9.78s | 15.7s |
| p90 | 1.96s | 4.02s | 10.3s | 16.1s |

Key services from `systemd-analyze blame` (p90 across all 20 runs):

| Service | p90 |
|---------|-----|
| `ovs-configuration.service` | 3.4s |
| `kubelet.service` | 0.71s |
| `crio.service` | 0.74s |
| `chrony-wait.service` | **skipped** (MachineConfig drop-in) |

### Boot 2: kubelet → NodeReady

Timeline (r1 2a reference, 60s Boot2→Ready):

```
t+0s   Boot 2 kernel
t+15s  systemd graphical.target reached; kubelet + CRI-O active
t+15s  First CRI-O image pulls begin (9 concurrent)
t+46s  Last blocking image pull completes
t+60s  NodeReady condition set (14s gap: CNI initialization)
```

---

## Image Pull Analysis (r1 2a reference run)

### Boot 2 images — 22 images, 9,740 MB

All images are from `quay.io/openshift-release-dev/ocp-v5.0-art-dev`. NodeReady
was set at **t+60s**. Timestamps are relative to Boot 2 kernel (t+0).

9 images start pulling simultaneously at t+15s — pulls are not serialized globally.

#### Blocking images — 14 images, 6,380 MB (complete before NodeReady at t+60s)

| Size | Start | End | Dur |
|-----:|------:|----:|----:|
| 258 MB  | t+15s | t+24s |  9s |
| 219 MB  | t+15s | t+22s |  7s |
| 319 MB  | t+15s | t+26s | 11s |
| 324 MB  | t+15s | t+27s | 12s |
| 370 MB  | t+15s | t+28s | 13s |
| 391 MB  | t+15s | t+31s | 16s |
| 472 MB  | t+15s | t+32s | 17s |
| 1,311 MB | t+15s | t+46s | 31s |
| 1,477 MB | t+15s | t+48s | 33s |
| 525 MB  | t+27s | t+36s |  9s |
| 213 MB  | t+28s | t+34s |  6s |
| 213 MB  | t+35s | t+37s |  2s |
| 202 MB  | t+37s | t+40s |  3s |
| 198 MB  | t+40s | t+46s |  6s |

Last blocking image completes at t+46s. The 14s gap to NodeReady (t+60s) is CNI
plugin initialization, not image pulling.

#### Non-blocking images — 8 images, 3,360 MB (complete after NodeReady)

| Size | Start | End | Dur |
|-----:|------:|----:|----:|
| 795 MB  | t+48s  | t+62s  | 14s |
| 293 MB  | t+62s  | t+65s  |  3s |
| 195 MB  | t+62s  | t+64s  |  2s |
| 392 MB  | t+62s  | t+71s  |  9s |
| 258 MB  | t+64s  | t+66s  |  2s |
| 252 MB  | t+80s  | t+81s  |  1s |
| 420 MB  | t+80s  | t+83s  |  3s |
| 646 MB  | t+83s  | t+90s  |  7s |

---

## Comparison: RHCOS10 vs RHCOS9 (same cluster, OCP 5.0.0-ec.4)

RHCOS9 baseline: n=10 (5 rounds). RHCOS10: n=20 (10 rounds).

| Phase | RHCOS9 p90 | RHCOS10 p90 | Delta | RHCOS9 median | RHCOS10 median | Delta |
|-------|-----------|------------|-------|--------------|----------------|-------|
| VM provisioning | 24s | 24s | 0s | 22s | 21.5s | −0.5s |
| Boot 1 | 145s | **134s** | **−11s** | 134s | 107s | **−27s** |
| Reboot | 18s | 18s | 0s | 17s | 16.5s | −0.5s |
| Boot2→Ready | 94s | **60s** | **−34s** | 74s | 56.5s | **−17.5s** |
| **Total** | **277s** | **233s** | **−44s** | **245s** | **202s** | **−43s** |

### Boot 2 systemd startup

| | RHCOS9 p90 | RHCOS10 p90 | Delta |
|-|------------|-------------|-------|
| Kernel | 1.84s | 1.96s | +0.12s |
| Initrd | 2.96s | 4.02s | +1.06s |
| Userspace | 21.3s | 10.3s | **−11s** |
| **Total** | **26.4s** | **16.1s** | **−10.3s** |

---

## Key Observations

### 1. RHCOS10 is 44s faster p90, 43s faster in median

Total scale-up time: 233s p90 (vs 277s RHCOS9), 202s median (vs 245s RHCOS9).
Both p90 and median show consistent, large improvements with no regressions in
VM provisioning or reboot time.

### 2. Boot2→Ready drives the improvement (−34s p90)

The KTR improvement comes from two sources:
- **Faster systemd userspace**: 10.3s vs 21.3s p90 (−11s). `kubelet.service`
  activation drops from 5.0s to 0.71s; `ovs-configuration.service` from 5.8s to 3.4s.
  RHCOS10 systemd userspace variance is also much tighter: 9.5s–10.7s vs 8.8s–22.2s.
- **Shorter CNI initialization** after last image pull: ~14s vs ~25s (−11s).
- Images start pulling 7s earlier (t+15s vs t+22s) from the faster systemd startup.

### 3. Boot1 improved 11s p90, 27s median

Boot1 p90: 134s vs 145s (−11s). The two round-2 outliers (164s, 159s) are clearly
anomalous EC2/registry events — every other round is 93–134s. With n=20 they no
longer pull the p90 up; median of 107s is the better central-tendency estimate.

The Boot1 improvement is primarily **post-rebase shutdown**: 9.5s median vs ~23s
(−13.5s). RHCOS10 eliminates the OSTree finalize cost that dominated RHCOS9 Boot1.
Rebase fetch time is nearly identical (52s p90 in both).

### 4. Identical rebase composition

Both RHCOS9 and RHCOS10 pull 885.9 MB (51 chunks + 3 custom layers, 14 pre-cached).
The fetch time is not a differentiator — all gains come from systemd startup and
post-rebase shutdown, not from network/storage speed differences.

### 5. Same Boot 2 image set

Both pull 22 images, 9,740 MB. The KTR improvement is not from fewer or smaller
images — it comes entirely from faster systemd startup and faster CNI initialization.

### 6. KTR variance collapsed

RHCOS9 KTR ranged 56s–104s (48s spread). RHCOS10 ranges 51s–61s (10s spread).
The variance reduction comes from RHCOS10's consistent systemd userspace startup
(9.5s–10.7s, 1.2s spread) vs RHCOS9's highly variable 8.8s–22.2s.

---

## Artifacts

All raw data in `data/5.0-m6a-rhcos10-baseline/`:

| Pattern | Description |
|---------|-------------|
| `node-journal-*-r{1..10}-{2a,2b}.log` | Full journalctl (all boots) |
| `node-boot-list-*-r{1..10}-{2a,2b}.txt` | journalctl --list-boots |
| `node-systemd-analyze-*-r{1..10}-{2a,2b}.txt` | systemd-analyze |
| `node-systemd-blame-*-r{1..10}-{2a,2b}.txt` | systemd-analyze blame |
| `node-systemd-critical-chain-*-r{1..10}-{2a,2b}.txt` | systemd-analyze critical-chain |
| `new-machine-*-r{1..10}-{2a,2b}-final.yaml` | Machine object YAML |
| `new-node-*-r{1..10}-{2a,2b}.yaml` | Node object YAML |
| `node-images-detail-*-r{1..10}-{2a,2b}.json` | crictl images JSON |
| `csr-list-*-r{1..10}.txt` | CSR list (one per round) |
| `timings-*-r{1..10}-{2a,2b}.json` | Extracted timing data |
| `rebase-info-*-r{1..10}-{2a,2b}.json` | rpm-ostree rebase details |
| `nodeready-images-*-r{1..10}-{2a,2b}.json` | Boot 2 image pull events |
| `summary.csv` | Aggregated metrics for all 20 runs |
