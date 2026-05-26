# Node Scale-Up Timing

This project measures and analyzes OpenShift node scale-up time on Azure and AWS clusters. We create MachineSets with different VM/instance types, time how long it takes from MachineSet creation to NodeReady, and break down each phase of the boot process.

## Repository Structure

```
README.md          — summary of findings and optimization opportunities
CLAUDE.md          — this file (project conventions and workflow)
manifests/         — MachineConfig manifests for optimization testing
reports/           — final analysis reports only (.md, .html) — committed to git
data/              — ALL raw/collected artifacts (.txt, .yaml, .json, .log) — gitignored
diagrams/          — SVG diagrams referenced by reports — committed to git
```

## Workflow

1. **Get a cluster** via cluster-bot (or any Azure/AWS OpenShift cluster). Set `KUBECONFIG`.
2. **Create test MachineSets** at 0 replicas with names containing `worker-test` (one-time setup).
   Scripts auto-detect MAPI (`openshift-machine-api`) vs CAPI (`openshift-cluster-api`).
3. **Run the study** — scripts scale up, wait for Ready, collect artifacts, and scale back down:
   ```bash
   export KUBECONFIG=kubeconfigs/my-cluster
   export STUDY_NAME=my-study
   scripts/run-study.sh 5 my-study-suffix          # 5 rounds
   scripts/run-round.sh 1 my-study-suffix           # or a single round
   ```
4. **Produce analysis** — a markdown/HTML report in `reports/` breaking down each boot phase.
   Use **p90** (90th percentile) instead of averages for summary statistics. p90 better
   represents the tail latency a user is likely to experience. Run **5 rounds** (n=10
   with 2 zones per round) so p90 cleanly equals the 2nd-highest value.

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

All collected raw data goes in `data/` (gitignored). Only final analysis reports go in `reports/`.
**Never write raw collected data (.txt, .yaml, .json, .log) to `reports/`.**

Artifacts are collected into `data/${STUDY_NAME}/` subdirectories. For each round+zone
(e.g. suffix `5.0-m6a-baseline-r2a`):
- `data/${STUDY_NAME}/node-journal-{suffix}.log` — full journalctl from the node (all boots)
- `data/${STUDY_NAME}/node-boot-list-{suffix}.txt` — `journalctl --list-boots`
- `data/${STUDY_NAME}/node-systemd-analyze-{suffix}.txt` — `systemd-analyze` output (boot 2)
- `data/${STUDY_NAME}/node-systemd-blame-{suffix}.txt` — `systemd-analyze blame`
- `data/${STUDY_NAME}/node-systemd-critical-chain-{suffix}.txt` — `systemd-analyze critical-chain`
- `data/${STUDY_NAME}/new-machine-{suffix}-final.yaml` — Machine object YAML
- `data/${STUDY_NAME}/new-node-{suffix}.yaml` — Node object YAML
- `data/${STUDY_NAME}/csr-list-{suffix}.txt` — CSR list
- `data/${STUDY_NAME}/node-images-detail-{suffix}.json` — container images on the node (crictl JSON)
- `data/${STUDY_NAME}/machineset-{suffix}.json` — MachineSet definition used
- `reports/scale-up-analysis-{suffix}.md` — final analysis report (the only file in reports/)

## Naming Conventions

- Azure VM types: `d4s-v3`, `d4s-v5`, `d4s-v6` (for Standard_D4s_v{3,5,6})
- AWS instance types: `m6a`, `m7a`, `m8a` (for m{6,7,8}a.xlarge)
- OCP version prefix: `4.18-d4s-v3`, `4.21-m8a`
- Tuning experiment suffixes: `m8a-tuned` (chrony+zstd), `m8a-chrony` (chrony only)

## Creating a MachineSet

### Legacy MAPI clusters (pre-4.22, namespace: openshift-machine-api)

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

### CAPI clusters (4.22+, namespace: openshift-cluster-api)

CAPI clusters use `cluster.x-k8s.io/v1beta2` MachineSet + a separate `AWSMachineTemplate`
object. Detect which API you have: if `oc get machinesets -n openshift-machine-api` returns
nothing, check `oc get machinesets -n openshift-cluster-api`.

```bash
# Identify cluster and base objects
CLUSTER=$(oc get machinesets -n openshift-cluster-api -o jsonpath='{.items[0].spec.clusterName}')
BASE_MS=$(oc get machinesets -n openshift-cluster-api -o jsonpath='{.items[0].metadata.name}')
BASE_AWSMT=$(oc get machineset $BASE_MS -n openshift-cluster-api \
  -o jsonpath='{.spec.template.spec.infrastructureRef.name}')

# Names for the test objects (reused across all runs; scale to 0/1 between runs)
NEW_MS=${CLUSTER}-worker-test
NEW_AWSMT=${NEW_MS}-awsmt

# Create AWSMachineTemplate (keeps same instance type as base; change instanceType if desired)
oc get awsmachinetemplate $BASE_AWSMT -n openshift-cluster-api -o json | jq '
  del(.metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp, .metadata.generation, .status) |
  del(.metadata.annotations["cluster.x-k8s.io/paused"]) |
  .metadata.name = "'$NEW_AWSMT'" |
  .metadata.labels["machine.openshift.io/cluster-api-machineset"] = "'$NEW_MS'"
' > data/awsmachinetemplate-test.json

# Create MachineSet
oc get machineset $BASE_MS -n openshift-cluster-api -o json | jq '
  del(.metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp, .metadata.generation, .status) |
  del(.metadata.annotations["cluster.x-k8s.io/paused"]) |
  del(.metadata.finalizers) |
  .metadata.name = "'$NEW_MS'" |
  .metadata.labels["machine.openshift.io/cluster-api-machineset"] = "'$NEW_MS'" |
  .spec.selector.matchLabels["machine.openshift.io/cluster-api-machineset"] = "'$NEW_MS'" |
  .spec.template.metadata.labels["machine.openshift.io/cluster-api-machineset"] = "'$NEW_MS'" |
  .spec.template.spec.infrastructureRef.name = "'$NEW_AWSMT'" |
  .spec.replicas = 1
' > data/machineset-test.json

oc create -f data/awsmachinetemplate-test.json -n openshift-cluster-api
oc create -f data/machineset-test.json -n openshift-cluster-api
```

