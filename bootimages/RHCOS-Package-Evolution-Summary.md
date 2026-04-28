# RHCOS Node Image Package Evolution Analysis

**Date:** April 27, 2026  
**Scope:** OCP 4.12 through 4.19 — comparing `.0` GA releases to their latest z-stream, plus cross-major and boot image comparisons

---

## Terminology

- **Node Image:** The RHCOS container image shipped with each OCP release, used during MCD firstboot to rebase the OS via rpm-ostree. Each z-stream release contains a node image. The `rpms-{version}.txt` files in this analysis are extracted from node images.
- **Boot Image:** The VMDK/AMI/ISO disk image used to initially boot a new node before Ignition and MCD run. Boot images are updated infrequently and may lag the node image by many z-streams. The `rpms-vmdk.txt` file is extracted from a boot image.

---

## Overview

We extracted the full RPM package lists from RHCOS node images across five OCP major versions (4.12, 4.14, 4.16, 4.18, 4.19), comparing each `.0` GA release to its latest z-stream. We also compared the 4.19 node image against a boot image (raw VMDK), and performed a cross-major comparison (4.16.0 to 4.18.38) to isolate the effect of the RHEL base version.

## Summary Table

| Release Pair        | GA Pkgs | End Pkgs | Identical | Updated | Added | Removed | Unchanged | Updated |
|---------------------|--------:|---------:|----------:|--------:|------:|--------:|----------:|--------:|
| 4.12.0 → 4.12.87   |     503 |      501 |       312 |     188 |     1 |       3 |       62% |     37% |
| 4.14.0 → 4.14.64   |     517 |      519 |       350 |     165 |     4 |       2 |       67% |     31% |
| 4.16.0 → 4.16.60   |     542 |      542 |       337 |     205 |     0 |       0 |       62% |     37% |
| 4.18.0 → 4.18.38   |     564 |      564 |       383 |     180 |     1 |       1 |       67% |     31% |
| 4.19.0 → 4.19.29   |     570 |      570 |       373 |     195 |     4 |       4 |       65% |     34% |
| **Cross-major:**    |         |          |           |         |       |         |           |         |
| 4.16.0 → 4.18.38   |     542 |      564 |       336 |     205 |    23 |       1 |       61% |     37% |

## Key Findings

### 1. Remarkably Consistent Update Rate

Across all five major versions, **62-67% of packages remain at their GA version** by the final z-stream, while **31-37% get updated**. This ratio holds regardless of how many z-streams a release has (ranging from 29 to 87 z-streams).

### 2. RHEL Base Version Dominates Package Churn

Comparing 4.16.0 to 4.18.38 (both on RHEL 9.4) yields almost the same update ratio as the within-version 4.16.0 → 4.16.60 comparison (61% vs 62% unchanged, both with 205 updated packages). The only meaningful difference is 23 newly added packages in 4.18 (python3 modules, subscription-manager, OCP runtime components). This shows the **RHEL base version** is the dominant factor, not the OCP major version.

### 3. Steady Node Image Growth

The RHCOS node image has grown from **503 packages (4.12) to 570 packages (4.19)**, adding roughly 67 packages over four major versions.

| Version | GA Pkgs | Latest Pkgs | Z-Streams |
|---------|--------:|------------:|----------:|
| 4.12    |     503 |         501 |        87 |
| 4.14    |     517 |         519 |        64 |
| 4.16    |     542 |         542 |        60 |
| 4.18    |     564 |         564 |        38 |
| 4.19    |     570 |         570 |        29 |

### 4. Minimal Mid-Lifecycle Churn

Package additions and removals within a z-stream lifecycle are **very rare** (0-4 per cycle). The package manifest is essentially fixed at GA time.

### 5. Open vSwitch Rotation

Every release cycle swaps Open vSwitch versions, always done mid-z-stream:

| Transition       | OVS Version Change |
|------------------|-------------------|
| 4.12.0 → 4.12.87 | 2.17 → 3.1       |
| 4.14.0 → 4.14.64 | 3.1 → 3.3        |
| 4.16.0 → 4.16.60 | 3.3 (unchanged)   |
| 4.18.0 → 4.18.38 | 3.4 → 3.5        |
| 4.19.0 → 4.19.29 | 3.5 (unchanged)   |

---

## Package Update Frequency

