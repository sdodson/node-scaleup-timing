# RHCOS Boot Image Analysis

This directory contains an analysis of RHCOS boot image package evolution across OCP 4.12 through 4.19.

## Key files

- `RHCOS-Package-Evolution-Summary.md` — Polished markdown summary of all findings
- `rhcos-rpm-evolution-report.txt` — Full detailed report with per-package diffs
- `rpms-{version}.txt` — Raw RPM lists per release (GA and latest z-stream)
- `rpms-vmdk.txt` — RPM list from a raw VMDK disk image
- `packages-never-updated-in-zstreams.txt` — 230 packages unchanged across all 5 z-stream lifecycles
- `scripts/` — Shell scripts for extraction and comparison

## Context

- Compares .0 GA releases to latest z-streams for 5 major versions
- Includes cross-major comparison (4.16.0 → 4.18.38, both RHEL 9.4)
- Includes container image vs VMDK comparison for 4.19
- Analysis considers full NEVRA (name-epoch-version-release.arch), not just package names
