#!/bin/bash
echo "Downloading NVIDIA fabric manager for driver version $DRIVER_VERSION"
set -x
DRIVER_BRANCH=$(echo "$DRIVER_VERSION" | grep -oE '^[0-9]+')
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

mkdir -p /tmp/nvidia

# shellcheck disable=SC2164
pushd /tmp/nvidia

# Download Fabric Manager tarball
wget -O /tmp/keyring.deb https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-keyring_1.1-1_all.deb && dpkg -i /tmp/keyring.deb
apt-get update
apt-get install -V nvidia-fabricmanager-"$DRIVER_BRANCH"="$DRIVER_VERSION"-1

