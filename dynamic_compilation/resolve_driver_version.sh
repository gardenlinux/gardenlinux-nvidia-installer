#!/bin/bash
# Sourced by load_install_gpu_driver.sh and test_resolve_driver_version.bats

resolve_driver_version() {
    local runsc_output
    if ! runsc_output=$(nsenter -t 1 -m -u -n -i /var/bin/containerruntimes/runsc nvproxy list-supported-drivers 2>/dev/null); then
        echo "[INFO] runsc not available or failed - gVisor not enabled; using DRIVER_VERSION=${DRIVER_VERSION} as-is"
        return
    fi

    local resolved
    if [[ "${DRIVER_VERSION}" =~ ^[0-9]+$ ]]; then
        # Plain integer: pick the latest supported version with that major.
        local major="${DRIVER_VERSION}"
        resolved=$(echo "${runsc_output}" \
            | grep -E "^${major}\." \
            | sort -t. -k1,1n -k2,2n -k3,3n \
            | tail -1)

        if [ -z "${resolved}" ]; then
            echo "[ERROR] runsc listed no supported drivers for major version ${major}"
            exit 1
        fi
    else
        # Full semver: pick the latest supported version with the same major that is <= DRIVER_VERSION.
        resolved=$(echo "${runsc_output}" \
            | sort -t. -k1,1n -k2,2n -k3,3n \
            | awk -F. -v target="${DRIVER_VERSION}" '
                BEGIN { split(target, t, ".") }
                $1 == t[1] && ($2 < t[2] || ($2 == t[2] && $3 <= t[3])) { last = $0 }
                END { print last }
            ')

        if [ -z "${resolved}" ]; then
            echo "[ERROR] runsc listed no supported drivers <= ${DRIVER_VERSION}"
            exit 1
        fi
    fi

    echo "[INFO] DRIVER_VERSION resolved via runsc: ${DRIVER_VERSION} -> ${resolved}"
    DRIVER_VERSION="${resolved}"
    export DRIVER_VERSION
}
