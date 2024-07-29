#!/bin/bash
echo "Downloading NVIDIA fabric manager for driver version $DRIVER_VERSION"
set -x

if [ -z "$TARGET_ARCH" ]; then
    echo "Error: TARGET_ARCH is not set."
    exit 1
fi

declare -A arch_translation
arch_translation=(["amd64"]="x86_64" ["arm64"]="aarch64")

if [[ ! ${arch_translation[$TARGET_ARCH]+_} ]]; then
    echo "Error: Unsupported TARGET_ARCH value."
    exit 2
fi

ARCH_TYPE=${arch_translation[$TARGET_ARCH]}

mkdir -p /tmp/nvidia

# shellcheck disable=SC2164
pushd /tmp/nvidia

# Download Fabric Manager tarball
OUTDIR=/out/nvidia-fabricmanager/$DRIVER_VERSION
FABRICMANAGER_ARCHIVE="fabricmanager-linux-$ARCH_TYPE-$DRIVER_VERSION-archive"
FABRICMANAGER_URL="https://developer.download.nvidia.com/compute/cuda/redist/fabricmanager/linux-$ARCH_TYPE/${FABRICMANAGER_ARCHIVE}.tar.xz"
if wget -q --spider FABRICMANAGER_URL; then
  mkdir -p "$OUTDIR"
  wget --directory-prefix="${OUTDIR}" "${FABRICMANAGER_URL}"
else
  echo "No NVIDIA Fabric Manager for driver version $DRIVER_VERSION exists. Skipping download."
fi
