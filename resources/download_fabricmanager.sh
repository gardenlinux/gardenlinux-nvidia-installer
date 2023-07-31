#!/bin/bash
echo "Downloading NVIDIA fabric manager for driver version $DRIVER_VERSION"
set -x
mkdir -p /tmp/nvidia
# shellcheck disable=SC2164
pushd /tmp/nvidia

# Download Fabric Manager tarball
OUTDIR=/out/nvidia-fabricmanager/$DRIVER_VERSION
FABRICMANAGER_ARCHIVE="fabricmanager-linux-x86_64-$DRIVER_VERSION-archive"
FABRICMANAGER_URL="https://developer.download.nvidia.com/compute/cuda/redist/fabricmanager/linux-x86_64/${FABRICMANAGER_ARCHIVE}.tar.xz"
mkdir -p "$OUTDIR"
wget --directory-prefix="${OUTDIR}" "${FABRICMANAGER_URL}"