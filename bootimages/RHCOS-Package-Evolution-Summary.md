# RHCOS Boot Image Package Evolution Analysis

**Date:** April 27, 2026  
**Scope:** OCP 4.12 through 4.19 — comparing `.0` GA releases to their latest z-stream, plus cross-major and VMDK comparisons

---

## Overview

We extracted the full RPM package lists from RHCOS boot images across five OCP major versions (4.12, 4.14, 4.16, 4.18, 4.19), comparing each `.0` GA release to its latest z-stream. We also compared the 4.19 container image against a raw VMDK disk image, and performed a cross-major comparison (4.16.0 to 4.18.38) to isolate the effect of the RHEL base version.

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

### 3. Steady Image Growth

The RHCOS image has grown from **503 packages (4.12) to 570 packages (4.19)**, adding roughly 67 packages over four major versions.

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

## VMDK vs Container Image Comparison (4.19)

We compared the 4.19 RHCOS container image (570 packages) against a raw VMDK disk image (557 packages). **373 packages are common to both** with identical versions.

Packages present in the container image but absent from the VMDK are primarily OCP-specific runtime components:

- **Container/OCP runtime:** cri-o, cri-tools, openshift-clients, openshift-kubelet, conmon-rs
- **Networking:** NetworkManager-ovs, openvswitch3.5, openvswitch-selinux-extra-policy
- **Cloud credentials:** ose-azure-acr-image-credential-provider, ose-gcp-gcr-image-credential-provider
- **Other:** unbound-libs, gpg-pubkey

---

## Methodology

1. **Container images:** RPM lists extracted from RHCOS release container images using `rpm --dbpath` against the embedded rpmdb
2. **VMDK:** RPM database extracted from a raw VMDK disk image by mounting the rpmdb.sqlite directly
3. **Comparison scripts:** Custom shell scripts in `scripts/` directory performed the diff and evolution analysis
4. **Data files:** Raw RPM lists stored as `rpms-{version}.txt`, package name maps as `name-map-*.txt`, and the full evolution report as `rhcos-rpm-evolution-report.txt`

---

## Files in This Analysis

| File | Description |
|------|-------------|
| `rpms-{version}.txt` | Full RPM list for each release (10 files, GA + latest for each version) |
| `rpms-vmdk.txt` | RPM list extracted from the VMDK disk image |
| `rpms-common-all-three.txt` | Packages common to 4.19.0, 4.19.29, and the VMDK |
| `rpms-same-containers.txt` | Packages identical between the two container image versions |
| `name-map-*.txt` | Package name → full NEVRA mappings |
| `pkgnames-rpms-*.txt` | Deduplicated package name lists |
| `rhcos-rpm-evolution-report.txt` | Full detailed evolution report with per-package diffs |
| `scripts/` | Shell scripts used for extraction and analysis |
