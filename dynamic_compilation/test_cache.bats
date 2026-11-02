#!/usr/bin/env bats
#
# Tests for cache.sh: compute_cache_tag, verify_artifact, pull_from_cache,
# push_to_cache, wait_for_cache_on_compile_fail
#
# Run from repo root: test/bats/bin/bats dynamic_compilation/test_cache.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="${REPO_ROOT}/dynamic_compilation/cache.sh"

load "${REPO_ROOT}/test/test_helper/bats-support/load"
load "${REPO_ROOT}/test/test_helper/bats-assert/load"

setup() {
    TEST_STAGING_DIR="$(mktemp -d)"
    DRIVER_CACHE_STAGING_DIR="${TEST_STAGING_DIR}"

    ORAS_PULL_EXIT_CODE=0
    ORAS_PUSH_EXIT_CODE=0
    ORAS_PULL_VALID=true   # true = valid .ko archive; false = wrong-kernel archive

    oras() {
        local subcmd="$1"; shift
        case "${subcmd}" in
        pull)
            local outdir="" prev=""
            for arg in "$@"; do
                [[ "${prev}" == "--output" ]] && outdir="${arg}"
                prev="${arg}"
            done
            if [[ "${ORAS_PULL_EXIT_CODE}" -eq 0 && -n "${outdir}" ]]; then
                if [[ "${ORAS_PULL_VALID}" == "true" ]]; then
                    make_archive "${outdir}/driver.tar.gz" "lib/modules/$(uname -r)/nvidia.ko"
                else
                    make_archive "${outdir}/driver.tar.gz" "lib/modules/9.9.9-wrong/nvidia.ko"
                fi
            fi
            return "${ORAS_PULL_EXIT_CODE}"
            ;;
        push)
            return "${ORAS_PUSH_EXIT_CODE}"
            ;;
        *)
            return 1
            ;;
        esac
    }

    timeout() { local _dur="$1"; shift; "$@"; }
    sleep() { :; }

    # shellcheck disable=SC1090
    . "${SCRIPT}"
}

teardown() {
    rm -rf "${TEST_STAGING_DIR:-}"
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

# ---------------------------------------------------------------------------
# pull_from_cache
# ---------------------------------------------------------------------------

@test "pull_from_cache: returns non-zero when oras fails both attempts" {
    ORAS_PULL_EXIT_CODE=1
    run pull_from_cache "registry/repo:tag"
    assert_failure
    assert_output --partial "[ERROR]"
}

@test "pull_from_cache: returns non-zero on timeout (both attempts time out)" {
    timeout() { return 124; }
    run pull_from_cache "registry/repo:tag"
    assert_failure
    assert_output --partial "[ERROR]"
}

@test "pull_from_cache: returns non-zero when verify_artifact fails (wrong-kernel archive)" {
    ORAS_PULL_VALID=false
    run pull_from_cache "registry/repo:tag"
    assert_failure
    assert_output --partial "[ERROR]"
}

@test "pull_from_cache: returns 0 and staging dir has kernel module on clean pull" {
    run pull_from_cache "registry/repo:tag"
    assert_success
    [[ -f "${DRIVER_CACHE_STAGING_DIR}/lib/modules/$(uname -r)/nvidia.ko" ]]
}

# ---------------------------------------------------------------------------
# push_to_cache
# ---------------------------------------------------------------------------

@test "push_to_cache: returns 0 even when oras push fails (fire-and-forget)" {
    ORAS_PUSH_EXIT_CODE=1
    local driver_dir
    driver_dir="$(mktemp -d)"
    mkdir -p "${driver_dir}/lib/modules"
    touch "${driver_dir}/lib/modules/nvidia.ko"
    run push_to_cache "registry/repo:tag" "${driver_dir}" \
        "6.1.0-1-cloud-amd64" "560.35.03" "open" "amd64"
    assert_success
    rm -rf "${driver_dir}"
}

@test "push_to_cache: returns 0 when oras push succeeds" {
    ORAS_PUSH_EXIT_CODE=0
    local driver_dir
    driver_dir="$(mktemp -d)"
    touch "${driver_dir}/dummy"
    run push_to_cache "registry/repo:tag" "${driver_dir}" \
        "6.1.0-1-cloud-amd64" "560.35.03" "open" "amd64"
    assert_success
    rm -rf "${driver_dir}"
}

# ---------------------------------------------------------------------------
# wait_for_cache_on_compile_fail
# ---------------------------------------------------------------------------

@test "wait_for_cache_on_compile_fail: returns success when hit arrives mid-window" {
    local call_file="${BATS_TEST_TMPDIR}/calls"
    echo 0 > "${call_file}"
    pull_from_cache() {
        local n
        n=$(( $(cat "${call_file}") + 1 ))
        echo "${n}" > "${call_file}"
        [[ "${n}" -ge 3 ]] && return 0
        return 1
    }
    DRIVER_CACHE_COMPILE_FAIL_POLL_INTERVAL=1
    DRIVER_CACHE_COMPILE_FAIL_WAIT_SECS=10
    run wait_for_cache_on_compile_fail "registry/repo:tag"
    assert_success
}

@test "wait_for_cache_on_compile_fail: returns non-zero after window is exhausted" {
    pull_from_cache() { return 1; }
    DRIVER_CACHE_COMPILE_FAIL_POLL_INTERVAL=1
    DRIVER_CACHE_COMPILE_FAIL_WAIT_SECS=3
    run wait_for_cache_on_compile_fail "registry/repo:tag"
    assert_failure
    assert_output --partial "[ERROR]"
}

@test "wait_for_cache_on_compile_fail: respects POLL_INTERVAL and WAIT_SECS overrides" {
    local call_file="${BATS_TEST_TMPDIR}/calls"
    echo 0 > "${call_file}"
    pull_from_cache() {
        local n
        n=$(( $(cat "${call_file}") + 1 ))
        echo "${n}" > "${call_file}"
        return 1
    }
    # interval=3, max=10 → iterations at elapsed 0,3,6,9 → 4 calls before elapsed=12≥10
    # shellcheck disable=SC2034
    DRIVER_CACHE_COMPILE_FAIL_POLL_INTERVAL=3
    # shellcheck disable=SC2034
    DRIVER_CACHE_COMPILE_FAIL_WAIT_SECS=10
    run wait_for_cache_on_compile_fail "registry/repo:tag"
    assert_failure
    assert_equal "$(cat "${call_file}")" "4"
}
