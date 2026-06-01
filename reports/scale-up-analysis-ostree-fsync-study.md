# Node Scale-Up Analysis: ostree fsync Disable — MCD Firstboot Study

## Cluster

- **OCP version**: 4.21.17
- **Region**: us-east-1 (zones: us-east-1a, us-east-1d)
- **Instance type**: m6a.xlarge (AMD EPYC, 4 vCPU, 16 GB RAM)
- **API**: Legacy MAPI (openshift-machine-api)
- **Boot image (AMI)**: ami-04018496b0a1da2d2 — RHCOS **9.6.20251212-1** (Dec 12 2025)
- **Target RHCOS (post-rebase)**: 9.6.20260520-0 (~5 months of boot image drift)
- **Kernel**: 5.14.0-570.116.1.el9_6.x86_64
- **rpm-ostree**: 2025.6-5.el9_6 → 2025.6-6.el9_6 (upgraded during rebase)

---

## Hypothesis

ostree's `core.fsync` setting controls whether the ostree library calls `syncfs()` after writing
each chunk during an image pull. With fsync enabled (default), rpm-ostree issues a blocking
`syncfs()` call after every chunk — Dusty Mabe's analysis of an FCoS baseline showed this added
~23s of wall-clock time during a 66-chunk rebase, with the first call alone taking 15.5s.

The hypothesis: disabling `core.fsync` during the MCD firstboot rebase would meaningfully
reduce the MCD firstboot phase duration and thus total node scale-up time.

---

## Method

A MachineConfig drop-in was applied to `machine-config-daemon-firstboot.service` that:

1. Runs `ostree config --repo=/sysroot/ostree/repo set core.fsync false` in `ExecStartPre`
   before the MCD container launches (and before `rpm-ostreed` is D-Bus activated)
2. Restores `ostree config --repo=/sysroot/ostree/repo set core.fsync true` in `ExecStopPost`

The drop-in is applied via:

```
manifests/machineconfig-mcd-firstboot-disable-fsync.yaml
```

**Why this unit:** `rpm-ostreed` is D-Bus socket-activated by MCD ~1s after
`machine-config-daemon-firstboot.service` starts. The `ExecStartPre` writes to the ostree repo
config before `rpm-ostreed` activates, so it reads `fsync=false` from the start. The drop-in on
`machine-config-daemon-firstboot.service` correctly scopes the change to firstboot only, rather
than affecting all `rpm-ostreed` operations.

**Firstboot duration** is used as a proxy for rpm-ostree rebase time. It is measured from
`Starting Machine Config Daemon Firstboot` to the `SIGTERM` sent to the service at reboot, as
logged by systemd.

---

## Results

**Baseline** — 5 rounds, n=8 complete samples (2 samples had journals truncated before the TERM
signal and could not be reliably estimated):

| Sample | Duration |
|--------|----------|
| r1-1a | 102s |
| r1-1d | 94s |
| r2-1a | 81s |
| r2-1d | 92s |
| r3-1a | 99s |
| r3-1d | 83s |
| r4-1d | 105s |
| r5-1a | 83s |
| **p90** | **102s** |
| min/max | 81s / 105s |

**fsync-disabled** — 5 rounds, n=9 complete samples:

| Sample | Duration |
|--------|----------|
| r1-1a | 95s |
| r1-1d | 108s |
| r2-1a | 78s |
| r3-1a | 86s |
| r3-1d | 80s |
| r4-1a | 88s |
| r4-1d | 93s |
| r5-1a | 96s |
| r5-1d | 77s |
| **p90** | **96s** |
| min/max | 77s / 108s |

| Metric | Baseline | fsync-disabled | Delta |
|--------|----------|----------------|-------|
| p90 | 102s | 96s | −6s |
| min | 81s | 77s | −4s |
| max | 105s | 108s | +3s |

---

## Key Finding: No Per-Chunk syncfs in 4.21.17

Journal inspection of both conditions shows **no per-chunk `syncfs()` calls** during the fetch
phase in either the baseline or the fsync-disabled runs. The chunk fetch pattern is identical —
chunks complete in rapid succession with no syncfs interleaved:

```
17:09:24  [0/42] Fetching ostree chunk 831efff... (623.0 MB)...done
17:09:25  [1/42] Fetching ostree chunk 6b3b350... (32.0 MB)...done
17:09:25  [2/42] Fetching ostree chunk 739066c... (22.3 MB)...done
...
```

This is in contrast to the FCoS baseline Dusty observed (older rpm-ostree), which showed a
blocking `syncfs()` call after every chunk — 66 calls totaling 23s, with the first alone taking
15.5s.

The only `syncfs` activity in the 4.21.17 journals appears in **boot 2** (post-reboot), where
`rpm-ostreed` does a single `syncfs() for /ostree` taking ~8.7s. This is unrelated to the
firstboot rebase.

The 6s p90 improvement and overlapping ranges are consistent with normal run-to-run noise, not a
real effect. The optimization target simply does not exist in rpm-ostree 2025.6 on 4.21.17.

---

## Conclusion

**The MachineConfig has no meaningful effect on 4.21.17.** rpm-ostree 2025.6 does not perform
per-chunk `syncfs()` during the fetch phase, so disabling `core.fsync` in the ostree repo config
provides no benefit during the MCD firstboot rebase on this version.

---

## Next Steps

Test on **OCP 4.22**, which ships a newer rpm-ostree version that is expected to emit per-chunk
`syncfs` log messages (as seen in Dusty's FCoS test). Presence of those log messages will
confirm the blocking syncfs behavior is active and that the optimization has something to act on.
If confirmed, re-run this study on a 4.22 cluster with back-to-back baseline and fsync-disabled
rounds.
