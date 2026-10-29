# Mutual TLS for the Driver Cache registry

The Driver Cache registry terminates **mutual TLS** with strict client-certificate verification (`distribution` `http.tls.clientauth: require-and-verify-client-cert`). Every driver pod authenticates with a single uniform client certificate that grants both pull and push; the NetworkPolicy becomes defense-in-depth rather than the sole authorization boundary. This overturns the plain-HTTP element of the registry-deployment decision (#407) while leaving its other decisions intact.

Two forces drove this past plain-HTTP-plus-NetworkPolicy: a compliance rule forbidding plain HTTP traffic in-cluster, and the wish to keep a NetworkPolicy failure from being sufficient to reach — and poison — the cache, whose artifacts are loaded as privileged kernel modules on every node.

mTLS is a transport and defense-in-depth boundary, not a per-identity authorization system. `distribution`'s client-CA check is all-or-nothing, so a pull-only vs read-write split is not possible without an external token server or reverse proxy. Because the write-back design (#404) makes every driver pod a pusher, a split would add a component for no benefit, so all pods share one write-capable identity. The residual threat — a compromised legitimate node poisoning the cache — is explicitly left to the artifact integrity/trust decision (#406).

## Considered options

- **Anonymous-in-cluster + NetworkPolicy** (plain HTTP, per #407): rejected — violates the no-plain-HTTP compliance rule, and a NetworkPolicy failure alone would expose the cache to read and poisoning.
- **htpasswd basic-auth**: rejected — meaningful only over TLS (cleartext credentials otherwise), so it does not avoid the TLS work while adding credential distribution with no authorization benefit here.
- **Mutual TLS, uniform client identity**: adopted.
- **Istio mesh mTLS**: rejected — not present in a Gardener shoot by default, non-portable, and the privileged GPU-Operator-templated driver pod does not reliably accept an Envoy sidecar.

## Certificate issuance

- **Helm-generated self-signed CA, generate-once**: adopted baseline — no cluster prerequisites; the chart owns CA, server cert, and one client bundle. Certs pinned across `helm upgrade` with a `lookup` guard.
- **Gardener `shoot-cert-service`** (`shootIssuers` + CA-backed `Issuer.cert.gardener.cloud`): documented alternative where managed rotation or Gardener-native certs are required; costs a Shoot-spec extension prerequisite.
- **Upstream cert-manager**: rejected — not default in a Gardener shoot; a third-party install imposed on every consumer.

## Delivery

ORAS presents client certs via `--cert-file`/`--key-file`/`--ca-file`, so no OS trust-anchor (`driver.certConfig`) wiring is needed. CA + client cert + key ship in one Secret referenced by the GPU Operator ClusterPolicy `driver.secretEnv`; the startup script writes the PEMs to temp files for `oras`. The Secret lives in the GPU Operator namespace (the registry chart owns only `nvidia-driver-cache`), wired as part of the manual `DRIVER_CACHE_REGISTRY` step (#403). Alternatives: chart-templated cross-namespace Secret; or operator-owned PKI (e.g. HashiCorp Vault + Vault Secrets Operator replicating the Secret into both namespaces).
