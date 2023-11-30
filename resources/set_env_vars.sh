#!/bin/bash
CACHE_DIR=${CACHE_DIR:-$BIN_DIR/cache}
INSTALL_DIR=${INSTALL_DIR:-/opt/drivers}
DEBUG=${DEBUG:-false}
DRIVER_NAME=nvidia
# Look for a file <driver version>.tar.gz and remove the .tar.gz to get the driver version
# shellcheck disable=SC2012
DRIVER_VERSION=$(ls /out/nvidia | sed 's/.tar.gz//')
NVIDIA_ROOT="${BIN_DIR}/cache/${DRIVER_NAME}/${DRIVER_VERSION}"
export LD_LIBRARY_PATH="${NVIDIA_ROOT}/lib"

declare -A arch_translation
arch_translation=(["amd64"]="x86_64" ["arm64"]="aarch64")
ARCH_TYPE=${arch_translation[$TARGET_ARCH]}
