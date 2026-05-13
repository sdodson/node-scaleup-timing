# Increased chrony-wait Max Correction

## Summary

Relaxing `chrony-wait.service`'s max-correction tolerance from 10 ms to 1 s via a systemd
drop-in reduces `chrony-wait` duration by **3.0 s (−27.5%)** and produces a modest but
inconsistent improvement in Boot 2 startup time. Across n=5 rounds the total scale-up time
is **statistically unchanged** (221.4 s vs. baseline 220.8 s) because `chrony-wait` is only
on the critical path when other Boot 2 services start quickly. When `crio` and `kubelet`
start slowly (rounds 3-5), the chrony-wait improvement is masked completely.

The change is safe — `chrony-wait` still runs and enforces time correctness to within 1 s —
but it delivers far less benefit than eliminating `chrony-wait` on first join (the
kubelet-cert-condition approach), which cuts total time by **8.6 s** and removes all Boot 2
variability from NTP sync.

## Configuration

| Property | Value |
|---|---|
| OCP Version | 4.19.30 |
| Instance Type | m6i.xlarge (4 vCPU, 16 GB RAM) |
| Zone | us-east-2a |
| Boot Image (AMI) | ami-0fd7c367ed8a90d52 (RHCOS 4.19.23 — 7 z-streams stale) |
| Partial images | `enable_partial_images = "true"` (same as all 4.19 runs) |
| MachineConfig | `99-worker-chrony-wait-max-correction` |
| Cluster ID | sdodson-nt-kkvhd |

### MachineConfig drop-in applied

```ini
[Service]
ExecStart=
ExecStart=/usr/bin/chronyc -h 127.0.0.1,::1 waitsync 0 1 0.0 1
```

Default: `waitsync 0 0 0.0 10` — waits until offset < 10 ms.
Applied: `waitsync 0 1 0.0 1` — waits until offset < 1 s.

The 4th argument (`max-correction`) is the threshold; the 3rd (`max-skew`) is 0 (ignored).
The change means `chrony-wait` exits as soon as the clock is within 1 second of real time,
not within 10 ms.

## Results

### Per-round timing

| Round | Total | VM Prov | Boot 1 | Reboot | SA | chrony-wait | KTR | Boot-list |
|---|---|---|---|---|---|---|---|---|
| r1 | 218 s | 21 s | 119 s | 11 s | 15.9 s | **7.0 s** | 41.1 s | 17:30:25→17:32:34 / 17:32:45 |
| r2 | 200 s | 20 s | 114 s | 11 s | 16.0 s | **7.0 s** | 39.0 s | 17:46:01→17:47:55 / 17:48:06 |
| r3 | 217 s | 22 s | 133 s | 11 s | 26.0 s | **7.5 s** | 43.0 s | 17:51:27→17:53:42 / 17:53:53 |
| r4 | 231 s | 20 s | 133 s | 18 s | 25.7 s | **9.1 s** | 34.3 s | 17:57:03→17:59:16 / 17:59:34 |
| r5 | 241 s | 16 s | 139 s | 19 s | 27.1 s | **9.0 s** | 34.9 s | 18:06:11→18:08:30 / 18:08:49 |

Boot-list columns: Boot 1 FIRST ENTRY → Boot 1 LAST ENTRY / Boot 2 FIRST ENTRY.
SA = systemd-analyze total (kernel+initrd+userspace). KTR = (NodeReady − Boot2 kernel) − SA.

### Summary statistics

