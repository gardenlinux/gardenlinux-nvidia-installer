#!/bin/bash
echo "nvidia-installer begins"
set -e

BIN_DIR=${BIN_DIR:-/opt/nvidia-installer}
# shellcheck disable=SC1090
source "$BIN_DIR"/set_env_vars.sh
LD_ROOT=${LD_ROOT:-/root}
NVIDIA_ROOT=${NVIDIA_ROOT:-/run/nvidia/driver}
echo $DRIVER_VERSION
DRIVER_VERSION="590.48.01"

main() {
    # Populate DRIVER_NAME, DRIVER_VERSION, NVIDIA_ROOT, etc.
    parse_parameters "$@"

    # Always run cleanup if your script provides it
    trap post_process EXIT

    # Safer shell defaults; optional tracing
    #set -euo pipefail
    [ "${DEBUG:-false}" = "true" ] && set -x

    # ------------------------------------------------------------------------------
    # 0) Guard: refuse to proceed if host NVIDIA modules are still loaded.
    #    The GPU Operator's k8s-driver-manager should have evicted GPU users and
    #    unloaded modules before we restage the driver. If modules are still loaded,
    #    we bail out to avoid racing a live driver or mixing userlands.
    # ------------------------------------------------------------------------------
    if nsenter -t 1 -m -u -n -i lsmod | grep -qE '^(nvidia|nvidia_uvm|nvidia_modeset) '; then
        echo "[ERROR] Host NVIDIA kernel modules are still loaded; refusing to restage."
        echo "        Ensure driver-manager eviction/unload completed (or drain the node) and retry."
        exit 1
    fi

    # ------------------------------------------------------------------------------
    # 1) Resolve KERNEL_MODULE_TYPE and locate the pre-compiled driver tarball
    #    embedded in the image under /opt/nvidia-installer/drivers/.
    #    KERNEL_MODULE_TYPE selects which tarball to deploy. Valid values:
    #      "open"        – use open kernel modules
    #      "proprietary" – use proprietary kernel modules
    #      "auto"        – detect the recommended type from the driver version (default)
    #    When "auto", drivers >= 560 default to open modules; older drivers default to
    #    proprietary. Set explicitly to override.
    # ------------------------------------------------------------------------------
    resolve_kernel_module_type
    #locate_driver_tarball
    

    # Stage new contents into a temporary directory
    rm -rf /run/nvidia/.staging-driver || true
    mkdir -p /run/nvidia/.staging-driver /run/nvidia/driver

    cp /opt/nvidia-installer/compile.sh /run/nvidia/.staging-driver/

    chmod +x /opt/nvidia-installer/compile.sh

    /opt/nvidia-installer/compile.sh

    # extract INTO staging but drop the leading "driver/" path from the archive
    # tar xzf "${DRIVER_TARBALL_PATH}" -C /run/nvidia/.staging-driver --strip-components=1

    # Make /run/nvidia/driver an exact mirror of staging WITHOUT requiring rsync:
    #  - First, remove existing contents of /run/nvidia/driver, including dotfiles.
    #  - Then, copy everything from staging (preserving perms/links with -a).
    #  Notes:
    #    * We remove the contents, not the directory, to avoid breaking any watches.
    #    * The glob trick handles hidden files/dirs (.[!.]* and ..?*).
    #
    # shellcheck disable=SC2115
    #rm -rf /run/nvidia/driver/* /run/nvidia/driver/.[!.]* /run/nvidia/driver/..?* 2>/dev/null || true
    #cp -a /run/nvidia/.staging-driver/. /run/nvidia/driver/

    # ------------------------------------------------------------------------------
    # 2) Run install(): 
    #    We also pass NVIDIA_BIN so probes can find tools easily inside this pod.
    # ------------------------------------------------------------------------------
    NVIDIA_USR_BIN="${NVIDIA_ROOT}/usr/bin" # For nvidia-modprobe
    NVIDIA_BIN="${NVIDIA_ROOT}/bin"
    cp "${NVIDIA_USR_BIN}"/* "${NVIDIA_BIN}"

    install "$DRIVER_NAME" "$NVIDIA_BIN"

    # ------------------------------------------------------------------------------
    # 3) Make the CLI tools available INSIDE THIS POD (not the host) for probes.
    #    We intentionally avoid host /usr/bin to prevent conflicts with the OS.
    # ------------------------------------------------------------------------------
    cp "${NVIDIA_BIN}"/* /usr/bin

    # ------------------------------------------------------------------------------
    # 4) Final verification from the pod. This exercises host devices (/dev/nvidia*)
    #    through the container and ensures userland is in place for probes.
    # ------------------------------------------------------------------------------
    if ! /usr/bin/nvidia-smi >/dev/null 2>&1; then
        echo "[ERROR] driver installation failed: nvidia-smi did not run successfully."
        # Best-effort diagnostics
     s   ls -l /dev/nvidia* 2>/dev/null || true
        nsenter -t 1 -m -u -n -i lsmod | grep -E '^(nvidia|nvidia_uvm|nvidia_modeset) ' || true
        exit 1
    fi

    echo "[INFO] NVIDIA driver install/refresh OK for ${DRIVER_NAME}:${DRIVER_VERSION} (${KERNEL_MODULE_TYPE} modules, kernel ${KERNEL_NAME})"
}


resolve_kernel_module_type() {
    local requested="${KERNEL_MODULE_TYPE:-auto}"

    case "${requested}" in
        open|proprietary)
            KERNEL_MODULE_TYPE="${requested}"
            ;;
        auto)
            # Derive the recommended type from the driver version major number and the
            # GPU architecture present on the host.
            #
            # NVIDIA open kernel modules require Turing (2018) or newer GPU architecture.
            # Pre-Turing architectures — Maxwell (M40), Pascal (P100), Volta (V100) — are
            # only supported by the proprietary modules, regardless of driver version.
            #
            # GPU architecture is identified by PCI device ID: Turing and later GPUs have
            # device IDs >= 0x1E00; Maxwell/Pascal/Volta have device IDs < 0x1E00.
            local driver_major
            driver_major=$(echo "${DRIVER_VERSION}" | cut -d. -f1)

            if [ "${driver_major}" -lt 560 ]; then
                # Driver branches older than 560 ship proprietary modules only.
                KERNEL_MODULE_TYPE="proprietary"
                echo "[INFO] KERNEL_MODULE_TYPE=auto resolved to 'proprietary' (driver branch ${driver_major} predates open-module support)"
            elif _has_pre_turing_gpu; then
                # Open modules do not support Maxwell, Pascal, or Volta GPUs.
                KERNEL_MODULE_TYPE="proprietary"
                echo "[INFO] KERNEL_MODULE_TYPE=auto resolved to 'proprietary' (pre-Turing GPU detected)"
            else
                KERNEL_MODULE_TYPE="open"
                echo "[INFO] KERNEL_MODULE_TYPE=auto resolved to 'open' (driver branch ${driver_major}, Turing or newer GPU)"
            fi
            ;;
        *)
            echo "[ERROR] KERNEL_MODULE_TYPE has invalid value '${requested}'. Must be 'open', 'proprietary', or 'auto'."
            exit 1
            ;;
    esac

    echo "[INFO] Kernel module type: ${KERNEL_MODULE_TYPE}"
    export KERNEL_MODULE_TYPE
}


# Returns 0 (true) if any NVIDIA GPU on the host has a PCI device ID below 0x1E00,
# which indicates a pre-Turing architecture (Maxwell, Pascal, or Volta).
# Turing (TU102+) and all newer architectures start at device ID 0x1E00.
# lspci is called via nsenter so it reads the host PCI bus, not the container's view.
_has_pre_turing_gpu() {
    local dev_id
    # List NVIDIA GPUs (vendor 10de, PCI class 0300 VGA or 0302 3D controller).
    # -d 10de: selects NVIDIA vendor; -n prints numeric IDs; awk extracts the device ID field.
    while IFS= read -r dev_id; do
        # dev_id is a 4-digit hex string, e.g. "1db1". Compare numerically against 0x1E00.
        if [ $(( 16#${dev_id} )) -lt $(( 16#1E00 )) ]; then
            return 0
        fi
    done < <(nsenter -t 1 -m -u -n -i -- \
        lspci -d 10de: -n 2>/dev/null \
        | awk '{ print $3 }' \
        | cut -d: -f2)
    return 1
}


locate_driver_tarball() {
    local tarball_name="driver-${DRIVER_VERSION}-${KERNEL_MODULE_TYPE}-${KERNEL_NAME}.tar.gz"
    local tarball_path="/opt/nvidia-installer/drivers/${tarball_name}"

    if [ ! -f "${tarball_path}" ]; then
        echo "[ERROR] Driver tarball not found in image: ${tarball_path}"
        echo "        Expected a tarball for driver ${DRIVER_VERSION} (${KERNEL_MODULE_TYPE}) on kernel ${KERNEL_NAME}."
        exit 1
    fi

    DRIVER_TARBALL_PATH="${tarball_path}"
    echo "[INFO] Using embedded driver tarball: ${DRIVER_TARBALL_PATH}"
    export DRIVER_TARBALL_PATH
}



install() {
    local DRIVER_NAME=$1
    local NVIDIA_BIN=$2

    # The docker file sets the LD_LIBRARY_PATH to the nvidia LIBs
    # so we need to run ldconfig on the host so we need to use nsenter for that.
    # if [ -d "${INSTALL_DIR}/${DRIVER_NAME}/lib" ] ; then
    #     mkdir -p "${LD_ROOT}/etc/ld.so.conf.d"
    #     echo "${INSTALL_DIR}/${DRIVER_NAME}/lib" \
    #         > "${LD_ROOT}/etc/ld.so.conf.d/${DRIVER_NAME}.conf"
    #     ldconfig -r "${LD_ROOT}" 2> /dev/null
    # fi
    nsenter -t 1 -m -u -n -i /bin/sh -lc '
      set -e
      cat >/etc/ld.so.conf.d/nvidia-staged.conf <<EOF
/run/nvidia/driver/lib
/run/nvidia/driver/lib64
/run/nvidia/driver/usr/lib/x86_64-linux-gnu
EOF
      # ldconfig may live in /sbin or /usr/sbin depending on the distro
      if command -v ldconfig >/dev/null 2>&1; then
        ldconfig
      elif [ -x /sbin/ldconfig ]; then
        /sbin/ldconfig
      elif [ -x /usr/sbin/ldconfig ]; then
        /usr/sbin/ldconfig
      else
        echo "[ERROR] ldconfig not found on host"; exit 1
      fi
    '
    
    set +e
    # shellcheck disable=SC1090
    source "${BIN_DIR}/install.sh"
    set -e 
}

print_menu() {
    printf '%s is a tool for automatically installing (and potentially compiling) gpu drivers on gardenlinux nodes.\n\n' "$(basename "$0")"
    printf 'Usage:\n\n \t %s [options]\n\n' "$(basename "$0")"
    printf 'The options are:\n\n'

    echo "       | --debug                  Debug flag for more noisy logging."
    echo "  -h   | --help                   Prints the help"
    echo ""
}

parse_parameters() {

  while [ "$#" -gt 0 ]
  do
    case "$1" in
    -h|--help)
      print_menu
      exit 0
      ;;
    --debug)
      export DEBUG="true"
      ;;
    --)
      break
      ;;
    -*)
      echo "Invalid option '$1'. Use --help to see the valid options" >&2
      exit 1
      ;;
    *)  
      break
      ;;
    esac
    shift
  done
}

check_required() {
    if [ -z "${!2}" ]; then
      print_menu
      error "${1} \"${2}\" is not set"
    fi
}

error() {
  echo -e "\033[1;31m[-] [ERROR]: $*\033[0m";
  exit 1
}

log() {
  echo -e "\033[1;32m[+]: $*\033[0m"
}

post_process() {
    if ${DEBUG}; then
        sleep infinity
    fi
}

main "${@}"
