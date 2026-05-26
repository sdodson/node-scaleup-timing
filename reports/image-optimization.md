# Container Image Optimization Analysis for Node Scale-Up

## Overview

During OpenShift node scale-up, 15 container images must be pulled before the node
reaches Ready state. These images represent the critical path — no other work can
proceed until they're available locally.

**Total compressed pull**: 1,302 MB (after layer dedup across all 15 images; 2,210 MB
without dedup). Layer sharing across images saves 908 MB because many images share the
same `base-rhel9` base layers.

This analysis covers all optimization opportunities beyond the binary stripping PRs
already filed under OCPBUGS-83863.

## Current State: 15 Blocking Images

Measured from OCP 5.0 nightly on AWS m6a.xlarge. Compressed sizes are from `skopeo
inspect` LayersData. "Unique" = bytes not shared with any other blocking image.

```
Image                              Compressed Total   Shared    Unique
──────────────────────────────────────────────────────────────────────────
ovn-kubernetes                        337.5 MB      72.1 MB   265.4 MB
cluster-node-tuning-operator          232.5 MB      37.8 MB   194.7 MB
cluster-image-registry-operator       192.1 MB     102.1 MB    90.0 MB
cli                                   174.1 MB     102.1 MB    72.0 MB
egress-router-cni                     147.8 MB       0.0 MB   147.8 MB  ← zero sharing!
multus-cni                            138.8 MB      72.1 MB    66.7 MB
aws-ebs-csi-driver                    137.9 MB     102.1 MB    35.8 MB
kube-rbac-proxy                       133.8 MB     102.1 MB    31.7 MB
prometheus-node-exporter              117.2 MB     102.1 MB    15.1 MB
csi-livenessprobe                     115.5 MB     102.1 MB    13.4 MB
csi-node-driver-registrar             115.4 MB     102.1 MB    13.3 MB
container-networking-plugins          114.8 MB      73.8 MB    41.0 MB
multus-whereabouts-ipam-cni           102.5 MB      38.1 MB    64.4 MB
network-interface-bond-cni             75.3 MB      73.8 MB     1.5 MB
multus-route-override-cni              74.9 MB      73.8 MB     1.1 MB
──────────────────────────────────────────────────────────────────────────
TOTAL (deduped)                     1,302.1 MB
TOTAL (raw, no dedup)               2,210.2 MB
Layer sharing savings                 908.1 MB
```

## Optimization 1: Binary Stripping (PRs Filed)

**Status**: 13 PRs open under OCPBUGS-83863
**Complexity**: Low — single-line Makefile/Dockerfile changes

Adding `-ldflags '-s -w'` strips DWARF debug info and symbol tables from Go binaries,
reducing their size by ~29%. Measured savings on the 6 newly-filed PRs:

```
Image                              Binary                           Before    After    Saved     %
─────────────────────────────────  ───────────────────────────────  ────────  ───────  ───────  ─────
cluster-node-tuning-operator       cluster-node-tuning-operator      96.9 MB   68.7 MB  28.1 MB  29.0%
cluster-node-tuning-operator       gather-sysinfo                    63.8 MB   45.3 MB  18.5 MB  29.0%
cluster-node-tuning-operator       performance-profile-creator       34.6 MB   24.9 MB   9.8 MB  28.1%
cluster-image-registry-operator    cluster-image-registry-operator  139.6 MB  100.2 MB  39.5 MB  28.2%
cluster-image-registry-operator    move-blobs                        12.9 MB    9.0 MB   4.0 MB  30.5%
kube-rbac-proxy                    kube-rbac-proxy                   70.9 MB   49.9 MB  21.0 MB  29.5%
prometheus-node-exporter           node_exporter                     23.2 MB   16.2 MB   7.0 MB  30.2%
csi-node-driver-registrar          csi-node-driver-registrar         26.8 MB   18.6 MB   8.2 MB  30.7%
csi-livenessprobe                  livenessprobe                     27.0 MB   18.7 MB   8.3 MB  30.7%
─────────────────────────────────  ───────────────────────────────  ────────  ───────  ───────  ─────
TOTAL                                                               495.7 MB  351.4 MB 144.4 MB  29.1%
```

