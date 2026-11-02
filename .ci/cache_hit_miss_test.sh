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
    --create-namespace

# Wait for the PVC to be Bound before Helm --wait tries to schedule the pod.
# On Cinder-backed clusters the volume can stay in "creating" for several
# minutes; Kubernetes will retry the attach but emit FailedAttachVolume warnings
# until the volume is available. Polling the PVC first avoids that race.
echo "=== Waiting for PVC driver-cache to be Bound (up to 10 min) ==="
kubectl wait pvc driver-cache \
    -n nvidia-driver-cache \
    --for=jsonpath='{.status.phase}'=Bound \
    --timeout=10m

echo "=== Waiting for driver-cache pod to be Ready ==="
kubectl rollout status deployment/driver-cache \
    -n nvidia-driver-cache \
    --timeout=5m

# ---------------------------------------------------------------------------
# 2. Cross-copy TLS secret into gpu-operator namespace
# ---------------------------------------------------------------------------
echo "=== Copying TLS secret to gpu-operator namespace ==="
kubectl get secret driver-cache-tls -n nvidia-driver-cache -o json \
    | jq 'del(.metadata.creationTimestamp,.metadata.resourceVersion,.metadata.uid,.metadata.managedFields)
          | .metadata.namespace = "gpu-operator"' \
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
kubectl wait pod \
    -n gpu-operator \
    -l app=nvidia-driver-daemonset \
    --for=condition=Ready \
    --timeout=35m

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
# 6. Delete the pod; wait for replacement (cache hit — pulls from registry)
# ---------------------------------------------------------------------------
echo "=== Deleting ${FIRST_POD} to trigger cache-hit run ==="
kubectl delete pod -n gpu-operator "${FIRST_POD}"
kubectl wait pod -n gpu-operator "${FIRST_POD}" --for=delete --timeout=2m

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
