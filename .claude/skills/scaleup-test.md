---
name: scaleup-test
description: Run a node scale-up timing test for a given instance type on the current cluster
user_invocable: true
---

# Node Scale-Up Timing Test

Run a complete node scale-up timing test for a specified instance type (Azure VM type or AWS instance type).

## Usage

The user will provide an instance type (e.g. `Standard_D4s_v6` for Azure, `m6i.xlarge` for AWS) and optionally a suffix label (e.g. `d4s-v6`, `m6i-xl`). If no suffix is given, derive one from the instance type name.

## Steps

### 1. Verify cluster access

```bash
oc get clusterversion
oc get machinesets -n openshift-machine-api
```

Confirm the cluster is reachable and identify the base worker MachineSet to clone from. Note the cluster infrastructure ID from the MachineSet names.

### 2. Create a new MachineSet

Clone the first worker MachineSet, modifying:
- `.metadata.name` — append the VM generation suffix (e.g. `-v6`)
- `.spec.selector.matchLabels["machine.openshift.io/cluster-api-machineset"]` — match new name
- `.spec.template.metadata.labels["machine.openshift.io/cluster-api-machineset"]` — match new name
- `.spec.template.spec.providerSpec.value.vmSize` (Azure) or `.spec.template.spec.providerSpec.value.instanceType` (AWS) — set to the requested instance type
- `.spec.replicas` — set to 1
- Remove `.metadata.uid`, `.metadata.resourceVersion`, `.metadata.creationTimestamp`, `.metadata.generation`, `.status`

Save the MachineSet JSON as `machineset-{suffix}.json` and create it.

Record the exact time of creation (UTC) — this is the start of the scale-up timer.

### 3. Wait for Machine provisioning and NodeReady

Poll every 15 seconds:
```bash
oc get machines -n openshift-machine-api -l machine.openshift.io/cluster-api-machineset=<machineset-name>
```

Once the Machine has a node ref, poll the node:
```bash
oc get node <node-name> -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
```

Record the time when the node transitions to Ready.

### 4. Collect artifacts

Once the node is Ready, wait 2 minutes for DaemonSet pods to settle, then collect all artifacts. Use `oc debug node/<name> -- chroot /host <command>` for node-level commands.

Collect these artifacts (see CLAUDE.md for the full list):
- Journal log (all boots)
- Boot list
- systemd-analyze, blame, critical-chain
- Machine YAML, Node YAML
- CSR list
- Container images on node
- MachineSet JSON (already saved)

### 5. Analyze boot phases

Parse the journal log to identify timestamps for each boot phase:

1. **Cloud VM Provisioning**: MachineSet creation time → first journal entry (boot -1)
2. **Boot 1 Ignition**: first journal entry → end of Ignition stages
3. **Boot 1 pivot**: sysroot transition
4. **Boot 1 MCD firstboot**: MCD image pull, rpm-ostree rebase start/end, total MCD phase
5. **Reboot**: last entry boot -1 → first entry boot 0
6. **Boot 2 chrony-wait**: from systemd-analyze critical-chain
7. **Boot 2 CRI-O + Kubelet**: from journal
8. **Boot 2 Kubelet to NodeReady**: kubelet start → NodeReady condition

### 6. Produce the analysis report

Write `scale-up-analysis-{suffix}.md` with:
- Cluster details (version, region, VM type)
- Total scale-up time
- Phase breakdown table (phase, start, end, duration, notes)
- Time spent summary table (category, duration, % of total)
- MCD firstboot detail (image pull time, rpm-ostree rebase time)
- Boot list
- systemd-analyze output
- systemd-analyze critical-chain
- Key observations
- Comparison table if other VM type results exist in the directory
- List of saved artifacts

Use the existing `scale-up-analysis-*.md` files in this directory as the template for format and structure.
