#!/bin/bash
echo "nvidia-installer begins"
set -e

BIN_DIR=${BIN_DIR:-/opt/nvidia-installer}
# shellcheck disable=SC1090
source "$BIN_DIR"/set_env_vars.sh
LD_ROOT=${LD_ROOT:-/}

main() {
    parse_parameters "${@}"

    trap post_process EXIT

    if ${DEBUG}; then
      set -x
    fi

    check_status "${DRIVER_NAME}" "${DRIVER_VERSION}" && exit 0

    driver_cached=$(driver_in_cache "${DRIVER_NAME}" "${DRIVER_VERSION}")

    if ! ${driver_cached}; then
      mkdir -p "${CACHE_DIR}"/"${DRIVER_NAME}"
      tar xzf /out/"${DRIVER_NAME}"/"${DRIVER_VERSION}".tar.gz -C "${CACHE_DIR}"/"${DRIVER_NAME}"
    fi

    NVIDIA_BIN="${NVIDIA_ROOT}/bin"
    install "$DRIVER_NAME" "$DRIVER_VERSION" "$NVIDIA_BIN"

    if ! "${NVIDIA_BIN}/nvidia-smi"; then
        echo "[ERROR] driver installation failed. Could not run nvidia-smi."
        exit 1
    fi

}

check_status() {
    local DRIVER_NAME=$1
    local DRIVER_VERSION=$2
    # Check to see if /dev/nvidia0 exists already - this means that a previous driver version already exists,
    #  in which case we don't want to overwrite with a conflicting new version
    if [ -e /dev/nvidia0 ] && [ -e /dev/nvidiactl ] && [ -e /dev/nvidia-uvm ]; then
      echo "[INFO] /dev/nvidia* files exist - driver version $(ls "${CACHE_DIR}"/"${DRIVER_NAME}") already installed"
      return 0
    fi

    echo "$DRIVER_NAME $DRIVER_VERSION is out of date" 1>&2
    return 1;
}

driver_in_cache() {
    local DRIVER_NAME=$1
    local DRIVER_VERSION=$2
    # shellcheck disable=SC2155
    local KERNEL_NAME=$(uname -r)
    if [ -d "${CACHE_DIR}/${DRIVER_NAME}/${DRIVER_VERSION}/lib/modules/${KERNEL_NAME}" ]; then
        echo "true"
    fi
    echo "false"
}

install() {
    local DRIVER_NAME=$1
    local DRIVER_VERSION=$2
    local NVIDIA_BIN=$3

    mkdir -p "${INSTALL_DIR}"
    rm -rf "${INSTALL_DIR:?}/${DRIVER_NAME}"
    ln -s "${CACHE_DIR}/${DRIVER_NAME}/${DRIVER_VERSION}" "${INSTALL_DIR}/${DRIVER_NAME}"

    if [ -d "${INSTALL_DIR}/${DRIVER_NAME}/lib" ] ; then
        mkdir -p "${LD_ROOT}/etc/ld.so.conf.d"
        echo "${INSTALL_DIR}/${DRIVER_NAME}/lib" \
            > "${LD_ROOT}/etc/ld.so.conf.d/${DRIVER_NAME}.conf"
        ldconfig -r "${LD_ROOT}" 2> /dev/null
    fi
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