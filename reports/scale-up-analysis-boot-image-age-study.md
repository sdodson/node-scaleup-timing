# Node Scale-Up Timing: Boot Image Age Study

## Executive Summary

This study measured how RHCOS boot image age affects OpenShift node scale-up time using 195 samples across 13 boot image versions (4.10.20 through 4.18.40, an exact-match 4.18.27 boot image on a 4.18.26 cluster, and a 4.19.23 boot image on a 4.19.22 cluster).

**Key finding: Boot image age doesn't matter — until it's old enough to require a 3-boot sequence.**

Across RHEL 9 (4.13–4.18) and even RHEL 8 4.12, scale-up time is flat at **~197–227s** regardless of boot image age. The exact-match boot image (4.18.27 on 4.18.26, with 51/51 chunks cached) comes in at **~197s** — only ~16s faster than the native 4.18.24 boot image — demonstrating that ostree chunk fetch volume has minimal impact on total time even when eliminating it entirely. A boot image *newer* than the cluster (4.18.40) also works transparently. Ostree chunk sharing drops to zero within 2 minor versions, adding ~800 MB of fetch — but this costs only ~10-15s and is absorbed by variance in other phases.

The oldest RHEL 8 boot images (4.11 and 4.10) trigger a **3-boot sequence** — an intermediate rebase through a RHEL 9 pivot before reaching the target — that adds 80–110s (+35-50%), jumping scale-up time to 308–334s. Notably, 4.12 (also RHEL 8) does *not* require this intermediate pivot and completes in a normal 2-boot sequence. The 3-boot path appears to be specific to sufficiently old RHEL 8 images rather than all RHEL 8 images.

**4.19+ architectural change**: OCP 4.19 introduced a split between the RHCOS base image (versioned by RHEL minor, baked into the boot AMI) and OCP-specific content (kubelet, cri-o, etc.) shipped as separate "custom layers". The 4.19.23 test shows all 51 RHCOS base chunks present on the boot image (0 MB ostree fetch), but 2 custom layers totaling **219.6 MB are always fetched** regardless of boot image age. Total scale-up time is **216s** — nearly identical to the 4.18.24 native baseline (213s) — but the rebase structure is fundamentally different: a fixed 220 MB custom-layer fetch replaces the variable 0–1.2 GB ostree chunk fetch of 4.18.x.

```
Total Scale-Up Time by Boot Image Version (mean, steady-state samples)

    4.18.27 |███████████████████░   197s  ← exact match (cluster 4.18.26, n=12)
    4.18.40 |████████████████████░  209s  (newer than cluster, n=15)
    4.18.24 |█████████████████████░ 213s  ← native baseline (n=15)
     4.18.0 |█████████████████████░ 211s
    4.17.35 |████████████████████░  208s
    4.16.41 |████████████████████░  202s
    4.15.51 |█████████████████████░ 214s
    4.14.38 |█████████████████████░ 219s
    4.13.51 |██████████████████████░224s
    4.12.40 |██████████████████████░227s     (RHEL 8, but 2-boot)
    --------|-------------------------------------- 3-boot penalty ------
    4.11.35 |██████████████████████████████░  308s  ← 3 boots (older RHEL 8)
    4.10.20 |█████████████████████████████████░334s ← 3 boots (older RHEL 8)
            0       100       200       300       400
                              seconds

  4.19+ architecture (cluster 4.19.22, always fetches 220 MB OCP custom layers):
    4.19.23 |█████████████████████░ 216s  ← native/exact match (n=15)

Ostree Chunk Sharing (51 total chunks)

    4.18.27 |███████████████████████████████████████  51 present /  0 needed (0 MB) ← exact match
    4.18.40 |████████████████░░░░░░░░░░░░░░░░░░░░░░  16 present / 35 needed (596 MB)
    4.18.24 |███████████████████████████░░░░░░░░░░░  27 present / 24 needed (437 MB)
     4.18.0 |███████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   7 present / 44 needed (1.2 GB)
    4.17.35 |███████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   7 present / 44 needed (1.2 GB)
    4.16.41 |░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   0 present / 51 needed (1.2 GB)
    4.15.51 |░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   0 present / 51 needed (1.2 GB)
    4.14.38 |░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   0 present / 51 needed (1.2 GB)
    4.13.51 |░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   0 present / 51 needed (1.2 GB)
    4.12.40 |░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   0 present / 51 needed (1.2 GB)
    4.11.35 |░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   0 present / 51 needed (1.2 GB)
    4.10.20 |░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   0 present / 51 needed (1.2 GB)
             █ = cached on boot image    ░ = fetched during rebase

  4.19+ architecture: RHCOS base is in the boot image; OCP content ships as custom layers (always fetched):
    4.19.23 |███████████████████████████████████████  51 present /  0 needed + 2 custom layers (220 MB)
             █ = RHCOS base cached    custom layers always fetched
```

**Practical takeaway**: There is no urgency to refresh boot images frequently. Even eliminating the ostree fetch entirely (exact-match boot image) only saves ~16s vs the native boot image, because the container image pull phase (~69s) dominates. Only the oldest RHEL 8 images (4.11 and earlier) trigger the costly 3-boot path. In 4.19+, the architecture changes so that a fixed 220 MB OCP custom-layer fetch replaces the variable ostree chunk fetch entirely.

## Purpose

Measure how boot image age affects node scale-up time on an OCP cluster. The cluster version stays constant across each test series; the RHCOS AMI used to provision worker nodes varies. The primary series uses an OCP 4.18.24 cluster with boot images from 4.18.24 down to 4.10.20 — spanning 8 minor versions and the RHEL 8/9 boundary. A follow-on test uses an OCP 4.18.26 cluster with the 4.18.27 boot image to measure the exact-match baseline.

## Test Setup

- **Cloud**: AWS
- **Region**: us-east-2
- **Instance type**: m6i.xlarge (4 vCPU, 16 GB RAM)
- **Primary cluster version**: 4.18.24 (boot images 4.18.40 through 4.10.20)
- **Follow-on cluster version**: 4.18.26 (boot image 4.18.27 exact-match test)
- **4.19 cluster version**: 4.19.22 (boot image 4.19.23 — 4.19+ layered architecture study)
- **Availability zones**: us-east-2a, us-east-2b, us-east-2c
- **Rounds per boot image**: 5 (3 zones per round)
- **Samples per boot image**: 15 (5 rounds × 3 zones); 12 for 4.18.27 (round 1 excluded — post-upgrade cold caches)
- **Date started**: 2026-05-09

## Boot Image Versions

| Boot Image | AMI | RHEL Base | Cluster | Status |
|---|---|---|---|---|
| 4.19.23 (4.19+ layered) | ami-0fd7c367ed8a90d52 | RHEL 9 | 4.19.22 | **Complete** |
| 4.18.27 (exact match) | ami-04756c1a4f51bb2c9 | RHEL 9 | 4.18.26 | **Complete** |
| 4.18.40 (newer) | ami-0b9fcc2f8bed8771e | RHEL 9 | 4.18.24 | **Complete** |
| 4.18.24 (native) | ami-0adb8862ffe5cc2ab | RHEL 9 | 4.18.24 | **Complete** |
| 4.18.0 | ami-078e26f293629fe91 | RHEL 9 | 4.18.24 | **Complete** |
| 4.17.35 | ami-022fbb77a3226215f | RHEL 9 | 4.18.24 | **Complete** |
| 4.16.41 | ami-09ab4b62c2f0a4555 | RHEL 9 | 4.18.24 | **Complete** |
| 4.15.51 | ami-0d6c4efce8daf7d2d | RHEL 9 | 4.18.24 | **Complete** |
| 4.14.38 | ami-0dd810c1f47c5c233 | RHEL 9 | 4.18.24 | **Complete** |
| 4.13.51 | ami-031d6e5e3d4f2f192 | RHEL 9 | 4.18.24 | **Complete** |
| 4.12.40 | ami-00a8ad62bbaede57f | RHEL 8 | 4.18.24 | **Complete** |
| 4.11.35 | ami-0f2483edc1ec85f51 | RHEL 8 | 4.18.24 | **Complete** |
| 4.10.20 | ami-08750efc5bc9eb5ff | RHEL 8 | 4.18.24 | **Complete** |

## Summary