Across all five z-stream lifecycles, packages fall into clear tiers:

| Category             | Count | Description |
|----------------------|------:|-------------|
| Always updated (5/5) |   100 | Updated in every single OCP release |
| Updated 4/5 cycles   |    38 | |
| Updated 3/5 cycles   |    47 | |
| Updated 2/5 cycles   |    26 | |
| Updated 1/5 cycles   |    87 | |
| Never updated         |   315 | Absolute stable core of RHCOS |

### Always-Updated Packages (100 packages, updated every cycle)

These are the packages that **always** receive z-stream updates:

- **Core OS:** kernel, glibc, systemd, pam, openssh, openssl, grub2
- **Security:** ca-certificates, gnupg2, gnutls, krb5-libs, selinux-policy
- **Networking:** NetworkManager (all subpackages), bind, curl, libcurl
- **Container runtime:** cri-o, crun, runc, podman, skopeo
- **OCP-specific:** openshift-clients, ignition, ostree
- **Identity:** sssd (all subpackages), samba (all subpackages)
- **Other:** linux-firmware, git-core, python3-libs, sqlite-libs, tzdata

### Never-Updated Packages (315 packages)

These form the stable core and include foundational packages that rarely receive CVE fixes or feature updates within a RHEL minor release: bash, coreutils, findutils, grep, sed, gawk, util-linux, perl modules, python3 standard library bindings, fuse, clevis/jose/luksmeta (LUKS), and many small libraries.

---

## Cross-Version Consistency of Unchanged Packages

We examined the 454 packages present in all five GA releases to determine whether a package's "unchanged" or "updated" status is consistent across OCP minor versions. In other words: if `coreutils` stays at its GA version throughout 4.14.z, does it also stay unchanged in 4.16.z?

### Consistency Distribution

| Behavior | Packages | % of 454 |
|----------|----------|----------|
| **Always unchanged** (5/5 versions) | 230 | 51% |
| **Always updated** (0/5 versions) | 100 | 22% |
| Unchanged in 4/5 versions | 59 | 13% |
| Unchanged in 1/5 versions | 29 | 6% |
| Unchanged in 2/5 versions | 19 | 4% |
| Unchanged in 3/5 versions | 17 | 4% |

**73% of packages** (330/454) behave identically across all five OCP versions — either always unchanged or always updated. The remaining **27%** (124 packages) are a "swing tier" whose update status varies by version.

The full list of 230 packages that never received a z-stream update in any OCP version is in [`packages-never-updated-in-zstreams.txt`](packages-never-updated-in-zstreams.txt).

### Swing Tier Patterns

The 124 inconsistent packages fall into recognizable patterns:

- **4/5 unchanged (59 packages):** Nearly stable, with a one-off CVE fix in a single version — e.g., `bzip2` (only updated in 4.16), `dbus` (only in 4.12), `elfutils-*` (only in 4.19).

- **1/5 unchanged (29 packages):** Nearly always updated, with one version where the GA version happened to survive — e.g., `dracut` (unchanged only in 4.12), `libgcc`/`libstdc++` (unchanged only in 4.19).

- **2-3/5 unchanged (36 packages):** Genuinely unpredictable — e.g., the `perl-*` interpreter packages shifted from stable in 4.12/4.14 to always-updated starting in 4.16; `polkit` went the other direction. These often reflect a RHEL rebase boundary where upstream cadence changed.

---

## Z-Stream Bisection: First Half vs Second Half

We extracted RPM lists from the midpoint of each z-stream lifecycle (4.12.43, 4.14.32, 4.16.30, 4.18.19, 4.19.14) to determine whether updates are front-loaded or back-loaded. Note that the "midpoint" here is by z-stream number, not by calendar time — see the next section for calendar-based analysis.

### Update Counts by Half

| Version | Range | Unchanged | Updated | Added | Removed | % Updated |
|---------|-------|----------:|--------:|------:|--------:|----------:|
| 4.12 | .0 → .43 (1st half) | 372 | 131 | 0 | 0 | 26% |
|        | .43 → .87 (2nd half) | 341 | 159 | 1 | 3 | 31% |
| 4.14 | .0 → .32 (1st half) | 395 | 122 | 1 | 0 | 23% |
|        | .32 → .64 (2nd half) | 372 | 144 | 3 | 2 | 27% |
| 4.16 | .0 → .30 (1st half) | 409 | 133 | 0 | 0 | 24% |
|        | .30 → .60 (2nd half) | 365 | 177 | 0 | 0 | 32% |
| 4.18 | .0 → .19 (1st half) | 483 | 81 | 0 | 0 | 14% |
|        | .19 → .38 (2nd half) | 399 | 164 | 1 | 1 | 29% |
| 4.19 | .0 → .14 (1st half) | 434 | 132 | 0 | 4 | 23% |
|        | .14 → .29 (2nd half) | 434 | 132 | 4 | 0 | 23% |

