#!/bin/bash
echo "modulus begins"
set -e

BIN_DIR=${BIN_DIR:-/opt/modulus}
# shellcheck disable=SC1090
[ -e "$BIN_DIR"/.env ] && source "$BIN_DIR"/.env
CACHE_DIR=${CACHE_DIR:-$BIN_DIR/cache}
INSTALL_DIR=${INSTALL_DIR:-/opt/drivers}
LD_ROOT=${LD_ROOT:-/}
GARDENLINUX_VERSION=${GARDENLINUX_VERSION}
DEBUG=${DEBUG:-false}
COMPILATION_ALLOWED=${COMPILATION_ALLOWED:-false}
FORCE_COMPILE=${FORCE_COMPILE:-false}

S3_ALIAS="s3_access"

main() {
    parse_parameters "${@}"

    trap post_process EXIT
    
    check_status "${DRIVER_NAME}" "${DRIVER_VERSION}" && exit 0

    driver_cached=$(driver_in_cache "${DRIVER_NAME}" "${DRIVER_VERSION}")
    
    mc alias set "${S3_ALIAS}" https://s3.amazonaws.com "${AWS_ACCESS_KEY_ID}" "${AWS_SECRET_ACCESS_KEY}"
    
    compiled_new_driver="false"
    if ${FORCE_COMPILE} && ${COMPILATION_ALLOWED}; then
        compile "$DRIVER_NAME" "$DRIVER_VERSION"
        compiled_new_driver="true"
    elif ! ${driver_cached}; then
        download || {
            if ${COMPILATION_ALLOWED}; then
                compile "$DRIVER_NAME" "$DRIVER_VERSION"
                compiled_new_driver="true"
            fi
        }
    fi

    install "$DRIVER_NAME" "$DRIVER_VERSION"

    export LD_LIBRARY_PATH="${BIN_DIR}/cache/${DRIVER_NAME}/${DRIVER_VERSION}/lib"
    if ! "${BIN_DIR}/cache/${DRIVER_NAME}/${DRIVER_VERSION}/bin/nvidia-smi"; then
        echo "[ERROR] driver installation failed. Could not run nvidia-smi."
        exit 1
    fi

    if ${compiled_new_driver}; then
        upload "$DRIVER_NAME" "$DRIVER_VERSION"
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

download() {
    mkdir -p "$CACHE_DIR"
    pushd "$CACHE_DIR" > /dev/null

    log "downloading driver ${DRIVER_ARCHIVE} from s3"

    driver_downloaded="true"
    msg="driver does not exist in"
    mc cp "${S3_ALIAS}/${BUCKET}/${DRIVER_ARCHIVE}" "${DRIVER_ARCHIVE}" 2> /dev/null || {
        log "Compilation required: ${msg} \"${BUCKET}/${DRIVER_ARCHIVE}\""
        driver_downloaded="false"
    }

    if ${driver_downloaded}; then
        tar -xzf "${DRIVER_ARCHIVE}"
        popd
        return 0
    else
        popd
        return 1
    fi

}


compile() {
    local DRIVER_NAME=$1
    local DRIVER_VERSION=$2

    echo "Compiling kernel modules for $DRIVER_NAME $DRIVER_VERSION, Garden Linux $GARDENLINUX_VERSION"
    mkdir -p "$CACHE_DIR/$DRIVER_NAME/$DRIVER_VERSION"
    pushd "$CACHE_DIR/$DRIVER_NAME/$DRIVER_VERSION" > /dev/null

    tar czf /cmd/opt-modulus.tgz --directory "$BIN_DIR" .
    mkfifo /cmd/command_fifo 2> /dev/null || true
    mkfifo /cmd/response_fifo 2> /dev/null || true
    # Next line will complete when the dev container reads from the FIFO
    cat << EOF > /cmd/command_fifo &
        mkdir -p /opt/modulus
        tar xzf /cmd/opt-modulus.tgz --directory /opt/modulus
        DRIVER_VERSION=$DRIVER_VERSION /opt/modulus/$DRIVER_NAME/compile
EOF
    echo "Sent command to dev container, now wait to hear back..."

    cat /cmd/response_fifo > /tmp/response
    exit_status=$(cat /tmp/response | head -n 1)

    echo "Response:"
    tail -n +2 /tmp/response

    if [[ "${exit_status}" != 0 ]]; then
        echo "[ERROR] compilation in dev container failed, see above response."       
        exit ${exit_status}
    fi

    popd
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

upload() {
    local DRIVER_NAME=$1
    local DRIVER_VERSION=$2
    pushd "$CACHE_DIR"

    log "uploading compiled driver ${DRIVER_ARCHIVE} to s3 \"${S3_ALIAS}/${BUCKET}/\""
    tar -czf "${DRIVER_ARCHIVE}" --exclude=coreos_developer_container* "$DRIVER_NAME"/"$DRIVER_VERSION"

    mc cp "${DRIVER_ARCHIVE}" "${S3_ALIAS}/${BUCKET}/${DRIVER_ARCHIVE}"

    popd
}



print_menu() {
    printf '%s is a tool for automatically installing (and potentially compiling) gpu drivers on gardenlinux nodes.\n\n' "$(basename "$0")"
    printf 'Usage:\n\n \t %s [options]\n\n' "$(basename "$0")"
    printf 'The options are:\n\n'

    echo "       | --compile-if-needed      If this flag is set, the gpu driver is compiled if it does not yet exist in the s3 bucket."
    echo "                                  This flag requires the environment variables for dev and prod s3 buckets."
    echo "  -d   | --driver-name            GPU driver name, e.g. \"nvidia\"."
    echo "  -v   | --driver-version         GPU driver version."
    echo "  -gv  | --gardenlinux-version    Gardenlinux version."
    echo "  -prod| --production             If this flag is set, the production s3 bucket will be used instead of the default dev s3 bucket."
    echo "  -f   | --force                  If this flag and the \"--compile-if-needed\" are set, then the recompilation is forced."
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
    --compile-if-needed)
      export COMPILATION_ALLOWED="true"
      ;;
    -d|--driver-name)
      export DRIVER_NAME="$2"
      shift
      ;;
    -v|--driver-version)
      export DRIVER_VERSION="$2"
      shift
      ;;
    -gv|--gardenlinux-version)
      export GARDENLINUX_VERSION="$2"
      shift
      ;;
    -f|--force)
      export FORCE_COMPILE=true
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
  check_required "parameter" GARDENLINUX_VERSION

  check_required "environment variable" AWS_ACCESS_KEY_ID
  check_required "environment variable" AWS_SECRET_ACCESS_KEY
  check_required "environment variable" BUCKET

  export DRIVER_ARCHIVE="gardenlinux-$GARDENLINUX_VERSION"-"$DRIVER_NAME"-"$DRIVER_VERSION".tar.gz

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