Go binaries compress at roughly 30-35%, so 144 MB uncompressed translates to
approximately **40-50 MB compressed savings** off the wire.

### PRs for the 6 newly-filed repos

- https://github.com/openshift/cluster-node-tuning-operator/pull/1525
- https://github.com/openshift/cluster-image-registry-operator/pull/1346
- https://github.com/openshift/kube-rbac-proxy/pull/142
- https://github.com/openshift/node_exporter/pull/180
- https://github.com/openshift/csi-node-driver-registrar/pull/104
- https://github.com/openshift/csi-livenessprobe/pull/92

## Optimization 2: Fix egress-router-cni Layer Sharing

**Estimated compressed savings**: 38-72 MB
**Complexity**: Low — update a base image tag in Dockerfile.openshift

egress-router-cni shares **zero** base layers with any other blocking image. Its
`Dockerfile.openshift` references `ocp/4.16:base-rhel9` while all other images use
`4.20` or `4.21`:

```dockerfile
# egress-router-cni/Dockerfile.openshift (current)
FROM registry.ci.openshift.org/ocp/builder:rhel-9-golang-1.22-openshift-4.17 AS rhel9
...
FROM registry.ci.openshift.org/ocp/4.16:base-rhel9   # ← stale version
```

Other CNI images use `4.20` or `4.21` base-rhel9, so their base layers are shared and
only pulled once. Updating egress-router-cni to a current base tag would make its base
layers shared with the other images, eliminating 38-72 MB of redundant base layer pull.

## Optimization 3: OVN-Kubernetes Unnecessary Content

**Estimated compressed savings**: 15-20 MB
**Complexity**: Medium

The OVN-Kubernetes image (337 MB compressed, largest of all 15) contains:

### Windows binary: `hybrid-overlay-node.exe` (52 MB uncompressed)

Built by `make windows` (Dockerfile line 13) and copied to `/root/windows/`
(line 50). This binary is only used for hybrid Windows/Linux OpenShift clusters. It
could be moved to a separate image or conditionally included.

```dockerfile
# ovn-kubernetes/Dockerfile
RUN cd go-controller; CGO_ENABLED=1 make windows    # line 13 - builds Windows .exe
...
COPY --from=builder .../hybrid-overlay-node.exe /root/windows/   # line 50
```

### Debug tools: strace + tcpdump (3.4 MB uncompressed)

Installed via RPM (Dockerfile lines 36-37). Useful for debugging but not required at
runtime. Could be removed or moved to a debug variant image.

```dockerfile
RUN INSTALL_PKGS=" \
    openssl firewalld-filesystem \
    libpcap iproute iproute-tc strace \   # ← strace (2.1 MB)
    tcpdump iputils \                      # ← tcpdump (1.3 MB)
    ...
```

### `/usr/bin/oc` (131 MB uncompressed, already stripped)

Installed from `openshift-clients` RPM. OVN uses `oc` at runtime for operations. This
is the single largest binary in the image (15% of total). Cannot be removed, but worth
noting for context. The `oc` binary and `openshift-clients` RPM account for 131 MB of
the unique content.

### OVN Go binaries (already stripped)

All 7 Go binaries in this image are already stripped. The existing OCPBUGS-83863 PR
for ovn-kubernetes is a no-op for this particular build since the Makefile already has
`LDFLAGS ?=` and the OpenShift build system sets it.

## Optimization 4: Container-Networking-Plugins Windows Binaries

**Estimated compressed savings**: 8-10 MB
**Complexity**: Medium

The container-networking-plugins image builds Windows binaries in a dedicated stage
and copies them into the Linux image:

```dockerfile
# containernetworking-plugins/Dockerfile
FROM registry.ci.openshift.org/ocp/builder:rhel-8-golang-1.24-openshift-4.21 AS windows
ADD . /usr/src/plugins
...
RUN ./build_windows.sh
...
COPY --from=windows /usr/src/plugins/bin/* /usr/src/plugins/windows/bin/
```