### Update Overlap Between Halves

Most updated packages get updated in both halves — these are packages that receive continuous CVE/bugfix attention throughout the lifecycle:

| Version | 1st half | 2nd half | Both halves | 1st only | 2nd only |
|---------|----------|----------|-------------|----------|----------|
| 4.12    | 131      | 159      | 101         | 30       | 58       |
| 4.14    | 122      | 144      | 99          | 23       | 45       |
| 4.16    | 133      | 177      | 105         | 28       | 72       |
| 4.18    | 81       | 164      | 64          | 17       | 100      |
| 4.19    | 132      | 132      | 71          | 61       | 61       |

The "2nd half only" bucket is consistently larger than "1st half only", meaning more packages transition from unchanged to updated in the second half than settle down after an early update.

### Consistently Late-Arriving Packages

Packages that are only updated in the second half across 4+ versions — these consistently receive their first z-stream update late in the lifecycle:

- `gnupg2` (5/5), `bsdtar`/`libarchive` (4/5), `jq` (4/5), `libssh` (4/5), `rsync` (4/5), `vim-minimal` (4/5), `nftables` (4/5), `irqbalance` (4/5), `libbrotli` (4/5), `libxslt` (4/5)

### Consistently Front-Loaded Packages

Only 3 packages are consistently updated in the first half but not the second (in 3/5 versions): `containers-common`, `rpm-ostree`, `rpm-ostree-libs`. These are OCP-specific components that stabilize early.

---

## Calendar-Based Drift Analysis (4.12)

The z-stream bisection above splits by z-stream number, but OpenShift z-stream cadence is not uniform: releases ship weekly early in the lifecycle, biweekly as the release matures, and every ~4 weeks during the EUS tail. For 4.12, the lifecycle spans 3.2 years (Jan 2023 – Apr 2026).

To correct for this, we selected the z-stream release closest to each 6-month calendar boundary and compared packages within each window. The "Updated" column counts packages whose version changed *within that specific window* — not cumulative from GA.

### Per-Window Package Updates

| Window | Range | Date Range | Months | Z-streams | Cadence | Updated | Added | Removed |
|--------|-------|------------|-------:|----------:|--------:|--------:|------:|--------:|
| 1 | .0 → .25  | Jan 2023 – Jul 2023 |  6.0 | 25 |  7d/z |  82 | 0 | 0 |
| 2 | .25 → .47 | Jul 2023 – Jan 2024 |  6.0 | 22 |  8d/z | 112 | 1 | 1 |
| 3 | .47 → .60 | Jan 2024 – Jun 2024 |  5.3 | 13 | 12d/z | 117 | 0 | 2 |
| 4 | .60 → .72 | Jun 2024 – Jan 2025 |  7.4 | 12 | 19d/z |  54 | 0 | 0 |
| 5 | .72 → .78 | Jan 2025 – Jul 2025 |  5.1 |  6 | 26d/z |  36 | 0 | 0 |
| 6 | .78 → .87 | Jul 2025 – Apr 2026 |  8.9 |  9 | 30d/z |  80 | 0 | 0 |

### Cumulative Drift from GA

| Range | Months from GA | Total updated | Still at GA | % drifted |
|-------|---------------:|--------------:|------------:|----------:|
| .0 → .25  |  6.0 |  82 | 421 | 16% |
| .0 → .47  | 12.0 | 141 | 361 | 28% |
| .0 → .60  | 17.2 | 173 | 327 | 35% |
| .0 → .72  | 24.6 | 179 | 321 | 36% |
| .0 → .78  | 29.7 | 181 | 319 | 36% |
| .0 → .87  | 38.6 | 188 | 312 | 38% |

### Key Observations

