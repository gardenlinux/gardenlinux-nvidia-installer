# driver-cache Helm chart

Deploys a standalone `distribution` OCI registry into a dedicated namespace. Driver pods in Runtime Compilation Mode check this registry before compiling NVIDIA kernel modules; a cache hit skips compilation entirely.

In-cluster address: `driver-cache.<namespace>.svc.cluster.local:5000` (default namespace: `nvidia-driver-cache`).

## Installation

```sh
helm install driver-cache ./helm/driver-cache \
  -n nvidia-driver-cache \
  --create-namespace
```

The chart generates a self-signed CA and client certificate on first install and pins them across upgrades via a `lookup` guard. The in-cluster address resolves to `driver-cache.nvidia-driver-cache.svc.cluster.local:5000`.

## Configuration

| Parameter | Default | Description |
|---|---|---|
| `image.repository` | `registry` | Registry image (distribution v2) |
| `image.tag` | `2` | Image tag |
| `storage.size` | `20Gi` | PVC capacity |
| `storage.storageClass` | `""` | StorageClass name; empty = cluster default |
| `storage.volumeType` | `""` | Cinder volume type (e.g. `vmware`); when set, creates a dedicated StorageClass with that type. Empty = use StorageClass default |
| `networkPolicy.gpuOperatorNamespace` | `gpu-operator` | Source namespace allowed ingress on port 5000 |

## mTLS and client credentials

The chart creates a Secret `driver-cache-tls` in the chart namespace containing:

| Key | Purpose |
|---|---|
| `ca.crt` | CA certificate — used by the registry to verify clients; used by clients to verify the registry |
| `server.crt` | Registry server certificate |
| `server.key` | Registry server private key |
| `client.crt` | Client Identity certificate (shared by all driver pods) |
| `client.key` | Client Identity private key |

To wire the Client Identity into the GPU Operator, copy `ca.crt`, `client.crt`, and `client.key` from `driver-cache-tls` into a Secret in the GPU Operator namespace, then reference it in `helm/gpu-operator-values-runtime.yaml` via `driver.env` with `valueFrom.secretKeyRef` entries for `DRIVER_CACHE_CA_PEM`, `DRIVER_CACHE_CERT_PEM`, and `DRIVER_CACHE_KEY_PEM`. The driver startup script materialises those PEM env vars into temp files and passes them to ORAS via `--cert-file`/`--key-file`/`--ca-file`.

### Alternative: Gardener shoot-cert-service

If managed certificate rotation or Gardener-native PKI is required, you can issue certs via the Gardener `shoot-cert-service` extension. The chart's `secret.yaml` uses a `lookup` guard: if `driver-cache-tls` already exists in the namespace, Helm reuses it and skips generation entirely. The workflow is therefore: issue certs via cert-service → assemble the expected Secret → then install the chart.

This approach requires the `shoot-cert-service` extension to be present in the Gardener landscape.

#### Step 1: Enable shoot-cert-service in the Shoot spec

```yaml
# shoot.yaml (patch or apply via gardenctl / Gardener Dashboard)
spec:
  extensions:
    - type: shoot-cert-service
```

#### Step 2: Create a CA Issuer and Certificate resources

First, provide the CA key material in a Secret. If you don't have an existing CA, generate one with `openssl` and encode it:

```sh
openssl req -x509 -newkey rsa:4096 -keyout ca.key -out ca.crt -days 3650 -nodes \
  -subj "/CN=driver-cache-ca"

kubectl create namespace nvidia-driver-cache --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret tls driver-cache-ca \
  -n nvidia-driver-cache \
  --cert=ca.crt --key=ca.key
```

Create an `Issuer` backed by that CA:

```yaml
# issuer.yaml
apiVersion: cert.gardener.cloud/v1alpha1
kind: Issuer
metadata:
  name: driver-cache-ca
  namespace: nvidia-driver-cache
spec:
  ca:
    privateKeySecretRef:
      name: driver-cache-ca
      namespace: nvidia-driver-cache
```

Issue the server cert. The `dnsNames` list must cover every address the registry is reachable at:

