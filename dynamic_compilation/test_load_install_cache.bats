#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # bats @test blocks run in subshells; variable-locality warnings are expected
#
# Tests for the cache wiring inside _run_cache_or_compile() in
# dynamic_compilation/load_install_gpu_driver.sh
#
# Run from repo root: test/bats/bin/bats dynamic_compilation/test_load_install_cache.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="${REPO_ROOT}/dynamic_compilation/load_install_gpu_driver.sh"

load "${REPO_ROOT}/test/test_helper/bats-support/load"
load "${REPO_ROOT}/test/test_helper/bats-assert/load"

setup() {
    # Mock BIN_DIR so set_env_vars.sh and compile.sh are under our control.
    MOCK_BIN_DIR="$(mktemp -d)"

    cat >"${MOCK_BIN_DIR}/set_env_vars.sh" <<'EOF'
#!/bin/bash
export DEBUG="${DEBUG:-false}"
export DRIVER_NAME="driver"
export DRIVER_VERSION="${DRIVER_VERSION:-560.35.03}"
export KERNEL_NAME="${KERNEL_NAME:-6.1.0-1-cloud-amd64}"
export ARCH_TYPE="${ARCH_TYPE:-amd64}"
export INSTALL_DIR="${INSTALL_DIR:-/tmp/test-nvidia}"
export NVIDIA_ROOT="${INSTALL_DIR}/driver"
export LD_LIBRARY_PATH="${NVIDIA_ROOT}/lib"
EOF

    # compile.sh reads its desired exit code from a temp file so that both
    # direct calls and run-captured subshell calls behave identically.
    COMPILE_STATUS_FILE="${BATS_TEST_TMPDIR}/compile_exit"
    echo 0 > "${COMPILE_STATUS_FILE}"

    cat >"${MOCK_BIN_DIR}/compile.sh" <<EOF
#!/bin/bash
echo "compile.sh called with: \$*"
exit \$(cat "${COMPILE_STATUS_FILE}" 2>/dev/null || echo 0)
EOF
    chmod +x "${MOCK_BIN_DIR}/compile.sh"

    export BIN_DIR="${MOCK_BIN_DIR}"

    # Source the script. The BASH_SOURCE guard prevents main() from running.
    # shellcheck disable=SC1090
    . "${SCRIPT}"
    set +e  # script activates set -e; disable so tests can inspect non-zero returns

    # Override _SCRIPT_DIR so _run_cache_or_compile sources our mock cache.sh
    # rather than the real one (which would overwrite the function mocks below).
    MOCK_SCRIPT_DIR="$(mktemp -d)"
    _SCRIPT_DIR="${MOCK_SCRIPT_DIR}"

    # Write a mock cache.sh whose functions read PULL_EXIT_CODE / WAIT_EXIT_CODE
    # from the shell environment so each test can control behaviour without
    # re-writing files.
    cat >"${MOCK_SCRIPT_DIR}/cache.sh" <<'EOF'
#!/bin/bash
compute_cache_tag() { echo "${2}-${3}-${4}-${1}"; }
pull_from_cache()             { [[ "${PULL_EXIT_CODE:-0}" -eq 0 ]]; }
push_to_cache()               { echo "push_to_cache called with: $*"; return 0; }
wait_for_cache_on_compile_fail() { [[ "${WAIT_EXIT_CODE:-0}" -eq 0 ]]; }
EOF

    # Env vars _run_cache_or_compile reads (exported so subshells and sourced fns see them)
    export KERNEL_NAME="6.1.0-1-cloud-amd64"
    export DRIVER_VERSION="560.35.03"
    export KERNEL_MODULE_TYPE="open"
    export ARCH_TYPE="amd64"
    export NVIDIA_BIN="/tmp/test-nvidia-bin"
    unset DRIVER_CACHE_REGISTRY

    PULL_EXIT_CODE=0
    WAIT_EXIT_CODE=0
}

teardown() {
    rm -rf "${MOCK_BIN_DIR:-}" "${MOCK_SCRIPT_DIR:-}"
}

# ---------------------------------------------------------------------------
# Kill switch: DRIVER_CACHE_REGISTRY unset or empty
# ---------------------------------------------------------------------------

@test "no DRIVER_CACHE_REGISTRY: compile.sh is called" {
    DRIVER_CACHE_REGISTRY=""
    run _run_cache_or_compile
    assert_success
    assert_output --partial "compile.sh called"
}

@test "no DRIVER_CACHE_REGISTRY: no [CACHE] log lines emitted" {
    DRIVER_CACHE_REGISTRY=""
    run _run_cache_or_compile
    refute_output --partial "[CACHE]"
}

# ---------------------------------------------------------------------------
# Cache Hit
# ---------------------------------------------------------------------------

@test "cache hit: compile.sh is NOT called" {
    DRIVER_CACHE_REGISTRY="registry.example.com/cache"
    PULL_EXIT_CODE=0
    run _run_cache_or_compile
    assert_success
    refute_output --partial "compile.sh called"
}

@test "cache hit: emits [CACHE] hit log line" {
    DRIVER_CACHE_REGISTRY="registry.example.com/cache"
    PULL_EXIT_CODE=0
    run _run_cache_or_compile
    assert_success
    assert_output --partial "[CACHE] hit key=560.35.03-open-amd64-6.1.0-1-cloud-amd64"
}

@test "cache hit: _COMPILED is 0" {
    DRIVER_CACHE_REGISTRY="registry.example.com/cache"
    PULL_EXIT_CODE=0
    _run_cache_or_compile
    assert_equal "${_COMPILED}" "0"
}

# ---------------------------------------------------------------------------
# Cache Miss → compile success
# ---------------------------------------------------------------------------

