# OpenShift Node Scale-Up Timing

Measuring and analyzing how long it takes for a new worker node to go from MachineSet creation to `NodeReady` in OpenShift clusters, broken down by boot phase.

> **Note:** All results so far are from **OCP Standalone (Self-Managed)** clusters. ROSA (AWS) and ARO HCP (Azure) testing is planned — those platforms have different node bootstrapping paths and may show significantly different timing profiles.

## Why

Node scale-up time directly impacts cluster autoscaler responsiveness and workload scheduling latency. Understanding where time is spent — cloud provisioning, OS bootstrapping, container image pulls, NTP sync — identifies which optimizations actually matter.

## Test Matrix

### OCP Standalone — Azure

| VM Type | OCP 4.18 | OCP 4.22 |
|---------|----------|----------|
| Standard_D4s_v3 (4 vCPU, 16 GB) | 7m 54s | 7m 03s |
| Standard_D4s_v5 (4 vCPU, 16 GB) | 5m 23s | 4m 43s |
| Standard_D4s_v6 (4 vCPU, 16 GB) | 4m 20s | 3m 59s |

### OCP Standalone — AWS (OCP 4.21, us-west-2)

| Instance Type | CPU Gen | Baseline | With chrony tuning |
|--------------|---------|----------|--------------------|
| m6a.xlarge (4 vCPU, 16 GB) | AMD EPYC 3rd Gen | 4m 26s | — |
| m7a.xlarge (4 vCPU, 16 GB) | AMD EPYC 4th Gen | 4m 19s | — |
| m8a.xlarge (4 vCPU, 16 GB) | AMD EPYC 5th Gen | 3m 32s | 3m 38s* |

