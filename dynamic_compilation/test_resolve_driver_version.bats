#!/usr/bin/env bats
#
# Tests for resolve_driver_version() in dynamic_compilation/load_install_gpu_driver.sh
#
# Run from repo root: test/bats/bin/bats dynamic_compilation/test_resolve_driver_version.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="${REPO_ROOT}/dynamic_compilation/resolve_driver_version.sh"

load "${REPO_ROOT}/test/test_helper/bats-support/load"
load "${REPO_ROOT}/test/test_helper/bats-assert/load"

setup() {
    RUNSC_EXIT_CODE=0
    RUNSC_OUTPUT=""
    nsenter() { echo "${RUNSC_OUTPUT}"; return "${RUNSC_EXIT_CODE}"; }
    # shellcheck disable=SC1090
    . "${SCRIPT}"
}

# ---------------------------------------------------------------------------
# runsc unavailable
# ---------------------------------------------------------------------------

@test "runsc unavailable: integer version is left unchanged" {
    RUNSC_EXIT_CODE=1
    DRIVER_VERSION=560
    resolve_driver_version
    assert_equal "$DRIVER_VERSION" "560"
}

@test "runsc unavailable: full semver is left unchanged" {
    RUNSC_EXIT_CODE=1
    DRIVER_VERSION=560.35.03
    resolve_driver_version
    assert_equal "$DRIVER_VERSION" "560.35.03"
}

# ---------------------------------------------------------------------------
# Integer DRIVER_VERSION
# ---------------------------------------------------------------------------

@test "integer: picks latest version matching major" {
    RUNSC_OUTPUT="$(printf '560.28.03\n560.35.03\n560.94.02\n570.00.01\n')"
    DRIVER_VERSION=560
    resolve_driver_version
    assert_equal "$DRIVER_VERSION" "560.94.02"
}

@test "integer: errors when no version matches major" {
    RUNSC_OUTPUT="$(printf '570.00.01\n570.86.10\n')"
    DRIVER_VERSION=560
    run resolve_driver_version
    assert_failure
    assert_output --partial "[ERROR]"
}

# ---------------------------------------------------------------------------
# Full semver DRIVER_VERSION
# ---------------------------------------------------------------------------

@test "semver: exact match is selected" {
    RUNSC_OUTPUT="$(printf '560.28.03\n560.35.03\n560.94.02\n')"
    DRIVER_VERSION=560.35.03
    resolve_driver_version
    assert_equal "$DRIVER_VERSION" "560.35.03"
}

@test "semver: picks latest supported version below target when no exact match" {
    RUNSC_OUTPUT="$(printf '560.28.03\n560.35.03\n560.94.02\n')"
    DRIVER_VERSION=560.50.00
    resolve_driver_version
    assert_equal "$DRIVER_VERSION" "560.35.03"
}

@test "semver: picks latest when target equals highest supported version" {
    RUNSC_OUTPUT="$(printf '560.28.03\n560.35.03\n560.94.02\n')"
    DRIVER_VERSION=560.94.02
    resolve_driver_version
    assert_equal "$DRIVER_VERSION" "560.94.02"
}

@test "semver: errors when no same-major version is <= target" {
    RUNSC_OUTPUT="$(printf '560.28.03\n560.35.03\n')"
    DRIVER_VERSION=560.10.00
    run resolve_driver_version
    assert_failure
    assert_output --partial "[ERROR]"
}

@test "semver: errors when only a lower major version is available" {
    RUNSC_OUTPUT="$(printf '550.90.07\n560.28.03\n560.35.03\n')"
    DRIVER_VERSION=560.10.00
    run resolve_driver_version
    assert_failure
    assert_output --partial "[ERROR]"
}

@test "semver: errors when all supported versions are above target" {
    RUNSC_OUTPUT="$(printf '570.00.01\n570.86.10\n')"
    DRIVER_VERSION=560.35.03
    run resolve_driver_version
    assert_failure
    assert_output --partial "[ERROR]"
}