| Phase | Baseline m6i-partial (n=5) | Chrony-skip (n=4) | Chrony-maxcorr (n=5) | vs. Baseline |
|---|---|---|---|---|
| VM Prov | 19.0 ± 2.1 s | 20.8 ± 1.3 s | 19.6 ± 2.1 s | +0.6 s |
| Boot 1 | 120.0 ± 17.3 s | 123.0 ± 11.1 s | 127.2 ± 9.9 s | +7.2 s |
| Reboot | 13.2 ± 4.0 s | 12.8 ± 3.5 s | 14.0 ± 4.1 s | +0.8 s |
| SA (Boot 2) | 19.8 ± 4.9 s | 19.4 ± 8.1 s | 22.1 ± 5.7 s | +2.3 s |
| **chrony-wait** | **10.9 ± 4.8 s** | **0 s** | **7.9 ± 1.0 s** | **−3.0 s (−27.5%)** |
| KTR | 48.8 ± 10.0 s | 36.3 ± 1.1 s | 38.5 ± 3.8 s | −10.3 s |
| **Total** | **220.8 ± 21.8 s** | **212.2 ± 17.0 s** | **221.4 ± 15.5 s** | **+0.6 s** |

Chrony-skip n=4 (r2 machine YAML lost, so creation timestamp unavailable for total/KTR calculation).

### systemd-analyze per round

| Round | SA total | chrony-wait in blame |
|---|---|---|
| r1 | 15.867 s (kernel 1.555 + initrd 2.984 + userspace 11.327) | 7.043 s |
| r2 | 15.956 s (kernel 1.519 + initrd 2.846 + userspace 11.590) | 7.039 s |
| r3 | 26.021 s (kernel 1.446 + initrd 2.861 + userspace 21.712) | 7.453 s |
| r4 | 25.679 s (kernel 1.580 + initrd 2.717 + userspace 21.381) | 9.061 s |
| r5 | 27.103 s (kernel 1.676 + initrd 3.254 + userspace 22.172) | 9.045 s |

## Analysis

### chrony-wait behavior (confirmed working)

`chrony-wait.service` appears in `systemd-analyze blame` in all 5 rounds, taking 7.0–9.1 s
(mean 7.9 s, stdev 1.0 s). This is consistent and significantly tighter than the baseline
mean of 10.9 s (stdev 4.8 s). The 1-second tolerance means `chronyc waitsync` exits as soon
as the kernel clock is within 1 s of the NTP reference, rather than waiting for the tighter
10 ms convergence. AWS NTP sync is fast enough that the clock is within 1 s almost
immediately, so the service exits in ~7–9 s (dominated by `chronyd` startup latency and
initial NTP exchange, not by waiting for fine-grained correction).

### Critical-path analysis: why total time is unchanged

The improvement in `chrony-wait` duration does **not** always translate to an improvement in
Boot 2 time, because `chrony-wait` is not always on the critical path to
`graphical.target`.

**Rounds 1 and 2 — chrony-wait on the critical path:**

```
graphical.target @11.3 s
└─kubelet.service @10.8 s +545 ms
  └─crio.service @10.1 s +632 ms
    └─kubelet-dependencies.target @10.1 s
      └─chrony-wait.service @3.1 s +7.043 s   ← bottleneck
        └─chronyd.service @2.985 s
```

`crio` and `kubelet` start instantly once chrony-wait finishes (632 ms and 545 ms). SA = 15.9 s.
With the 10 ms tolerance, chrony-wait would have taken ~10–11 s, adding ~3 s to SA.

**Rounds 3–5 — crio/kubelet startup is the bottleneck:**

```
graphical.target @21.7 s
└─kubelet.service @17.1 s +4.562 s
  └─crio.service @12.2 s +4.948 s
    └─kubelet-dependencies.target @12.2 s
      └─node-valid-hostname.service @12.1 s +13 ms   ← resolves late
        └─basic.target @3.2 s
```

`chrony-wait` does not appear in this critical chain — it runs in parallel and finishes before
`crio` begins. The bottleneck is `crio` itself taking ~5 s (vs. 630 ms in fast rounds) and
`kubelet` taking ~4.6 s (vs. 545 ms). `ovs-configuration.service` also took 6.8–6.3 s in
blame across r3–r5. This high-SA pattern occurs in ~60% of runs and is independent of the
chrony-wait configuration — it appears in the partial baseline (r2: SA=27.2 s, r5: SA=15.6 s)
and chrony-skip (r3: SA=27.2 s, r5: SA=25.7 s) as well.

### Total time: no statistically significant change

