---
name: analyze-scaleup
description: Analyze collected node artifacts to produce a scale-up timing breakdown report
user_invocable: true
---

# Analyze Scale-Up Timing

Parse previously collected node artifacts and produce a detailed scale-up timing analysis report.

## Usage

The user provides:
- A suffix label (e.g. `d4s-v6`) identifying which set of artifacts to analyze
- The MachineSet creation timestamp (UTC) — the scale-up start time
- Optionally, the OCP version and cluster details (or derive from existing artifacts)

## Input Artifacts

Read these files from the working directory:
- `node-journal-{suffix}.log` — primary source for all timing data
- `node-boot-list-{suffix}.txt` — boot boundaries
- `node-systemd-analyze-{suffix}.txt` — boot 2 startup time
- `node-systemd-blame-{suffix}.txt` — boot 2 service blame
- `node-systemd-critical-chain-{suffix}.txt` — boot 2 critical chain
- `new-machine-{suffix}-final.yaml` — machine details (VM type, zone)
- `new-node-{suffix}.yaml` — node Ready condition timestamp

## Analysis Process

### 1. Determine boot boundaries

From the boot list, identify:
- Boot -1 (first boot): first and last entry timestamps
- Boot 0 (second boot): first and last entry timestamps

### 2. Parse Boot 1 phases from journal

Search the journal for key markers:
- **Ignition start**: `ignition` entries near the start of boot -1
- **Ignition stages**: `ignition[*]: files: op(*)` or `Ignition finished successfully`
- **Pivot/sysroot**: `ostree-prepare-root` or `Switching root` entries
- **MCD firstboot start**: `machine-config-daemon-firstboot` or `machine-config-daemon` entries
- **MCD image pull**: `Pulling image` or `pulling` entries with `machine-config` in the image name
- **rpm-ostree rebase start**: `rpm-ostree` rebase or `Rebasing` entries
- **rpm-ostree staging done**: `Staging deployment` or `Transaction complete`
- **Reboot initiated**: last entries of boot -1, or `shutdown` / `reboot` entries

### 3. Parse Boot 2 phases

- **chrony-wait**: from critical-chain, note the start time and duration
- **CRI-O start**: `crio.service` start from journal or blame
- **Kubelet start**: `kubelet.service` start from journal
- **NodeReady**: search journal for `NodeReady` or `node .* status is now: NodeReady`; also check node YAML `.status.conditions[?(@.type=="Ready")].lastTransitionTime`

### 4. Calculate total and per-phase times

Total = MachineSet creation time → NodeReady time

### 5. Write the report

Output `scale-up-analysis-{suffix}.md` following the established format (see existing reports in the directory for the template). Include:

1. Cluster info header
2. Total scale-up time
3. Phase breakdown table
4. Time spent summary table (with % of total)
5. MCD firstboot detail (if data available)
6. Boot list
7. systemd-analyze output
8. systemd-analyze critical-chain
9. Key observations (what was fast/slow, comparisons)
10. Comparison table with other VM types if other `scale-up-analysis-*.md` files exist
11. List of saved artifacts

### 6. If comparing across OCP versions

If the user wants a cross-version comparison (e.g. 4.18 vs 4.22), produce a separate `scale-up-analysis-{version}-comparison.md` that includes side-by-side phase tables for each VM type across versions. See `scale-up-analysis-4.18-comparison.md` for the format.
