# Research: Is the Gardener Registry Cache writable, or do we need a separate in-cluster registry?

- **Issue:** [#401](https://github.com/gardenlinux/gardenlinux-nvidia-installer/issues/401)
- **Date:** 2026-10-29
- **Status:** Resolved
- **Placement note:** The repo has no existing convention for research/design notes (`docs/` follows Diátaxis but only `how-to/` is populated). This file is placed under a new `docs/research/` directory, kept separate from the product docs.

## Question

Can the Gardener **Registry Cache** (the `distribution/distribution` registry deployed by the
[registry-cache extension](https://gardener.cloud/docs/extensions/others/gardener-extension-registry-cache/registry-cache/configuration/))
accept **pushes** of a locally-produced artifact (e.g. a runtime-compiled NVIDIA driver), or is it
strictly a **pull-through mirror** (read-only proxy of upstream registries)? If pull-through only,
what is the lightest-weight **writable in-cluster registry** option instead?

## Verdict (headline)

**The "reuse the Gardener Registry Cache as a push target" assumption does NOT hold.**

The Gardener registry-cache extension runs `distribution` exclusively in **proxy / pull-through
mode**, and the upstream `distribution` project explicitly declares that **pushing to a registry
configured as a pull-through cache is unsupported**. A runtime-compiled driver artifact was never in
any upstream registry, so it can never appear in the cache via the normal fetch-on-miss path, and it
cannot be pushed in. **We must deploy a separate writable in-cluster registry.**

## Findings

### 1. The Gardener registry-cache extension is pull-through only (not configurable read-write)

Primary source — Gardener extension docs / repo
([`gardener/gardener-extension-registry-cache`](https://github.com/gardener/gardener-extension-registry-cache),
`docs/usage/registry-cache/configuration.md`; mirrored at
[gardener.cloud](https://gardener.cloud/docs/extensions/others/gardener-extension-registry-cache/registry-cache/configuration/)):

- Repo one-liner: *"Gardener extension controller which deploys pull-through caches for container
  registries."* (extension `README.md`).
- *"The registry-cache extension deploys and manages a registry in the Shoot cluster that runs as
  pull-through cache. The used registry implementation is distribution/distribution."*
- Configuration is keyed entirely on **`upstream`** + optional **`remoteURL`** — i.e. every deployed
  cache is bound to exactly one upstream registry it proxies. *"The used registry implementation
  (the Distribution project) supports mirroring of only one upstream registry. The extension deploys
  a pull-through cache for each configured upstream."*
- Fetch-on-miss flow: *"The first time an image is requested from the pull-through cache, it pulls
  the image from the configured upstream registry and stores it locally… On subsequent requests, the
  pull-through cache is able to serve the image from its own storage."*
- containerd is wired to use the cache as a **mirror** and to **fall back to the upstream** on any
  failure. There is **no configuration surface for a write/push workflow** — the provider config
  exposes only `upstream`, `remoteURL`, `volume`, `serviceNameSuffix`, `proxy.{http,https}Proxy`,
  `http.tls`, `garbageCollection`, and `highAvailability`. None of these turns off proxy mode or
  enables an origin/writable registry.

**Conclusion:** the extension offers no read-write mode. It is pull-through by construction.

### 2. `distribution` in proxy mode rejects pushes (primary confirmation)

Primary source — upstream `distribution` configuration reference
([distribution.github.io/distribution/about/configuration](https://distribution.github.io/distribution/about/configuration/),
`proxy` section):

> **"Pushing to a registry configured as a pull-through cache is unsupported."**

The `proxy` block (`remoteurl`, `username`, `password`, `ttl`, `rangepassthrough`) is exactly what
turns a `distribution` instance into a pull-through cache. So the behaviour is a property of the
upstream software, not a Gardener choice — it cannot be worked around via extension config.

### 3. Lightest-weight writable in-cluster registry option

There is **no Gardener-provided writable in-cluster registry**. The extension project ships only two
things, both read/proxy-oriented: the **registry cache** (pull-through, above) and the **registry
mirror** (just configures containerd mirror hosts — it does not run a writable registry either).

**Lightest-weight option: deploy a standalone `distribution/distribution` registry ourselves**
(the same software, but with the `proxy` block omitted so it runs as a normal read-write origin
registry). It is a single container image, needs one PVC for the `filesystem` storage driver, and a
`ClusterIP` Service.

How pods reach it (in-cluster):

- **DNS:** standard Kubernetes Service DNS — `http(s)://<svc-name>.<namespace>.svc.cluster.local:<port>`
  (a bare `<svc-name>.<namespace>` also resolves in-cluster).
- **Port:** `distribution` listens on **5000** by default; expose it on the Service (e.g. 5000 for
  plain HTTP, or 443 fronting 5000 when TLS is enabled).
- **TLS:** `distribution` serves plain HTTP unless `http.tls` is configured. For in-cluster pushes
  you either (a) terminate TLS on the registry (cert via cluster CA / cert-manager), or (b) run HTTP
  and mark the endpoint insecure in the client/containerd config. TLS is strongly recommended if any
  form of basic auth is used (see §4).

> Note: the Gardener cache itself is a `distribution` StatefulSet with a per-replica volume and a
> ClusterIP Service — so a standalone writable `distribution` Deployment/StatefulSet is operationally
> very similar to what the platform already runs, just without the `proxy` block. This keeps the
> design close to existing, understood infrastructure.

### 4. Auth models the writable option exposes

Primary source — `distribution` `auth` configuration
([distribution.github.io/distribution/about/configuration](https://distribution.github.io/distribution/about/configuration/)):

`distribution` supports four auth backends, selected via the `auth` block:

| Backend     | Use                                                                 |
|-------------|---------------------------------------------------------------------|
| `none`      | No authentication (anonymous). Viable for in-cluster-only access gated by NetworkPolicy. |
| `htpasswd`  | Basic auth against an Apache htpasswd file. **Docs warn: use only with TLS configured**, since basic auth sends the password in the HTTP header. |
| `token`     | Bearer-token auth delegated to an external token issuer (`realm`, `service`, `issuer`, `rootcertbundle`, optional `jwks`, `signingalgorithms`). |
| `silly`     | Development-only; checks only for the presence of an Authorization header. Not for production. |

mTLS is not an `auth` backend per se but can be layered at the TLS/ingress tier. For an
in-cluster-only registry, the practical candidates are **anonymous (`none`) + NetworkPolicy**, or
**`htpasswd` + TLS** for a credentialed push. (This feeds the downstream auth ticket.)

### 5. Arbitrary OCI artifacts vs. runnable images only

Primary source — `distribution` landing docs
([distribution.github.io/distribution](https://distribution.github.io/distribution/)):

- *"The distribution registry implements the OCI Distribution Spec version 1.0.1."*
- It is described as storing and distributing *"container images and other content."*

Because it is a conformant OCI Distribution Spec registry, it accepts arbitrary OCI artifacts pushed
via **ORAS** (any client that speaks the OCI distribution API can push non-image artifact manifests),
not just runnable container images. So a compiled-driver tarball can be wrapped as an OCI artifact
and pushed/pulled. (This feeds the downstream artifact-format ticket.)

> Confidence note: the "container images and other content" / OCI-Distribution-Spec-1.0.1 statements
> are explicit primary-source facts. "Therefore ORAS artifacts work" is a well-supported inference
> from OCI Distribution Spec conformance rather than a verbatim distribution-docs sentence; worth a
> 5-minute live `oras push` smoke test to confirm the exact registry version in use (see §6).

## Residual verification requiring LIVE CLUSTER access (NOT done here — no cluster access)

The following cannot be confirmed from public docs and must be checked against the actual Gardener
shoot before committing the design:

1. **Exact `distribution` version** deployed by the installed registry-cache extension, and whether
   the organisation's shoot pins an older release with different behaviour.
2. **Whether a standalone writable `distribution` can be deployed into the shoot** at all — i.e. no
   admission webhook / PodSecurity / policy (e.g. Gatekeeper/Kyverno) blocks it, and a suitable
   `StorageClass` / PVC provisioning is available.
3. **Service reachability for a *push* from a node/pod** — the extension docs document reachability
   for the *cache* Service (kube-proxy iptables/IPVS timing on new nodes); a bespoke writable
   registry needs its own Service reachability and NetworkPolicy validated, especially during node
   bootstrap when the driver pod runs.
4. **TLS trust**: whether in-cluster clients (the driver pod / containerd) will trust the writable
   registry's certificate, or require insecure-registry config, under the cluster's CA setup.
5. **Live `oras push`/`pull` smoke test** of a non-image artifact to confirm ORAS behaviour and the
   registry's artifact-manifest support at the pinned version.
6. **gVisor/`runsc` nodes**: whether pushing/pulling the artifact from inside a sandboxed pod behaves
   the same (relevant because runtime-compilation mode is the gVisor path).

## Sources

- Gardener registry-cache extension — configuration docs:
  https://gardener.cloud/docs/extensions/others/gardener-extension-registry-cache/registry-cache/configuration/
- Gardener registry-cache extension — repo (`README.md`, `docs/usage/registry-cache/configuration.md`):
  https://github.com/gardener/gardener-extension-registry-cache
- `distribution/distribution` configuration reference (`proxy`, `auth`):
  https://distribution.github.io/distribution/about/configuration/
- `distribution/distribution` project docs (OCI Distribution Spec 1.0.1):
  https://distribution.github.io/distribution/