@test "cache miss: compile.sh is called" {
    DRIVER_CACHE_REGISTRY="registry.example.com/cache"
    PULL_EXIT_CODE=1
    run _run_cache_or_compile
    assert_success
    assert_output --partial "compile.sh called"
}

@test "cache miss: emits [CACHE] miss — compiled log line" {
    DRIVER_CACHE_REGISTRY="registry.example.com/cache"
    PULL_EXIT_CODE=1
    run _run_cache_or_compile
    assert_success
    assert_output --partial "[CACHE] miss key=560.35.03-open-amd64-6.1.0-1-cloud-amd64 — compiled"
}

@test "cache miss: _COMPILED is 1 after successful compile" {
    DRIVER_CACHE_REGISTRY="registry.example.com/cache"
    PULL_EXIT_CODE=1
    _run_cache_or_compile
    assert_equal "${_COMPILED}" "1"
}

@test "cache miss: _CACHE_REF is set to registry/driver:tag" {
    DRIVER_CACHE_REGISTRY="registry.example.com/cache"
    PULL_EXIT_CODE=1
    _run_cache_or_compile
    assert_equal "${_CACHE_REF}" "registry.example.com/cache/driver:560.35.03-open-amd64-6.1.0-1-cloud-amd64"
}

# ---------------------------------------------------------------------------
# Compile failure → fallback hit
# ---------------------------------------------------------------------------

@test "compile fail + fallback hit: emits compile-failed fallback-hit log line" {
    DRIVER_CACHE_REGISTRY="registry.example.com/cache"
    PULL_EXIT_CODE=1
    echo 1 > "${COMPILE_STATUS_FILE}"
    WAIT_EXIT_CODE=0
    run _run_cache_or_compile
    assert_success
    assert_output --partial "[CACHE] compile-failed key=560.35.03-open-amd64-6.1.0-1-cloud-amd64 — fallback-hit"
}

@test "compile fail + fallback hit: _COMPILED is 0 (driver came from cache)" {
    DRIVER_CACHE_REGISTRY="registry.example.com/cache"
    PULL_EXIT_CODE=1
    echo 1 > "${COMPILE_STATUS_FILE}"
    WAIT_EXIT_CODE=0
    _run_cache_or_compile
    assert_equal "${_COMPILED}" "0"
}

# ---------------------------------------------------------------------------
# Compile failure → fallback timeout
# ---------------------------------------------------------------------------

@test "compile fail + fallback timeout: exits non-zero with fallback-timeout log line" {
    # shellcheck disable=SC2034
    DRIVER_CACHE_REGISTRY="registry.example.com/cache"
    # shellcheck disable=SC2034
    PULL_EXIT_CODE=1
    echo 1 > "${COMPILE_STATUS_FILE}"
    # shellcheck disable=SC2034
    WAIT_EXIT_CODE=1
    run _run_cache_or_compile
    assert_failure
    assert_output --partial "[CACHE] compile-failed key=560.35.03-open-amd64-6.1.0-1-cloud-amd64 — fallback-timeout"
}

# ---------------------------------------------------------------------------
# _setup_cache_tls: PEM env vars → temp cert files
# ---------------------------------------------------------------------------

@test "_setup_cache_tls: no-op when DRIVER_CACHE_REGISTRY is unset" {
    unset DRIVER_CACHE_REGISTRY
    export DRIVER_CACHE_CA_PEM="fake-ca"
    _setup_cache_tls
    assert [ -z "${DRIVER_CACHE_CA_FILE:-}" ]
}

@test "_setup_cache_tls: no-op when no PEM vars are set" {
    export DRIVER_CACHE_REGISTRY="registry.example.com/cache"
    unset DRIVER_CACHE_CA_PEM DRIVER_CACHE_CERT_PEM DRIVER_CACHE_KEY_PEM
    _setup_cache_tls
    assert [ -z "${DRIVER_CACHE_CA_FILE:-}" ]
    assert [ -z "${DRIVER_CACHE_CERT_FILE:-}" ]
    assert [ -z "${DRIVER_CACHE_KEY_FILE:-}" ]
}

@test "_setup_cache_tls: writes CA PEM to file and sets DRIVER_CACHE_CA_FILE" {
    export DRIVER_CACHE_REGISTRY="registry.example.com/cache"
    export DRIVER_CACHE_CA_PEM="-----BEGIN CERTIFICATE-----
fake-ca-content
-----END CERTIFICATE-----"
    unset DRIVER_CACHE_CERT_PEM DRIVER_CACHE_KEY_PEM
    _setup_cache_tls
    assert [ -n "${DRIVER_CACHE_CA_FILE:-}" ]
    assert [ -f "${DRIVER_CACHE_CA_FILE}" ]
    run grep -c "fake-ca-content" "${DRIVER_CACHE_CA_FILE}"
    assert_success
}

@test "_setup_cache_tls: writes all three PEM vars to separate files" {
    export DRIVER_CACHE_REGISTRY="registry.example.com/cache"
    export DRIVER_CACHE_CA_PEM="ca-pem"
    export DRIVER_CACHE_CERT_PEM="cert-pem"
    export DRIVER_CACHE_KEY_PEM="key-pem"
    _setup_cache_tls
    assert [ -f "${DRIVER_CACHE_CA_FILE}" ]
    assert [ -f "${DRIVER_CACHE_CERT_FILE}" ]
    assert [ -f "${DRIVER_CACHE_KEY_FILE}" ]
    # Files must be in the same temp directory
    assert_equal "$(dirname "${DRIVER_CACHE_CA_FILE}")" "$(dirname "${DRIVER_CACHE_CERT_FILE}")"
    assert_equal "$(dirname "${DRIVER_CACHE_CA_FILE}")" "$(dirname "${DRIVER_CACHE_KEY_FILE}")"
}
