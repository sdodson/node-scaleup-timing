---
name: compare-scaleup
description: Compare node scale-up timings across VM types or OCP versions
user_invocable: true
---

# Compare Scale-Up Results

Generate a comparison report across multiple scale-up tests, either across VM types within the same cluster or across OCP versions.

## Usage

The user specifies what to compare:
- **VM types**: e.g. "compare v3 vs v5 vs v6" — reads existing `scale-up-analysis-*.md` files
- **OCP versions**: e.g. "compare 4.18 vs 4.22" — reads both versioned and unversioned analysis files

## Process

### 1. Identify available analysis reports

Look for `scale-up-analysis-*.md` files in the working directory. Parse each one to extract:
- VM type
- OCP version
- Total scale-up time
- Per-phase timings

### 2. Build comparison tables

Create tables showing:
- Total time per VM type / version
- Phase-by-phase comparison
- Delta columns (absolute and percentage)
- Speedup summary

### 3. Key observations

Highlight:
- Which phases benefit most from hardware upgrades vs version changes
- Fixed costs that don't change (e.g. chrony-wait)
- Surprising results (e.g. rpm-ostree being faster on older versions)
- The dominant factor (VM generation vs OCP version)

### 4. Output

Write to `scale-up-analysis-{label}-comparison.md` where label describes the comparison (e.g. `4.18-comparison`, `vm-generations`, etc.).

Use the format from existing comparison files as a template.
