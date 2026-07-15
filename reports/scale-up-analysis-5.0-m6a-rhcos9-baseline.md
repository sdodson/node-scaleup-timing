# Node Scale-Up Analysis: OCP 5.0.0-ec.4 RHCOS9 Baseline (us-east-2)

## Cluster

- **Cluster**: sdods-el10-m4lm6 (OCP 5.0.0-ec.4)
- **Region**: us-east-2 (zones: us-east-2a, us-east-2b)
- **Instance type**: m6a.xlarge (AMD EPYC 3rd Gen, 4 vCPU, 16 GB RAM)
- **OS**: Red Hat Enterprise Linux CoreOS 9.8.20260627-0 (Plow, RHEL 9)
- **Kernel**: 5.14.0-687.19.1.el9_8.x86_64
- **Kubelet**: v1.35.3, CRI-O: 1.36.1
- **Boot image (AMI)**: ami-0f87100a0927b4e1e
- **API**: Legacy MAPI (openshift-machine-api)
- **Rounds**: 5 (n=10 samples: 2 zones × 5 rounds)
- **Date**: 2026-07-14, 16:30–17:12 UTC

### Purpose

RHCOS9 baseline on OCP 5.0.0-ec.4, establishing a control measurement to compare
against an upcoming RHCOS10 experiment on the same cluster. Key question: does RHCOS10
improve or regress node scale-up time relative to RHCOS9 at the same OCP version?

The cluster has the chrony-wait skip MachineConfig active (`10-skip-on-first-join.conf`),
so chrony-wait does not appear in the Boot 2 critical path.

### Test infrastructure

Test MachineSets `sdods-el10-m4lm6-worker-test-us-east-2a` and `...-us-east-2b`
at 0 replicas, cloned from existing worker MachineSets with identical instance type.

---

## Summary: All 10 Runs

| Run      | Zone | VM Prov | Boot 1 | Reboot | Boot2→Ready | Total |
|----------|------|---------|--------|--------|-------------|-------|
| r1 2a    | 2a   | 21s     | 123s   | 17s    | 81s         | 242s  |
| r1 2b    | 2b   | 24s     | 176s   | 18s    | 59s         | **277s** |
| r2 2a    | 2a   | 21s     | 126s   | 11s    | 88s         | 246s  |
| r2 2b    | 2b   | 24s     | 126s   | 17s    | 104s        | 271s  |
| r3 2a    | 2a   | 21s     | 140s   | 17s    | 65s         | 243s  |
| r3 2b    | 2b   | 25s     | 142s   | 18s    | 94s         | **279s** |
| r4 2a    | 2a   | 19s     | 128s   | 11s    | 72s         | 230s  |
| r4 2b    | 2b   | 23s     | 128s   | 11s    | 76s         | 238s  |
| r5 2a    | 2a   | 21s     | 143s   | 17s    | 56s         | 237s  |
| r5 2b    | 2b   | 24s     | 145s   | 19s    | 63s         | 251s  |
| **p90**  |      | **24s** | **145s** | **18s** | **94s**  | **277s** |
| Median   |      | 22s     | 134s   | 17s    | 74s         | 245s  |
| Min      |      | 19s     | 123s   | 11s    | 56s         | 230s  |
| Max      |      | 25s     | 176s   | 19s    | 104s        | 279s  |

**Boot 1** = kernel start through end of MCD firstboot (Ignition, pivot, MCD pull, rpm-ostree rebase, shutdown).
**Reboot** = gap between Boot 1 last journal entry and Boot 2 first kernel entry.
**Boot2→Ready** = Boot 2 kernel to NodeReady condition timestamp.

---

## Phase Detail

### Boot 1: MCD Firstboot

Boot 1 breaks down into three sub-phases:

| Sub-phase | Median | p90 |
|-----------|--------|-----|
| Ignition (pre-rebase) | 16s | 22s |
| MCD rebase (fetch + apply) | 60s | 73s |
| — rebase fetch only | 46s | 52s |
| — rebase apply only | ~14s | ~21s |
| Post-rebase (finalize + shutdown) | 53s | 67s |
| **Boot 1 total** | **134s** | **145s** |

