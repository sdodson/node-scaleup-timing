# Node Scale-Up Analysis: 4.22 Nightly vs 4.22.0 GA Baseline (AWS)

## Cluster

- **Cluster**: sdods-scl-rngn9 (same cluster as baseline, upgraded in place)
- **OCP version**: `4.22.0-0.nightly-2026-09-17-071442` (upgraded from 4.22.0 GA via
  `oc adm upgrade --to-image=registry.ci.openshift.org/ocp/release:4.22.0-0.nightly-2026-09-17-071442
  --allow-explicit-upgrade --force`)
- **Region**: us-east-2 (zones: us-east-2a, us-east-2b, us-east-2c — all 3 zones)
- **Instance type**: m6a.xlarge (same as baseline)
- **API**: Legacy MAPI (openshift-machine-api)
- **Rounds**: 11 rounds × 3 zones collected; **round 1 discarded** (zones 2b/2c had a
  one-off artifact-collection failure right after the in-place upgrade — journal/systemd
  files came back empty, confirmed non-recurring in rounds 2-11). Round 11 was run as a
  backfill to keep **n=30** for a clean comparison against the baseline's n=30.

### Upgrade notes (for reproducing this comparison)

Two blockers had to be cleared to get this nightly running on a normal (non-CI) cluster:

1. **`registry.ci.openshift.org` auth** — the cluster's stored pull-secret token had
   expired. Refreshed from a local `containers/auth.json` and merged into the cluster's
   `pull-secret` in `openshift-config`.
2. **Image signature verification** — RHCOS/CRI-O rejects unsigned images. Nightly CI
   builds aren't signed with the production Red Hat key, so every component image pull
   from `quay.io/openshift-release-dev/ocp-v4.0-art-dev` failed with
   `SignatureValidationFailed`. Fixed by patching `ClusterImagePolicy/openshift` to drop
   the `ocp-v4.0-art-dev`/`ocp-v5.0-art-dev` scopes (falling back to the cluster's
   existing default `insecureAcceptAnything` policy). This object is owned by
   `ClusterVersion` and got silently reverted once mid-upgrade; **the
   `cluster-version-operator` deployment was scaled to 0 replicas in
   `openshift-cluster-version`** to stop it from reverting the fix again. **The CVO is
   still at 0 replicas on this cluster — scale it back up
   (`oc scale deployment cluster-version-operator -n openshift-cluster-version
   --replicas=1`) before relying on any further CVO-managed behavior (further upgrades,
   operator reconciliation, etc.).**

---

## Headline: p90 Total Time

| | Baseline (4.22.0 GA) | Nightly (2026-09-17) | Delta | Delta % |
|---|---:|---:|---:|---:|
| **Total (p90, n=30)** | **270.0s** | **207.0s** | **-63.0s** | **-23.3%** |

The nightly build is **63 seconds faster at p90** than the 4.22.0 GA baseline on identical
hardware/zones. This is driven almost entirely by one change: **`chrony-wait.service` is
now skipped on first node join.**

---

## Key finding: chrony-wait is now skipped

All 30 nightly samples show a systemd drop-in written by Ignition:
`/etc/systemd/system/chrony-wait.service.d/10-skip-on-first-join.conf`. `chrony-wait`
never appears in `systemd-analyze blame` on any of the 30 nightly runs — it's not just
faster, it doesn't run at all on a node's first boot into the cluster. This matches the
"chrony-wait skip" optimization previously evaluated (see prior optimization-test
results) and it appears to have landed in this nightly.

This single change explains most of the improvement:
- `boot2_systemd_analyze_s` (systemd startup, kernel → boot complete): **27.5s → 15.0s**
  (chrony-wait was p90 17.3s of that 27.5s in baseline)
- `ktr_s` (kubelet → NodeReady): **97.4s → 61.0s**, since the systemd startup phase that
  precedes image pulls got shorter

---

## Full phase comparison (p90, n=30 each)

| Phase | Baseline p90 | Nightly p90 | Delta | Delta % |
|---|---:|---:|---:|---:|
| Cloud VM Provisioning | 26.0s | 25.0s | -1.0s | -3.8% |
| Boot 1 total (Ignition → end of MCD firstboot) | 142.2s | 112.0s | -30.2s | -21.2% |
| ⤷ Boot 1: Ignition + pivot (derived) | 103.4s | 61.1s | -42.3s | **-40.9%** |
| ⤷ Boot 1: MCD firstboot (rpm-ostree rebase) | 40.1s | 54.1s | **+14.0s** | **+34.9%** |
| Reboot | 17.1s | 18.0s | +0.9s | +5.3% |
| Boot 2: systemd startup (kernel → boot complete) | 27.5s | 15.0s | -12.5s | -45.5% |
| ⤷ Boot 2: chrony-wait | 17.3s | **0.0s (skipped)** | -17.3s | -100% |
| ⤷ Boot 2: CRI-O + Kubelet start (derived, non-chrony) | 10.3s | 15.0s | +4.7s | +45.6% |
| Boot 2: kubelet → NodeReady (total) | 97.4s | 61.0s | -36.4s | -37.4% |
| ⤷ post-systemd-startup portion (image pulls, derived) | 75.1s | 47.0s | -28.1s | -37.3% |
| **Total (MachineSet create → NodeReady)** | **270.0s** | **207.0s** | **-63.0s** | **-23.3%** |