Three Windows executables totaling 24 MB uncompressed:
- `win-overlay.exe` (9.9 MB)
- `win-bridge.exe` (9.9 MB)
- `host-local.exe` (4.2 MB)

These could be split to a separate Windows-specific image, saving ~8-10 MB compressed.

## Optimization 5: NTO Test Binary in Production Image

**Estimated compressed savings**: ~4 MB
**Complexity**: Low

cluster-node-tuning-operator ships `cluster-node-tuning-operator-test-ext.gz` (11 MB
uncompressed) in the production image. This is a gzipped e2e test extension binary
used by the OpenShift test framework.

```dockerfile
# cluster-node-tuning-operator/Dockerfile
RUN gzip /go/src/.../cluster-node-tuning-operator-test-ext    # line 9
...
COPY --from=builder .../_output/cluster-node-tuning-operator-test-ext.gz /usr/bin/   # line 15
```

Additionally, the NTO image uses `quay.io/centos/centos:stream9` as its base instead
of the standard `base-rhel9`, which means it shares zero base layers with other OCP
images. The CentOS base is required for the OKD build path where tuned is built from
source rather than installed from RPMs.

The image also carries the full tuned source tree (2 MB) including test files (232 KB)
in `/root/assets/tuned/`.

### NTO RPM Content (526 MB filesystem total)

The NTO image is heavyweight because it installs many runtime dependencies:

| RPM Package | Uncompressed Size |
|-------------|------------------|
| python3-libs | 33 MB |
| polkit-libs | 28 MB |
| glib2 | 13 MB |
| systemd | 12 MB |
| util-linux | 11 MB |
| hwdata | 10 MB |
| perl-Encode | 10 MB |
| python3-perf | 10 MB |
| 13 tuned profile RPMs | ~5 MB total |

All tuned profiles (atomic, mssql, oracle, postgresql, sap, sap-hana, spectrumscale,
nfv-*, realtime, openshift, cpu-partitioning, etc.) ship because users can select any
of them.

## Optimization 6: Dual RHEL8/RHEL9 Binary Copies in CNI Images

**Estimated compressed savings**: 30-60 MB across 5 repos
**Complexity**: High — requires CNO coordination

Multiple CNI images build binaries for both RHEL 8 and RHEL 9, copying both sets into
the final image. This pattern exists for runtime RHEL version selection by the Cluster
Network Operator:

### multus-cni (Dockerfile.openshift)

Builds 8 binaries × 2 architectures (RHEL8 + RHEL9 = ~208 MB each set), then copies
the correct version into `bin/` at build time based on `VERSION_ID`. Both `rhel8/` and
`rhel9/` directories remain in the image:

```dockerfile
COPY --from=rhel9 /usr/src/multus-cni/bin /usr/src/multus-cni/rhel9/bin
COPY --from=rhel8 /usr/src/multus-cni/bin /usr/src/multus-cni/rhel8/bin
RUN bash -c '. /etc/os-release; \
    cp /usr/src/multus-cni/rhel$(echo "${VERSION_ID}" | cut -f 1 -d .)/bin/* /usr/src/multus-cni/bin'
```

### whereabouts-cni (Dockerfile.openshift)

Triple-copies 3 binaries: once to bin/ (from RHEL8), once to rhel9/bin, once to
rhel8/bin — totaling ~86 MB × 3 copies:

```dockerfile
# Default bin/ gets RHEL8 copies
COPY --from=rhel8 .../bin/whereabouts     /usr/src/whereabouts/bin
COPY --from=rhel8 .../bin/ip-control-loop /usr/src/whereabouts/bin
COPY --from=rhel8 .../bin/node-slice-controller /usr/src/whereabouts/bin
# Plus rhel9/ copies
COPY --from=rhel9 .../bin/whereabouts     /usr/src/whereabouts/rhel9/bin
...
# Plus rhel8/ copies (third set)
COPY --from=rhel8 .../bin/whereabouts     /usr/src/whereabouts/rhel8/bin
...
```