The rebase uses the chunked native container format (`ostree-unverified-registry:`),
same format introduced in RHCOS10 but now present in RHCOS9 5.0. All 10 runs
show identical fetch composition:

- **49 ostree chunks** needed, 16 present in boot image (33 pulled fresh)
- **3 custom layers** (MachineConfig-derived), 200.8 MB total
- **Total fetch**: ~1.4 GB
- **Largest single chunk**: 657 MB (dominant bottleneck)

The 657 MB chunk is pulled first and takes 3–5s of the total fetch time. The
post-rebase shutdown phase (53s median) includes OSTree finalize staged
deployment (~12s), MCD reboot command, and systemd shutdown services.

**Outlier**: r1 2b (176s Boot 1, 91s rebase fetch) reflects slower registry or
EBS response in one instance — likely a one-time EC2 placement effect.

### Boot 2: systemd startup

| | Kernel | Initrd | Userspace | Total |
|--|--------|--------|-----------|-------|
| Median | 1.83s | 2.87s | 15.6s | 20.3s |
| p90 | 1.84s | 2.96s | 21.6s | 26.4s |

Key services from `systemd-analyze blame` (p90):

| Service | p90 |
|---------|-----|
| `ovs-configuration.service` | 5.8s |
| `kubelet.service` | 5.0s |
| `crio.service` | included in kubelet ordering |
| `chrony-wait.service` | **skipped** (MachineConfig drop-in) |

### Boot 2: kubelet → NodeReady

Timeline (r1 2a reference, 81s Boot2→Ready):

```
t+0s   Boot 2 kernel
t+22s  systemd graphical.target reached; kubelet + CRI-O active
t+23s  First CRI-O image pulls begin
t+81s  NodeReady condition set
```

---

## Image Pull Analysis (r1 2a reference run)

### Boot 2 images — 22 images, 9,740 MB

All images are from `quay.io/openshift-release-dev/ocp-v5.0-art-dev`. Timestamps
are relative to Boot 2 kernel (t+0). NodeReady was set at **t+81s**.

All times are from CRI-O journal (`Pulling image` → `Pulled image` events, matched
by request ID). 8 images begin pulling simultaneously at t+23s — CRI-O pulls
are **not serialized globally**; each pod independently requests its images.

#### Blocking images — 14 images, 6,490 MB (all complete before NodeReady at t+81s)

Timings from run r1-2a (CRI-O ISO timestamps, t+0 = Boot 2 kernel). Absolute t+ values
carry ±1s from the boot-list reference; durations are sub-millisecond accurate.

