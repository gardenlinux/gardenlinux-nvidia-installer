#!/bin/bash
# Sourced by load_install_gpu_driver.sh and test_cache.bats

# compute_cache_tag: maps {kernel-release, driver-patch-version, kernel-module-type, arch}
# to an OCI tag of the form {driver-patch}-{module-type}-{arch}-{kernel-release-normalized}.
# Slashes in the kernel release are replaced with '-'.
compute_cache_tag() {
    local kernel_release="$1"
    local driver_version="$2"
    local kernel_module_type="$3"
    local arch="$4"
    local normalized_kernel="${kernel_release//\//-}"
    echo "${driver_version}-${kernel_module_type}-${arch}-${normalized_kernel}"
}

# verify_artifact: checks that the archive at $1 contains at least one .ko file
# whose path includes the running kernel release (uname -r).
# Returns non-zero for wrong-kernel, no-.ko, empty path, or corrupt/missing archive.
verify_artifact() {
    local archive="$1"
    if [[ -z "${archive}" ]]; then
        echo "[ERROR] verify_artifact: no archive path given" >&2
        return 1
    fi
    if [[ ! -f "${archive}" ]]; then
        echo "[ERROR] verify_artifact: archive not found: ${archive}" >&2
        return 1
    fi
    local kernel
    kernel=$(uname -r)
    local listing
    if ! listing=$(tar -tzf "${archive}" 2>/dev/null); then
        echo "[ERROR] verify_artifact: corrupt or unreadable archive: ${archive}" >&2
        return 1
    fi
    if ! echo "${listing}" | grep "\.ko" | grep -q "${kernel}"; then
        echo "[ERROR] verify_artifact: no .ko file matching kernel '${kernel}' in archive" >&2
        return 1
    fi
    return 0
}

pull_from_cache() {
    local ref="$1"
    local staging_dir="${DRIVER_CACHE_STAGING_DIR:-/run/nvidia/.staging-driver}"
    local tmpdir
    tmpdir=$(mktemp -d)

    local tls_args=()
    [[ -n "${DRIVER_CACHE_CERT_FILE:-}" ]] && tls_args+=(--cert-file "${DRIVER_CACHE_CERT_FILE}")
    [[ -n "${DRIVER_CACHE_KEY_FILE:-}" ]]  && tls_args+=(--key-file  "${DRIVER_CACHE_KEY_FILE}")
    [[ -n "${DRIVER_CACHE_CA_FILE:-}" ]]   && tls_args+=(--ca-file   "${DRIVER_CACHE_CA_FILE}")

    local pulled=0
    local attempt
    for attempt in 1 2; do
        if timeout 30 oras pull "${ref}" "${tls_args[@]}" --output "${tmpdir}"; then
            pulled=1
            break
        fi
        echo "[WARN] pull_from_cache: attempt ${attempt} failed for ${ref}" >&2
    done

    if [[ "${pulled}" -eq 0 ]]; then
        echo "[ERROR] pull_from_cache: all pull attempts failed for ${ref}" >&2
        rm -rf "${tmpdir}"
        return 1
    fi

    local archive
    archive=$(find "${tmpdir}" -name "*.tar.gz" -type f | head -1)
    if [[ -z "${archive}" ]]; then
        echo "[ERROR] pull_from_cache: no .tar.gz artifact in pulled content" >&2
        rm -rf "${tmpdir}"
        return 1
    fi

    if ! verify_artifact "${archive}"; then
        rm -rf "${tmpdir}"
        return 1
    fi

    mkdir -p "${staging_dir}"
    if ! tar -xzf "${archive}" -C "${staging_dir}"; then
        echo "[ERROR] pull_from_cache: failed to extract archive to ${staging_dir}" >&2
        rm -rf "${tmpdir}"
        return 1
    fi

    rm -rf "${tmpdir}"
    return 0
}

# Fire-and-forget: always returns 0 so a push failure never blocks the caller.
push_to_cache() {
    local ref="$1"
    local driver_dir="$2"
    local kernel_release="$3"
    local driver_version="$4"
    local kernel_module_type="$5"
    local arch="$6"

    local tls_args=()
    [[ -n "${DRIVER_CACHE_CERT_FILE:-}" ]] && tls_args+=(--cert-file "${DRIVER_CACHE_CERT_FILE}")
    [[ -n "${DRIVER_CACHE_KEY_FILE:-}" ]]  && tls_args+=(--key-file  "${DRIVER_CACHE_KEY_FILE}")
    [[ -n "${DRIVER_CACHE_CA_FILE:-}" ]]   && tls_args+=(--ca-file   "${DRIVER_CACHE_CA_FILE}")

    local tmpdir
    tmpdir=$(mktemp -d)
    local archive="${tmpdir}/driver.tar.gz"

    if ! tar -czf "${archive}" -C "${driver_dir}" .; then
        echo "[WARN] push_to_cache: failed to create archive from ${driver_dir}" >&2
        rm -rf "${tmpdir}"
        return 0
    fi

    local attempt
    for attempt in 1 2; do
        if timeout 30 oras push "${ref}" \
            "${tls_args[@]}" \
            --annotation "kernel.release=${kernel_release}" \
            --annotation "driver.version=${driver_version}" \
            --annotation "kernel.module.type=${kernel_module_type}" \
            --annotation "arch=${arch}" \
            "${archive}:application/vnd.oci.image.layer.v1.tar+gzip"; then
            break
        fi
        echo "[WARN] push_to_cache: attempt ${attempt} failed for ${ref}" >&2
    done

    rm -rf "${tmpdir}"
    return 0
}

wait_for_cache_on_compile_fail() {
    local ref="$1"
    local interval="${DRIVER_CACHE_COMPILE_FAIL_POLL_INTERVAL:-30}"
    local max_wait="${DRIVER_CACHE_COMPILE_FAIL_WAIT_SECS:-600}"
    local elapsed=0

    echo "[INFO] wait_for_cache_on_compile_fail: polling ${ref} every ${interval}s (max ${max_wait}s)" >&2

    while [[ "${elapsed}" -lt "${max_wait}" ]]; do
        if pull_from_cache "${ref}"; then
            return 0
        fi
        sleep "${interval}"
        elapsed=$(( elapsed + interval ))
    done

    echo "[ERROR] wait_for_cache_on_compile_fail: timed out after ${max_wait}s" >&2
    return 1
}