| Boot Image | n | Total (mean) | Stdev | Boot 1 | Rebase | Reboot | SA | chrony | KTR | Chunks (P/N) | Fetch |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **4.19.23** (4.19+ layered) | 15 | **216s** | 11s | 114s | 36s | 12s | 22s | 13s | 69s | 51/0+2CL‡ | 220 MB |
| **4.18.27** (exact match) | 12† | **197s** | 17s | 91s | 13s | 11s | 26s | 10s | 69s | 51/0 | 0 MB |
| **4.18.40** | 15 | **209s** | 12s | 104s | 25s | 14s | 25s | 14s | 71s | 16/35 | 596 MB |
| **4.18.24** | 15 | **213s** | 21s | 111s | 22s | 14s | 20s | 11s | 62s | 27/24 | 437 MB |
| **4.18.0** | 15 | **211s** | 22s | 112s | 37s | 15s | 20s | 12s | 62s | 7/44 | 1.2 GB |
| **4.17.35** | 15 | **208s** | 12s | 103s | 33s | 14s | 19s | 10s | 69s | 7/44 | 1.2 GB |
| **4.16.41** | 15 | **202s** | 14s | 100s | 30s | 14s | 19s | 10s | 66s | 0/51 | 1.2 GB |
| **4.15.51** | 15 | **214s** | 10s | 111s | 42s | 14s | 22s | 10s | 67s | 0/51 | 1.2 GB |
| **4.14.38** | 15 | **219s** | 29s | 106s | 38s | 15s | 21s | 12s | 78s | 0/51 | 1.2 GB |
| **4.13.51** | 15 | **224s** | 25s | 121s | 48s | 18s | 23s | 13s | 64s | 0/51 | 1.2 GB |
| **4.12.40** | 15 | **227s** | 18s | 131s | 49s | 14s | 22s | 12s | 61s | 0/51 | 1.2 GB |
| **4.11.35** | 15 | **308s** | 19s | — | — | — | 22s | 13s | 68s | 0/51 | 1.2 GB |
| **4.10.20** | 15 | **334s** | 18s | — | — | — | 21s | 12s | 59s | 0/51 | 1.2 GB |

† Round 1 excluded from 4.18.27 stats: run immediately after cluster upgrade to 4.18.26, newly-promoted container images not yet warm in registry (KTR ~175s vs steady-state ~69s).
‡ 4.19+ layered architecture: 51/51 RHCOS base chunks present on boot image (0 MB ostree fetch), but 2 OCP-specific custom layers (219.6 MB) are always fetched regardless of boot image age. CL = custom layers.

## Ostree Chunk/Layer Summary

| Boot Image | Chunks Present | Chunks Needed | Custom Layers | Total Fetch |
|---|---|---|---|---|
| **4.19.23** (4.19+ layered) | 51 | 0 | 2 (219.6 MB) | 220 MB |
| **4.18.27** (exact match) | 51 | 0 | 0 | 0 MB |
| **4.18.40** | 16 | 35 | 0 | 596 MB |
| **4.18.24** | 27 | 24 | 0 | 437 MB |
| **4.18.0** | 7 | 44 | 0 | 1.2 GB |
| **4.17.35** | 7 | 44 | 0 | 1.2 GB |
| **4.16.41** | 0 | 51 | 0 | 1.2 GB |
| **4.15.51** | 0 | 51 | 0 | 1.2 GB |
| **4.14.38** | 0 | 51 | 0 | 1.2 GB |
| **4.13.51** | 0 | 51 | 0 | 1.2 GB |
| **4.12.40** | 0 | 51 | 0 | 1.2 GB |
| **4.11.35** | 0 | 51 | 0 | 1.2 GB |
| **4.10.20** | 0 | 51 | 0 | 1.2 GB |

## OCP 4.19.23 — 4.19+ Layered Image Architecture (Cluster 4.19.22)

OCP 4.19 introduced a split between the RHCOS base image and OCP-specific content. The boot AMI now contains only the RHCOS base (all RHEL-minor-versioned ostree chunks), while kubelet, cri-o, and other OCP-version-specific packages are shipped as separate "custom layers" that are always fetched during firstboot. This test used the 4.19.23 RHCOS AMI (`ami-0fd7c367ed8a90d52`) on an OCP 4.19.22 cluster, representing the native/exact-match case for the new architecture.

### All Data Points

| Round | Zone | Total | VM Prov | Boot 1 | Rebase | Reboot | SA | chrony | KTR |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 210s | 20s | 117s | 42s | 12s | 23.9s | 15.2s | 61s |
| 1 | 2 | 206s | 22s | 88s | 23s | 12s | 27.0s | 18.1s | 84s |
| 1 | 3 | 206s | 24s | 100s | 28s | 12s | 25.1s | 16.1s | 70s |
| 2 | 1 | 203s | 21s | 89s | 26s | 12s | 24.5s | 15.2s | 81s |
| 2 | 2 | 201s | 22s | 104s | 34s | 12s | 25.9s | 17.2s | 63s |
| 2 | 3 | 203s | 24s | 102s | 29s | 12s | 25.5s | 16.1s | 65s |
| 3 | 1 | 217s | 21s | 122s | 51s | 12s | 24.7s | 15.2s | 62s |
| 3 | 2 | 218s | 22s | 116s | 46s | 12s | 17.3s | 8.0s | 68s |
| 3 | 3 | 214s | 24s | 114s | 41s | 12s | 25.7s | 17.2s | 64s |
| 4 | 1 | 235s | 20s | 136s | 37s | 11s | 18.3s | 9.0s | 68s |
| 4 | 2 | 232s | 22s | 135s | 37s | 11s | 18.3s | 9.0s | 64s |
| 4 | 3 | 230s | 23s | 99s | 24s | 12s | 16.0s | 7.0s | 96s |
| 5 | 1 | 228s | 20s | 135s | 50s | 13s | 17.4s | 8.1s | 60s |
| 5 | 2 | 220s | 22s | 121s | 32s | 12s | 21.1s | 12.1s | 65s |
| 5 | 3 | 220s | 24s | 124s | 36s | 12s | 21.6s | 13.2s | 60s |

### Statistics (n=15)

| Metric | Mean | Stdev | Min | Max |
|---|---|---|---|---|
| **Total** | **216s** | 11s | 201s | 235s |
| VM Provisioning | 22s | 2s | 20s | 24s |
| Boot 1 | 114s | 16s | 88s | 136s |
| Rebase (total) | 36s | 9s | 23s | 51s |
| Reboot | 12s | 1s | 11s | 13s |
| systemd-analyze | 22s | 4s | 16s | 27s |
| chrony-wait | 13s | 4s | 7s | 18s |
| KTR | 69s | 10s | 60s | 96s |

### Ostree Chunks and Custom Layers

51/51 RHCOS base chunks present on the boot image — zero-byte ostree fetch. However, 2 custom layers totaling **219.6 MB** are fetched on every firstboot. These custom layers contain the OCP-version-specific packages (kubelet, cri-o, etc.) that are no longer baked into the base RHCOS image. The custom layer hash (`bdc94d91c552c179636`) and size (219.6 MB) were identical across all 15 runs.

The MCD image pull takes ~19s (rebase_start_s, mean across all runs) — approximately half the ~35s observed in the 4.18.27 journal. The 4.19 MCD image may be smaller or structured differently.

### Notes

- **Total 216s: within noise of 4.18.24 native (213s)**: Despite the architectural change, scale-up time is essentially unchanged vs the 4.18.x baseline on the same instance type.
- **Fixed 220 MB fetch replaces variable ostree fetch**: In 4.18.x, the ostree chunk fetch ranged from 0 MB (exact match) to 1.2 GB (old boot image). In 4.19+, the RHCOS base is always fully cached on the boot image, but the 220 MB OCP custom layers are always fetched — a predictable fixed cost.
- **Boot image staleness largely irrelevant in 4.19+**: As long as the boot image matches the RHEL minor (e.g., RHEL 9.6), all RHCOS base chunks are present. The OCP custom layers are always fetched fresh regardless. Only a RHEL minor version bump (9.5 → 9.6) in the base OS would cause ostree chunks to be missing.
- **MCD image pull faster**: rebase_start_s mean of 19s (vs ~35s in 4.18.27). Reduction is consistent and unexplained by boot image differences — likely a smaller or differently-structured 4.19 MCD image.
- **KTR unchanged**: 69s mean, identical to 4.18.27 and similar to most 4.18.x versions. The container image pull phase is not affected by the architecture change.

## OCP 4.18.27 — Exact Match Boot Image (Cluster 4.18.26)