| Size | Start | End | Dur | Image | Pods (namespace/pod/container) |
|-----:|------:|----:|----:|-------|------|
| 258 MB | t+22.566s | t+25.057s | 2.491s | `kube-rbac-proxy` | `openshift-machine-config-operator/kube-rbac-proxy-crio/setup` `openshift-machine-config-operator/kube-rbac-proxy-crio/kube-rbac-proxy-crio` `openshift-machine-config-operator/machine-config-daemon/kube-rbac-proxy` `openshift-monitoring/node-exporter/kube-rbac-proxy` `openshift-ovn-kubernetes/ovnkube-node/kube-rbac-proxy-node` `openshift-ovn-kubernetes/ovnkube-node/kube-rbac-proxy-ovn-metrics` `openshift-multus/network-metrics-daemon/kube-rbac-proxy` `openshift-dns/dns-default/kube-rbac-proxy` `openshift-insights/insights-runtime-extractor/kube-rbac-proxy` |
| 219 MB | t+23.469s | t+26.360s | 2.891s | `prometheus-node-exporter` | `openshift-monitoring/node-exporter/init-textfile` `openshift-monitoring/node-exporter/node-exporter` |
| 319 MB | t+23.457s | t+30.246s | 6.789s | `egress-router-cni` | `openshift-multus/multus-additional-cni-plugins/egress-router-binary-copy` |
| 324 MB | t+23.465s | t+32.814s | 9.349s | `aws-ebs-csi-driver` | `openshift-cluster-csi-drivers/aws-ebs-csi-driver-node/csi-driver` |
| 370 MB | t+23.475s | t+32.864s | 9.390s | `cluster-image-registry-operator` | `openshift-image-registry/node-ca/node-ca` |
| 391 MB | t+23.447s | t+35.794s | 12.347s | `cli` | `openshift-network-operator/iptables-alerter/iptables-alerter` `openshift-dns/node-resolver/dns-node-resolver` |
| 472 MB | t+23.496s | t+39.134s | 15.638s | `cluster-node-tuning-operator` | `openshift-cluster-node-tuning-operator/tuned/tuned` |
| 1,311 MB | t+23.463s | t+49.900s | 26.437s | `ovn-kubernetes` | `openshift-ovn-kubernetes/ovnkube-node/kubecfg-setup` `openshift-ovn-kubernetes/ovnkube-node/ovn-acl-logging` `openshift-ovn-kubernetes/ovnkube-node/northd` `openshift-ovn-kubernetes/ovnkube-node/nbdb` `openshift-ovn-kubernetes/ovnkube-node/sbdb` `openshift-ovn-kubernetes/ovnkube-node/ovn-controller` `openshift-ovn-kubernetes/ovnkube-node/ovnkube-controller` |
| 1,477 MB | t+23.479s | t+55.167s | 31.688s | `multus-cni` | `openshift-multus/multus/kube-multus` `openshift-multus/multus-additional-cni-plugins/kube-multus-additional-cni-plugins` |
| 213 MB | t+33.238s | t+36.002s | 2.763s | `csi-node-driver-registrar` | `openshift-cluster-csi-drivers/aws-ebs-csi-driver-node/csi-node-driver-registrar` |
| 525 MB | t+33.380s | t+46.699s | 13.320s | `container-networking-plugins` | `openshift-multus/multus-additional-cni-plugins/cni-plugins` |
| 213 MB | t+36.278s | t+40.826s | 4.548s | `csi-livenessprobe` | `openshift-cluster-csi-drivers/aws-ebs-csi-driver-node/csi-liveness-probe` |
| 202 MB | t+50.464s | t+52.663s | 2.199s | `network-interface-bond-cni` | `openshift-multus/multus-additional-cni-plugins/bond-cni-plugin` |
| 198 MB | t+53.495s | t+56.998s | 3.503s | `multus-route-override-cni` | `openshift-multus/multus-additional-cni-plugins/routeoverride-cni` |

Last blocking image completes at **t+56s**. The subsequent 25s gap to NodeReady
(t+81s) is CNI plugin initialization and pod network setup — not image pulling.

#### Non-blocking images — 8 images, 3,250 MB (complete after NodeReady)

| Size | Start | End | Dur | Digest |
|-----:|------:|----:|----:|--------|
| 795 MB  | t+75s  | t+86s  | 11s | `sha256:0f1e9b` |
| 293 MB  | t+82s  | t+86s  |  4s | `sha256:92b2a4` |
| 392 MB  | t+82s  | t+87s  |  5s | `sha256:692792` |
| 195 MB  | t+82s  | t+85s  |  3s | `sha256:08d0b6` |
| 258 MB  | t+85s  | t+92s  |  7s | `sha256:feeb2b` |
| 252 MB  | t+87s  | t+88s  |  1s | `sha256:a7bf99` |
| 420 MB  | t+87s  | t+103s | 16s | `sha256:cf12da` |
| 646 MB  | t+131s | t+144s | 13s | `sha256:ebe090` |

The non-blocking images begin pulling in two waves: one at t+75s (still in progress
at NodeReady) and a burst at t+82s (after NodeReady). The 646 MB image at t+131s
is notably late — its pod is scheduled much later than the rest.

The 22 images total 9.74 GB (cumulative pull time 213s pulled concurrently).
Actual wall-clock pull span: t+22s to t+144s (122s total), with NodeReady at t+81s.

Image count and total size increased compared to 5.0 nightly baselines (~8.4 GB
in baseline-2). This reflects additional components or larger images in ec.4.

---

## Comparison: 5.0.0-ec.4 vs prior baselines

