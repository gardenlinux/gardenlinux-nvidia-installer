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
