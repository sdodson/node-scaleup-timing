---
name: collect-node-artifacts
description: Collect boot timing artifacts from an OpenShift node for scale-up analysis
user_invocable: true
---

# Collect Node Artifacts

Collect all boot timing and system artifacts from a specified OpenShift node. This is used after a scale-up test when the node is Ready.

## Usage

The user provides:
- A node name (e.g. `ci-ln-rm0x8pk-1d09d-vkpbd-worker-eastus21-v6-8hct8`)
- A suffix label for filenames (e.g. `d4s-v6` or `4.18-d4s-v6`)

## Artifacts to Collect

Run each command via `oc debug node/<name> -- chroot /host <command>` and save to the corresponding file:

| Command | Output File |
|---------|-------------|
| `journalctl --no-pager` | `node-journal-{suffix}.log` |
| `journalctl --list-boots` | `node-boot-list-{suffix}.txt` |
| `systemd-analyze` | `node-systemd-analyze-{suffix}.txt` |
| `systemd-analyze blame` | `node-systemd-blame-{suffix}.txt` |
| `systemd-analyze critical-chain` | `node-systemd-critical-chain-{suffix}.txt` |
| `crictl images` | `node-images-{suffix}.txt` |
| `rpm-ostree status` | `node-rpm-ostree-status-{suffix}.txt` |

Also collect from the API server:
| Command | Output File |
|---------|-------------|
| `oc get machine <machine> -n openshift-machine-api -o yaml` | `new-machine-{suffix}-final.yaml` |
| `oc get node <node> -o yaml` | `new-node-{suffix}.yaml` |
| `oc get csr` | `csr-list-{suffix}.txt` |

Identify the machine name from:
```bash
oc get machines -n openshift-machine-api -o json | jq -r '.items[] | select(.status.nodeRef.name == "<node-name>") | .metadata.name'
```

## Notes

- The `oc debug` commands each spawn a debug pod. They take ~10-15 seconds each. Run them sequentially (parallel debug pods may conflict).
- The journal log can be large (10K+ lines). This is expected.
- `systemd-analyze` commands report on the current boot (boot 2 / boot 0), which is what we want.
- If the user also wants detailed image info, collect `crictl images -o json` → `node-images-detail-{suffix}.json`.
