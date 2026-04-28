# RHCOS Node Image & Boot Image Analysis

This directory analyzes RHCOS package evolution across OCP 4.12 through 4.19.

- **Node Image:** The RHCOS container image shipped with each OCP release, used during MCD firstboot to rebase the OS. Updated every z-stream.
- **Boot Image:** The VMDK/AMI/ISO disk image used to initially boot a new node. Updated infrequently.

## Key files

- `RHCOS-Package-Evolution-Summary.md` — Polished markdown summary of all findings
- `rhcos-rpm-evolution-report.txt` — Full detailed report with per-package diffs
- `rpms-{version}.txt` — Raw RPM lists from node images per release (GA, midpoint, and latest z-stream)
- `rpms-vmdk.txt` — RPM list from a boot image (raw VMDK disk image)
- `packages-never-updated-in-zstreams.txt` — 230 packages unchanged across all 5 z-stream lifecycles
- `scripts/` — Shell scripts for extraction and comparison

## Context

- Compares .0 GA node images to latest z-stream node images for 5 major versions
- Includes cross-major comparison (4.16.0 → 4.18.38, both RHEL 9.4)
- Includes boot image (VMDK) vs node image comparison for 4.19
- Analysis considers full NEVRA (name-epoch-version-release.arch), not just package names
