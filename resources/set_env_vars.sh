#!/bin/bash
export INSTALL_DIR=${INSTALL_DIR:-/run/nvidia}
export DEBUG=${DEBUG:-false}
export DRIVER_NAME=driver
# Look for a file <driver version>.tar.gz and remove the .tar.gz to get the driver version
# shellcheck disable=SC2155,SC2012
export DRIVER_VERSION=$(cat /tmp/driver-version)
export NVIDIA_ROOT="${INSTALL_DIR}/${DRIVER_NAME}"
export LD_LIBRARY_PATH="${NVIDIA_ROOT}/lib"

if [ -z "$TARGET_ARCH" ]; then
  ARCH_TYPE=$(uname -m)
else
  declare -A arch_translation
  arch_translation=(["amd64"]="x86_64" ["arm64"]="aarch64")
  ARCH_TYPE=${arch_translation[$TARGET_ARCH]}
fi
export ARCH_TYPE