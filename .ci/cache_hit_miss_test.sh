#!/usr/bin/env bash
# End-to-end cache hit/miss round-trip test.
#
# Requires a KUBECONFIG pointing at a Gardener GPU cluster.
# Usage: .ci/cache_hit_miss_test.sh [--skip-cleanup]
#
# --skip-cleanup  Leave the chart and namespace behind on pass (useful for
#                 inspecting state). Cleanup always runs on failure.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKIP_CLEANUP=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-cleanup) SKIP_CLEANUP=true ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

cleanup() {
    echo "=== Cleanup ==="
    helm uninstall gpu-operator -n gpu-operator 2>/dev/null || true
    helm uninstall driver-cache -n nvidia-driver-cache 2>/dev/null || true
    # StatefulSet volumeClaimTemplates are not deleted by helm uninstall.
    kubectl delete pvc -n nvidia-driver-cache --all --ignore-not-found
    kubectl delete secret driver-cache-tls -n gpu-operator --ignore-not-found
    kubectl delete namespace nvidia-driver-cache --ignore-not-found
}

if [[ "${SKIP_CLEANUP}" == "false" ]]; then
    trap cleanup EXIT
else
    # Always clean up on failure even when --skip-cleanup is set.
    trap 'if [[ $? -ne 0 ]]; then cleanup; fi' EXIT
fi

# ---------------------------------------------------------------------------
# 1. Deploy driver-cache chart
# ---------------------------------------------------------------------------
echo "=== Installing driver-cache chart ==="
helm upgrade --install driver-cache "${REPO_ROOT}/helm/driver-cache" \
    -n nvidia-driver-cache \
    --create-namespace \
    --set storage.volumeType=vmware

# On Cinder-backed clusters the PVC becomes Bound as soon as the PV is
# provisioned, but the underlying block device can still be in "creating"
# state for several more minutes.  Kubernetes retries the CSI attach until
# it succeeds, so we just need to wait long enough for the full round-trip:
# Cinder volume ready → CSI attach → kubelet mount → container start.
# kubectl rollout status waits for the pod to be Ready, which covers all of
# those steps. Use a 15 min timeout to accommodate slow Cinder provisioning.
echo "=== Waiting for driver-cache pod to be Ready (up to 15 min) ==="
kubectl rollout status statefulset/driver-cache \
    -n nvidia-driver-cache \
    --timeout=15m

# ---------------------------------------------------------------------------
# 2. Cross-copy TLS secret into gpu-operator namespace
# ---------------------------------------------------------------------------
echo "=== Copying TLS secret to gpu-operator namespace ==="
# Rename keys to valid bash identifiers so secretEnv can inject them directly.
# ca.crt → DRIVER_CACHE_CA_PEM, client.crt → DRIVER_CACHE_CERT_PEM, client.key → DRIVER_CACHE_KEY_PEM
kubectl get secret driver-cache-tls -n nvidia-driver-cache -o json \
    | jq 'del(.metadata.creationTimestamp,.metadata.resourceVersion,.metadata.uid,.metadata.managedFields)
          | .metadata.namespace = "gpu-operator"
          | .data = {
              "DRIVER_CACHE_CA_PEM":   .data["ca.crt"],
              "DRIVER_CACHE_CERT_PEM": .data["client.crt"],
              "DRIVER_CACHE_KEY_PEM":  .data["client.key"]
            }' \
    | kubectl apply -f -

# ---------------------------------------------------------------------------
# 3. Install GPU Operator with runtime cache values
# ---------------------------------------------------------------------------
echo "=== Installing GPU Operator (runtime compilation + cache) ==="
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
helm upgrade --install -n gpu-operator gpu-operator nvidia/gpu-operator \
    --values "${REPO_ROOT}/helm/gpu-operator-values-runtime.yaml"

