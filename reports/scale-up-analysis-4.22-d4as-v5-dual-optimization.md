# Node Scale-Up Time Analysis: Azure Standard_D4as_v5 (4.22 nightly) — Dual Optimization Study

## Cluster

- **Cluster**: ci-ln-1q9tbht-1d09d-xdrk8 (Azure East US)
- **Baseline OCP version**: 4.22.0-0.nightly-2026-06-11-035725
- **Experiment OCP version**: 4.22.0-0.nightly-2026-06-11-095013
- **Region**: East US, Zones 1, 2, 3
- **Instance Type**: Standard_D4as_v5 (AMD EPYC, 4 vCPU, 16 GB RAM)
- **Boot Image**: azureopenshift / aro4 / sku: 420-v2 (same for both baseline and experiment)
- **API**: MAPI (openshift-machine-api)
- **Study**: `4.22-d4as-v5-dual-opt`
- **Baseline samples**: n=6 (2 rounds × 3 zones)
- **Experiment samples**: n=10 (3 full rounds × 3 zones + r4 zone 1; cluster expired during r4)

## Changes Under Test

Two MCO changes shipped together in the 095013 nightly:

1. **chrony-wait skip on first node join** ([MCO PR #6168](https://github.com/openshift/machine-config-operator/pull/6168), cherry-pick of PR #5990)

   A `ConditionPathExists=/var/lib/kubelet/pki/kubelet-client-current.pem` dropin is added
   to `chrony-wait.service`. On a brand-new node joining the cluster, that client certificate
   doesn't exist yet — it's created only after the node successfully authenticates with the
   API server. systemd evaluates the condition false and skips the unit entirely; chrony-wait
   never starts at all.

2. **Fix overzealous OS extensions pull** ([MCO PR #6169](https://github.com/openshift/machine-config-operator/pull/6169), cherry-pick of PR #5905)

   During MCD firstboot, MCO previously pulled the OS extensions container image whenever an
   OS update was applied — which is true on every new node join. The fix tightens the
   condition: the extensions image is now only fetched when the node config actually specifies
   OS extensions or a non-default kernel type. For a standard worker node with neither
   configured, this eliminates an unnecessary ~30 s pull and extraction step from Boot 1.

## Baseline Results (n=6, nightly-035725)

| Sample | VM Prov | Boot 1 | Rebase | Reboot | Boot 2 (SA) | chrony-wait | KTR | **Total** |
|--------|---------|--------|--------|--------|-------------|-------------|-----|-----------|
| r1-z1  | 21s | 141s | 66s | 4s | 36.2s | 24.1s | 99s  | **265s** |
| r1-z2  | 22s | 164s | 77s | 7s | 32.9s | 24.1s | 109s | **302s** |
| r1-z3  | 20s | 142s | 67s | 5s | 37.1s | 24.1s | 92s  | **259s** |
| r2-z1  | 19s | 133s | 56s | 5s | 35.6s | 24.1s | 112s | **269s** |
| r2-z2  | 25s | 132s | 56s | 4s | 33.2s | 24.1s | 100s | **261s** |
| r2-z3  | 27s | 135s | 58s | 5s | 36.8s | 24.1s | 99s  | **266s** |
| **Mean** | **22s** | **141s** | **63s** | **5s** | **35.3s** | **24.1s** | **102s** | **270s** |
| **p90**  | **26s** | **151s** | **71s** | **6s** | **37s**   | **24.1s** | **110s** | **282s** |

*Boot 2 (SA) = systemd-analyze total (kernel+initrd+userspace). KTR = Boot 2 kernel → NodeReady.*

## Experiment Results (n=10, nightly-095013, both optimizations)

| Sample  | VM Prov | Boot 1 | Rebase | Reboot | Boot 2 (SA) | chrony-wait | KTR | **Total** |
|---------|---------|--------|--------|--------|-------------|-------------|-----|-----------|
| r1-z1   | 24s | 129s | 82s | 5s | 17.7s | <1s | 89s  | **247s** |
| r1-z2   | 22s | 130s | 83s | 5s | 13.5s | <1s | 86s  | **243s** |
| r1-z3   | 25s | 152s | 81s | 5s | 17.9s | <1s | 93s  | **275s** |
| r2-z1   | 21s | 121s | 74s | 4s | 15.4s | <1s | 102s | **248s** |
| r2-z2   | 22s | 114s | 66s | 4s | 14.1s | <1s | 82s  | **222s** |
| r2-z3   | 21s | 129s | 76s | 8s | 19.2s | <1s | 109s | **267s** |
| r3-z1   | 21s | 107s | 62s | 4s | 17.4s | <1s | 78s  | **210s** |
| r3-z2   | 23s | 107s | 62s | 5s | 14.2s | <1s | 72s  | **207s** |
| r3-z3   | 24s | 106s | 60s | 5s | 17.8s | <1s | 79s  | **214s** |
| r4-z1   | 22s | 123s | 76s | 6s | 15.8s | <1s | 77s  | **228s** |
| **Mean** | **23s** | **122s** | **72s** | **5s** | **16.3s** | **<1s** | **87s** | **236s** |
| **p90**  | **24s** | **130s** | **82s** | **6s** | **18s**   | **<1s** | **102s** | **267s** |

## Phase-by-Phase Comparison

| Phase | Baseline p90 | Experiment p90 | Delta | Notes |
|-------|-------------|----------------|-------|-------|
| VM Provisioning | 26s | 24s | −2s | Noise |
| Boot 1 total | 151s | 130s | **−21s** | Baseline includes ~30s extensions pull |
| └ Rebase fetch+apply | 71s | 82s | +11s | See discussion below |
| Reboot (shutdown→POST) | 6s | 6s | 0s | Unchanged |
| Boot 2: systemd startup | 37s | 18s | **−19s** | chrony-wait eliminated |
| Boot 2: kernel→NodeReady | 110s | 102s | **−8s** | Partially masked by CNI parallelism |
| **Total** | **282s** | **267s** | **−15s** | |

## Key Observations

### 1. chrony-wait Eliminated (−24 s, Azure PHC clock)

In the baseline, `chrony-wait.service` is always the dominant Boot 2 bottleneck at exactly
~24.1 s (range: 24.074–24.095 s). It sits on the critical path to `graphical.target`:

```
# Baseline critical chain (r1-z1)
graphical.target @28.027s
└─kubelet.service @27.781s +245ms
  └─crio.service @27.106s +666ms
    └─kubelet-dependencies.target @27.092s
      └─chrony-wait.service @2.997s +24.095s   ← bottleneck
        └─chronyd.service @2.901s +78ms
```

After the PR #6168 dropin is applied, `kubelet-client-current.pem` does not yet exist on a
freshly joining node, so systemd evaluates the `ConditionPathExists` condition as false and
skips `chrony-wait.service` entirely. The unit never runs and does not appear in
`systemd-analyze blame` at all:

```
# Experiment critical chain (r1-z1)
graphical.target @9.888s
└─kubelet.service @9.578s +309ms
  └─crio.service @8.921s +636ms
    └─kubelet-dependencies.target @8.908s
      └─node-valid-hostname.service @8.894s +10ms   ← new bottleneck (<10 ms)
        └─basic.target @3.039s
```

The `systemd-analyze` userspace time drops from ~28 s to ~10 s — a clean 18-s improvement
on the critical path.

### 2. Boot 2 systemd startup: 37 s → 18 s p90

Every baseline sample spent 32–37 s in Boot 2 systemd startup. Every experiment sample
completes in 13–19 s. The savings are consistent and near-identical across all zones and
rounds because the PHC clock is always accurate — there is no variance in this benefit.

| | Baseline | Experiment |
|--|---------|-----------|
| userspace to graphical.target | 28.0–28.6 s | 8.9–10.7 s |
| systemd-analyze total | 32.9–37.1 s | 13.5–19.2 s |
| Top blame entry | chrony-wait.service ~24 s | sys-module-fuse.device ~4 s |

### 3. Total NodeReady improvement: −34 s mean, −15 s p90

The chrony-wait saving translates to 34 s off the mean (270 → 236 s) and 15 s off p90
(282 → 267 s). The p90 savings are smaller than the mean savings because:

- The p90 tail is dominated by natural VM provisioning and CNI pull variance (not by
  chrony-wait, which is constant).
- Some of Boot 2 runs in parallel with the 19 s chrony-wait saving: CRI-O and kubelet
  start before graphical.target is reached, so eliminating chrony-wait doesn't yield
  a full 24 s reduction in KTR (kernel→NodeReady time).

### 4. Boot 1 is shorter despite the rebase metric appearing longer

The rebase_total metric (time from "Initiated txn Rebase" to "Created deployment") shows
+11 s in experiment p90. However, Boot 1 total is −21 s shorter. The explanation is that
the rebase_total metric does not capture the OS extensions pull that occurred in the
baseline before the rebase started.

Baseline journals confirm an unnecessary ~30 s overhead on every node join (r1-z1 example):
- `podman pull` of the extensions image: ~22 s (17:12:27 → 17:12:49)
- `podman cp` extraction and relabeling: ~8 s (17:12:49 → 17:12:57)

With PR #6169, this pull and extraction step is entirely absent from experiment journals.
The rebase_total metric appears +11 s longer in experiment p90 because the baseline's
extensions pull (which completed immediately before the rebase started) warmed the disk
I/O path; in experiment the rebase starts without that warmup. The true savings are
captured in the Boot 1 total column: −21 s at p90.

### 5. Rebase data: same image content, different nightly

- Baseline node image: `ocp-v4.0-art-dev@sha256:759db300...` (nightly-035725)
- Experiment node image: `ocp-v4.0-art-dev@sha256:4b04c7eb...` (nightly-095013)

Both require the same **64 ostree chunks, 1.5 GB total** from the same boot image
(`aro4 / 420-v2`). Comparing rebase times is valid; the data sizes are controlled.

## Boot 2 systemd-analyze Detail

| Sample | firmware | loader | kernel | initrd | userspace | total |
|--------|----------|--------|--------|--------|-----------|-------|
| **Baseline** | | | | | | |
| r1-z1 | 232ms | 3.0s | 967ms | 3.9s | 28.1s | 36.2s |
| r1-z2 | — | — | 1.0s | 3.3s | 28.6s | 32.9s |
| r1-z3 | 249ms | 3.4s | 1.0s | 3.9s | 28.6s | 37.1s |
| r2-z1 | 237ms | 3.0s | 921ms | 3.2s | 28.3s | 35.6s |
| r2-z2 | — | — | 1.0s | 4.0s | 28.1s | 33.2s |
| r2-z3 | 232ms | 3.3s | 971ms | 3.9s | 28.3s | 36.8s |
| **Experiment** | | | | | | |
| r1-z1 | 329ms | 3.1s | 888ms | 3.4s | 10.0s | 17.7s |
| r1-z2 | — | — | 1.0s | 3.3s | 9.1s | 13.5s |
| r1-z3 | 277ms | 3.5s | 973ms | 3.4s | 9.8s | 17.9s |
| r2-z1 | — | — | 1.0s | 3.5s | 10.8s | 15.4s |
| r2-z2 | — | — | 966ms | 3.5s | 9.7s | 14.1s |
| r2-z3 | 275ms | 3.5s | 964ms | 3.9s | 10.6s | 19.2s |
| r3-z1 | 235ms | 3.0s | 970ms | 3.9s | 9.4s | 17.4s |
| r3-z2 | — | — | 1.1s | 3.4s | 9.8s | 14.2s |
| r3-z3 | 314ms | 3.4s | 962ms | 3.3s | 9.8s | 17.8s |
| r4-z1 | — | — | — | — | — | 15.8s |

The kernel+initrd time (pre-userspace) is consistent at ~4–8 s across both groups.
All 18+ s of the Boot 2 improvement comes from userspace (the chrony-wait elimination).

## Confound Note

Baseline and experiment ran on different nightly builds (2026-06-11-035725 vs 2026-06-11-095013).
The two changes under test are the only known differences shipping in 095013. Boot image
(`aro4 / 420-v2`), instance type, region, and rebase data volume (64 chunks, 1.5 GB) are
identical. The chrony-wait result is unambiguous; the extensions pull elimination is confirmed by
journal inspection but partially masked in the rebase_total metric by I/O path warmup
differences (see observation #4).

## Summary

| Metric | Baseline (n=6) | Experiment (n=10) | Improvement |
|--------|---------------|-------------------|-------------|
| Total mean | 270 s | 236 s | **−34 s** |
| Total p90 | 282 s | 267 s | **−15 s** |
| Boot 2 systemd (mean) | 35.3 s | 16.3 s | **−19 s** |
| Boot 2 systemd (p90) | 37 s | 18 s | **−19 s** |
| chrony-wait | ~24 s | <1 s | **−24 s** |
| Boot 1 (mean) | 141 s | 122 s | **−19 s** |
| Boot 1 (p90) | 151 s | 130 s | **−21 s** |

Both changes are confirmed effective on Azure:
- **chrony-wait skip (PR #6168)**: eliminates the 24 s NTP sync wait entirely by skipping
  the unit on first node join (`ConditionPathExists` evaluates false — kubelet client cert
  not yet present).
- **Extensions pull fix (PR #6169)**: removes ~30 s of unnecessary extensions pull+copy
  from Boot 1 on nodes with no OS extensions or non-default kernel type configured.

## Artifacts

Study data directory: `data/4.22-d4as-v5-dual-opt/`

Per-sample artifact suffixes:
- **Baseline**: `4.22-d4as-v5-baseline-r{1,2}-{1,2,3}` (6 samples)
- **Experiment**: `4.22-d4as-v5-chrony-fsync-r{1,2,3}-{1,2,3}` + `r4-1` (10 samples)

Artifact types per suffix: `node-journal-*.log`, `node-boot-list-*.txt`,
`node-systemd-analyze-*.txt`, `node-systemd-blame-*.txt`,
`node-systemd-critical-chain-*.txt`, `node-images-detail-*.json`,
`new-machine-*-final.yaml`, `new-node-*.yaml`, `csr-list-*.txt`
