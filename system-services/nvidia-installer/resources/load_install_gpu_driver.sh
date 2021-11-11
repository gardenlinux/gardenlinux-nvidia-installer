#!/bin/bash
echo "modulus begins"
set -e

BIN_DIR=${BIN_DIR:-/opt/modulus}
# shellcheck disable=SC1090
[ -e "$BIN_DIR"/.env ] && source "$BIN_DIR"/.env
CACHE_DIR=${CACHE_DIR:-$BIN_DIR/cache}
INSTALL_DIR=${INSTALL_DIR:-/opt/drivers}
LD_ROOT=${LD_ROOT:-/}
DEBUG=${DEBUG:-false}

main() {
    parse_parameters "${@}"

    trap post_process EXIT

    if ${DEBUG}; then
      set -x
    fi

    check_status "${DRIVER_NAME}" "${DRIVER_VERSION}" && exit 0

    driver_cached=$(driver_in_cache "${DRIVER_NAME}" "${DRIVER_VERSION}")

    if ! ${driver_cached}; then
      mkdir -p ${CACHE_DIR}
      cp -ar /out/* ${CACHE_DIR}
    fi

    install "$DRIVER_NAME" "$DRIVER_VERSION"

    export LD_LIBRARY_PATH="${BIN_DIR}/cache/${DRIVER_NAME}/${DRIVER_VERSION}/lib"
    if ! "${BIN_DIR}/cache/${DRIVER_NAME}/${DRIVER_VERSION}/bin/nvidia-smi"; then
        echo "[ERROR] driver installation failed. Could not run nvidia-smi."
        exit 1
    fi

}

check_status() {
    local DRIVER_NAME=$1
    local DRIVER_VERSION=$2
    # shellcheck disable=SC2155
    local KERNEL_VERSION=$(uname -r)
    # the "-ef" operator means: True if file1 and file2 refer to the same device and inode numbers.
    # source: https://www.gnu.org/savannah-checkouts/gnu/bash/manual/bash.html#Bash-Conditional-Expressions
    if [ -d "${INSTALL_DIR}/${DRIVER_NAME}/lib/modules/${KERNEL_VERSION}" ] \
    && [ "${CACHE_DIR}/${DRIVER_NAME}/${DRIVER_VERSION}" -ef "${INSTALL_DIR}/${DRIVER_NAME}" ]; then

        up_to_date="true"
        if [ ! -e /dev/nvidia0 ] ; then
            echo "$DRIVER_NAME $DRIVER_VERSION is out of date: (\"/dev/nvidia0\" does not exist)" 1>&2
            up_to_date="false";
        fi
        if [ ! -e /dev/nvidiactl ] ; then
            echo "$DRIVER_NAME $DRIVER_VERSION is out of date: (\"/dev/nvidiactl\" does not exist)" 1>&2
            up_to_date="false";
        fi
        if [ ! -e /dev/nvidia-uvm ] ; then
            echo "$DRIVER_NAME $DRIVER_VERSION is out of date: (\"/dev/nvidia-uvm\" does not exist)" 1>&2
            up_to_date="false";
        fi
        if ${up_to_date}; then
            echo "$DRIVER_NAME $DRIVER_VERSION is up to date"
            return 0;
        else
            return 1;
        fi
    fi
    
    echo "$DRIVER_NAME $DRIVER_VERSION is out of date" 1>&2
    return 1;
}

driver_in_cache() {
    local DRIVER_NAME=$1
    local DRIVER_VERSION=$2
    # shellcheck disable=SC2155
    local KERNEL_VERSION=$(uname -r)
    if [ -d "${CACHE_DIR}/${DRIVER_NAME}/${DRIVER_VERSION}/lib/modules/${KERNEL_VERSION}" ]; then
        echo "true"
    fi
    echo "false"
}

install() {
    local DRIVER_NAME=$1
    local DRIVER_VERSION=$2

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
    source "${BIN_DIR}/${DRIVER_NAME}/install"
}

print_menu() {
    printf '%s is a tool for automatically installing (and potentially compiling) gpu drivers on gardenlinux nodes.\n\n' "$(basename "$0")"
    printf 'Usage:\n\n \t %s [options]\n\n' "$(basename "$0")"
    printf 'The options are:\n\n'

    echo "  -d   | --driver-name            GPU driver name, e.g. \"nvidia\"."
    echo "  -v   | --driver-version         GPU driver version."
    echo "       | --debug                  Debug flag for more noisy logging."
    echo "  -h   | --help                   Prints the help"
    echo ""
}

parse_parameters() {

  input_params="${@}"

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
    -d|--driver-name)
      export DRIVER_NAME="$2"
      shift
      ;;
    -v|--driver-version)
      export DRIVER_VERSION="$2"
      shift
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

  check_required "parameter" DRIVER_NAME
  check_required "parameter" DRIVER_VERSION
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