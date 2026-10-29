# Garden Linux NVIDIA Installer

A build and packaging system for NVIDIA GPU drivers on Garden Linux, with two distinct runtime modes. The context below focuses on the vocabulary that has emerged from designing the in-cluster driver cache; terms already defined precisely in `CLAUDE.md` are not repeated.

## Language

### Build and deployment modes

**Precompiled Mode**: The deployment mode (`usePrecompiled: true`) where driver kernel modules are compiled during CI and embedded in the container image. Nodes load the pre-built driver from the image at startup.
_Avoid_: static mode, baked mode

**Runtime Compilation Mode**: The deployment mode (`usePrecompiled: false`) where driver kernel modules are compiled on the node at container startup. Required for gVisor nodes that must resolve the driver version against the node's own `runsc` binary.
_Avoid_: dynamic mode, on-demand mode

**Kernel Module Type**: Whether the NVIDIA kernel modules are the open-source (`open`) or proprietary (`proprietary`) variant. Resolved at runtime based on driver major version and GPU architecture; forms part of the cache key.
_Avoid_: module type, driver type

**Kernel Flavor**: The Garden Linux kernel variant in use — `cloud` (default) or `metal`. Encoded inside `uname -r` output and therefore captured implicitly by the cache key's `kernel-release` component; not a separate key dimension.

### In-cluster driver cache

**Driver Cache**: The standalone in-cluster OCI registry (`distribution`, ClusterIP `driver-cache:5000`) that stores pre-compiled driver artifacts for the Runtime Compilation Mode. A node checks it before compiling; a hit skips compilation.
_Avoid_: artifact cache, build cache, registry cache (the Gardener Registry Cache is a different, read-only system)

**Cache Key**: The four-component identity used to look up or store a driver artifact: `{kernel-release, driver-patch-version, kernel-module-type, arch}`. Encoded as an OCI tag. The `kernel-release` value comes from `uname -r`; the driver-patch-version is resolved (possibly via `runsc nvproxy list-supported-drivers`) before the lookup.
_Avoid_: tag, artifact key

**Cache Hit**: A successful pull of a driver artifact matching the node's cache key. Allows compilation to be skipped entirely; the pulled artifact is staged and promoted identically to a compiled one.

**Cache Miss**: No artifact present in the Driver Cache for the node's cache key. The node falls back to runtime compilation.

**Cold Miss**: A cache miss for a cache key that has never been pushed to the Driver Cache — typically the first scale-up for a new kernel or driver version. Every node compiles independently; only after the first successful push do subsequent nodes see a cache hit. Not a special code path; just the first occurrence of a cache miss for a given key.
_Avoid_: first miss, uncached

**Write-back**: The act of pushing a freshly compiled driver artifact to the Driver Cache after a successful compilation. Performed by the same driver pod that compiled the artifact, as a fire-and-forget background operation after `install()` completes. Non-fatal — a failed write-back is logged and ignored; the node continues normally.
_Avoid_: cache push, upload, publish

**Compile-failure Fallback**: The passive cache-poll behavior triggered when `compile.sh` fails (e.g. NVIDIA or APT servers unreachable). The pod polls the Driver Cache at a configured interval for up to a configured ceiling, waiting for a peer node that succeeded to complete its write-back. On a hit the artifact is pulled and staged as normal; on timeout the pod exits and K8s `restartPolicy` takes over.
_Avoid_: retry wait, compile retry (it is passive — no recompile during the wait)

**Registry mTLS**: The Driver Cache's authentication mechanism — mutual TLS (`distribution` strict client-cert verification) with a single uniform **Client Identity** shared by all driver pods, granting both pull and push. The NetworkPolicy becomes defense-in-depth rather than the sole authorization boundary. Blocks only certless attackers; a compromised node holding the write-capable cert can still poison the cache (left to the integrity decision).
_Avoid_: basic auth, token auth, per-node identity

**Client Identity**: The single client certificate all driver pods present to the Driver Cache under Registry mTLS. Uniform (not per-node) because `distribution` cannot scope a cert to pull-only and every pod is a pusher (Write-back); delivered via the GPU Operator `driver.secretEnv`.
_Avoid_: pull credential, push credential (there is one identity for both)

**Artifact Integrity**: The assurance that a pulled Driver Cache artifact is uncorrupted in transit and storage. Provided automatically by OCI content-addressing — `distribution` stores every layer by sha256 digest and ORAS verifies it on pull. Does not cover artifacts pushed by a node with a valid Client Identity that is malfunctioning or compromised.
_Avoid_: content verification, checksum verification

**Post-Pull Sanity Check**: The coherence validation performed by `verify_artifact()` after a successful Cache Hit pull: confirms the staged tarball contains at least one `.ko` file whose path includes the expected kernel release string (`uname -r`). Distinct from Artifact Integrity — catches wrong-kernel or wrong-driver artifacts rather than storage corruption. Failure is treated as a Cache Miss and falls back to compile.
_Avoid_: artifact verification, integrity check (that term belongs to Artifact Integrity)

**Cache-decision Log Signal**: The single structured, greppable log line emitted by `load_install_gpu_driver.sh` recording each cache-decision outcome (Cache Hit, Cache Miss → compiled, Compile-failure Fallback → hit, Compile-failure Fallback → timeout), with the Cache Key stamped in. The v1 observability signal — the cache ships no monitoring components of its own (**cluster-native, component-free**: no `ServiceMonitor`/`PrometheusRule`, `distribution`'s `:5001` metrics port not exposed). Registry metrics scraping and PVC-usage alerting are left to the cluster operator as documented runbook hooks.
_Avoid_: cache metric, hit/miss metric (v1 emits a log line, not a metric)