```yaml
# server-cert.yaml
apiVersion: cert.gardener.cloud/v1alpha1
kind: Certificate
metadata:
  name: driver-cache-server
  namespace: nvidia-driver-cache
spec:
  commonName: driver-cache
  dnsNames:
    - driver-cache
    - driver-cache.nvidia-driver-cache
    - driver-cache.nvidia-driver-cache.svc
    - driver-cache.nvidia-driver-cache.svc.cluster.local
  issuerRef:
    name: driver-cache-ca
    namespace: nvidia-driver-cache
  secretRef:
    name: driver-cache-server-tls
    namespace: nvidia-driver-cache
```

Issue the client cert (no DNS SANs needed — it is used for client identity only):

```yaml
# client-cert.yaml
apiVersion: cert.gardener.cloud/v1alpha1
kind: Certificate
metadata:
  name: driver-cache-client
  namespace: nvidia-driver-cache
spec:
  commonName: driver-cache-client
  issuerRef:
    name: driver-cache-ca
    namespace: nvidia-driver-cache
  secretRef:
    name: driver-cache-client-tls
    namespace: nvidia-driver-cache
```

Apply and wait:

```sh
kubectl apply -f issuer.yaml -f server-cert.yaml -f client-cert.yaml
kubectl wait --for=condition=Ready \
  certificate/driver-cache-server certificate/driver-cache-client \
  -n nvidia-driver-cache --timeout=120s
```

#### Step 3: Assemble `driver-cache-tls` before chart install

The cert-service stores each cert's data under `tls.crt` / `tls.key` / `ca.crt`. Merge them into the key names the chart expects, then add the `helm.sh/resource-policy: keep` annotation so `helm uninstall` does not delete the cert-service-managed Secret:

```sh
# Read from the two cert-service Secrets (values are already base64-encoded)
CA_CRT=$(kubectl get secret driver-cache-server-tls \
  -n nvidia-driver-cache -o jsonpath='{.data.ca\.crt}')
SERVER_CRT=$(kubectl get secret driver-cache-server-tls \
  -n nvidia-driver-cache -o jsonpath='{.data.tls\.crt}')
SERVER_KEY=$(kubectl get secret driver-cache-server-tls \
  -n nvidia-driver-cache -o jsonpath='{.data.tls\.key}')
CLIENT_CRT=$(kubectl get secret driver-cache-client-tls \
  -n nvidia-driver-cache -o jsonpath='{.data.tls\.crt}')
CLIENT_KEY=$(kubectl get secret driver-cache-client-tls \
  -n nvidia-driver-cache -o jsonpath='{.data.tls\.key}')

kubectl create secret generic driver-cache-tls \
  -n nvidia-driver-cache \
  --from-literal=ca.crt="$(echo "$CA_CRT" | base64 -d)" \
  --from-literal=server.crt="$(echo "$SERVER_CRT" | base64 -d)" \
  --from-literal=server.key="$(echo "$SERVER_KEY" | base64 -d)" \
  --from-literal=client.crt="$(echo "$CLIENT_CRT" | base64 -d)" \
  --from-literal=client.key="$(echo "$CLIENT_KEY" | base64 -d)"

kubectl annotate secret driver-cache-tls \
  -n nvidia-driver-cache \
  helm.sh/resource-policy=keep
```

Now install the chart. The `lookup` guard finds the pre-created Secret and leaves it untouched:

```sh
helm install driver-cache ./helm/driver-cache \
  -n nvidia-driver-cache \
  --create-namespace
```

**Handling cert rotation:** After the cert-service renews a cert, re-run the `kubectl create secret generic` step (replacing `create` with `delete` + re-create, or using `--dry-run=client -o yaml | kubectl apply -f -`), then restart the Deployment to pick up the new Secret:

```sh
kubectl rollout restart deployment/driver-cache -n nvidia-driver-cache
```

## Integration test — cache hit/miss round-trip

The `cache-hit-miss-test` job in `.github/workflows/test_installer.yml` verifies an end-to-end cold-miss → write-back → cache-hit cycle on a real Gardener GPU cluster.

**What it does:**

1. Deploys this chart into `nvidia-driver-cache`.
2. Cross-copies the chart-generated `driver-cache-tls` Secret into `gpu-operator` (where the driver pods resolve `valueFrom.secretKeyRef`).
3. Installs the GPU Operator with `helm/gpu-operator-values-runtime.yaml` (runtime compilation mode, `DRIVER_CACHE_REGISTRY` wired).
4. Waits up to 35 minutes for the first driver pod to reach `Ready` (cold miss — compiles the driver and writes it to the cache).
5. Asserts `[CACHE] miss` in that pod's logs and that `nvidia-smi` exits 0.
6. Pins the old pod name, deletes the pod, waits for it to disappear, then waits up to 10 minutes for the replacement to reach `Ready` (cache hit — pulls from the registry).
7. Asserts `[CACHE] hit` in the new pod's logs and that `nvidia-smi` exits 0.
8. Cleans up the chart, the cross-namespace Secret, and the `nvidia-driver-cache` namespace on pass or fail.

