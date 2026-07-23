#!/usr/bin/env bats
#
# Tests for functions in .ci/helm_test.sh
#
# Run from repo root: test/bats/bin/bats test/bats/test_helm_test.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/.ci/helm_test.sh"

load "${REPO_ROOT}/test/test_helper/bats-support/load"
load "${REPO_ROOT}/test/test_helper/bats-assert/load"

setup() {
    kubectl() { echo ""; }
    # shellcheck disable=SC1090
    . "${SCRIPT}"
    LOG_FILE="${BATS_TEST_TMPDIR}/test-output.log"
}

# ---------------------------------------------------------------------------
# evaluate_helm_test_output
# ---------------------------------------------------------------------------

@test "evaluate_helm_test_output: clean log and exit 0 passes" {
    echo "Suite passed" > "$LOG_FILE"
    run evaluate_helm_test_output "$LOG_FILE" 0
    assert_success
}

@test "evaluate_helm_test_output: FAILED in log causes failure" {
    echo "FAILED: some-test" > "$LOG_FILE"
    run evaluate_helm_test_output "$LOG_FILE" 0
    assert_failure
    assert_output --partial "Test output indicates failure"
}

@test "evaluate_helm_test_output: Error in log causes failure" {
    echo "Error running pod" > "$LOG_FILE"
    run evaluate_helm_test_output "$LOG_FILE" 0
    assert_failure
    assert_output --partial "Test output indicates failure"
}

@test "evaluate_helm_test_output: non-zero exit code causes failure" {
    echo "Suite passed" > "$LOG_FILE"
    run evaluate_helm_test_output "$LOG_FILE" 1
    assert_failure
    assert_output --partial "exit code: 1"
}

@test "evaluate_helm_test_output: missing log file causes failure" {
    run evaluate_helm_test_output "/nonexistent/path.log" 0
    assert_failure
    assert_output --partial "Log file not found"
}

# ---------------------------------------------------------------------------
# check_pod_statuses
# ---------------------------------------------------------------------------

@test "check_pod_statuses: all Succeeded pods pass" {
    kubectl() {
        case "$*" in
            "get pods -n gpu-operator -l app=test -o jsonpath={.items[*].metadata.name}")
                echo "pod-a pod-b" ;;
            "get pod pod-a -n gpu-operator -o jsonpath={.status.phase}")
                echo "Succeeded" ;;
            "get pod pod-b -n gpu-operator -o jsonpath={.status.phase}")
                echo "Succeeded" ;;
        esac
    }
    run check_pod_statuses "gpu-operator" "app=test"
    assert_success
}

@test "check_pod_statuses: Failed pod causes failure with pod name" {
    kubectl() {
        case "$*" in
            "get pods -n gpu-operator -l app=test -o jsonpath={.items[*].metadata.name}")
                echo "pod-a" ;;
            "get pod pod-a -n gpu-operator -o jsonpath={.status.phase}")
                echo "Failed" ;;
        esac
    }
    run check_pod_statuses "gpu-operator" "app=test"
    assert_failure
    assert_output --partial "pod-a"
    assert_output --partial "Failed"
}

@test "check_pod_statuses: no matching pods passes" {
    kubectl() {
        case "$*" in
            "get pods -n gpu-operator -l app=test -o jsonpath={.items[*].metadata.name}")
                echo "" ;;
        esac
    }
    run check_pod_statuses "gpu-operator" "app=test"
    assert_success
}
