#!/usr/bin/env bash
# Helm test result evaluation for test_installer CI job.
# Sourced by CI steps and bats tests — not executed directly.
set -euo pipefail

# evaluate_helm_test_output LOG_FILE HELM_EXIT_CODE
# Returns 0 if tests passed, 1 on any failure.
# Pure function — reads the log file, no helm or kubectl calls.
evaluate_helm_test_output() {
    local log_file="$1"
    local helm_exit_code="$2"

    if [[ ! -f "$log_file" ]]; then
        echo "Log file not found: $log_file"
        return 1
    fi

    if grep -q "FAILED" "$log_file" || grep -q "Error" "$log_file"; then
        echo "Test output indicates failure"
        return 1
    fi

    if [[ "$helm_exit_code" -ne 0 ]]; then
        echo "Helm test command failed with exit code: $helm_exit_code"
        return 1
    fi

    return 0
}

# check_pod_statuses NAMESPACE LABEL_SELECTOR
# Iterates all pods matching LABEL_SELECTOR in NAMESPACE.
# Returns 1 if any pod is not in Succeeded phase.
check_pod_statuses() {
    local namespace="$1"
    local selector="$2"

    local pods
    # shellcheck disable=SC2086
    pods=$(kubectl get pods -n "$namespace" -l "$selector" \
        -o jsonpath='{.items[*].metadata.name}')

    local pod status
    for pod in $pods; do
        status=$(kubectl get pod "$pod" -n "$namespace" \
            -o jsonpath='{.status.phase}')
        if [[ "$status" != "Succeeded" ]]; then
            echo "Test pod $pod failed with status: $status"
            return 1
        fi
    done
}
