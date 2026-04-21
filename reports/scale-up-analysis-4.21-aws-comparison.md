# Node Scale-Up Comparison: AWS m6a vs m7a vs m8a (OCP 4.21)

## Cluster Details

| | Value |
|--|-------|
| **OCP Version** | 4.21.11 |
| **Kubernetes** | (4.21-based) |
| **Platform** | AWS |
| **Region** | us-west-2 (us-west-2a) |
| **CRI-O** | 1.34.6-2.rhaos4.21 |
| **Cluster** | ci-ln-0mi9cpt-76ef8-8g76q |
| **Test Date** | 2026-04-18 |

## Total Scale-Up Times

| Instance Type | CPU Gen | Total Time |
|--------------|---------|------------|
| **m6a.xlarge** | AMD EPYC 3rd Gen | **4m 26sec** |
| **m7a.xlarge** | AMD EPYC 4th Gen | **4m 19sec** |
| **m8a.xlarge** | AMD EPYC 5th Gen | **3m 32sec** |

## Detailed Phase Comparison

| Phase | m6a.xlarge | m7a.xlarge | m8a.xlarge |
|-------|-----------|-----------|-----------|
| AWS Instance Provisioning | 23s | 25s | 20s |
| Boot 1: Ignition (all stages) | 11s | 10s | 10s |
| Boot 1: Pivot to real root | 26s | 26s | 24s |
| Boot 1: MCD pull + rpm-ostree | **1m 33sec** | **1m 29sec** | **1m 10sec** |
| Reboot (shutdown + POST) | 35s | 39s | 32s |
| Boot 2: Kernel + initrd | 7s | 7s | 5s |
| Boot 2: chrony-wait | 14s | 13s | 13s |
| Boot 2: CRI-O + Kubelet | 2s | 2s | 3s |
| Boot 2: Kubelet -> NodeReady | **55s** | **48s** | **35s** |
| **Total** | **266s** | **259s** | **212s** |

## systemd-analyze (Boot 2)

| Metric | m6a | m7a | m8a |
|--------|-----|-----|-----|
| Kernel | 1.744s | 4.409s | 2.407s |
| initrd | 3.445s | 3.641s | 2.402s |
| Userspace | 20.407s | 18.839s | 17.922s |
| **Total** | **25.598s** | **26.891s** | **22.732s** |

## Key Observations

### 1. m8a is 20% faster than m6a overall

Moving from m6a to m8a saves 54 seconds (4m 26sec -> 3m 32sec). The improvement comes from:
- MCD firstboot: 23s faster (1m 33sec -> 1m 10sec) — faster NVMe I/O for rpm-ostree rebase
- Kubelet to NodeReady: 20s faster (55s -> 35s) — faster container image pulls and pod startup
- Boot 2 kernel/initrd: 2s faster (7s -> 5s) — faster CPU initialization
- Reboot: 3s faster (35s -> 32s) — faster shutdown/POST

### 2. MCD firstboot remains the largest bottleneck (33-35% of total)

Across all three instance types, the MCD pull + rpm-ostree rebase phase consumes the most time. All three pulled the same rebase target (`sha256:5f140840...`) and upgraded the kernel from 5.14.0-570.74.1 to 5.14.0-570.107.1. The difference is pure I/O throughput.

### 3. Kubelet to NodeReady is the second largest phase (17-21%)

This phase covers CSR approval, CNI pod startup (multus, OVN-Kubernetes), and container image pulls. CSR approval itself is nearly instant (<2s on all three), so the time is dominated by pod scheduling and image pulls.

### 4. chrony-wait is consistent at ~13s on AWS

Unlike Azure where chrony-wait is ~24s (due to PHC refclock `/dev/ptp_hyperv` needing 3 polling intervals at `poll 3`), AWS uses standard NTP to the AWS Time Sync Service at 169.254.169.123. The ~13s is from initial source selection and synchronization, about 10s less than Azure.

### 5. AWS provisioning time is fast and consistent (20-25s)

All three instance types launched in 20-25s, with no significant generation-dependent variance. This is comparable to the best Azure provisioning times (18-19s for D4s_v5/v6 in eastus2).

### 6. Ignition and pivot times are hardware-independent

The Ignition phase (~10-11s) and pivot to real root (~24-26s) are essentially the same across all three types. These phases are network and OS initialization, not I/O intensive.

## AWS vs Azure Comparison

| Phase | AWS m8a (best) | Azure D4s_v6 (best, 4.22) | Notes |
|-------|---------------|--------------------------|-------|
| VM Provisioning | 20s | 18s | Similar |
| Ignition + Pivot | 34s | 15s | AWS pivot is slower |
| MCD firstboot | 1m 10sec | 2m 09sec | **AWS is 59s faster** |
| Reboot | 32s | 11s | Azure is faster |
| chrony-wait | 13s | 24s | **AWS is 11s faster** |
| Boot 2 systemd total | 22.7s | 31.7s | AWS is faster |
| Kubelet -> NodeReady | 35s | 62s | **AWS is 27s faster** |
| **Total** | **3m 32sec** | **3m 59sec** | **AWS is 27s faster** |

Key differences:
- **AWS MCD firstboot is much faster** — likely faster network throughput to container registries from us-west-2
- **AWS chrony-wait is 11s faster** — standard NTP vs PHC refclock polling
- **Azure reboots faster** — 11s vs 32s, likely due to hypervisor differences
- **AWS Kubelet->NodeReady is faster** — faster container image pulls

## Saved Artifacts
- Per-type analysis: `scale-up-analysis-4.21-m6a.md`, `scale-up-analysis-4.21-m7a.md`, `scale-up-analysis-4.21-m8a.md`
- Journals: `node-journal-4.21-m6a.log`, `node-journal-4.21-m7a.log`, `node-journal-4.21-m8a.log`
- Boot lists: `node-boot-list-4.21-*.txt`
- systemd analysis: `node-systemd-analyze-4.21-*.txt`, `node-systemd-blame-4.21-*.txt`, `node-systemd-critical-chain-4.21-*.txt`
- Machine/Node objects: `new-machine-4.21-*-final.yaml`, `new-node-4.21-*.yaml`
- CSR lists: `csr-list-4.21-*.txt`
- Container images: `node-images-4.21-*.txt`
- MachineSet definitions: `machineset-4.21-m6a.json`, `machineset-4.21-m7a.json`, `machineset-4.21-m8a.json`