\* chrony-wait showed high variance across runs (7s, 13s, 20s) — see [Chrony Tuning Experiments](#chrony-tuning-experiments) below.

## Key Findings

### VM generation is the dominant factor

On Azure, moving from v3 to v6 saves **~3m 18s on average (44%)** regardless of OCP version. On AWS, m8a is **20% faster** than m6a (3m32s vs 4m26s). The improvement comes from faster NVMe storage (dramatically speeds up rpm-ostree rebase) and faster CPU/POST times.

### Where the time goes (best case: AWS m8a, ~3.5 minutes)

| Phase | Duration | % |
|-------|----------|---|
| MCD firstboot (rpm-ostree rebase) | 1m 10s | 33% |
| Kubelet to NodeReady (CSR + CNI) | 35s | 17% |
| chrony-wait (NTP sync) | 7-20s | 3-9% |
| Everything else (VM provision, Ignition, boot, reboot) | 1m 34s-1m 54s | 41-47% |

### The two biggest bottlenecks

1. **MCD firstboot / rpm-ostree rebase (33-47% of total)** — The node pulls a container image and rebases the OS via rpm-ostree, then reboots. This is I/O-bound and benefits significantly from faster storage (v6 does it in 50s vs 120s on v3).

2. **Kubelet to NodeReady (17-31% of total)** — After kubelet starts, the node waits for CSR approval and CNI readiness. CSR approval itself is nearly instant (<2s). **75-85% of this phase is spent pulling container images** — the CNI images (multus-cni ~1.4 GB, ovn-kubernetes ~1.4 GB) plus pod infrastructure images must be pulled before the node can become Ready. Pre-pulling these images would be the highest-impact optimization for this phase.

### AWS is faster than Azure for comparable hardware

AWS m8a.xlarge (3m 32s) beats Azure D4s_v6 (3m 59s) by 27 seconds:
- MCD firstboot: 1m10s vs 2m09s (faster network to registries)
- chrony-wait: 7-20s vs 24s (NTP vs PHC refclock)
- Kubelet-to-NodeReady: 35s vs 62s (faster container image pulls)
- Azure wins only on reboot time (11s vs 32s)

### chrony-wait: platform-dependent

- **Azure**: ~24s fixed cost. PHC refclock (`/dev/ptp_hyperv`) with `poll 3` needs ~3 polling intervals (3 x 8s).
- **AWS**: 7-20s variable. Standard NTP to 169.254.169.123 (AWS Time Sync Service). Shows more variance than Azure — depends on initial clock drift and NTP source selection timing.

### OCP version matters less than hardware

OCP 4.22 is 21-51s faster overall than 4.18 on Azure, but most of that difference comes from regional VM provisioning time differences (eastus2 vs westus), not OCP improvements.

### rpm-ostree is faster on 4.18 than 4.22

rpm-ostree rebase is faster on 4.18 (32-64s) than 4.22 (50-120s) across all Azure VM types. Likely due to a larger OS image delta in 4.22 or a larger target image.

## Chrony Tuning Experiments

We tested a MachineConfig that short-circuits `chrony-wait.service` on Boot 2 when a drift file from a recent sync exists (see `manifests/machineconfig-chrony-wait-skip-reboot.yaml`). Results on AWS m8a.xlarge:

| Run | chrony-wait | MCD firstboot | Total |
|-----|-------------|---------------|-------|
| Baseline (no tuning) | 13.1s | 1m 10s | 3m 32s |
| chrony tuning + zstd osImageURL | 7.0s | 1m 28s (different image) | 3m 38s |
| chrony tuning only | 20.1s | 1m 20s | 3m 42s |

chrony-wait showed high variance (7s, 13s, 20s) across all three runs. On AWS, the `waitsync` condition depends on initial clock drift magnitude, which varies per boot. The short-circuit config may not reliably fire on new nodes where the drift file doesn't exist yet from a prior boot.

We also tested rebasing to a zstd-compressed OS image (`quay.io/sdodsonrht/4.21.11:zstd`). The rebase was 18s slower than the standard release image, likely due to the image being served from a personal registry rather than the CDN-backed release registry. A fair zstd comparison would require serving from the same infrastructure.

## Repository Structure

```
README.md                  — this file
CLAUDE.md                  — project conventions and workflow
manifests/                 — MachineConfig manifests for optimization testing
reports/                   — all collected data, analysis, and comparison reports
```

### manifests/

Durable MachineConfig manifests for node bootstrapping optimizations:

- `machineconfig-chrony-wait-skip-reboot.yaml` — skip chrony-wait on Boot 2 when clock was recently synced
- `99-worker-osimageurl.yaml` — template for testing custom OS images (e.g. zstd-compressed)
- `99-worker-rhel-10.1.yaml` — RHEL 10.1 based node image config
- `99-worker-custom.yaml` — minimal test MachineConfig

### reports/

All collected data and analysis, organized by naming convention:

**Analysis reports** (`scale-up-analysis-*.md`):
- Per-VM-type: `scale-up-analysis-d4s-v3.md`, `-d4s-v5.md`, `-d4s-v6.md` (Azure 4.22)
- Per-instance-type: `scale-up-analysis-4.21-m6a.md`, `-m7a.md`, `-m8a.md` (AWS 4.21)
- Comparisons: `scale-up-analysis-4.18-comparison.md`, `scale-up-analysis-4.21-aws-comparison.md`

**Per-node artifacts** (suffixed by VM type, e.g. `-d4s-v5`, `-4.21-m8a`, `-4.21-m8a-tuned`):
- `node-journal-*.log` — full journalctl (all boots)
- `node-boot-list-*.txt` — `journalctl --list-boots`
- `node-systemd-analyze-*.txt` — `systemd-analyze` (boot 2 timing)
- `node-systemd-blame-*.txt` — `systemd-analyze blame`
- `node-systemd-critical-chain-*.txt` — `systemd-analyze critical-chain`
- `node-images-*.txt` — container images on node (`crictl images`)
- `new-machine-*-final.yaml` — Machine object YAML
- `new-node-*.yaml` — Node object YAML
- `csr-list-*.txt` — CSR list at time of collection
- `machineset-*.json` — MachineSet definition used

**Additional Azure 4.18 artifacts**: chrony config files (`chrony-*.txt`), machine API events

## Optimization Opportunities

| Optimization | Estimated Savings | Difficulty |
|-------------|-------------------|------------|
| Pre-pull CNI images (multus, OVN-K) into base AMI/image | 20-30s | Medium — custom image build |
| Use newer VM generation (v3→v6 Azure, m6a→m8a AWS) | 1-3m | Easy — change MachineSet instanceType/vmSize |
| Use AWS instead of Azure (comparable instance types) | ~27s | Easy — platform choice |
| Tune chrony (`poll 2`, `minsamples 1`) on Azure | 12-20s | Medium — MachineConfig change |
| Short-circuit chrony-wait on Boot 2 | 7-24s | Medium — MachineConfig (see manifests/) |
| Pre-cache machine-os image in base OS | 50-120s | Hard — custom RHCOS image build |
| Use zstd-compressed OS images | TBD | Medium — needs same-registry comparison |

## Planned Testing

- **ROSA (Red Hat OpenShift on AWS)** — managed control plane, potentially different node bootstrap path
- **ARO HCP (Azure Red Hat OpenShift, Hosted Control Planes)** — HyperShift-based, nodes join a hosted control plane rather than running local API servers
