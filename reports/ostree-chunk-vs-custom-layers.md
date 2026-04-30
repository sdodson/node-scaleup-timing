# Ostree Chunk Layers vs Custom Layers

An ostree-native container image (like the OCP machine-os image) has two kinds of OCI layers:

## Ostree Chunk Layers

The `ostree container encapsulate` tool takes the full ostree commit (the entire RHCOS filesystem) and splits it into multiple OCI image layers using a deterministic chunking algorithm that consults RPM metadata. The idea is that if only a few packages change between versions, most chunks stay identical and clients only download the changed ones. In our data, there are consistently 51 of these across all OCP versions tested (4.16–4.20).

During rebase, ostree chunks are imported directly into the ostree object store as native ostree objects — this is fast because it's just content-addressed blob storage.

## Custom Layers

Custom layers are standard OCI layers added *on top* of the ostree base using a Containerfile/Dockerfile — `RUN`, `COPY`, etc. They represent modifications made after the base ostree commit was encapsulated. In the journal fetch log they appear after all the ostree chunk fetches as "Fetching layer" (not "Fetching ostree chunk"):

```
[50/52] Fetching layer d9d9e220935ca44ca15 (192.9 MB)...done
[51/52] Fetching layer 84b2325426791ea0a8a (6.7 kB)...done
```

Two custom layers appeared in OCP 4.19: one ~193 MB layer and one 6.7 kB metadata layer. They were not present in 4.16–4.18.

During rebase, custom layers are applied as filesystem overlays on top of the ostree commit — rpm-ostree has to unpack and merge them into the deployment. This is significantly more expensive than importing ostree chunks.

## Impact on Rebase Apply Time

The introduction of 2 custom layers in 4.19 caused the rebase apply phase (post-fetch, staging the deployment) to jump from ~7.5s to ~20s — a +12.5s regression that persists through 4.20 regardless of platform or boot image freshness. See the [Rebase Apply Time breakdown](scale-up-analysis-aro-upgrade-study.md#rebase-apply-time-fetch-vs-apply-breakdown) in the upgrade study for the full data.

The 193 MB custom layer likely contains content that was previously either part of the base ostree commit itself or delivered through a different mechanism (like the os-extensions image). Moving it into a custom layer on top of the base image is architecturally cleaner from a build perspective, but it costs ~12.5s in apply time on every node scale-up.

## References

- [ostree native containers | rpm-ostree](https://coreos.github.io/rpm-ostree/container/)
- [rpm-ostree container.md](https://github.com/coreos/rpm-ostree/blob/main/docs/container.md)
- [Changes/OstreeNativeContainerStable - Fedora Project Wiki](https://fedoraproject.org/wiki/Changes/OstreeNativeContainerStable)
