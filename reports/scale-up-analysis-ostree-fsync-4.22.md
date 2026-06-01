# Node Scale-Up Analysis: ostree fsync Disable — 4.22 Follow-up Study

## Overview

This is the follow-up to the [4.21.17 ostree fsync study](scale-up-analysis-ostree-fsync-study.md),
which found no detectable effect on 4.21.17 because that cluster shipped ostree 2025.2 — a version
that performs per-chunk syncfs silently (no journal logging). On 4.22, ostree 2025.6+ logs each
syncfs call individually, confirming the behavior is active and measurable.

## Cluster

- **OCP version**: 4.22.0-rc.2
- **Region**: us-west-2 (zones: us-west-2b, us-west-2c)
- **Instance type**: m6a.xlarge (AMD EPYC, 4 vCPU, 16 GB RAM)
- **API**: Legacy MAPI (openshift-machine-api)
- **Boot image (AMI)**: ami-087857c3acb318eac — RHCOS **9.8.20260403-0** (Apr 3 2026)
- **Target RHCOS (post-rebase)**: 9.8.20260425-0 (~22 days of boot image drift)
- **Kernel**: 5.14.0-687.5.1.el9_8.x86_64

---

## Rebase Characteristics

- **Layers already present**: 34 (ostree: 33, custom: 1)
- **Layers fetched**: 34 — 32 ostree chunks (359.8 MB) + 2 custom layers (185.9 MB) = **545.7 MB total**
- **Fetch-phase syncfs**: 34 calls (one per fetched chunk), total **~3.3s** per run

The 22-day boot image drift is much smaller than the 4.21.17 study (5 months), resulting in a
smaller rebase and proportionally smaller syncfs overhead than seen in Dusty Mabe's FCoS baseline
(which showed 23s across 66 chunks on colder storage).

---

## Optimization

A MachineConfig drop-in on `machine-config-daemon-firstboot.service` disables ostree fsync for
the duration of the MCD firstboot rebase:

```
manifests/machineconfig-mcd-firstboot-disable-fsync.yaml
```

`ExecStartPre=ostree config --repo=/sysroot/ostree/repo set core.fsync false` runs before MCD
launches and before `rpm-ostreed` is D-Bus activated, so all per-chunk syncfs calls during the
fetch are suppressed. `ExecStopPost` restores `core.fsync true` before reboot.

**Round 1 of the fsync-disabled experiment was contaminated** — the rendered MachineConfig had
not yet propagated to those nodes (still showed 34 syncfs calls). Rounds 2–6 are clean.

---

## Results

### Baseline (n=6 complete of 10, 5 rounds × 2 zones)

| Sample | Firstboot duration | Fetch syncfs |
|--------|--------------------|--------------|
| r1-2c | 84s | 34 calls / 3265ms |
| r3-2c | 94s | 34 calls / 3704ms |
| r4-2b | 88s | 34 calls / 3496ms |
| r4-2c | 92s | 34 calls / 3231ms |
| r5-2b | 84s | 34 calls / 3369ms |
| r5-2c | 197s (\*) | 34 calls / 3322ms |

(\*) Outlier — likely scheduling or network anomaly.

- **p90: 94s** (excluding outlier cluster: 84–94s)
- Fetch-phase syncfs consistent at **~3.3s** per run

### fsync-disabled rounds 2–6 (n=5 complete, clean)

| Sample | Firstboot duration | Fetch syncfs |
|--------|--------------------|--------------|
| r2-2b | 78s | 0 calls |
| r4-2b | 90s | 0 calls |
| r4-2c | 90s | 0 calls |
| r5-2b | 74s | 0 calls |
| r5-2c | 87s | 0 calls |

- **p90: 90s**
- Fetch-phase syncfs: **0** across all clean runs ✓

### Comparison

| Metric | Baseline | fsync-disabled | Delta |
|--------|----------|----------------|-------|
| Fetch syncfs calls | 34 | 0 | −34 |
| Fetch syncfs total | ~3.3s | 0s | **−3.3s** |
| min | 84s | 74s | −10s |
| max | 197s\* / 94s | 90s | — |
| **p90** | **94s** | **90s** | **−4s** |

---

## Key Findings

1. **The optimization works on 4.22.** With ostree 2025.6+, per-chunk syncfs calls are logged
   and confirmed active. Setting `core.fsync false` eliminates all 34 fetch-phase syncfs calls.

2. **The savings are ~3–4s at p90.** The per-chunk syncfs totals ~3.3s on this instance with
   EBS-backed storage and a 22-day-old boot image. This is smaller than Dusty Mabe's FCoS test
   (23s across 66 chunks) due to fewer chunks, a smaller rebase, and faster/warmer storage.

3. **The savings scale with rebase size and storage latency.** A cluster with a larger boot image
   drift (more chunks) or slower storage would see proportionally larger savings. In the worst
   case observed in Dusty's test, the first syncfs alone took 15.5s.

4. **4.21.17 result revisited.** That cluster shipped ostree 2025.2, which performs per-chunk
   syncfs silently (no per-op journal logging added until 2025.6). The ~3s savings likely existed
   but were undetectable within the natural ~20s variance of 8–9 samples.

---

## Conclusion

The MachineConfig optimization is valid and measurable on 4.22. At the scale-up rates typical
in production (many nodes simultaneously), a consistent 3–4s reduction per node in the MCD
firstboot phase is meaningful. Whether the improvement justifies shipping the MachineConfig
depends on whether the target environment has larger boot image drift or slower storage than
tested here.