**Scaling between runs** (instead of delete/recreate):
```bash
# Scale down (deletes the machine)
oc scale machineset $NEW_MS -n openshift-cluster-api --replicas=0

# Wait for deletion (use grep -q not grep -c; grep -c exits 1 on no match which messes up
# the || fallback pattern)
until ! oc get machines -n openshift-cluster-api 2>/dev/null | grep -q "worker-test"; do
  echo "$(date -u +%H:%M:%S) waiting for deletion..."
  sleep 15
done

# Scale back up for next run
oc scale machineset $NEW_MS -n openshift-cluster-api --replicas=1
echo "New run started at $(date -u +%H:%M:%S) UTC"
```

**Finding the node name from the machine** (CAPI):
```bash
oc get machines -n openshift-cluster-api | grep worker-test
NODE=$(oc get machine ${NEW_MS}-<suffix> -n openshift-cluster-api \
  -o jsonpath='{.status.nodeRef.name}')
```

**CAPI artifact collection** — same commands as legacy but use correct machine namespace:
```bash
MACHINE=$(oc get machines -n openshift-cluster-api --no-headers | grep worker-test | awk '{print $1}')
oc get machine $MACHINE -n openshift-cluster-api -o yaml > data/new-machine-$SUFFIX-final.yaml
# AMI/instance info is in the AWSMachine object:
oc get awsmachine $MACHINE -n openshift-cluster-api -o json | jq '{ami: .spec.ami, instanceType: .spec.instanceType}'
```

## Running Studies

All study scripts auto-detect MAPI vs CAPI and discover test MachineSets by name pattern.

### Environment variables

Required:
- `KUBECONFIG` — path to kubeconfig file
- `STUDY_NAME` — study identifier; artifacts go to `data/${STUDY_NAME}/`

Optional (overridable):
- `MACHINESET_PATTERN` — MachineSet name pattern (default: `worker-test`)
- `WAIT_TIMEOUT` — max wait for NodeReady in seconds (default: `900`)
- `POLL_INTERVAL` — seconds between readiness checks (default: `20`)
- `COOLDOWN` — seconds between rounds (default: `30`)
- `MACHINE_NS` — force namespace instead of auto-detecting

### Scripts

All scripts source `scripts/config.env` which provides shared functions:
- `check_kubeconfig` — validates KUBECONFIG is set and exists
- `detect_machine_namespace` — auto-detects MAPI vs CAPI namespace, sets `MACHINE_NS`
- `discover_test_machinesets` — finds MachineSets matching `MACHINESET_PATTERN`, populates `TEST_MACHINESETS` array
- `ms_to_zone_id` — extracts zone suffix from MachineSet name (e.g. `...-1a` → `1a`)

| Script | Purpose |
|--------|---------|
| `scripts/config.env` | Shared configuration, env defaults, and helper functions |
| `scripts/run-study.sh <rounds> <suffix>` | Run N rounds of scale-up/collect/scale-down |
| `scripts/run-round.sh <round> <suffix>` | Run a single round |
| `scripts/collect-artifacts.sh <node> <machine> <suffix>` | Collect all artifacts from a node |
| `scripts/wait-for-ready.sh <machineset>` | Wait for a MachineSet node to be Ready |
| `scripts/extract-timings.sh <suffix>` | Parse boot phase timings from artifacts |
| `scripts/extract-rebase-info.sh <suffix>` | Parse rpm-ostree rebase details |
| `scripts/extract-nodeready-images.sh <suffix>` | Parse CRI-O image pull events |
| `scripts/aggregate-results.sh` | Merge all extracted JSON into summary CSV |

### Example

```bash
export KUBECONFIG=kubeconfigs/aws-5.0
export STUDY_NAME=cni-baseline

# Run 4 rounds (discovers worker-test-* MachineSets automatically)
scripts/run-study.sh 4 5.0-m6a-baseline

# Resume from round 3
scripts/run-study.sh 4 5.0-m6a-baseline --start-round 3

# Custom MachineSet pattern
MACHINESET_PATTERN="worker-bench" scripts/run-study.sh 3 5.0-m6a-bench
```

### Collecting artifacts manually

Use `scripts/collect-artifacts.sh` which writes all output to `data/`:

```bash
STUDY_NAME=my-study scripts/collect-artifacts.sh <node_name> <machine_name> <suffix>
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