This test used the 4.18.27 RHCOS AMI (`ami-04756c1a4f51bb2c9`) on a freshly upgraded OCP 4.18.26 cluster. The 4.18.27 boot image is the first refresh after the cluster version, meaning the ostree chunk content is essentially identical to the running node image — producing a perfect 51/51 cache hit and zero-byte fetch.

### All Data Points

| Round | Zone | Total | VM Prov | Boot 1 | Rebase | Reboot | SA | chrony | KTR |
|---|---|---|---|---|---|---|---|---|---|
| 1† | 1 | 300s | 24s | 89s | 10s | 11s | 34.7s | 20.2s | 176s |
| 1† | 2 | 298s | 17s | 99s | 17s | 10s | 30.2s | 7.0s | 172s |
| 1† | 3 | 298s | 24s | 88s | 13s | 11s | 32.5s | 9.1s | 175s |
| 2 | 1 | 226s | 32s | 113s | 16s | 12s | 34.0s | 16.2s | 69s |
| 2 | 2 | 225s | 31s | 114s | 16s | 11s | 33.2s | 15.1s | 69s |
| 2 | 3 | 224s | 30s | 112s | 14s | 11s | 32.9s | 14.2s | 71s |
| 3 | 1 | 192s | 24s | 82s | 14s | 12s | 25.8s | 9.0s | 74s |
| 3 | 2 | 190s | 24s | 71s | 8s | 13s | 22.2s | 9.0s | 82s |
| 3 | 3 | 190s | 24s | 94s | 15s | 11s | 26.2s | 9.0s | 61s |
| 4 | 1 | 189s | 27s | 86s | 9s | 10s | 19.6s | 9.0s | 66s |
| 4 | 2 | 190s | 26s | 92s | 17s | 10s | 25.5s | 9.0s | 62s |
| 4 | 3 | 187s | 25s | 91s | 15s | 10s | 24.5s | 7.0s | 61s |
| 5 | 1 | 183s | 22s | 75s | 14s | 11s | 19.4s | 7.0s | 75s |
| 5 | 2 | 182s | 22s | 83s | 10s | 11s | 20.4s | 7.0s | 66s |
| 5 | 3 | 182s | 24s | 80s | 13s | 11s | 27.1s | 9.0s | 67s |

† Round 1 run immediately after cluster upgrade completes; newly-promoted 4.18.26 container images not yet warm in registry (KTR ~175s). Excluded from statistics below.

### Statistics (n=12, rounds 2–5)

| Metric | Mean | Stdev | Min | Max |
|---|---|---|---|---|
| **Total** | **197s** | 17s | 182s | 226s |
| VM Provisioning | 26s | 3s | 22s | 32s |
| Boot 1 | 91s | 15s | 71s | 114s |
| Rebase (total) | 13s | 3s | 8s | 17s |
| Reboot | 11s | 1s | 10s | 13s |
| systemd-analyze | 26s | 5s | 19s | 34s |
| chrony-wait | 10s | 3s | 7s | 16s |
| KTR | 69s | 6s | 61s | 82s |

### Ostree Chunks

51/51 chunks present on the boot image, 0 chunks needed — zero-byte fetch. This is the theoretical best case: the boot image content is essentially identical to the running node image, so the entire ostree layer is already cached locally.

### Notes

- **Rebase is nearly instant**: 8–17s (mean 13s) vs 22s for the native 4.18.24 boot image. With nothing to download, rebase time is purely apply overhead.
- **Savings vs native baseline are modest**: 197s vs 213s — a 16s improvement despite eliminating the entire 437 MB fetch. This confirms ostree chunk fetch is not a significant bottleneck even at 1.2 GB.
- **KTR dominates**: 69s mean (similar to all other 2-boot versions). Container image pulls are unaffected by boot image matching.
- **Round 2 elevated**: VM provisioning 30–32s (vs ~24s normally) and KTR 69–71s are slightly above steady-state for rounds 3–5. The cluster was still fully settling after the upgrade.
- **Same cluster, different version**: This test ran on OCP 4.18.26 (not 4.18.24), so absolute numbers may differ slightly from the primary study.

## OCP 4.18.40 — Newer Than Cluster (Forward Drift)

### All Data Points

| Round | Zone | Total | VM Prov | Boot 1 | Rebase | Reboot | SA | chrony | KTR |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 219s | 24s | 111s | 25s | 17s | 22.3s | 14.1s | 67s |
| 1 | 2 | 221s | 20s | 118s | 25s | 14s | 22.3s | 14.2s | 69s |
| 1 | 3 | 215s | 22s | 104s | 22s | 18s | 17.6s | 9.1s | 71s |
| 2 | 1 | 224s | 22s | 130s | 50s | 18s | 22.3s | 14.1s | 54s |
| 2 | 2 | 220s | 16s | 110s | 24s | 18s | 31.0s | 19.2s | 76s |
| 2 | 3 | 218s | 23s | 118s | 30s | 11s | 24.2s | 16.1s | 66s |
| 3 | 1 | 214s | 23s | 115s | 24s | 11s | 25.8s | 17.1s | 65s |
| 3 | 2 | 211s | 20s | 94s | 22s | 11s | 31.2s | 19.2s | 86s |
| 3 | 3 | 211s | 22s | 101s | 22s | 18s | 28.1s | 19.2s | 70s |
| 4 | 1 | 204s | 22s | 83s | 18s | 11s | 22.3s | 14.2s | 88s |
| 4 | 2 | 203s | 16s | 91s | 17s | 12s | 28.3s | 19.2s | 84s |
| 4 | 3 | 203s | 24s | 85s | 16s | 14s | 22.3s | 14.1s | 80s |
| 5 | 1 | 191s | 18s | 90s | 22s | 12s | 22.2s | 14.1s | 71s |
| 5 | 2 | 190s | 18s | 95s | 19s | 11s | 16.0s | 7.0s | 66s |
| 5 | 3 | 191s | 22s | 117s | 37s | 11s | 17.9s | 9.0s | 41s |

### Statistics (n=15)

| Metric | Mean | Stdev | Min | Max |
|---|---|---|---|---|
| **Total** | **209s** | 12s | 190s | 224s |
| VM Provisioning | 21s | 3s | 16s | 24s |
| Boot 1 | 104s | 14s | 83s | 130s |
| Rebase (total) | 25s | 9s | 16s | 50s |
| Reboot | 14s | 3s | 11s | 18s |
| systemd-analyze | 25s | 4s | 16s | 31s |
| chrony-wait | 14s | 4s | 7s | 19s |
| KTR | 71s | 10s | 41s | 89s |

### Ostree Chunks

