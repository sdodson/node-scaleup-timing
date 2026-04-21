# Node Scale-Up Variance Analysis: Standard_D4s_v5 (ARO, OCP 4.20.15, eastus2)

## Test Setup
- **Cluster**: ARO (Azure Red Hat OpenShift) — `sdodson-ws867`
- **OCP Version**: 4.20.15 (Kubernetes 1.33.6, CRI-O 1.33.9)
- **OS**: RHCOS 9.6.20260217-1 (Plow), kernel 5.14.0-570.92.1.el9_6
- **Region**: eastus2, Zones 1/2/3
- **Date**: 2026-04-23
- **VM Type**: Standard_D4s_v5 (4 vCPU, 16 GB RAM)
- **Rounds**: 10 (all 3 zones per round, machinesets created simultaneously)
- **Total samples**: 26 of 30 (4 zone-1 journals captured before NodeReady)
- **IDMS**: `image-digest-mirror` active — redirects quay.io/openshift-release-dev/* to arosvc.azurecr.io

## Results Summary

**Overall scale-up time:** Mean = **284s (4m 44sec)**, stdev = 11s, range 268-307s

## All Data Points

| Round | Zone | Total | VM Prov | Boot 1 | Reboot | KTR | systemd-analyze | chrony-wait |
|------:|-----:|------:|--------:|-------:|-------:|----:|----------------:|------------:|
| 1 | 1 | 272s | 19s | 148s | 3s | 68s | 31.8s | 24.07s |
| 1 | 2 | 272s | 17s | 160s | 4s | 58s | 31.6s | 24.08s |
| 1 | 3 | 273s | 19s | 153s | 4s | 63s | 36.1s | 24.07s |
| 2 | 2 | 306s | 18s | 163s | 6s | 87s | 32.7s | 24.07s |
| 2 | 3 | 307s | 20s | 173s | 5s | 75s | 32.8s | 24.07s |
| 3 | 1 | 295s | 19s | 168s | 6s | 71s | 31.9s | 24.09s |
| 3 | 2 | 293s | 17s | 170s | 4s | 68s | 32.6s | 24.07s |
| 3 | 3 | 300s | 21s | 181s | 7s | 59s | 32.4s | 24.08s |
| 4 | 2 | 287s | 19s | 157s | 5s | 74s | 32.0s | 24.06s |
| 4 | 3 | 289s | 17s | 164s | 7s | 70s | 36.0s | 24.07s |
| 5 | 1 | 270s | 20s | 157s | 6s | 55s | 32.1s | 24.07s |
| 5 | 2 | 269s | 18s | 152s | 8s | 61s | 31.8s | 24.08s |
| 5 | 3 | 268s | 17s | 157s | 5s | 56s | 32.8s | 24.07s |
| 6 | 1 | 291s | 19s | 146s | 7s | 89s | 31.8s | 24.07s |
| 6 | 2 | 291s | 19s | 171s | 4s | 63s | 32.1s | 24.06s |
| 6 | 3 | 290s | 19s | 175s | 7s | 57s | 32.7s | 24.07s |
| 7 | 1 | 278s | 17s | 151s | 3s | 73s | 35.0s | 24.08s |
| 7 | 2 | 278s | 20s | 154s | 7s | 66s | 31.9s | 24.07s |
| 7 | 3 | 284s | 20s | 167s | 8s | 59s | 35.6s | 24.07s |
| 8 | 1 | 277s | 18s | 153s | 3s | 68s | 32.6s | 24.07s |
| 8 | 2 | 275s | 18s | 149s | 6s | 71s | 31.8s | 24.06s |
| 8 | 3 | 274s | 19s | 159s | 8s | 58s | 35.7s | 24.07s |
| 9 | 2 | 286s | 19s | 160s | 6s | 69s | 32.2s | 24.07s |
| 9 | 3 | 285s | 17s | 160s | 7s | 70s | 36.2s | 24.07s |
| 10 | 2 | 288s | 18s | 166s | 7s | 66s | 31.8s | 24.07s |
| 10 | 3 | 288s | 18s | 151s | 8s | 80s | 32.3s | 24.07s |

## Overall Statistics (n=26)

| Metric | Mean | Stdev | Min | Max |
|:---|---:|---:|---:|---:|
| **Total Scale-up** | **284.1s** | 11.1s | 268s | 307s |
| VM Provisioning | 18.5s | 1.1s | 17s | 21s |
| Boot 1 Duration | 160.2s | 9.1s | 146s | 181s |
| Reboot Gap | 5.8s | 1.6s | 3s | 8s |
| Kubelet to NodeReady | 67.5s | 8.9s | 55s | 89s |
| systemd-analyze | 33.0s | 1.6s | 31.6s | 36.2s |
| chrony-wait | 24.07s | 0.007s | 24.06s | 24.09s |

## Per-Zone Statistics

| Metric | Zone 1 (n=6) | Zone 2 (n=10) | Zone 3 (n=10) |
|:---|---:|---:|---:|
| **Total Mean** | **280.5s ± 10.2s** | **284.5s ± 11.2s** | **285.8s ± 12.1s** |
| VM Provisioning | 18.7s ± 1.0s | 18.5s ± 0.9s | 18.5s ± 1.3s |
| Boot 1 | 153.8s ± 7.6s | 160.2s ± 7.5s | 163.6s ± 10.3s |
| KTR | 70.7s ± 11.9s | 68.3s ± 8.4s | 65.0s ± 8.5s |

**No statistically significant zonal differences.** Consistent with all previous findings.

## Variance Analysis

**This cluster has the lowest variance of any tested** — stdev 11.1s vs 49.0s (standalone eastus2) and 40.1s (ARO brazilsouth). No outlier rounds. The tight variance suggests stable I/O conditions in the eastus2 region during testing.

## IDMS Mirror Analysis

The IDMS (`image-digest-mirror`) redirects all `quay.io/openshift-release-dev/*` pulls to `arosvc.azurecr.io`. Journal analysis confirms:

### Boot 1 (MCD firstboot)
- **MCD container image pull** (podman): ~8-11s for the 1.07 GB MCD image. Podman logs reference `quay.io/...` as the image name but the pull is redirected through `arosvc.azurecr.io` via `/etc/containers/registries.conf` (written by Ignition before MCD firstboot starts).
- **rpm-ostree rebase**: ~71-82s. Uses `ostree-unverified-registry:quay.io/...` reference, also redirected via registries.conf.
- **Boot 1 total: 160s** — essentially identical to standalone OCP eastus2 (157s). The arosvc.azurecr.io mirror adds no measurable overhead for Boot 1 image pulls in the same region.

### Boot 2 (CRI-O pulls)
- CRI-O explicitly logs `Trying to access "arosvc.azurecr.io/openshift-release-dev/..."` — confirmed mirror usage.
- Total CRI-O pull window: ~77s for 28 images.
- Individual pull times range from 0.7s to 28.6s depending on image size and layer sharing.
- **KTR total: 67.5s** — 11s slower than standalone OCP eastus2 (56s). This is the only phase where the IDMS mirror shows measurable overhead.

### IDMS speed impact summary

| Phase | ARO eastus2 (via arosvc.azurecr.io) | Standalone eastus2 (via quay.io) | Delta |
|-------|-------------------------------------|----------------------------------|-------|
| Boot 1 (rpm-ostree rebase) | 160s | 157s | +3s (neutral) |
| KTR (CNI image pulls) | 67.5s | 56.1s | +11s |
| VM Provisioning | 18.5s | 39.6s | −21s |
| **Total** | **284s** | **294s** | **−10s** |

The IDMS mirror adds ~11s to CRI-O image pulls compared to direct quay.io access in the same region. However, ARO's faster VM provisioning (−21s) more than compensates, resulting in a net 10s advantage.

## Comparison with Other Clusters

| Metric | ARO eastus2 4.20 (n=26) | OCP Standalone eastus2 4.20 (n=24) | ARO brazilsouth 4.20 (n=30) | OCP Standalone eastus 4.22 (n=12) |
|:---|---:|---:|---:|---:|
| **Total** | **284s (4m 44sec)** | **294s (4m 54sec)** | **335s (5m 35sec)** | **247s (4m 07sec)** |
| VM Provisioning | 18.5s | 39.6s | 21.8s | 20.5s |
| Boot 1 | 160.2s | 157.3s | 199.0s | 128.3s |
| Reboot | 5.8s | 6.1s | 6.1s | 5.4s |
| chrony-wait | 24.07s | 24.07s | 24.07s | 24.07s |
| systemd-analyze | 33.0s | 34.3s | 28.4s | 33.1s |
| KTR | 67.5s | 56.1s | 75.5s | 60.6s |
| **Total stdev** | **11.1s** | **49.0s** | **40.1s** | **11.3s** |

### Key findings

1. **ARO eastus2 is 10s (3.4%) faster than standalone OCP eastus2** — same region, same OCP version, same VM type. The net gain comes from faster VM provisioning (−21s) offsetting slower KTR (+11s from IDMS mirror overhead).

2. **ARO eastus2 is 51s faster than ARO brazilsouth** — confirming the Brazil region penalty is ~51s, split between Boot 1 (−39s) and KTR (−8s), entirely attributable to registry distance.

3. **Boot 1 is identical between ARO and standalone in the same region** (160s vs 157s). The arosvc.azurecr.io mirror has no measurable impact on rpm-ostree rebase time when the mirror is in the same Azure region.

4. **KTR is 11s slower on ARO than standalone** (67.5s vs 56.1s). CRI-O pulls via arosvc.azurecr.io are slightly slower than direct quay.io pulls, possibly because quay.io uses CDN edge locations while arosvc.azurecr.io is a single Azure Container Registry.

5. **Variance is remarkably low** — stdev 11.1s, the lowest of any cluster tested. No outlier rounds, no zonal differences.

## Saved Artifacts

Per round/zone (r1-r10, z1-z3):
- `new-machine-aro-eastus2-d4s-v5-r{R}-z{Z}-final.yaml`
- `new-node-aro-eastus2-d4s-v5-r{R}-z{Z}.yaml`
- `machineset-aro-eastus2-d4s-v5-r{R}-z{Z}.json`
- `node-boot-list-aro-eastus2-d4s-v5-r{R}-z{Z}.txt`
- `node-systemd-analyze-aro-eastus2-d4s-v5-r{R}-z{Z}.txt`
- `node-systemd-blame-aro-eastus2-d4s-v5-r{R}-z{Z}.txt`
- `node-systemd-critical-chain-aro-eastus2-d4s-v5-r{R}-z{Z}.txt`
- `node-images-aro-eastus2-d4s-v5-r{R}-z{Z}.txt`
- `node-journal-aro-eastus2-d4s-v5-r{R}-z{Z}.log` (full journals for IDMS analysis)
- `csr-list-aro-eastus2-r{R}.txt`
- `rendered-worker-ignition-aro-eastus2.json` (worker ignition config with registries.conf)
