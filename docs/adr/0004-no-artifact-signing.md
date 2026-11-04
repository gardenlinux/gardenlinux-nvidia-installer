# No artifact signing; accept compromised-node push risk

The Driver Cache uses OCI content-addressing (sha256 digest verification on every pull) for storage and transit integrity, plus a lightweight Post-Pull Sanity Check in `verify_artifact()` (tar contains `.ko` files for the expected kernel release). We explicitly chose not to add cosign or any other artifact signing scheme.

Signing only raises the bar against a malicious pusher if the signing key is held *outside* the driver pod. In this design the key would live in the same Kubernetes Secret as the mTLS client cert — a compromised node already holds both, so signing adds no security against the threat it is meant to address.

The accepted risk — a node holding the Client Identity pushes a malicious or wrong-kernel artifact — is not a regression from the baseline: the current runtime-compilation path downloads an unsigned `.run` from NVIDIA's CDN over TLS and trusts CDN integrity. The in-cluster trust boundary (mTLS + NetworkPolicy) is comparable in attack surface.

The `verify_artifact()` seam is retained for a future iteration where a signing service with a separately held key could be introduced without changing the pull-flow contract.

## Considered options

- **cosign / Notary with key in driver pod Secret**: rejected — the signing key lives alongside the push cert; a compromised node has both and can push a valid signature over a malicious artifact.
- **Separate signing service (sidecar or dedicated pod)**: rejected for this iteration — out of scope for the planning effort; the `verify_artifact()` seam preserves the hook.
- **OCI digest + Post-Pull Sanity Check**: adopted.