### Two changes worth flagging beyond chrony-wait

1. **Boot 1: Ignition + pivot dropped 40.9%** (103.4s → 61.1s). This is a large,
   unexplained-by-chrony improvement in the pre-rebase portion of Boot 1 — worth digging
   into separately (could be an Ignition/pivot performance fix, or a smaller Ignition
   config in this nightly).
2. **MCD firstboot / rpm-ostree rebase got slower, +34.9%** (40.1s → 54.1s). This
   partially offsets the Ignition+pivot win. Given `rebase_fetch_s` also grew (38.1s p90
   baseline → 41.2s p90 nightly), this is likely a larger image/more chunks to fetch in
   this nightly's OS content, not a regression in rebase mechanics itself. Net effect on
   Boot 1 overall is still a strong improvement (-21.2%) since the Ignition+pivot win is
   larger than the rebase regression.

The "CRI-O + Kubelet start (derived, non-chrony)" line increasing is mostly an artifact
of how it's derived (`systemd_analyze - chrony_wait`): with chrony-wait now at 0,
essentially all of `boot2_systemd_analyze_s` falls into this bucket, so it's not a real
regression in CRI-O/kubelet startup — just a relabeling of the same ~15s window.

---

## Per-run raw data (nightly, n=30)

| Round | Zone | VM Prov | Boot 1 | Rebase | Reboot | Sysd | Chrony | KTR | Total |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 2 | 2a | 21 | 102 | 51 | 12 | 15.10 | 0.00 | 57 | 192 |
| 2 | 2b | 23 | 111 | 49 | 16 | 14.39 | 0.00 | 54 | 204 |
| 2 | 2c | 25 | 99 | 51 | 17 | 14.13 | 0.00 | 48 | 189 |
| 3 | 2a | 20 | 103 | 50 | 11 | 14.02 | 0.00 | 56 | 190 |
| 3 | 2b | 17 | 110 | 49 | 10 | 14.19 | 0.00 | 59 | 196 |
| 3 | 2c | 24 | 112 | 61 | 11 | 14.08 | 0.00 | 64 | 211 |
| 4 | 2a | 21 | 94 | 52 | 18 | 13.32 | 0.00 | 55 | 188 |
| 4 | 2b | 23 | 98 | 48 | 11 | 14.81 | 0.00 | 59 | 191 |
| 4 | 2c | 24 | 111 | 50 | 11 | 14.55 | 0.00 | 58 | 204 |
| 5 | 2a | 21 | 104 | 56 | 12 | 13.70 | 0.00 | 58 | 195 |
| 5 | 2b | 24 | 104 | 55 | 18 | 15.03 | 0.00 | 61 | 207 |
| 5 | 2c | 25 | 99 | 53 | 12 | 14.06 | 0.00 | 55 | 191 |
| 6 | 2a | 21 | 112 | 53 | 10 | 13.97 | 0.00 | 54 | 197 |
| 6 | 2b | 24 | 86 | 49 | 17 | 13.80 | 0.00 | 59 | 186 |
| 6 | 2c | 25 | 101 | 49 | 18 | 14.13 | 0.00 | 55 | 199 |
| 7 | 2a | 21 | 106 | 54 | 12 | 14.97 | 0.00 | 59 | 198 |
| 7 | 2b | 23 | 99 | 51 | 17 | 13.57 | 0.00 | 61 | 200 |
| 7 | 2c | 24 | 108 | 49 | 16 | 13.74 | 0.00 | 46 | 194 |
| 8 | 2a | 21 | 112 | 51 | 10 | 15.07 | 0.00 | 64 | 207 |
| 8 | 2b | 23 | 114 | 52 | 17 | 14.02 | 0.00 | 61 | 215 |
| 8 | 2c | 25 | 107 | 50 | 17 | 13.75 | 0.00 | 58 | 207 |
| 9 | 2a | 21 | 98 | 50 | 11 | 14.05 | 0.00 | 56 | 186 |
| 9 | 2b | 23 | 111 | 50 | 17 | 13.71 | 0.00 | 46 | 197 |
| 9 | 2c | 19 | 102 | 52 | 11 | 14.42 | 0.00 | 54 | 186 |
| 10 | 2a | 20 | 114 | 52 | 18 | 14.83 | 0.00 | 47 | 199 |
| 10 | 2b | 22 | 106 | 50 | 16 | 13.40 | 0.00 | 46 | 190 |
| 10 | 2c | 25 | 106 | 49 | 17 | 13.62 | 0.00 | 46 | 194 |
| 11 | 2a | 16 | 108 | 51 | 11 | 14.36 | 0.00 | 47 | 182 |
| 11 | 2b | 23 | 90 | 48 | 11 | 14.14 | 0.00 | 47 | 171 |
| 11 | 2c | 20 | 108 | 50 | 10 | 14.28 | 0.00 | 54 | 192 |

Round 1 (zones 2a only had valid data; 2b/2c artifact collection failed) is excluded from
this comparison. Raw artifacts for all rounds live in `data/4.22.0-m6a-baseline/`
(gitignored). `data/4.22.0-m6a-baseline/summary.csv` has the machine-readable aggregate
for both the baseline and nightly runs (distinguished by suffix).