**Updates peak in months 6-18, then drop sharply.** Windows 2 and 3 each see 112-117 packages updated — the highest per-window counts in the lifecycle. This is when the bulk of RHEL errata for security-critical packages (kernel, glibc, openssl, curl, etc.) are flowing. By contrast, windows 4 and 5 drop to 54 and 36 updates respectively.

**Window 6 shows a late resurgence.** The final window (.78 → .87, Jul 2025 – Apr 2026) jumps back to 80 updated packages after the lull in windows 4-5. This coincides with late-lifecycle CVEs hitting packages that had been stable for over a year.

**Node image drift from GA plateaus after 18 months.** By 4.12.60 (~17 months), 35% of packages have drifted from their GA versions. The remaining 21 months only add 3 more percentage points (35% → 38%). The first 18 months account for 92% of all eventual drift.

**The z-stream number midpoint (4.12.43) is actually at month 10, not the calendar midpoint.** The first 43 z-streams span only 10 months (weekly cadence), while the last 44 span 28 months (biweekly → monthly). Bisecting by z-stream number is misleading — the "second half" has nearly 3x more calendar time.

**Z-stream cadence slows 4x over the lifecycle.** Early releases ship every 7-8 days; by the EUS tail it's every 26-30 days. This means each late z-stream carries more accumulated package changes than an early one, even though fewer packages are changing per month overall.

---

## Package Additions and Removals Per Lifecycle

### 4.12.0 → 4.12.87
- **Added:** openvswitch3.1
- **Removed:** compat-openssl10, make, openvswitch2.17

### 4.14.0 → 4.14.64
- **Added:** openssl-fips-provider, openssl-fips-provider-so, openvswitch3.3, ose-aws-ecr-image-credential-provider
- **Removed:** openldap-compat, openvswitch3.1

### 4.16.0 → 4.16.60
- **Added:** *(none)*
- **Removed:** *(none)*

### 4.18.0 → 4.18.38
- **Added:** openvswitch3.5
- **Removed:** openvswitch3.4

### 4.19.0 → 4.19.29
- **Added:** fcoe-utils, libconfig, lldpad, numad
- **Removed:** conntrack-tools, libnetfilter_cthelper, libnetfilter_cttimeout, libnetfilter_queue

---

## Boot Image vs Node Image Comparison (4.19)

We compared the 4.19 node image (570 packages) against the boot image (VMDK, 557 packages). **373 packages are common to both** with identical versions.

Packages present in the node image but absent from the boot image are primarily OCP-specific runtime components that get added during MCD firstboot:

- **Container/OCP runtime:** cri-o, cri-tools, openshift-clients, openshift-kubelet, conmon-rs
- **Networking:** NetworkManager-ovs, openvswitch3.5, openvswitch-selinux-extra-policy
- **Cloud credentials:** ose-azure-acr-image-credential-provider, ose-gcp-gcr-image-credential-provider
- **Other:** unbound-libs, gpg-pubkey

---

## Methodology

1. **Node images:** RPM lists extracted from RHCOS release container images (node images) using `rpm --dbpath` against the embedded rpmdb
2. **Boot image (VMDK):** RPM database extracted from a raw VMDK boot image by mounting the rpmdb.sqlite directly
3. **Comparison scripts:** Custom shell scripts in `scripts/` directory performed the diff and evolution analysis
4. **Data files:** Raw RPM lists stored as `rpms-{version}.txt`, package name maps as `name-map-*.txt`, and the full evolution report as `rhcos-rpm-evolution-report.txt`

---

## Files in This Analysis

| File | Description |
|------|-------------|
| `rpms-{version}.txt` | Full RPM list for each release's node image (GA, midpoint, and latest for each version) |
| `rpms-vmdk.txt` | RPM list extracted from the boot image (VMDK) |
| `rpms-common-all-three.txt` | Packages common to 4.19.0 node image, 4.19.29 node image, and the boot image |
| `rpms-same-containers.txt` | Packages identical between the two node image versions |
| `name-map-*.txt` | Package name → full NEVRA mappings |
| `pkgnames-rpms-*.txt` | Deduplicated package name lists |
| `packages-never-updated-in-zstreams.txt` | 230 packages unchanged in all 5 z-stream lifecycles |
| `rhcos-rpm-evolution-report.txt` | Full detailed evolution report with per-package diffs |
| `scripts/` | Shell scripts used for extraction and analysis |
