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
| `storage.storageClass` | `""` | StorageClass; empty = cluster default |
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

To wire the Client Identity into the GPU Operator, copy `ca.crt`, `client.crt`, and `client.key` from `driver-cache-tls` into a Secret in the GPU Operator namespace (e.g. `driver-cache-client-tls`), then reference it via `driver.secretEnv` in the ClusterPolicy. The driver startup script reads the PEM files and passes them to ORAS via `--cert-file`/`--key-file`/`--ca-file`.

### Alternative: Gardener shoot-cert-service

If managed certificate rotation or Gardener-native PKI is required, you can issue certs via the Gardener `shoot-cert-service` extension:

1. Enable the `shoot-cert-service` extension in the Shoot spec.
2. Create a `Certificate` resource (`cert.gardener.cloud/v1alpha1`) in the chart namespace backed by a CA `Issuer` for the server cert.
3. Disable the Helm-generated Secret by overriding the `driver-cache-tls` Secret with the one produced by the cert-service, and mount the resulting certs via the same key names.

This approach requires the `shoot-cert-service` extension to be present in the Gardener landscape.

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