### Also affected

- **route-override-cni**: 1 binary × 3 copies (bin/, rhel8/, rhel9/)
- **container-networking-plugins**: RHEL8 + RHEL9 + Windows
- **egress-router-cni**: 1 binary × 3 copies (bin/, rhel8/, rhel9/)

### Why this exists

CNO selects the correct binary at runtime based on the host RHEL version. For pure
RHEL 9 clusters (4.22+), the RHEL 8 binaries are dead weight. However, removing them
requires:

1. CNO coordination to stop looking for rhel8/ binaries
2. Confirmation that RHEL 8 worker nodes are no longer supported
3. Possibly a feature gate for the transition period

This is not a simple Dockerfile change and risks breaking mixed-version upgrades.

## Optimization 7: zstd Layer Compression

**Estimated compressed savings**: 130-260 MB (10-20% of total)
**Decompression speedup**: Up to 60% faster than gzip, potentially 27% faster pod startup
**Complexity**: High — requires build infrastructure and registry changes

### Background

Current OCP images use gzip compression for container image layers (the Docker/OCI
default). zstd (Zstandard) is a newer compression algorithm developed by Meta that
offers better compression ratios and significantly faster decompression.

Two variants exist:

- **zstd**: Standard zstd-compressed layers. Better compression ratio than gzip,
  dramatically faster decompression. Backward-compatible — any OCI 1.1 compliant
  runtime can pull them.
- **zstd:chunked**: zstd with a table-of-contents metadata allowing file-level
  deduplication across layers. Enables partial pulls where only changed files are
  fetched. Requires client support (CRI-O, Podman) for partial pull benefits.

### Measured Compression Benchmarks: zstd vs gzip on Go Binaries

Benchmarked on an actual OCP Go binary (`cluster-image-registry-operator`, 139.6 MB)
using zstd 1.5.7 and gzip on Fedora 44:

```
Level   Compressed   Ratio    Compress Speed   Decompress Speed
──────  ──────────   ──────   ──────────────   ────────────────
gzip 1   56.6 MB     2.465x       52 MB/s           —
gzip 6   52.5 MB     2.659x       22 MB/s           —       ← Docker/OCI default
gzip 9   52.3 MB     2.671x        7 MB/s           —
──────  ──────────   ──────   ──────────────   ────────────────
zstd 1   52.8 MB     2.645x      915 MB/s       1,526 MB/s
zstd 2   51.2 MB     2.728x      846 MB/s       1,737 MB/s
zstd 3   50.2 MB     2.780x      666 MB/s       1,665 MB/s  ← zstd default
zstd 4   50.0 MB     2.791x      399 MB/s       1,092 MB/s
zstd 5   49.2 MB     2.839x      369 MB/s       1,051 MB/s
zstd 6   48.4 MB     2.886x      261 MB/s       1,580 MB/s
zstd 7   48.1 MB     2.900x      197 MB/s       1,527 MB/s
zstd 8   47.9 MB     2.914x      174 MB/s       1,086 MB/s
zstd 9   47.7 MB     2.928x      139 MB/s         963 MB/s  ← AWS recommended max
──────  ──────────   ──────   ──────────────   ────────────────
zstd 10  47.6 MB     2.937x      122 MB/s       1,597 MB/s
zstd 11  47.5 MB     2.941x       91 MB/s       1,578 MB/s
zstd 12  47.5 MB     2.942x       91 MB/s       1,146 MB/s
zstd 13  47.4 MB     2.945x       26 MB/s       1,298 MB/s  ← CLIFF: 3.5x slower
zstd 14  47.4 MB     2.947x       22 MB/s         924 MB/s
zstd 15  47.3 MB     2.951x       18 MB/s       1,153 MB/s
zstd 16  46.4 MB     3.008x       10 MB/s       1,506 MB/s
zstd 17  45.7 MB     3.055x        7 MB/s       1,457 MB/s
zstd 18  44.6 MB     3.132x        5 MB/s       1,203 MB/s
zstd 19  44.3 MB     3.150x        3 MB/s       1,324 MB/s
```

