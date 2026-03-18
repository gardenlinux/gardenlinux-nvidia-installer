#!/bin/bash
export INSTALL_DIR=${INSTALL_DIR:-/run/nvidia}
export DEBUG=${DEBUG:-false}
export DRIVER_NAME=driver
# shellcheck disable=SC2155,SC2012
export DRIVER_VERSION=$(cat /tmp/driver-version)
# shellcheck disable=SC2155,SC2012
export KERNEL_NAME=$(cat /tmp/kernel-name)
export NVIDIA_ROOT="${INSTALL_DIR}/${DRIVER_NAME}"
export LD_LIBRARY_PATH="${NVIDIA_ROOT}/lib:${NVIDIA_ROOT}/usr/lib/x86_64-linux-gnu"

if [ -z "$TARGET_ARCH" ]; then
  ARCH_TYPE=$(uname -m)
else
  declare -A arch_translation
  arch_translation=(["amd64"]="x86_64" ["arm64"]="aarch64")
  ARCH_TYPE=${arch_translation[$TARGET_ARCH]}
fi
export ARCH_TYPE
