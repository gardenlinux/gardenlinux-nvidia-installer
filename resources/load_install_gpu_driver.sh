#!/bin/bash
echo "nvidia-installer begins"
set -e

BIN_DIR=${BIN_DIR:-/opt/nvidia-installer}
# shellcheck disable=SC1090
source "$BIN_DIR"/set_env_vars.sh
LD_ROOT=${LD_ROOT:-/root}

main() {
    # Populate DRIVER_NAME, DRIVER_VERSION, NVIDIA_ROOT, etc.
    parse_parameters "$@"

    # Always run cleanup if your script provides it
    trap post_process EXIT

    # Safer shell defaults; optional tracing
    set -euo pipefail
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

    # Stage new contents into a temporary directory
    rm -rf /run/nvidia/.staging-driver || true
    mkdir -p /run/nvidia/.staging-driver /run/nvidia/driver

    # extract INTO staging but drop the leading "driver/" path from the archive
    tar xzf /out/nvidia/driver.tar.gz -C /run/nvidia/.staging-driver --strip-components=1

    # Make /run/nvidia/driver an exact mirror of staging WITHOUT requiring rsync:
    #  - First, remove existing contents of /run/nvidia/driver, including dotfiles.
    #  - Then, copy everything from staging (preserving perms/links with -a).
    #  Notes:
    #    * We remove the contents, not the directory, to avoid breaking any watches.
    #    * The glob trick handles hidden files/dirs (.[!.]* and ..?*).
    #
    # shellcheck disable=SC2115
    rm -rf /run/nvidia/driver/* /run/nvidia/driver/.[!.]* /run/nvidia/driver/..?* 2>/dev/null || true
    cp -a /run/nvidia/.staging-driver/. /run/nvidia/driver/
    cp /usr/bin/nvidia-modprobe /run/nvidia/driver/bin 

    # ------------------------------------------------------------------------------
    # 1) Run install(): 
    #    We also pass NVIDIA_BIN so probes can find tools easily inside this pod.
    # ------------------------------------------------------------------------------
    NVIDIA_BIN="${NVIDIA_ROOT}/bin"
    install "$DRIVER_NAME" "$NVIDIA_BIN"

    # ------------------------------------------------------------------------------
    # 4) Make the CLI tools available INSIDE THIS POD (not the host) for probes.
    #    We intentionally avoid host /usr/bin to prevent conflicts with the OS.
    # ------------------------------------------------------------------------------
    cp "${NVIDIA_BIN}"/* /usr/bin

    # ------------------------------------------------------------------------------
    # 5) Final verification from the pod. This exercises host devices (/dev/nvidia*)
    #    through the container and ensures userland is in place for probes.
    # ------------------------------------------------------------------------------
    if ! /usr/bin/nvidia-smi >/dev/null 2>&1; then
        echo "[ERROR] driver installation failed: nvidia-smi did not run successfully."
        # Best-effort diagnostics
        ls -l /dev/nvidia* 2>/dev/null || true
        nsenter -t 1 -m -u -n -i lsmod | grep -E '^(nvidia|nvidia_uvm|nvidia_modeset) ' || true
        exit 1
    fi

    echo "[INFO] NVIDIA driver install/refresh OK for ${DRIVER_NAME}:${DRIVER_VERSION}"
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
    
    # shellcheck disable=SC1090
    source "${BIN_DIR}/install.sh"
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