**When it runs:**

The job is part of the weekday CI schedule (`0 18 * * 1-5`) and runs after the existing `test` job (precompiled mode). It requires the Gardener cluster secrets (`CLUSTER_SERVER`, `CLUSTER_CA_DISCOVERY_URL`) to be present in the repository.

**Running locally:**

```sh
export KUBECONFIG=/path/to/kubeconfig.yaml
.ci/cache_hit_miss_test.sh
```

Add `--skip-cleanup` to leave the chart and namespace behind on pass (useful for inspection). Cleanup always runs on failure regardless.

**Triggering in CI:**

```sh
gh workflow run test_installer.yml --ref <branch>
```

Or open the workflow in the GitHub Actions UI and click **Run workflow**.

**Reading the output:**

Look for these lines in the step logs:

| Step | Expected log line |
|---|---|
| Assert first pod — cold miss | `[CACHE] miss key=<driver-version>-<module-type>-<arch>-<kernel>` |
| Assert second pod — cache hit | `[CACHE] hit key=<driver-version>-<module-type>-<arch>-<kernel>` |

Both steps also exec `nvidia-smi` inside the driver container (`nvidia-driver-ctr`) and fail the workflow if it exits non-zero.

**Debugging a failure:**

The **Debug on failure** step runs automatically when any earlier step fails. It prints:

- `kubectl get pods` for the driver DaemonSet
- The last 100 lines of the driver container log
- `kubectl describe pod` for the driver pod
- `kubectl get pods` for the registry in `nvidia-driver-cache`

Logs for any completed step are also available in the GitHub Actions run summary.

## Manual garbage collection runbook

The registry config ships with `storage.delete.enabled: true`, which enables the `DELETE /v2/<name>/manifests/<digest>` API. Run the GC when the PVC is near capacity:

```sh
# 1. Scale down the registry (GC requires exclusive access to storage)
kubectl scale deployment driver-cache -n nvidia-driver-cache --replicas=0

# 2. Run the built-in GC tool inside a temporary pod sharing the same PVC
kubectl run gc --rm -it --restart=Never \
  --image=registry:2 \
  --overrides='{"spec":{"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"driver-cache"}}],"containers":[{"name":"gc","image":"registry:2","command":["registry","garbage-collect","/etc/distribution/config.yml"],"volumeMounts":[{"name":"data","mountPath":"/var/lib/registry"}]}]}}' \
  -n nvidia-driver-cache

# 3. Restore the registry
kubectl scale deployment driver-cache -n nvidia-driver-cache --replicas=1
```

Alternatively, delete specific tags via the OCI distribution DELETE API before running GC:

```sh
# Identify the digest for a tag
DIGEST=$(oras manifest fetch \
  --cert-file client.crt --key-file client.key --ca-file ca.crt \
  driver-cache.nvidia-driver-cache.svc.cluster.local:5000/<tag> \
  --descriptor | jq -r .digest)

# Delete the manifest
curl --cert client.crt --key client.key --cacert ca.crt \
  -X DELETE "https://driver-cache.nvidia-driver-cache.svc.cluster.local:5000/v2/<repo>/manifests/$DIGEST"
```

Then run the GC job above to reclaim storage.

## PVC usage alert

The registry metrics port `:5001` is not exposed (see ADR 0005). Use kubelet-native volume metrics instead. Recommended PromQL alert expression (~85% full):

```promql
(
  kubelet_volume_stats_used_bytes{namespace="nvidia-driver-cache", persistentvolumeclaim="driver-cache"}
  /
  kubelet_volume_stats_capacity_bytes{namespace="nvidia-driver-cache", persistentvolumeclaim="driver-cache"}
) > 0.85
```

Wire this into a `PrometheusRule` or Alertmanager rule in your monitoring namespace. The metric is available on any cluster with a Kubelet metrics scrape; no additional exporters are required.