16 chunks present on the boot image, 35 chunks needed (596 MB fetch). The 4.18.40 boot image is 16 z-stream releases **newer** than the 4.18.24 target — yet it shares only 16 of 51 chunks (fewer than the native 4.18.24 boot image's 27). This demonstrates that chunk drift is symmetric: forward drift (newer boot image than target) produces chunk divergence just as backward drift does.

### Notes

- **Forward drift works**: The rebase from 4.18.40 → 4.18.24 completes normally. rpm-ostree handles "downgrading" the OS image transparently.
- **Chunk sharing worse than native**: 16/51 present (vs 27/51 for native 4.18.24). 16 z-stream releases of forward drift diverged 11 more chunks than the native boot image's slight divergence.
- **Fetch volume moderate**: 596 MB — between the native (437 MB) and the fully-diverged versions (1.2 GB).
- **Total time matches baseline**: 209s vs 213s — statistically indistinguishable.

## OCP 4.18.24 — Baseline (Native Boot Image)

### All Data Points

| Round | Zone | Total | VM Prov | Boot 1 | Rebase | Reboot | SA | chrony | KTR |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 199s | 28s | 105s | 18s | 11s | 16.2s | 7.1s | 55s |
| 1 | 2 | 199s | 24s | 113s | 19s | 11s | 16.1s | 7.1s | 51s |
| 1 | 3 | 240s | 26s | 134s | 16s | 17s | 27.1s | 18.2s | 63s |
| 2 | 1 | 211s | 28s | 113s | 20s | 16s | 18.1s | 8.4s | 54s |
| 2 | 2 | 206s | 24s | 108s | 19s | 14s | 19.3s | 10.7s | 60s |
| 2 | 3 | 193s | 22s | 93s | 17s | 11s | 17.1s | 8.2s | 67s |
| 3 | 1 | 213s | 26s | 108s | 17s | 14s | 18.5s | 9.8s | 65s |
| 3 | 2 | 203s | 21s | 93s | 18s | 16s | 20.9s | 11.8s | 73s |
| 3 | 3 | 204s | 24s | 109s | 27s | 10s | 17.3s | 8.7s | 61s |
| 4 | 1 | 269s | 26s | 164s | 46s | 17s | 24.9s | 16.1s | 62s |
| 4 | 2 | 211s | 22s | 91s | 18s | 18s | 22.8s | 14.7s | 80s |
| 4 | 3 | 215s | 27s | 111s | 21s | 15s | 20.3s | 11.7s | 62s |
| 5 | 1 | 207s | 25s | 108s | 21s | 14s | 19.9s | 11.2s | 60s |
| 5 | 2 | 219s | 27s | 115s | 30s | 16s | 22.3s | 13.5s | 61s |
| 5 | 3 | 208s | 25s | 104s | 21s | 14s | 17.7s | 8.9s | 65s |

### Statistics (n=15)

| Metric | Mean | Stdev | Min | Max |
|---|---|---|---|---|
| **Total** | **213s** | 21s | 193s | 269s |
| VM Provisioning | 25s | 3s | 21s | 28s |
| Boot 1 | 111s | 22s | 91s | 164s |
| Rebase (total) | 22s | 7s | 16s | 46s |
| Reboot | 14s | 3s | 10s | 18s |
| systemd-analyze | 20s | 5s | 16s | 27s |
| chrony-wait | 11s | 5s | 7s | 18s |
| KTR | 63s | 10s | 51s | 80s |

### Ostree Chunks

27 chunks present on the boot image, 24 chunks needed (437 MB fetch). No custom layers (those were introduced in 4.19).

### Notes

- **Chunks present**: 27 of 51 total chunks are cached on the native boot image. The AMI is from the 4.18.24 release payload, but the RHCOS build used for the AMI differs slightly from the node image — producing different ostree chunk hashes for 24 of 51 chunks.
- **No custom layers**: OCP 4.18 predates the custom layer feature introduced in 4.19.
- **R4-Z1 outlier**: Total 269s with rebase 46s — likely a registry throughput dip during that round.

## OCP 4.18.0 — z-Stream Drift Within 4.18

### All Data Points

| Round | Zone | Total | VM Prov | Boot 1 | Rebase | Reboot | SA | chrony | KTR |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 194s | 19s | 98s | 27s | 17s | 25.7s | 17.3s | 60s |
| 1 | 2 | 189s | 21s | 93s | 24s | 17s | 19.9s | 11.1s | 58s |
| 1 | 3 | 188s | 22s | 94s | 22s | 16s | 15.8s | 7.0s | 56s |
| 2 | 1 | 206s | 20s | 115s | 36s | 18s | 19.7s | 10.1s | 53s |
| 2 | 2 | 203s | 20s | 113s | 38s | 17s | 18.7s | 10.0s | 53s |
| 2 | 3 | 201s | 23s | 96s | 26s | 11s | 17.5s | 9.0s | 71s |
| 3 | 1 | 196s | 20s | 92s | 28s | 12s | 28.5s | 19.2s | 72s |
| 3 | 2 | 194s | 22s | 98s | 24s | 18s | 15.9s | 7.0s | 56s |
| 3 | 3 | 193s | 23s | 87s | 23s | 12s | 22.9s | 14.1s | 71s |
| 4 | 1 | 228s | 20s | 141s | 48s | 17s | 14.8s | 7.0s | 50s |
| 4 | 2 | 262s | 21s | 163s | 60s | 17s | 27.6s | 19.2s | 61s |
| 4 | 3 | 223s | 23s | 117s | 42s | 11s | 24.3s | 16.1s | 72s |
| 5 | 1 | 233s | 20s | 129s | 52s | 17s | 21.9s | 14.1s | 67s |
| 5 | 2 | 230s | 21s | 129s | 51s | 17s | 16.0s | 7.0s | 63s |
| 5 | 3 | 228s | 23s | 122s | 49s | 12s | 16.9s | 8.0s | 71s |

### Statistics (n=15)

| Metric | Mean | Stdev | Min | Max |
|---|---|---|---|---|
| **Total** | **211s** | 22s | 188s | 262s |
| VM Provisioning | 21s | 1s | 19s | 23s |
| Boot 1 | 112s | 22s | 87s | 163s |
| Rebase (total) | 37s | 13s | 22s | 60s |
| Reboot | 15s | 3s | 11s | 18s |
| systemd-analyze | 20s | 5s | 15s | 29s |
| chrony-wait | 12s | 5s | 7s | 19s |
| KTR | 62s | 8s | 50s | 72s |

### Ostree Chunks

7 chunks present on the boot image, 44 chunks needed (1.2 GB fetch). The 4.18.0 RHCOS AMI shares only 7 of 51 chunks with the 4.18.24 node image — 24 z-stream releases within 4.18 caused 20 additional chunks to diverge from the native baseline (27 present → 7 present).

### Notes

- **Chunk sharing drops sharply**: 24 z-stream releases within 4.18 reduced shared chunks from 27 to 7 — a 74% cache miss increase (24 → 44 chunks needed). Fetch volume nearly tripled (437 MB → 1.2 GB).
- **Rebase variance high**: Rebase ranged from 22s (matching baseline) to 60s. Rounds 4-5 showed consistently higher rebase times (42-60s), likely due to registry throughput saturation from the larger fetch volume.
- **Total time unchanged**: Despite the 68% rebase increase, total scale-up time (211s vs 213s) is statistically indistinguishable. The ~15s of extra rebase time was absorbed by slightly faster VM provisioning (21s vs 25s) and natural variance.
- **Container images**: 18 vs 20 for the baseline — `cluster-network-operator` and `network-metrics-daemon` are absent.

## OCP 4.17.35 — Cross-Minor-Version (4.17 → 4.18)

### All Data Points

| Round | Zone | Total | VM Prov | Boot 1 | Rebase | Reboot | SA | chrony | KTR |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 205s | 28s | 109s | 28s | 11s | 17.4s | 9.0s | 57s |
| 1 | 2 | 203s | 23s | 106s | 29s | 10s | 15.5s | 7.0s | 64s |
| 1 | 3 | 201s | 25s | 100s | 28s | 12s | 15.8s | 7.1s | 64s |
| 2 | 1 | 215s | 21s | 105s | 23s | 16s | 17.1s | 9.0s | 73s |
| 2 | 2 | 218s | 22s | 131s | 61s | 14s | 14.8s | 7.0s | 51s |
| 2 | 3 | 213s | 22s | 101s | 27s | 17s | 17.1s | 9.1s | 73s |
| 3 | 1 | 197s | 20s | 79s | 23s | 13s | 15.5s | 7.1s | 85s |
| 3 | 2 | 195s | 21s | 93s | 24s | 17s | 14.8s | 7.1s | 64s |
| 3 | 3 | 197s | 23s | 96s | 28s | 17s | 26.3s | 18.2s | 61s |
| 4 | 1 | 230s | 20s | 129s | 53s | 17s | 28.2s | 20.2s | 64s |
| 4 | 2 | 226s | 21s | 120s | 51s | 17s | 19.5s | 11.1s | 68s |
| 4 | 3 | 225s | 23s | 92s | 27s | 18s | 18.2s | 10.1s | 92s |
| 5 | 1 | 199s | 16s | 87s | 24s | 12s | 17.4s | 9.1s | 84s |
| 5 | 2 | 198s | 22s | 81s | 25s | 11s | 25.5s | 17.2s | 84s |
| 5 | 3 | 200s | 22s | 114s | 40s | 11s | 15.3s | 7.0s | 53s |

### Statistics (n=15)

| Metric | Mean | Stdev | Min | Max |
|---|---|---|---|---|
| **Total** | **208s** | 12s | 195s | 230s |
| VM Provisioning | 22s | 3s | 16s | 28s |
| Boot 1 | 103s | 16s | 79s | 131s |
| Rebase (total) | 33s | 12s | 23s | 61s |
| Reboot | 14s | 3s | 10s | 18s |
| systemd-analyze | 19s | 4s | 15s | 28s |
| chrony-wait | 10s | 4s | 7s | 20s |
| KTR | 69s | 12s | 51s | 92s |

### Ostree Chunks

7 chunks present on the boot image, 44 chunks needed (1.2 GB fetch). Identical chunk profile to 4.18.0 — crossing the 4.17 → 4.18 minor version boundary did not change ostree chunk sharing relative to the within-z-stream 4.18.0 case.

### Notes

- **Same chunk profile as 4.18.0**: Both 4.17.35 and 4.18.0 share exactly 7 of 51 chunks with the 4.18.24 node image and require 1.2 GB fetch. The minor version boundary (4.17 → 4.18) had no additional effect on ostree chunk divergence.
- **Lower rebase variance**: Mean rebase 33s (vs 37s for 4.18.0), with less skew toward high outliers.
- **KTR slightly higher**: 69s mean (vs 62s for 4.18.0), possibly due to registry load or scheduling jitter.
- **Total consistent**: 208s mean is within noise of baseline (213s) and 4.18.0 (211s).

## OCP 4.16.41 — Two Minor Versions Back (4.16 → 4.18)

### All Data Points

| Round | Zone | Total | VM Prov | Boot 1 | Rebase | Reboot | SA | chrony | KTR |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 205s | 27s | 101s | 29s | 13s | 23.2s | 14.1s | 64s |
| 1 | 2 | 204s | 25s | 102s | 29s | 17s | 17.6s | 9.1s | 60s |
| 1 | 3 | 205s | 24s | 112s | 32s | 16s | 15.2s | 7.0s | 53s |
| 2 | 1 | 197s | 20s | 96s | 30s | 17s | 19.3s | 11.1s | 64s |
| 2 | 2 | 194s | 23s | 85s | 26s | 12s | 15.7s | 7.1s | 74s |
| 2 | 3 | 193s | 23s | 88s | 28s | 11s | 17.9s | 9.0s | 71s |
| 3 | 1 | 228s | 20s | 117s | 55s | 11s | 17.4s | 9.0s | 80s |
| 3 | 2 | 226s | 21s | 115s | 28s | 16s | 17.9s | 9.0s | 74s |
| 3 | 3 | 226s | 23s | 122s | 29s | 17s | 20.3s | 12.1s | 64s |
| 4 | 1 | 191s | 20s | 83s | 29s | 12s | 15.5s | 7.1s | 76s |
| 4 | 2 | 189s | 21s | 85s | 24s | 11s | 24.6s | 16.2s | 72s |
| 4 | 3 | 189s | 23s | 94s | 29s | 11s | 24.9s | 16.1s | 61s |
| 5 | 1 | 196s | 19s | 99s | 29s | 11s | 17.9s | 9.0s | 67s |
| 5 | 2 | 197s | 20s | 104s | 28s | 16s | 17.6s | 9.0s | 57s |
| 5 | 3 | 194s | 23s | 102s | 27s | 17s | 17.5s | 9.1s | 52s |

### Statistics (n=15)

| Metric | Mean | Stdev | Min | Max |
|---|---|---|---|---|
| **Total** | **202s** | 14s | 189s | 228s |
| VM Provisioning | 22s | 2s | 19s | 27s |
| Boot 1 | 100s | 12s | 83s | 122s |
| Rebase (total) | 30s | 7s | 24s | 55s |
| Reboot | 14s | 3s | 11s | 17s |
| systemd-analyze | 19s | 3s | 15s | 25s |
| chrony-wait | 10s | 3s | 7s | 16s |
| KTR | 66s | 8s | 52s | 80s |

### Ostree Chunks

0 chunks present on the boot image, all 51 chunks needed (1.2 GB fetch). No chunk sharing at all between the 4.16.41 RHCOS AMI and the 4.18.24 node image. The additional 7 chunks (vs 44 for 4.18.0/4.17.35) added only ~67 MB to the total fetch (1242 MB vs 1175 MB).

### Notes

- **Zero chunk sharing**: By 4.16.41 (two minor versions back), the RHCOS boot image shares zero ostree chunks with the 4.18.24 node image. Every chunk must be fetched from the registry.
- **Fetch volume plateaus**: Despite fetching all 51 chunks vs 44 for 4.18.0/4.17.35, total fetch is identical at 1.2 GB. The 7 extra chunks are only ~67 MB combined.
- **Rebase time stable**: 30s mean rebase — lower variance than 4.18.0 (37s) despite more chunks to fetch. Registry throughput, not chunk count, is the bottleneck.
- **Total time slightly lower**: 202s mean, the lowest so far. This is noise — all four versions are within 213±11s.

## OCP 4.15.51 — Three Minor Versions Back (4.15 → 4.18)

### All Data Points

| Round | Zone | Total | VM Prov | Boot 1 | Rebase | Reboot | SA | chrony | KTR |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 204s | 22s | 107s | 34s | 19s | 19.8s | 10.1s | 56s |
| 1 | 2 | 202s | 16s | 90s | 31s | 11s | 19.2s | 8.1s | 85s |
| 1 | 3 | 204s | 22s | 114s | 35s | 17s | 20.3s | 8.1s | 51s |
| 2 | 1 | 211s | 23s | 106s | 35s | 17s | 32.8s | 18.2s | 65s |
| 2 | 2 | 209s | 23s | 101s | 39s | 18s | 22.6s | 9.0s | 67s |
| 2 | 3 | 207s | 22s | 99s | 34s | 11s | 19.6s | 10.0s | 75s |
| 3 | 1 | 210s | 20s | 111s | 37s | 10s | 18.7s | 9.0s | 69s |
| 3 | 2 | 208s | 21s | 104s | 35s | 17s | 22.9s | 9.1s | 66s |
| 3 | 3 | 208s | 23s | 104s | 34s | 18s | 22.6s | 10.0s | 63s |
| 4 | 1 | 230s | 18s | 133s | 56s | 16s | 28.2s | 16.2s | 63s |
| 4 | 2 | 229s | 21s | 118s | 55s | 10s | 19.9s | 9.0s | 80s |
| 4 | 3 | 228s | 26s | 121s | 51s | 12s | 17.1s | 8.0s | 69s |
| 5 | 1 | 221s | 19s | 122s | 53s | 17s | 25.8s | 14.1s | 63s |
| 5 | 2 | 218s | 20s | 125s | 45s | 11s | 17.1s | 7.0s | 62s |
| 5 | 3 | 217s | 22s | 116s | 52s | 11s | 18.1s | 9.1s | 68s |

### Statistics (n=15)

| Metric | Mean | Stdev | Min | Max |
|---|---|---|---|---|
| **Total** | **214s** | 10s | 202s | 230s |
| VM Provisioning | 21s | 2s | 16s | 26s |
| Boot 1 | 111s | 11s | 90s | 133s |
| Rebase (total) | 42s | 9s | 31s | 56s |
| Reboot | 14s | 3s | 10s | 19s |
| systemd-analyze | 22s | 4s | 17s | 33s |
| chrony-wait | 10s | 3s | 7s | 18s |
| KTR | 67s | 9s | 51s | 85s |

### Ostree Chunks

0 chunks present on the boot image, all 51 chunks needed (1.2 GB fetch). Identical chunk profile to 4.16.41.

### Notes

- **Chunk profile unchanged**: Same as 4.16.41 — 0/51 chunks cached, 1.2 GB total fetch.
- **Rebase trending up**: 42s mean (vs 30s for 4.16.41). The higher rebase variance may reflect registry load patterns across rounds rather than boot image age, since the fetch volume is identical.
- **Total steady**: 214s mean is consistent with all previous versions (202-213s range).

## OCP 4.14.38 — Four Minor Versions Back (4.14 → 4.18)

### All Data Points

| Round | Zone | Total | VM Prov | Boot 1 | Rebase | Reboot | SA | chrony | KTR |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 207s | 20s | 104s | 37s | 17s | 17.2s | 8.1s | 66s |
| 1 | 2 | 207s | 20s | 108s | 38s | 14s | 22.3s | 14.2s | 65s |
| 1 | 3 | 205s | 20s | 105s | 38s | 16s | 17.5s | 9.0s | 64s |
| 2 | 1 | 266s | 20s | 112s | 42s | 17s | 27.7s | 19.2s | 117s |
| 2 | 2 | 264s | 20s | 111s | 44s | 17s | 28.4s | 19.2s | 116s |
| 2 | 3 | 291s | 22s | 114s | 46s | 18s | 17.7s | 9.1s | 137s |
| 3 | 1 | 212s | 20s | 108s | 39s | 10s | 23.3s | 14.1s | 74s |
| 3 | 2 | 212s | 21s | 100s | 35s | 13s | 19.3s | 10.2s | 78s |
| 3 | 3 | 211s | 23s | 100s | 33s | 12s | 22.1s | 14.1s | 76s |
| 4 | 1 | 198s | 20s | 98s | 30s | 14s | 16.3s | 7.0s | 66s |
| 4 | 2 | 199s | 19s | 107s | 39s | 14s | 16.1s | 7.0s | 59s |
| 4 | 3 | 195s | 21s | 108s | 37s | 10s | 19.3s | 10.2s | 56s |
| 5 | 1 | 204s | 19s | 106s | 36s | 12s | 22.2s | 14.1s | 67s |
| 5 | 2 | 204s | 23s | 100s | 34s | 12s | 24.9s | 16.1s | 69s |
| 5 | 3 | 205s | 19s | 110s | 40s | 14s | 20.3s | 11.2s | 62s |

### Statistics (n=15)

| Metric | Mean | Stdev | Min | Max |
|---|---|---|---|---|
| **Total** | **219s** | 29s | 195s | 291s |
| VM Provisioning | 20s | 1s | 19s | 23s |
| Boot 1 | 106s | 5s | 98s | 114s |
| Rebase (total) | 38s | 4s | 30s | 46s |
| Reboot | 15s | 3s | 10s | 18s |
| systemd-analyze | 21s | 4s | 16s | 28s |
| chrony-wait | 12s | 4s | 7s | 19s |
| KTR | 78s | 28s | 52s | 150s |

### Ostree Chunks

0 chunks present on the boot image, all 51 chunks needed (1.2 GB fetch). Identical chunk profile to 4.16.41 and 4.15.51.

### Notes

- **Round 2 outlier**: All three zones in round 2 showed KTR of 117-137s (vs 56-78s in other rounds), driving total times to 264-291s. This appears to be a cluster-wide registry or scheduling anomaly during that round.
- **Chunk profile unchanged**: Still 0/51, 1.2 GB — four minor versions of drift adds no incremental fetch volume beyond what was already needed at 4.16.41.
- **Rebase stable**: 38s mean, consistent with previous versions (30-42s range). The rebase phase is registry-throughput-limited, not chunk-count-limited.
- **Excluding round 2**: Without the R2 outlier, mean total drops to 205s — in line with all previous versions.

## OCP 4.13.51 — Five Minor Versions Back (4.13 → 4.18)

### All Data Points

| Round | Zone | Total | VM Prov | Boot 1 | Rebase | Reboot | SA | chrony | KTR |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 243s | 21s | 131s | 56s | 18s | 23.6s | 14.1s | 73s |
| 1 | 2 | 244s | 25s | 127s | 52s | 14s | 19.5s | 10.1s | 78s |
| 1 | 3 | 241s | 23s | 127s | 54s | 18s | 22.3s | 14.1s | 73s |
| 2 | 1 | 216s | 24s | 104s | 35s | 16s | 21.1s | 12.1s | 72s |
| 2 | 2 | 212s | 30s | 107s | 40s | 11s | 21.2s | 12.1s | 64s |
| 2 | 3 | 212s | 14s | 105s | 36s | 17s | 20.2s | 12.1s | 76s |
| 3 | 1 | 230s | 19s | 132s | 56s | 14s | 20.8s | 12.2s | 65s |
| 3 | 2 | 229s | 24s | 114s | 41s | 17s | 31.1s | 20.1s | 74s |
| 3 | 3 | 228s | 24s | 123s | 52s | 17s | 17.3s | 9.0s | 64s |
| 4 | 1 | 295s | 22s | 205s | 136s | 30s | 18.6s | 10.1s | 38s |
| 4 | 2 | 201s | 20s | 92s | 33s | 11s | 25.3s | 16.1s | 78s |
| 4 | 3 | 201s | 15s | 92s | 31s | 16s | 21.1s | 12.2s | 78s |
| 5 | 1 | 204s | 20s | 106s | 36s | 14s | 26.3s | 17.2s | 64s |
| 5 | 2 | 203s | 23s | 118s | 47s | 11s | 17.2s | 7.1s | 51s |
| 5 | 3 | 202s | 24s | 117s | 47s | 17s | 17.8s | 9.0s | 44s |

### Statistics (n=15)

| Metric | Mean | Stdev | Min | Max |
|---|---|---|---|---|
| **Total** | **224s** | 25s | 201s | 295s |
| VM Provisioning | 22s | 4s | 14s | 30s |
| Boot 1 | 121s | 28s | 92s | 205s |
| Rebase (total) | 48s | 25s | 31s | 136s |
| Reboot | 18s | 5s | 11s | 30s |
| systemd-analyze | 23s | 5s | 17s | 31s |
| chrony-wait | 13s | 5s | 7s | 20s |
| KTR | 64s | 9s | 38s | 78s |

### Ostree Chunks

0 chunks present on the boot image, all 51 chunks needed (1.2 GB fetch). The 4.13.51 journal uses a slightly different log format ("stored:" vs "present:") but the data is equivalent. Identical chunk profile to 4.14.38–4.16.41.

### Notes

- **R4-Z1 outlier**: 295s total with 136s rebase — a single-zone anomaly that inflated the mean. Without it, mean total drops to 219s.
- **Rebase variance increasing**: 48s mean with 25s stdev (vs 38s/4s for 4.14.38). The high variance comes from occasional very slow rebase (136s), not a consistent slow-down.
- **Reboot slightly higher**: 18s mean (vs 14-15s for all previous versions). The 4.13 boot image may have a slightly longer shutdown/POST cycle.
- **Last RHEL 9 version**: 4.13.51 is the oldest RHEL 9 boot image in this study. The next version (4.12.40) crosses the RHEL 8/9 boundary.

## OCP 4.12.40 — RHEL 8/9 Boundary (6 Minor Versions Back)

### All Data Points

| Round | Zone | Total | VM Prov | Boot 1 | Rebase | Reboot | SA | chrony | KTR |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 256s | 24s | 161s | 83s | 11s | 18.3s | 9.1s | 60s |
| 1 | 2 | 253s | 23s | 155s | 71s | 17s | 18.0s | 9.1s | 58s |
| 1 | 3 | 253s | 26s | 157s | 72s | 11s | 21.1s | 12.1s | 59s |
| 2 | 1 | 236s | 20s | 146s | 63s | 11s | 24.1s | 15.1s | 59s |
| 2 | 2 | 235s | 22s | 137s | 55s | 18s | 18.1s | 9.1s | 58s |
| 2 | 3 | 234s | 22s | 137s | 55s | 17s | 18.1s | 9.0s | 58s |
| 3 | 1 | 215s | 16s | 118s | 37s | 17s | 18.2s | 9.1s | 64s |
| 3 | 2 | 213s | 20s | 112s | 38s | 13s | 28.3s | 18.2s | 68s |
| 3 | 3 | 214s | 20s | 121s | 40s | 17s | 16.4s | 7.0s | 56s |
| 4 | 1 | 208s | 19s | 115s | 36s | 16s | 18.1s | 9.1s | 58s |
| 4 | 2 | 246s | 19s | 145s | 50s | 23s | 24.6s | 16.2s | 59s |
| 4 | 3 | 206s | 18s | 118s | 34s | 12s | 22.3s | 14.2s | 58s |
| 5 | 1 | 213s | 20s | 124s | 41s | 11s | 22.2s | 14.1s | 58s |
| 5 | 2 | 212s | 23s | 121s | 35s | 11s | 18.1s | 9.0s | 57s |
| 5 | 3 | 212s | 16s | 125s | 42s | 17s | 25.5s | 16.2s | 54s |

### Statistics (n=15)

| Metric | Mean | Stdev | Min | Max |
|---|---|---|---|---|
| **Total** | **227s** | 18s | 206s | 256s |
| VM Provisioning | 21s | 3s | 16s | 26s |
| Boot 1 | 131s | 17s | 112s | 161s |
| Rebase (total) | 49s | 15s | 34s | 83s |
| Reboot | 14s | 5s | 11s | 23s |
| systemd-analyze | 22s | 4s | 16s | 28s |
| chrony-wait | 12s | 4s | 7s | 18s |
| KTR | 61s | 4s | 54s | 68s |

### Ostree Chunks

0 chunks present on the boot image, all 51 chunks needed (1.2 GB fetch). Despite crossing the RHEL 8 → RHEL 9 major boundary, the chunk profile is identical to the RHEL 9 boot images (4.13-4.16). The rebase process handles the cross-major transition transparently.

### Notes

- **RHEL 8/9 boundary crossed successfully**: The RHEL 8 boot image (4.12.40) rebases to the RHEL 9 node image (4.18.24) without errors. The cross-major rebase is handled entirely by rpm-ostree/MCD.
- **Boot 1 longest so far**: 131s mean (vs 106-121s for RHEL 9 versions). The older RHEL 8 boot image has a slower initial boot sequence.
- **Rebase time consistent**: 49s mean matches 4.13.51 (48s) — the RHEL 8/9 boundary doesn't add rebase overhead.
- **R1 slower**: Rounds 1-2 were consistently 234-256s, while rounds 3-5 were 206-215s. This may reflect registry warm-up or caching effects.

## OCP 4.11.35 — Seven Minor Versions Back (4.11 → 4.18, RHEL 8, 3-Boot)

### All Data Points

The 4.11.35 RHCOS AMI uses RHEL 8 (kernel 4.18.0). Booting to a 4.18.24 cluster requires a **3-boot sequence** with two rebases: RHEL 8 → RHEL 9 intermediate, then RHEL 9 → 4.18.24 target. Standard 2-boot phase extraction doesn't apply; instead, the timeline is broken into the 3 boot phases.

| Round | Zone | Total | VM Prov | Boot -2 (RHEL8) | Reboot 1 | Boot -1 (RHEL9 rebase) | Reboot 2 | SA | chrony | KTR |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 319s | 32s | 130s | 29s | 55s | 12s | 22.8s | 14.1s | 61s |
| 1 | 2 | 319s | 30s | 136s | 23s | 53s | 12s | 22.1s | 14.1s | 65s |
| 1 | 3 | 319s | 30s | 135s | 24s | 57s | 12s | 16.6s | 7.0s | 61s |
| 2 | 1 | 300s | 22s | 129s | 17s | 57s | 12s | 20.2s | 12.1s | 63s |
| 2 | 2 | 298s | 17s | 126s | 11s | 65s | 11s | 18.3s | 9.1s | 68s |
| 2 | 3 | 299s | 22s | 127s | 17s | 55s | 12s | 18.2s | 9.1s | 66s |
| 3 | 1 | 322s | 24s | 118s | 17s | 75s | 11s | 22.1s | 14.1s | 77s |
| 3 | 2 | 321s | 23s | 123s | 12s | 68s | 12s | 16.5s | 7.0s | 83s |
| 3 | 3 | 320s | 24s | 121s | 11s | 85s | 12s | 22.4s | 14.1s | 67s |
| 4 | 1 | 289s | 22s | 102s | 17s | 56s | 13s | 27.3s | 18.2s | 79s |
| 4 | 2 | 352s | 22s | 182s | 17s | 59s | 12s | 25.3s | 16.1s | 60s |
| 4 | 3 | 286s | 24s | 118s | 17s | 58s | 11s | 17.2s | 8.0s | 58s |
| 5 | 1 | 291s | 17s | 118s | 11s | 57s | 12s | 16.9s | 8.0s | 76s |
| 5 | 2 | 290s | 22s | 121s | 17s | 51s | 11s | 22.2s | 14.1s | 68s |
| 5 | 3 | 291s | 23s | 119s | 17s | 56s | 12s | 22.2s | 14.2s | 64s |

### Statistics (n=15)

| Metric | Mean | Stdev | Min | Max |
|---|---|---|---|---|
| **Total** | **308s** | 19s | 286s | 352s |
| VM Provisioning | 24s | 4s | 17s | 32s |
| Boot -2 (RHEL 8 ignition + rebase) | 127s | 17s | 102s | 182s |
| Reboot 1 | 17s | 5s | 11s | 29s |
| Boot -1 (RHEL 9 MCD rebase) | 61s | 9s | 51s | 85s |
| Reboot 2 | 12s | 1s | 11s | 13s |
| systemd-analyze | 22s | 4s | 16s | 27s |
| chrony-wait | 13s | 4s | 7s | 18s |
| KTR | 68s | 8s | 58s | 83s |

### 3-Boot Sequence

The 4.11 RHCOS (RHEL 8) requires a unique 3-boot path to reach the 4.18.24 (RHEL 9) target:

1. **Boot -2** (kernel 4.18.0, RHEL 8): Ignition, network, MCD firstboot. First rebase transitions the OS from RHEL 8 to a RHEL 9 intermediate image. Duration: ~127s.
2. **Boot -1** (kernel 5.14.0, RHEL 9): Now running RHEL 9. MCD performs a second rebase from the intermediate to the final 4.18.24 node image, fetching all 51 ostree chunks (1.2 GB). Duration: ~61s.
3. **Boot 0** (kernel 5.14.0, RHEL 9): Final boot. systemd startup, chrony-wait, kubelet, NodeReady.

### Ostree Chunks

0 chunks present on the boot image, all 51 chunks needed (1.2 GB fetch) during the Boot -1 rebase. The first rebase (RHEL 8 → RHEL 9) fetches the intermediate image separately.

### Notes

- **3-boot sequence adds ~80s**: The extra reboot cycle (RHEL 8 → RHEL 9 intermediate → target) adds ~80s vs 4.12.40 (227s → 308s). This is the first version where boot image age measurably increases total scale-up time.
- **Two separate rebases**: The RHEL 8 → RHEL 9 transition requires an intermediate rebase step. The MCD handles this transparently but it adds a full boot cycle (~60s Boot -1 + ~17s reboot + ~12s reboot).
- **Boot -2 dominates**: At 127s, the RHEL 8 ignition + first rebase is the longest single phase.
- **R4-Z2 outlier**: Boot -2 of 182s (vs 118-136s typical) drove total to 352s.
- **multus-whereabouts-ipam-cni**: Reports 0 MB — possibly a manifest-only pull or size reporting artifact for this particular boot path.

## OCP 4.10.20 — Eight Minor Versions Back (4.10 → 4.18, RHEL 8, 3-Boot)

### All Data Points

Like 4.11.35, the 4.10.20 RHCOS AMI requires a 3-boot sequence with two rebases.

| Round | Zone | Total | VM Prov | Boot -2 (RHEL8) | Reboot 1 | Boot -1 (RHEL9 rebase) | Reboot 2 | SA | chrony | KTR |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 337s | 24s | 140s | 13s | 89s | 12s | 22.3s | 14.2s | 59s |
| 1 | 2 | 336s | 18s | 146s | 12s | 84s | 12s | 20.5s | 12.1s | 64s |
| 1 | 3 | 335s | 23s | 149s | 17s | 86s | 10s | 20.3s | 12.1s | 50s |
| 2 | 1 | 337s | 15s | 136s | 11s | 101s | 11s | 22.2s | 14.1s | 63s |
| 2 | 2 | 368s | 23s | 154s | 17s | 100s | 11s | 18.2s | 9.1s | 63s |
| 2 | 3 | 333s | 23s | 139s | 12s | 83s | 11s | 18.2s | 9.0s | 65s |
| 3 | 1 | 332s | 28s | 138s | 19s | 82s | 12s | 16.0s | 7.0s | 53s |
| 3 | 2 | 328s | 26s | 140s | 17s | 80s | 12s | 18.0s | 9.0s | 53s |
| 3 | 3 | 327s | 26s | 131s | 12s | 71s | 12s | 28.7s | 20.2s | 75s |
| 4 | 1 | 319s | 24s | 136s | 17s | 70s | 11s | 22.3s | 14.1s | 61s |
| 4 | 2 | 315s | 23s | 129s | 11s | 85s | 12s | 22.1s | 14.1s | 55s |
| 4 | 3 | 315s | 23s | 128s | 13s | 82s | 13s | 18.2s | 9.1s | 56s |
| 5 | 1 | 327s | 22s | 134s | 17s | 79s | 11s | 18.3s | 9.1s | 64s |
| 5 | 2 | 380s | 21s | 206s | 18s | 74s | 13s | 17.4s | 8.0s | 48s |
| 5 | 3 | 326s | 22s | 134s | 17s | 82s | 11s | 22.2s | 14.1s | 60s |

### Statistics (n=15)

| Metric | Mean | Stdev | Min | Max |
|---|---|---|---|---|
| **Total** | **334s** | 18s | 315s | 380s |
| VM Provisioning | 23s | 3s | 15s | 28s |
| Boot -2 (RHEL 8 ignition + rebase) | 143s | 19s | 128s | 206s |
| Reboot 1 | 15s | 3s | 11s | 19s |
| Boot -1 (RHEL 9 MCD rebase) | 83s | 9s | 70s | 101s |
| Reboot 2 | 12s | 1s | 10s | 13s |
| systemd-analyze | 21s | 5s | 16s | 29s |
| chrony-wait | 12s | 4s | 7s | 20s |
| KTR | 59s | 7s | 48s | 75s |

### 3-Boot Sequence

Same 3-boot path as 4.11.35, but each phase takes longer:

1. **Boot -2** (kernel 4.18.0, RHEL 8): Ignition + first rebase (RHEL 8 → RHEL 9). Duration: ~143s (vs 127s for 4.11.35).
2. **Boot -1** (kernel 5.14.0, RHEL 9): MCD secondrebase to 4.18.24 target image. Duration: ~83s (vs 61s for 4.11.35).
3. **Boot 0** (kernel 5.14.0, RHEL 9): Final boot, NodeReady.

### Ostree Chunks

0 chunks present on the boot image, all 51 chunks needed (1.2 GB fetch). Same as all non-baseline versions.

### Notes

- **Slowest version**: 334s mean — 57% slower than the baseline (213s) and 26s slower than 4.11.35 (308s).
- **Boot -1 much longer**: 83s mean (vs 61s for 4.11.35). The 4.10 → 4.18 rebase requires more work in the intermediate RHEL 9 boot, possibly due to a larger delta between the intermediate image and the final target.
- **R5-Z2 outlier**: Boot -2 of 206s drove total to 380s.

## Conclusions

### Boot Image Age vs Scale-Up Time

The study reveals three distinct regimes, plus two special-case data points:

1. **2-boot images (4.12–4.18, including exact-match, forward-drift)**: Total scale-up time spans **197–227s**. The exact-match boot image (4.18.27, 0 MB fetch) at 197s is only 16s faster than the native 4.18.24 boot image at 213s, and within noise of the oldest RHEL 9 (4.13.51, 224s) or the RHEL 8 4.12.40 (227s). All complete with a normal 2-boot sequence regardless of boot image age or direction.

2. **3-boot images (4.11 and 4.10)**: A step-function increase appears. 4.11.35 jumps to **308s** and 4.10.20 to **334s** due to a 3-boot sequence requiring an intermediate RHEL 9 pivot. These are also RHEL 8 boot images, but unlike 4.12 they cannot rebase directly to the RHEL 9 target. The specific RHEL 8 version threshold that triggers the 3-boot path was not investigated further.

3. **Older = slower within 3-boot**: Boot -1 (intermediate rebase) increases from 61s (4.11) to 83s (4.10), suggesting a larger delta to the intermediate image adds cost.

### Ostree Chunk Sharing

- **4.18.27 (exact match)**: 51/51 chunks present → 0 needed (0 MB fetch). Zero-byte rebase.
- **4.18.40 (newer)**: 16/51 chunks present → 35 needed (596 MB fetch). Forward drift diverges chunks too.
- **4.18.24 (native)**: 27/51 chunks present → 24 needed (437 MB fetch)
- **4.18.0**: 7/51 present → 44 needed (1.2 GB). z-stream drift within 4.18 already costs 74% of chunks.
- **4.17.35**: 7/51 present. Crossing a minor version boundary adds no additional chunk loss.
- **4.16.41 and older**: 0/51 present. Total cache miss — every chunk fetched. Fetch volume plateaus at 1.2 GB.
- **4.19.23**: 51/51 RHCOS base chunks present (0 MB ostree fetch) + 2 custom OCP layers (219.6 MB, always fetched).

**Key finding**: Chunk sharing drops to zero within 2 minor versions in either direction. After that, ostree fetch volume is constant regardless of boot image age. Eliminating fetch volume entirely (exact-match boot image, 0 MB) saves only ~16s vs the native boot image — confirming ostree rebase is NOT a significant bottleneck. The 3-boot path is the only meaningful penalty. Forward drift also causes chunk divergence at a similar rate to backward drift.

### 4.19+ Layered Architecture

OCP 4.19 restructured the node image into two separate components:

1. **RHCOS base** (in the boot AMI): All RHCOS filesystem content as ostree chunks, versioned by RHEL minor (e.g., RHEL 9.6). All 51 chunks are present on any boot image with the matching RHEL minor — eliminating the variable 0–1.2 GB ostree chunk fetch entirely.

2. **OCP custom layers**: 2 layers (219.6 MB) containing kubelet, cri-o, and other OCP-version-specific packages. These are **always fetched** on every firstboot, regardless of boot image age or freshness.

**Net impact**: Total scale-up time (216s) is essentially unchanged vs the 4.18.x baseline (213s native). The variable ostree chunk fetch (0–1.2 GB) is replaced by a fixed 220 MB OCP layer fetch. This makes firstboot time far more predictable but does not eliminate the rebase fetch cost. Boot image staleness now effectively only matters when crossing RHEL minor version boundaries — a much less frequent event than z-stream or minor OCP version updates.

### The 3-Boot Penalty

The 4.11 and 4.10 boot images (older RHEL 8) require two rebases instead of one, with an intermediate RHEL 9 pivot. The 4.12 boot image (also RHEL 8) does **not** require this intermediate step — it rebases directly to the target in a normal 2-boot sequence.

| Version | RHEL | Boots | Rebase Path | Extra Time |
|---|---|---|---|---|
| 4.12.40 | 8 | 2 | Direct RHEL 8 → 4.18.24 target | 0s (baseline) |
| 4.11.35 | 8 | 3 | RHEL 8 → RHEL 9 intermediate → 4.18.24 target | +81s |
| 4.10.20 | 8 | 3 | RHEL 8 → RHEL 9 intermediate → 4.18.24 target | +107s |

The extra boot cycle costs ~80-110s: an additional rebase (~60-83s), an additional reboot (~15s), and additional ignition/systemd time.

### Container Image Pulls

The same 18 images (or 20 for baseline/4.10) totaling 10.2–12.1 GB are pulled in every case. Image pulls are parallelized by CRI-O (sum of individual pull times ~168s, wall clock ~60s). Boot image age has no effect on container image pulls.

### Practical Implications

1. **Avoid the oldest RHEL 8 boot images** (4.11 and earlier) on RHEL 9 clusters — they trigger a 3-boot sequence adding ~80-110s (35-50% increase). RHEL 8 4.12 works fine with a normal 2-boot path.
2. **Boot image age has negligible impact on scale-up time** across a wide range. A 4.12 (RHEL 8) boot image on a 4.18 cluster is within noise of the native 4.18 boot image.
3. **Keeping boot images perfectly matched is not worth optimizing for**: The exact-match boot image (4.18.27 on 4.18.26, 0 MB fetch) saves only ~16s vs the native boot image (437 MB fetch). The ostree rebase phase simply isn't a bottleneck.
4. **Ostree chunk sharing plateaus quickly**: After 2 minor versions, all chunks are fetched regardless. The ~800 MB of extra fetch (437 MB → 1.2 GB) takes only ~10-15s additional rebase time.
5. **The dominant bottleneck is container image pulls (~60-70s)**, not ostree rebase (~13-50s). Pre-pulling NodeReady images would benefit all versions equally and would have a larger impact than any boot image optimization.
6. **MCD firstboot image pull is a hidden fixed cost (~35s in 4.18, ~19s in 4.19)**: The 4.18.27 Boot 1 journal shows ~35s spent pulling the 937 MB MCD image (`machine-config-operator`) before rpm-ostree even starts. The image is currently plain gzip with no partial-pull capability. If ART rebuilt it with zstd:chunked and MCO enabled `enable_partial_images = "true"` in `/etc/containers/storage.conf`, podman could fetch only the files needed to start the container (the `machine-config-daemon` binary and its dependencies, a small fraction of 937 MB) and skip the rest. Estimated savings: 15–25s off Boot 1 in 4.18.x; 4.19 appears to have reduced this cost already (~19s mean).
7. **In 4.19+, boot image staleness effectively disappears as a concern**: With the layered architecture, the RHCOS base is always fully present on any boot image with the same RHEL minor version. The OCP custom layers (220 MB fixed cost) are always fetched fresh. The total cost is predictable and comparable to the 4.18.x native baseline. Only a RHEL minor version bump in the boot image would cause ostree chunk misses.
