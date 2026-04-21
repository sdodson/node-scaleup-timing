# Node Scale-Up Timing

This project measures and analyzes OpenShift node scale-up time on Azure and AWS clusters. We create MachineSets with different VM/instance types, time how long it takes from MachineSet creation to NodeReady, and break down each phase of the boot process.

## Repository Structure

```
README.md          — summary of findings and optimization opportunities
CLAUDE.md          — this file (project conventions and workflow)
manifests/         — MachineConfig manifests for optimization testing
reports/           — analysis reports (.md) and text artifacts (.txt)
data/              — raw artifacts (YAML, JSON, logs, SVGs) — gitignored
```

## Workflow

1. **Get a cluster** via cluster-bot (or any Azure/AWS OpenShift cluster). Set `KUBECONFIG` to the kubeconfig file in this directory.
2. **Create a MachineSet** by cloning an existing worker MachineSet, changing `vmSize` (Azure) or `instanceType` (AWS) and the MachineSet name suffix.
3. **Wait for NodeReady** — poll `oc get machines` and `oc get nodes` until the new node is Ready.
4. **Collect artifacts** from the new node using `oc debug node/<name>`. Store in `reports/`.
5. **Produce analysis** — a markdown file in `reports/` breaking down each boot phase with timings.
6. **Delete the test MachineSet** promptly after collecting artifacts (clusters are temporary).

## Key Boot Phases (in order)

1. **Cloud VM Provisioning** — time from MachineSet create to first kernel boot in journal
2. **Boot 1: Ignition** — kernel, initrd, network, Ignition fetch and apply
3. **Boot 1: Pivot to real root** — sysroot transition, systemd init
4. **Boot 1: MCD firstboot** — machine-config-daemon pulls the MCD image, runs rpm-ostree rebase (typically the LARGEST phase)
5. **Reboot** — shutdown + POST + bootloader after MCD firstboot
6. **Boot 2: chrony-wait** — NTP time sync (~24s on Azure with PHC refclock, ~7-20s on AWS with NTP)
7. **Boot 2: CRI-O + Kubelet start** — container runtime and kubelet
8. **Boot 2: Kubelet to NodeReady** — CSR approval, CNI image pulls, node registration

## Artifacts Collected Per Test

Text artifacts (`.txt`) and analysis reports (`.md`) are in `reports/`. Raw data files (`.yaml`, `.json`, `.log`, `.svg`) are in `data/` (gitignored). For each VM type test (e.g. `d4s-v5` or `4.21-m8a`):
- `data/node-journal-{suffix}.log` — full journalctl from the node (all boots)
- `reports/node-boot-list-{suffix}.txt` — `journalctl --list-boots`
- `reports/node-systemd-analyze-{suffix}.txt` — `systemd-analyze` output (boot 2)
- `reports/node-systemd-blame-{suffix}.txt` — `systemd-analyze blame`
- `reports/node-systemd-critical-chain-{suffix}.txt` — `systemd-analyze critical-chain`
- `data/new-machine-{suffix}-final.yaml` — Machine object YAML
- `data/new-node-{suffix}.yaml` — Node object YAML
- `reports/csr-list-{suffix}.txt` — CSR list
- `reports/node-images-{suffix}.txt` — container images on the node
- `data/machineset-{suffix}.json` — MachineSet definition used
- `reports/scale-up-analysis-{suffix}.md` — final analysis report

## Naming Conventions

- Azure VM types: `d4s-v3`, `d4s-v5`, `d4s-v6` (for Standard_D4s_v{3,5,6})
- AWS instance types: `m6a`, `m7a`, `m8a` (for m{6,7,8}a.xlarge)
- OCP version prefix: `4.18-d4s-v3`, `4.21-m8a`
- Tuning experiment suffixes: `m8a-tuned` (chrony+zstd), `m8a-chrony` (chrony only)

## Creating a MachineSet

Clone an existing worker MachineSet and modify:
```bash
# Get the base machineset name
BASE_MS=$(oc get machinesets -n openshift-machine-api -o name | head -1)

# Azure example
oc get $BASE_MS -n openshift-machine-api -o json | jq '
  del(.metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp, .metadata.generation, .status) |
  .metadata.name += "-v6" |
  .spec.selector.matchLabels["machine.openshift.io/cluster-api-machineset"] = .metadata.name |
  .spec.template.metadata.labels["machine.openshift.io/cluster-api-machineset"] = .metadata.name |
  .spec.replicas = 1 |
  .spec.template.spec.providerSpec.value.vmSize = "Standard_D4s_v6"
' > data/machineset-v6.json

# AWS example (use instanceType instead of vmSize)
oc get $BASE_MS -n openshift-machine-api -o json | jq '
  del(.metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp, .metadata.generation, .status) |
  .metadata.name += "-m8a" |
  .spec.selector.matchLabels["machine.openshift.io/cluster-api-machineset"] = .metadata.name |
  .spec.template.metadata.labels["machine.openshift.io/cluster-api-machineset"] = .metadata.name |
  .spec.replicas = 1 |
  .spec.template.spec.providerSpec.value.instanceType = "m8a.xlarge"
' > data/machineset-4.21-m8a.json

oc create -f data/machineset-4.21-m8a.json
```

## Collecting Artifacts from a Node

```bash
NODE=<node-name>
SUFFIX=4.21-m8a

# Journal (all boots) — data/ (gitignored)
oc debug node/$NODE -- chroot /host journalctl --no-pager > data/node-journal-$SUFFIX.log

# Boot list
oc debug node/$NODE -- chroot /host journalctl --list-boots > reports/node-boot-list-$SUFFIX.txt

# systemd-analyze (runs against current boot = boot 2)
oc debug node/$NODE -- chroot /host systemd-analyze > reports/node-systemd-analyze-$SUFFIX.txt
oc debug node/$NODE -- chroot /host systemd-analyze blame > reports/node-systemd-blame-$SUFFIX.txt
oc debug node/$NODE -- chroot /host systemd-analyze critical-chain > reports/node-systemd-critical-chain-$SUFFIX.txt

# Machine and Node objects — data/ (gitignored, may contain secrets)
oc get machine <machine-name> -n openshift-machine-api -o yaml > data/new-machine-$SUFFIX-final.yaml
oc get node $NODE -o yaml > data/new-node-$SUFFIX.yaml

# CSRs
oc get csr > reports/csr-list-$SUFFIX.txt

# Images on node
oc debug node/$NODE -- chroot /host crictl images > reports/node-images-$SUFFIX.txt
```

## Known Bottlenecks

1. **MCD firstboot / rpm-ostree rebase** — 33-47% of total time. The node must pull the machine-os container image and rebase the OS, then reboot. I/O-bound — benefits from faster storage.
2. **Kubelet to NodeReady** — 17-31% of total time. 75-85% of this phase is container image pulls (CNI: multus, OVN-Kubernetes). CSR approval is <2s.
3. **chrony-wait** — ~24s on Azure (PHC refclock), ~7-20s on AWS (NTP). Tunable via chrony config or systemd override (see `manifests/`).

## Kubeconfig

Kubeconfig files are stored in this directory. Clusters from cluster-bot expire after a few hours. Set `KUBECONFIG` before running any `oc` commands:
```bash
export KUBECONFIG=/home/sdodson/node-scaleup-timing/kubeconfig
```
