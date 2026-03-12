#!/bin/bash
export INSTALL_DIR=${INSTALL_DIR:-/run/nvidia}
export DEBUG=${DEBUG:-false}
export DRIVER_NAME=driver
# Look for a file <driver version>.tar.gz and remove the .tar.gz to get the driver version
# shellcheck disable=SC2155,SC2012
export DRIVER_VERSION=$(cat /tmp/driver-version)
# shellcheck disable=SC2155,SC2012
export RELEASE_TAG=$(cat /tmp/release-tag)
if [[ -z "$RELEASE_TAG" ]]; then
  echo "ERROR: RELEASE_TAG not set (check /tmp/release-tag was written during image build)" >&2
  exit 1
fi
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

# Base URL for downloading pre-compiled driver tarballs from GitHub Releases.
# Tarballs are named: driver-<DRIVER_VERSION>-<KERNEL_TYPE>-<KERNEL_NAME>.tar.gz
# Override this variable to point at an alternative mirror or internal cache.
export TARBALL_BASE_URL=${TARBALL_BASE_URL:-https://github.com/gardenlinux/gardenlinux-nvidia-installer/releases/download}