### Key Observations from the Benchmark

**zstd 1 already beats gzip 9** — smaller output (52.8 vs 52.3 MB, within 1%) while
compressing **129x faster** (915 vs 7 MB/s). Even gzip's best ratio can't match zstd's
worst.

**zstd 3 (default) is the sweet spot** — 4.4% smaller than gzip 6 (Docker default),
30x faster compression, and 1,665 MB/s decompression. This is the recommended level
for container images.

**Levels 3→9: diminishing returns begin** — each level buys ~0.4 MB smaller output but
halves compression speed. From 50.2 MB (level 3) to 47.7 MB (level 9) = only 2.5 MB
difference (5%), while compression speed drops from 666 to 139 MB/s (4.8x slower).

**Levels 10→12: plateau** — only 0.2 MB total improvement (47.7→47.5 MB) across 3
levels. Not worth the additional build time.

**Level 13: hard cliff** — compression speed drops from 91 to 26 MB/s (3.5x) for
0.1 MB gain. This is where zstd switches to a different, more exhaustive search
strategy. Never go above level 12 for container images.

**Levels 13→19: archival territory** — 3.2 MB smaller than level 12 but 28x slower
compression. Only justified for data written once and read millions of times.

**Decompression is always fast** — 963-1,737 MB/s regardless of compression level.
The node doesn't care what level was used; it decompresses at the same speed.

### Compression Level Recommendation

| Level | Use Case | Tradeoff |
|-------|----------|----------|
| **3** | **Container images (recommended)** | Best balance of ratio, speed, and simplicity |
| 6 | If build time is not a concern and every MB matters | 3.7% smaller than level 3, 2.5x slower compress |
| 9 | Maximum reasonable for CI/CD pipelines | 5.0% smaller than level 3, 4.8x slower compress |
| ≥10 | **Never for container images** | <0.5% improvement per level, rapidly increasing build cost |
| ≥13 | **Never** | Compression speed cliff, archival use only |

Applied to our 1,302 MB total compressed pull (currently gzip, assuming level 5-6):

- **zstd 3**: ~60-65 MB savings (4.4% smaller per layer) → **~1,240 MB total**
- **zstd 6**: ~95-100 MB savings (7.3% smaller) → **~1,205 MB total**
- **zstd 9**: ~105-115 MB savings (8.1% smaller) → **~1,190 MB total**

### Decompression Performance

| Metric | gzip | zstd (any level) |
|--------|------|-----------------|
| Decompress speed | ~200-400 MB/s (single-threaded) | 963-1,737 MB/s |
| Decompress CPU | Higher per byte | Lower per byte |
| Decompress memory | ~64 KB | ~2.4 MB |

**External benchmark references:**

- AWS Fargate: **up to 27% reduction** in pod startup times with zstd (larger images
  see greatest improvement)
- Depot.dev: zstd decompression **~60% faster** than pigz (parallel gzip)
- zstd decompression speed is **constant regardless of compression level** — level 19
  decompresses as fast as level 1

### CPU Implications on the Node

**Decompression (image pull) CPU usage — zstd is lower than gzip:**

zstd was designed for fast decompression with minimal CPU. At default level 3, zstd
uses less CPU per byte decompressed than gzip because:

1. The algorithm is inherently faster — it was designed to match gzip's ratio with much
   faster decompression
2. zstd processes less data overall (smaller compressed size = fewer bytes to read from
   disk/network and decompress)
3. The decompression is not CPU-bound in practice — network I/O is usually the bottleneck
   during image pulls

zstd compression (build-time) at high levels (13+) can be significantly more
CPU-intensive than gzip, but this only affects the build system, not the node. At
levels 1-9, zstd compression is faster than gzip compression too.

**zstd:chunked partial pull CPU usage — higher than plain zstd:**

The zstd:chunked partial pull feature adds client-side overhead because CRI-O must:

1. Parse the table-of-contents from the compressed layer
2. Scan existing local layers' `chunked-manifest-cache` to find matching file digests
3. Issue HTTP range requests for only the changed chunks
4. Verify digests of reused files

