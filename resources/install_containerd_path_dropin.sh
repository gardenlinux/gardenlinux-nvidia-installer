#!/bin/bash
# shellcheck disable=SC2016
# install_containerd_path_dropin.sh
#
# Installs a systemd drop-in for containerd that extends PATH to include
# /opt/nvidia/toolkit. This is required for gVisor/runsc with nvproxy,
# which uses exec.LookPath("nvidia-container-cli") and needs the binary
# on containerd's PATH.
#
# The drop-in is written to the host filesystem. Containerd picks up the
# new PATH on its next restart (which the GPU Operator's toolkit DaemonSet
# triggers when it configures the container runtime).
#
# See: https://github.com/gardener/gardener-extension-runtime-gvisor/issues/411
# See: https://github.com/NVIDIA/nvidia-container-toolkit/issues/1880

set -e

TOOLKIT_PATH="/opt/nvidia/toolkit"
DROPIN_DIR="/etc/systemd/system/containerd.service.d"
DROPIN_FILE="${DROPIN_DIR}/nvidia-toolkit-path.conf"

install_containerd_path_dropin() {
    echo "[INFO] Ensuring containerd PATH includes ${TOOLKIT_PATH}"
    echo "[INFO] Drop-in target: ${DROPIN_FILE}"

    if ! nsenter -t 1 -m -u -n -i /bin/sh -c '
        DROPIN_DIR="'"${DROPIN_DIR}"'"
        DROPIN_FILE="'"${DROPIN_FILE}"'"
        TOOLKIT_PATH="'"${TOOLKIT_PATH}"'"

        DROPIN_CONTENT="[Service]
Environment=PATH=/var/bin/containerruntimes:${TOOLKIT_PATH}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
"

        if [ -f "${DROPIN_FILE}" ]; then
            existing=$(cat "${DROPIN_FILE}")
            if [ "${existing}" = "${DROPIN_CONTENT}" ]; then
                echo "[INFO] containerd PATH drop-in already installed and up-to-date"
                return 0
            fi
            echo "[INFO] containerd PATH drop-in exists but differs, updating"
        fi

        echo "[INFO] Installing containerd PATH drop-in to ${DROPIN_FILE}"
        mkdir -p "${DROPIN_DIR}"
        printf "%s" "${DROPIN_CONTENT}" > "${DROPIN_FILE}"
        echo "[INFO] Running systemctl daemon-reload"
        systemctl daemon-reload
        echo "[INFO] Drop-in installed. Containerd will use the updated PATH on next restart."
    '; then
        echo "[ERROR] Failed to install containerd PATH drop-in (nsenter exited $?)"
        echo "[ERROR] gVisor/runsc pods requiring nvidia-container-cli may fail to start"
        return 1
    fi

    echo "[INFO] containerd PATH drop-in step completed successfully"
}

install_containerd_path_dropin
