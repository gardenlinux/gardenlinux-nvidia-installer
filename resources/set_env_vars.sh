#!/bin/bash
export CACHE_DIR=${CACHE_DIR:-$BIN_DIR/cache}
export INSTALL_DIR=${INSTALL_DIR:-/opt/drivers}
export DEBUG=${DEBUG:-false}
export DRIVER_NAME=nvidia
# Look for a file <driver version>.tar.gz and remove the .tar.gz to get the driver version
# shellcheck disable=SC2155,SC2012
export DRIVER_VERSION=$(ls /out/nvidia | sed 's/.tar.gz//')
export NVIDIA_ROOT="${CACHE_DIR}/${DRIVER_NAME}/${DRIVER_VERSION}"
export LD_LIBRARY_PATH="${NVIDIA_ROOT}/lib"