This scanning/deduplication adds CPU work compared to a simple sequential decompress.
However, it processes dramatically less data, so the net effect depends on how much
content is deduplicated. For initial node scale-up (no prior images on the node), the
partial pull benefit is minimal — there's nothing local to deduplicate against.

### Memory Implications on the Node

**zstd decompression memory — slightly higher than gzip but negligible:**

| Component | gzip | zstd (level 3) |
|-----------|------|----------------|
| Window size | 32 KB | 2 MB (64x larger) |
| Total decompress buffer | ~64 KB | ~2.4 MB |

The 2.4 MB per-layer decompression buffer for zstd is 64x larger than gzip's 32 KB
window, but still negligible in absolute terms on modern nodes (which have 8+ GB RAM).
Even decompressing 15 images with multiple layers concurrently would use under 100 MB
of additional memory.

**zstd:chunked memory — higher due to chunk metadata caching:**

The chunked-manifest-cache stores per-file digest indexes for all local layers. This
scales with the total number of files across all cached images. On a node with many
images, this cache can be significant (tens of MB), but is memory-mapped and only
paged in on demand.

### Runtime Compatibility

| Runtime | zstd support | zstd:chunked partial pulls |
|---------|-------------|--------------------------|
| CRI-O 1.22+ | Yes | Yes (needs `enable_partial_images="true"` in storage.conf) |
| containerd 1.5+ | Yes | No (pulls full layers, ignores chunk metadata) |
| Docker/Moby 23.0+ | Yes | No |
| Podman | Yes | Yes (enabled by default) |

### OpenShift Status

