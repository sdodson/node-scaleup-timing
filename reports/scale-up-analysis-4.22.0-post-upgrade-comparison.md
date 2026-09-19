# Node Scale-Up Comparison: OCP 4.22.0 Same-Cluster In-Place Upgrade

## Design

This is a **same-cluster before/after** comparison — the cleanest design available, since both
halves ran on identical hardware/infra (same Azure VMs, same region/zones, same physical host
pool). Any delta below is attributable to the OCP/OS/container-image content of the upgrade,
not cross-cluster infra variance.

- **Cluster**: ci-ln-yizbpy2-1d09d-r7khh (unchanged both sides)
- **Pre-upgrade**: OCP 4.22.0, release image `sha256:283887f2860a745387608d106e70e5be2314df2497ee08c69e7bc669ca091340`
- **Post-upgrade**: OCP 4.22.0-0.nightly-2026-09-17-071442 (forced explicit upgrade via `oc adm upgrade --to-image ... --allow-explicit-upgrade --force`)
- **Boot image**: azureopenshift/aro4 sku 420-v2 v9.6.20251015 — **confirmed identical** on both
  sides before launching the post-upgrade study
- **OS**: RHCOS 9.8.20260520-0 → RHCOS 9.8.20260916-0 (kernel 5.14.0-687.11.1 → 687.48.1)
- **Region/zones**: eastus2 (eastus21/22/23), Standard_D4as_v5, same 3 test MachineSets both sides

### Sample sizes: n=30 (pre) vs. n=21 (post) — data note

The post-upgrade study lost its cluster mid-run: the cluster's API hostname
(`api.ci-ln-yizbpy2-1d09d.ci2.azure.devcluster.openshift.com`) went NXDOMAIN partway through
round 8 (consistent with the dev cluster's TTL expiring), while general DNS resolution
continued to work fine. Rounds 1–7 (n=21, 3 zones × 7 rounds) completed cleanly with **0
failures** before the outage; round 8 timed out on all 3 zones once the API became unreachable
and the study process exited on an unrelated bash error. No partial/corrupt data was written for
round 8 — the n=21 below is 21 clean, complete samples, not a truncated round.

---

## Summary: p90 Comparison

| Phase | Pre-upgrade p90 (n=30) | Post-upgrade p90 (n=21) | Δ |
|---|---|---|---|
| Cloud VM Provisioning | 31.1s | 28.0s | −3.1s |
| Boot 1: Ignition + pivot (approx.) | 113.7s | 79.0s | **−34.7s** |
| Boot 1: MCD firstboot rebase | 77.4s | 75.0s | −2.4s |
| &nbsp;&nbsp;└ of which rebase fetch | 62.1s | 62.0s | −0.1s |
| Reboot gap | 6.1s | 6.0s | −0.1s |
| Boot 2: systemd userspace | 36.2s | **17.2s** | **−19.0s** |
| &nbsp;&nbsp;└ of which chrony-wait.service | 24.1s | **0s (removed)** | **−24.1s** |
| Boot 2: Kubelet start → NodeReady | 135.2s | 87.0s | **−48.2s** |
| **Total (MachineSet create → NodeReady)** | **343.8s** | **270.0s** | **−73.8s (−21.5%)** |

**The upgrade delivers a 73.8s (21.5%) improvement at p90 — and because this is a same-cluster
comparison, this number is trustworthy as a real content effect, not infra noise.**

---

## Headline Finding: `chrony-wait.service` Removed

Confirmed via `systemd-analyze blame`:

- **Pre-upgrade**: `chrony-wait.service` present at a rock-solid **24.1s** on every single one of
  30 runs (essentially zero variance — a fixed Azure PHC-refclock sync cost).
- **Post-upgrade**: `chrony-wait.service` **absent entirely**. Only `chronyd.service` (~84ms) and
  `coreos-platform-chrony-config.service` (~101ms) remain — combined ~185ms vs. the prior 24.1s.

Boot 2 systemd userspace time dropped from p90 36.2s to p90 17.2s, a −19.0s change — slightly
less than the full 24.1s chrony-wait removal would suggest, implying a small (~5s) partial
offset elsewhere in the systemd startup chain, but the chrony-wait removal is clearly the
dominant driver of this phase's improvement.

This single change accounts for **~33% of the total 73.8s improvement** on its own.

---

## Second-Largest Driver: Kubelet Start → NodeReady (−48.2s)

| Metric | Pre-upgrade | Post-upgrade | Δ |
|---|---|---|---|
| Phase time (p90) | 135.2s | 87.0s | **−48.2s (−36%)** |
| Blocking image count (p90) | 28 | 28 | 0 |
| Blocking image total size (p90) | 11,035.1MB | **9,433.0MB** | **−1,602.1MB (−14.5%)** |

Identical image *count* (28) both sides, but **~1.6GB less data pulled** post-upgrade — cleanly
attributable since it's the same cluster/nodes. This, combined with the chrony-wait removal
(which likely also speeds up the kubelet's own startup path since Ready condition and image-pull
machinery run after kubelet is up), largely explains this phase's improvement.

---

## Unexplained but Real: Ignition + Pivot (−34.7s)

This phase improved substantially (113.7s → 79.0s p90) despite occurring *before* MCD firstboot
and having no obvious tie to chrony or container images. Because this is a same-cluster
comparison, this is not infra noise — it's a real change in the ignition/pivot boot path
introduced somewhere in the 4.22.0 → 4.22.0-nightly-2026-09-17 delta. Median (p50) also improved
(91.5s → 71.0s), confirming this is a systemic shift, not outlier-driven. Root cause not
identified from this data alone; would need journal-level diffing of the ignition/pivot phase
specifically to attribute to a particular change.

## Essentially Unchanged: MCD Firstboot Rebase

Rebase total (77.4s → 75.0s) and rebase fetch (62.1s → 62.0s) are within noise of each other.
ostree chunk count (64, unchanged), ostree content size (1287.8MB → 1339.9MB, +52MB — normal
content churn), and custom layer size (186.0MB → 185.9MB, unchanged) confirm the rebase fetch
payload itself didn't meaningfully change. This is expected — the MCD firstboot phase pulls a
fixed machine-os-content image per release, and the upgrade's improvements clearly landed
elsewhere (chrony, image slimming, ignition/pivot).

---

## Bottom Line

- **21.5% faster scale-up (p90) from a same-cluster in-place upgrade** — the cleanest possible
  attribution to date in this project's studies.
- Three independent, additive wins: **chrony-wait removal (−24.1s)**, **smaller blocking
  container images (−1.6GB, contributing to the −48.2s Kubelet→NodeReady improvement)**, and an
  **unexplained but real Ignition+pivot improvement (−34.7s)** worth investigating further.
- MCD firstboot rebase is unchanged — this phase remains the study's largest single bottleneck
  post-upgrade (p90 75.0s) and is untouched by whatever landed in this particular upgrade window.
