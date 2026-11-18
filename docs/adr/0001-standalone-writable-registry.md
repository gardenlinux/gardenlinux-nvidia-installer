# Standalone writable registry over Gardener Registry Cache

We deploy our own standalone `distribution` instance (ClusterIP `driver-cache:5000`) rather than reusing the Gardener Registry Cache that is already present in Gardener clusters. The Gardener Registry Cache runs `distribution` in pull-through/proxy mode only; proxy mode rejects push requests at the API level. Since writing back freshly compiled artifacts is the core requirement, a separate registry is the only option — the shared one cannot be made writable without operator-level reconfiguration outside our control.

## Considered options

- **Reuse Gardener Registry Cache**: ruled out by research (#401) — proxy mode rejects pushes unconditionally.
- **External registry (ghcr.io, ECR, etc.)**: rejected — requires external network at write-back time, which is the failure mode we are trying to mitigate.
- **Standalone `distribution`**: adopted — same image already used by Gardener, well-understood operationally, supports arbitrary OCI artifact pushes via ORAS.