| Phase | 5.0-baseline-1 p90 (east, nightly) | 5.0-baseline-2 p90 (west, nightly) | **5.0-ec.4 p90 (east-2, RHCOS9)** |
|-------|-----|-----|-----|
| VM provisioning | 30s | 27s | **24s** |
| Boot 1 (MCD firstboot) | 124s | 140s | **145s** |
| Reboot | 19s | 18s | **18s** |
| Boot2→Ready | 81s | 78s | **94s** |
| **Total** | **234s** | **253s** | **277s** |

The 24s increase over baseline-2 is driven mostly by Boot2→Ready (+16s),
consistent with the 9.74 GB image set being larger than the ~8.4 GB seen
in nightly builds — more content shipped in ec.4.

Boot 1 is similar to baseline-2 (5s higher p90), within noise for regional
registry performance differences.

---

## Key Observations

### 1. chrony-wait eliminated from boot path
The cluster MachineConfig writes a `10-skip-on-first-join.conf` drop-in via
Ignition, skipping chrony-wait in Boot 2. No NTP wait overhead is present.

### 2. Chunked ostree format in RHCOS9 5.0
RHCOS9 on OCP 5.0 uses the same chunked native container rebase format
that debuted in RHCOS10 on 4.22. The single largest chunk (657 MB) is the
dominant fetch bottleneck, pulling 3–5s. Total 1.4 GB fetched per node.

### 3. Post-rebase shutdown is the hidden Boot 1 cost
After the rebase completes, OSTree finalize + systemd shutdown adds 53s
median (67s p90) before Boot 2 begins. This is the largest single
opportunity for improvement within Boot 1 after the rebase itself.

### 4. Boot2→Ready variance is high
ktr ranges from 56s to 104s (48s spread), reflecting concurrent image
pull timing from Quay. The two largest images (1477 MB + 1311 MB) gate
NodeReady and their pull time is sensitive to registry and network conditions.

### 5. RHCOS10 result: 44s faster p90, 43s faster median

The RHCOS10 experiment (see `scale-up-analysis-5.0-m6a-rhcos10-baseline.md`)
on the same cluster (n=20) showed:

| Phase | RHCOS9 p90 | RHCOS10 p90 | Delta |
|-------|-----------|------------|-------|
| VM provisioning | 24s | 24s | 0s |
| Boot 1 | 145s | **134s** | **−11s** |
| Reboot | 18s | 18s | 0s |
| Boot2→Ready | **94s** | **60s** | **−34s** |
| **Total** | **277s** | **233s** | **−44s** |

The primary driver is Boot2→Ready (−34s): RHCOS10 systemd userspace startup is
10.3s vs 21.3s p90 (−11s, with tight 9.5–10.7s variance vs RHCOS9's 8.8–22.2s),
and CNI initialization after image pulls is ~14s vs ~25s (−11s). Boot1 improves
11s p90 (27s median), mostly from post-rebase shutdown dropping from ~23s to 9.5s.

---

## Artifacts

All raw data in `data/5.0-m6a-rhcos9-baseline/`:

| Pattern | Description |
|---------|-------------|
| `node-journal-*-r{1..5}-{2a,2b}.log` | Full journalctl (all boots) |
| `node-boot-list-*-r{1..5}-{2a,2b}.txt` | journalctl --list-boots |
| `node-systemd-analyze-*-r{1..5}-{2a,2b}.txt` | systemd-analyze |
| `node-systemd-blame-*-r{1..5}-{2a,2b}.txt` | systemd-analyze blame |
| `node-systemd-critical-chain-*-r{1..5}-{2a,2b}.txt` | systemd-analyze critical-chain |
| `new-machine-*-r{1..5}-{2a,2b}-final.yaml` | Machine object YAML |
| `new-node-*-r{1..5}-{2a,2b}.yaml` | Node object YAML |
| `node-images-detail-*-r{1..5}-{2a,2b}.json` | crictl images JSON |
| `csr-list-*-r{1..5}.txt` | CSR list (one per round) |
| `timings-*-r{1..5}-{2a,2b}.json` | Extracted timing data |
| `rebase-info-*-r{1..5}-{2a,2b}.json` | rpm-ostree rebase details |
| `nodeready-images-*-r{1..5}-{2a,2b}.json` | Boot 2 image pull events |
| `summary.csv` | Aggregated metrics for all 10 runs |