| Metric | Value |
|---|---|
| Baseline mean | 220.8 s |
| Maxcorr mean | 221.4 s |
| Difference | +0.6 s |
| Baseline stdev | 21.8 s |

A 0.6 s difference against a 21.8 s stdev is well within noise. The chrony-wait
improvement (−3 s) is real but too small to move the total given the high-SA variance.

### KTR: modest improvement

| Condition | KTR mean | Stdev |
|---|---|---|
| Baseline | 48.8 s | 10.0 s |
| Chrony-skip | 36.3 s | 1.1 s |
| Chrony-maxcorr | 38.5 s | 3.8 s |

KTR (time from Boot 2 kernel to NodeReady, minus SA) improved ~10 s vs. baseline. This is
consistent with the chrony-skip improvement (~12.5 s) and reflects earlier kubelet start
enabling earlier CNI image pulls. However, the baseline KTR stdev of 10 s means this
difference is marginally significant (≈1σ). The chrony-skip KTR of 36.3 s is tighter (stdev
1.1 s) because skipping chrony-wait entirely removes the variable network-online delay.

### Comparison with chrony-skip

| Aspect | Chrony-maxcorr | Chrony-skip |
|---|---|---|
| chrony-wait time | 7.9 s ± 1.0 s | 0 s (eliminated on first join) |
| SA improvement vs. baseline | −2.3 s (obscured by slow-boot variance) | −0.4 s (similar) |
| Total time | 221.4 s (no change) | 212.2 s (−8.6 s, plausible) |
| Safety | Strong — clock correctness enforced to 1 s | Weaker — first-join node clock unchecked |
| Complexity | Simple drop-in | Simple drop-in |
| Semantic fit | Tolerant sync (1 s accuracy guaranteed) | Skip-once on first join (cert-based condition) |

With the max-correction approach:
- **Pro**: `chrony-wait` still runs and guarantees clock accuracy to ±1 s before Kubelet starts
- **Pro**: Consistent behavior across first join and all subsequent reboots
- **Con**: Improvement is modest (3 s on chrony-wait, 0 s on total mean)
- **Con**: Cannot fully eliminate the 7–9 s floor imposed by chronyd startup + NTP exchange

With the chrony-skip (kubelet-cert-condition) approach:
- **Pro**: Eliminates chrony-wait entirely on first join → no NTP sync delay at all
- **Pro**: Tighter KTR variance (1.1 s stdev vs. 3.8 s)
- **Con**: Joining node has no enforced clock accuracy (relies on AWS default time sync being close)
- **Con**: First-join behavior differs from post-join reboots (condition checked per-boot)

## Conclusions

1. **chrony-wait duration reduced 27.5%** (10.9 → 7.9 s mean) by relaxing max-correction
   from 10 ms to 1 s. The change is consistent and the service remains active.

2. **Total scale-up time unchanged** (221.4 vs. 220.8 s) because the chrony-wait saving
   is less than the run-to-run variance from slow-crio/kubelet boots (which occur in ~60%
   of rounds regardless of chrony configuration).

3. **chrony-wait is on the critical path only in "fast" boots** (r1, r2: SA ~16 s). In
   "slow" boots (r3–r5: SA ~26 s), `crio` and `kubelet` themselves are the bottleneck,
   and reducing chrony-wait has no effect on the total.

4. **Chrony-skip remains the better approach** for maximum scale-up speed: it eliminates
   all NTP sync delay on first join (8.6 s total improvement, tighter KTR variance).

5. **The max-correction drop-in is the right choice when clock accuracy requirements are
   strict**: if operators need a guarantee that the node clock is within 1 s before Kubelet
   starts (e.g., for certificate issuance robustness), this approach provides that guarantee
   with minimal complexity and a modest 3 s saving vs. the 10 ms threshold.

6. **Filed as OCPBUGS-84814**: the default 10 ms max-correction in `chrony-wait.service`
   is unnecessarily tight for most workloads. A system-level change to 1 s (or a similar
   relaxed threshold) would provide this improvement to all clusters without requiring a
   per-cluster MachineConfig.