# ---------------------------------------------------------------------------
# 4. Wait for the first driver pod (cold miss — compiles the driver)
# ---------------------------------------------------------------------------
echo "=== Waiting for first driver pod (cold miss — up to 35 min) ==="
# The GPU Operator controller creates the driver DaemonSet asynchronously after
# the ClusterPolicy is reconciled; kubectl wait exits immediately with an error
# if no matching pods exist yet.  Poll until at least one pod appears, then wait.
DEADLINE=$(( $(date +%s) + 35*60 ))
until kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset --no-headers 2>/dev/null | grep -q .; do
    [[ $(date +%s) -lt ${DEADLINE} ]] || { echo "ERROR: timed out waiting for driver pod to appear" >&2; exit 1; }
    sleep 10
done
kubectl wait pod \
    -n gpu-operator \
    -l app=nvidia-driver-daemonset \
    --for=condition=Ready \
    --timeout=$(( DEADLINE - $(date +%s) ))s

# ---------------------------------------------------------------------------
# 5. Assert [CACHE] miss and nvidia-smi
# ---------------------------------------------------------------------------
FIRST_POD=$(kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset \
    -o jsonpath='{.items[0].metadata.name}')
echo "=== Asserting cache miss on ${FIRST_POD} ==="
kubectl logs -n gpu-operator "${FIRST_POD}" -c nvidia-driver-ctr \
    | grep -F "[CACHE] miss"
kubectl exec -n gpu-operator "${FIRST_POD}" -c nvidia-driver-ctr -- nvidia-smi
echo "PASS: cold miss + nvidia-smi OK"

# ---------------------------------------------------------------------------
# 6. Wait for the push to land, then restart the DaemonSet
# ---------------------------------------------------------------------------
# The cold-miss pod pushes the compiled driver to the cache as a fire-and-forget
# background job.  Wait for a successful PUT to appear in the registry pod's log
# before triggering the rollout; otherwise the replacement pod may start its pull
# before the push completes and will recompile instead of hitting the cache.
CACHE_TAG=$(kubectl logs -n gpu-operator "${FIRST_POD}" -c nvidia-driver-ctr \
    | grep -oP '(?<=\[CACHE\] miss key=)\S+')
echo "=== Waiting for cache push to land (tag: ${CACHE_TAG}) ==="
REGISTRY_POD=$(kubectl get pods -n nvidia-driver-cache -l app.kubernetes.io/name=driver-cache \
    -o jsonpath='{.items[0].metadata.name}')
PUSH_DEADLINE=$(( $(date +%s) + 5*60 ))
until kubectl logs -n nvidia-driver-cache "${REGISTRY_POD}" -c registry 2>/dev/null \
        | grep -q "\"http.request.method\":\"PUT\".*\"vars.reference\":\"${CACHE_TAG}\".*\"http.response.status\":201"; do
    [[ $(date +%s) -lt ${PUSH_DEADLINE} ]] || { echo "ERROR: timed out waiting for cache push" >&2; exit 1; }
    sleep 5
done
echo "Cache push confirmed."

# Use rollout restart rather than kubectl delete pod so the k8s-driver-manager
# init container runs first: it evicts GPU workloads and unloads kernel modules
# before nvidia-driver-ctr starts, which is the production upgrade code path and
# allows the lsmod guard in load_install_gpu_driver.sh to pass cleanly.
echo "=== Rolling restart of driver DaemonSet to trigger cache-hit run ==="
kubectl rollout restart daemonset/nvidia-driver-daemonset -n gpu-operator
kubectl wait pod -n gpu-operator "${FIRST_POD}" --for=delete --timeout=5m

echo "=== Waiting for replacement driver pod (cache hit — up to 10 min) ==="
kubectl wait pod \
    -n gpu-operator \
    -l app=nvidia-driver-daemonset \
    --for=condition=Ready \
    --timeout=10m

# ---------------------------------------------------------------------------
# 7. Assert [CACHE] hit and nvidia-smi
# ---------------------------------------------------------------------------
SECOND_POD=$(kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset \
    -o jsonpath='{.items[0].metadata.name}')
echo "=== Asserting cache hit on ${SECOND_POD} ==="
kubectl logs -n gpu-operator "${SECOND_POD}" -c nvidia-driver-ctr \
    | grep -F "[CACHE] hit"
kubectl exec -n gpu-operator "${SECOND_POD}" -c nvidia-driver-ctr -- nvidia-smi
echo "PASS: cache hit + nvidia-smi OK"
