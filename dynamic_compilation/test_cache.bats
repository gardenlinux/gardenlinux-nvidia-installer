#!/usr/bin/env bats
#
# Tests for compute_cache_tag() and verify_artifact() in dynamic_compilation/cache.sh
#
# Run from repo root: test/bats/bin/bats dynamic_compilation/test_cache.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="${REPO_ROOT}/dynamic_compilation/cache.sh"

load "${REPO_ROOT}/test/test_helper/bats-support/load"
load "${REPO_ROOT}/test/test_helper/bats-assert/load"

setup() {
    # shellcheck disable=SC1090
    . "${SCRIPT}"
}

# ---------------------------------------------------------------------------
# compute_cache_tag
# ---------------------------------------------------------------------------

@test "compute_cache_tag: basic tag" {
    run compute_cache_tag "6.1.0-1-cloud-amd64" "560.35.03" "open" "amd64"
    assert_success
    assert_output "560.35.03-open-amd64-6.1.0-1-cloud-amd64"
}

@test "compute_cache_tag: slashes in kernel release are replaced with dashes" {
    run compute_cache_tag "6.1.0/cloud/amd64" "560.35.03" "open" "amd64"
    assert_success
    assert_output "560.35.03-open-amd64-6.1.0-cloud-amd64"
}

@test "compute_cache_tag: multiple slashes are all replaced" {
    run compute_cache_tag "a/b/c" "570.00.01" "proprietary" "arm64"
    assert_success
    assert_output "570.00.01-proprietary-arm64-a-b-c"
}

@test "compute_cache_tag: kernel release without slashes is unchanged" {
    run compute_cache_tag "5.15.0-91-generic" "550.90.07" "proprietary" "amd64"
    assert_success
    assert_output "550.90.07-proprietary-amd64-5.15.0-91-generic"
}

@test "compute_cache_tag: arm64 arch is preserved" {
    run compute_cache_tag "6.6.0-1-cloud-arm64" "560.94.02" "open" "arm64"
    assert_success
    assert_output "560.94.02-open-arm64-6.6.0-1-cloud-arm64"
}

# ---------------------------------------------------------------------------
# verify_artifact
# ---------------------------------------------------------------------------

setup_fixture() {
    FIXTURE_DIR="$(mktemp -d)"
    KERNEL="$(uname -r)"
}

teardown_fixture() {
    rm -rf "${FIXTURE_DIR}"
}

make_archive() {
    local archive="$1"
    shift
    # Create files specified as relative paths, then tar them
    local tmpdir
    tmpdir="$(mktemp -d)"
    for f in "$@"; do
        mkdir -p "${tmpdir}/$(dirname "${f}")"
        touch "${tmpdir}/${f}"
    done
    tar -czf "${archive}" -C "${tmpdir}" .
    rm -rf "${tmpdir}"
}

@test "verify_artifact: passes for archive with matching .ko file" {
    setup_fixture
    local archive="${FIXTURE_DIR}/driver.tar.gz"
    make_archive "${archive}" "lib/modules/${KERNEL}/nvidia.ko"
    run verify_artifact "${archive}"
    assert_success
    teardown_fixture
}

@test "verify_artifact: fails for archive with .ko from wrong kernel" {
    setup_fixture
    local archive="${FIXTURE_DIR}/driver.tar.gz"
    make_archive "${archive}" "lib/modules/9.9.9-wrong/nvidia.ko"
    run verify_artifact "${archive}"
    assert_failure
    assert_output --partial "[ERROR]"
    teardown_fixture
}

@test "verify_artifact: fails for archive with no .ko files" {
    setup_fixture
    local archive="${FIXTURE_DIR}/driver.tar.gz"
    make_archive "${archive}" "lib/modules/${KERNEL}/nvidia.so"
    run verify_artifact "${archive}"
    assert_failure
    assert_output --partial "[ERROR]"
    teardown_fixture
}

@test "verify_artifact: fails for empty path argument" {
    run verify_artifact ""
    assert_failure
    assert_output --partial "[ERROR]"
}

@test "verify_artifact: fails for missing archive file" {
    run verify_artifact "/nonexistent/path/driver.tar.gz"
    assert_failure
    assert_output --partial "[ERROR]"
}

@test "verify_artifact: fails for corrupt archive" {
    setup_fixture
    local archive="${FIXTURE_DIR}/corrupt.tar.gz"
    echo "not a real tarball" > "${archive}"
    run verify_artifact "${archive}"
    assert_failure
    assert_output --partial "[ERROR]"
    teardown_fixture
}