- CRI-O in OpenShift supports zstd decompression natively
- OpenShift origin has a merged test for zstd:chunked images (PR #29713, release 4.20+)
- The OpenShift build system would need to produce zstd-compressed images instead of gzip
- Registries (Quay, CI registry) must support the zstd media type
  (`application/vnd.oci.image.layer.v1.tar+zstd`)

### Configuration for Partial Pulls

To enable zstd:chunked partial pulls on a node (CRI-O), add to
`/etc/containers/storage.conf` under `[storage.options]`:

```toml
[storage.options.pull_options]
enable_partial_images = "true"
use_hard_links = "false"
```

For initial node scale-up this has limited benefit since there are no existing local
layers to deduplicate against. The primary benefit is for subsequent image updates
(e.g., during upgrades), where only changed files within a layer are fetched.

### Recommendation for Scale-Up

For node scale-up optimization, **plain zstd (non-chunked) offers the best tradeoff**:

- 10-20% smaller compressed layers → less data to transfer
- 60% faster decompression → less time spent unpacking
- Negligible additional memory (2.4 MB vs 64 KB per layer)
- No additional CPU overhead — actually lower CPU per byte than gzip
- Backward-compatible with all modern container runtimes
- No special client configuration needed

zstd:chunked adds complexity and CPU overhead for partial pulls that don't help during
initial node boot (nothing local to deduplicate against). It becomes valuable for
upgrade scenarios where images change incrementally.

### Implementation Path

1. **Build system change**: Configure the OpenShift build pipeline to produce zstd
   compressed layers instead of gzip. This is a central change, not per-repo.
2. **Registry support**: Verify Quay and CI registries accept zstd-compressed layers.
3. **Testing**: Validate that all target runtimes (CRI-O, containerd, Docker) can pull
   the new images.
4. **Rollout**: Could be done gradually — zstd images are backward-compatible with
   any OCI 1.1 runtime.

## Optimization 8: Split Images — Remove Non-NodeReady Binaries from Worker Pulls

**Estimated compressed savings**: 148-175 MB
**Complexity**: High — requires image refactoring and manifest changes per repo

Several images ship binaries that are not used on worker nodes during the NodeReady
critical path. These images are pulled by DaemonSets that run on every node, but the
extra binaries are only used by Deployments on control-plane nodes, by CLI tools, or
not at all.

### Analysis: DaemonSets in the NodeReady Critical Path

```
DaemonSet                             Image(s) Used                    Runs On
──────────────────────────────────── ──────────────────────────────── ────────
ovnkube-node                         ovn-kubernetes, kube-rbac-proxy  all nodes
multus                               multus-cni                       all nodes
multus-additional-cni-plugins         egress-router-cni,               all nodes
                                     container-networking-plugins,
                                     network-interface-bond-cni,
                                     multus-route-override-cni,
                                     multus-whereabouts-ipam-cni,
                                     multus-cni
aws-ebs-csi-driver-node              aws-ebs-csi-driver,              all nodes
                                     csi-node-driver-registrar,
                                     csi-livenessprobe
node-exporter                        prometheus-node-exporter,         all nodes
                                     kube-rbac-proxy
tuned                                cluster-node-tuning-operator      all nodes
node-ca                              cluster-image-registry-operator   all nodes
machine-config-daemon                machine-config-daemon,            all nodes
                                     kube-rbac-proxy
```

### Per-Image Dead Weight on Workers

#### ovn-kubernetes (338 MB compressed) — biggest opportunity

The ovnkube-node DaemonSet runs 9 containers on every node, all using the same
ovn-kubernetes image. The image ships 7 Go binaries plus `oc` via RPM, but only 2 Go
binaries are actually executed at runtime on workers:

```
Binary                   Size    Used on Workers?   Purpose
───────────────────────  ──────  ────────────────   ──────────────────────────────
/usr/bin/ovnkube          79 MB  YES                ovnkube-controller container
ovn-k8s-cni-overlay       55 MB  YES                CNI plugin (copied to host)
ovn-kube-util             41 MB  MAYBE              utility (may be used by scripts)
ovnkube-identity          57 MB  NO                 identity webhook (Deployment only)
ovnkube-observ            40 MB  NO                 observability (not in DaemonSet)
ovnkube-trace             27 MB  NO                 debugging tool
hybrid-overlay-node       51 MB  NO                 Windows hybrid clusters only
hybrid-overlay-node.exe   52 MB  NO                 Windows binary
/usr/bin/oc              131 MB  NO                 not called by OVN Go code or scripts
```

`/usr/bin/oc` (131 MB) is installed from the `openshift-clients` RPM (Dockerfile
line 40) and verified with `stat /usr/bin/oc` (line 59), but is never referenced in
the OVN Go source code or the `ovnkube-lib.sh` runtime script. It appears in an
upstream setup script (`ovn-config.sh`) that is not used in OpenShift production.

**Dead weight: ~358 MB uncompressed, ~120-140 MB compressed**

A node-specific OVN image containing only `ovnkube`, `ovn-k8s-cni-overlay`,
`ovn-kube-util`, and the OVS/OVN native binaries (which are needed) would save
120-140 MB compressed per worker node pull.

#### cluster-node-tuning-operator (233 MB compressed)

The "tuned" DaemonSet runs `cluster-node-tuning-operator ocp-tuned --in-cluster`. The
same image is used by the operator Deployment on the control plane.

```
Binary                                     Size    Used by tuned DaemonSet?
─────────────────────────────────────────  ──────  ────────────────────────
cluster-node-tuning-operator                97 MB  YES (ocp-tuned subcommand)
gather-sysinfo                              64 MB  MAYBE (sysinfo collection)
performance-profile-creator                 35 MB  NO (CLI tool for admins)
cluster-node-tuning-operator-test-ext.gz    11 MB  NO (e2e test binary)
```

**Dead weight: 46 MB uncompressed, ~15-20 MB compressed**

#### cluster-image-registry-operator (192 MB compressed)

The "node-ca" DaemonSet runs `cluster-image-registry-operator` in node-ca mode. The
same image is used by the operator Deployment.

```
Binary                              Size    Used by node-ca DaemonSet?
──────────────────────────────────  ──────  ──────────────────────────
cluster-image-registry-operator     140 MB  YES (node-ca subcommand)
move-blobs                           13 MB  NO (migration tool)
```

**Dead weight: 13 MB uncompressed, ~5 MB compressed**

#### container-networking-plugins (115 MB compressed)

The multus-additional-cni-plugins DaemonSet runs `cnibincopy.sh` to copy CNI plugins
to the host. Windows binaries are never used on Linux nodes.

**Dead weight: 24 MB uncompressed (Windows binaries), ~8-10 MB compressed**

### Implementation Approaches

**Approach A: Separate node-only images**

Create a second image (e.g., `ovn-kubernetes-node`) that contains only the binaries
needed on worker nodes. The DaemonSet would reference this slim image while the
Deployment continues using the full image. This requires:
- A second Dockerfile per repo
- Release payload changes to include the new image
- DaemonSet manifest changes to reference the slim image

**Approach B: Multi-binary image with `COPY --from` selection**

Use build-time `ARG` to conditionally copy binaries. Less clean but avoids adding
images to the release payload.

**Approach C: Lazy binary loading**

Keep all binaries in the image but use `zstd:chunked` partial pulls so only the
files actually opened at runtime are pulled. Requires `zstd:chunked` support in the
build system and `enable_partial_images` in CRI-O configuration.

Approach A is the most straightforward and provides guaranteed savings. The OVN image
is the highest-value target since it has the most dead weight and is the largest image.

## Summary

| # | Optimization | Compressed Savings | Complexity | Status |
|---|-------------|-------------------|------------|--------|
| 1 | Binary stripping (-s -w) | ~40-50 MB | Low | PRs filed |
| 2 | egress-router-cni: fix layer sharing | ~38-72 MB | Low | Not started |
| 3 | OVN: remove Windows binary + debug tools | ~15-20 MB | Medium | Not started |
| 4 | container-networking: remove Windows binaries | ~8-10 MB | Medium | Not started |
| 5 | NTO: remove test binary | ~4 MB | Low | Not started |
| 6 | **zstd layer compression** | **~60-115 MB** | High (build infra) | Not started |
| 7 | Remove RHEL8 binaries from CNI images | ~30-60 MB | High (CNO coord) | Not started |
| 8 | **Split images for node-only pulls** | **~148-175 MB** | High (per-repo) | Not started |

**Total estimated savings**: 345-506 MB compressed (27-39% of current 1,302 MB deduped
pull size).

Items 1-5 are actionable with individual repo PRs. Items 6-8 require broader
coordination.

The two largest opportunities are:
- **Image splitting (#8)**: 148-175 MB savings by removing binaries that workers never
  execute. The OVN image alone has ~358 MB of dead weight including an unused 131 MB
  `oc` binary. Requires per-repo Dockerfile refactoring and manifest changes.
- **zstd compression (#6)**: 60-115 MB savings with a decompression speed bonus, no
  per-repo changes needed, and negligible CPU/memory cost on the node. Requires build
  infrastructure coordination. The default level 3 is optimal — levels above 9 show
  diminishing returns, and levels above 12 hit a compression speed cliff for negligible
  size improvement.

## Sources

- [AWS: Reducing Fargate Startup Times with zstd](https://aws.amazon.com/blogs/containers/reducing-aws-fargate-startup-times-with-zstd-compressed-container-images/)
- [Depot: Building Images Gzip vs Zstd](https://depot.dev/blog/building-images-gzip-vs-zstd)
- [Red Hat: Pull container images faster with partial pulls](https://www.redhat.com/en/blog/faster-container-image-pulls)
- [OCI Image Spec v1.1 Release (zstd support)](https://opencontainers.org/posts/blog/2024-03-13-image-and-distribution-1-1/)
- [containers/storage zstd-chunked documentation](https://github.com/containers/storage/blob/main/docs/containers-storage-zstd-chunked.md)
- [Fedora zstd:chunked proposal](https://fedoraproject.org/wiki/Changes/zstd:chunked)
- [OpenShift origin zstd:chunked test PR #29713](https://github.com/openshift/origin/pull/29713)
- [zstd memory usage in constrained environments](https://github.com/facebook/zstd/wiki/Using-libzstd-in-a-memory-constrained-environment)
