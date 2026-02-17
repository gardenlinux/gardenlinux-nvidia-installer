#!/bin/bash
if [ -z "$DRIVER_VERSION" ]; then
    echo "Error: DRIVER_VERSION is not set."
    exit 1
fi
if [ -z "$KERNEL_NAME" ]; then
    echo "Error: KERNEL_NAME is not set."
    exit 1
fi

if [ -z "$KERNEL_TYPE" ]; then
    echo "Error: KERNEL_TYPE is not set."
    exit 1
fi

echo "Compiling NVIDIA modules for $KERNEL_TYPE driver version $DRIVER_VERSION on kernel $KERNEL_NAME"

set -x
mkdir -p /tmp/nvidia

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

# shellcheck disable=SC2164
pushd /tmp/nvidia
pushd "./NVIDIA-Linux-$ARCH_TYPE-$DRIVER_VERSION"
export IGNORE_MISSING_MODULE_SYMVERS=1
OUTDIR="/out/nvidia/driver"

#Install ucx
mkdir -p "$OUTDIR"/ucx
mkdir -p "$OUTDIR"/ucx/usr

apt install -y libibverbs-dev librdmacm-dev pkg-config

pushd /tmp/nvidia
git clone https://github.com/openucx/ucx.git
pushd /tmp/nvidia/ucx

# Run autogen to process templates
./autogen.sh

# Configure to generate all necessary files including version info
./configure --prefix="$OUTDIR"/ucx/usr

dpkg-buildpackage -us -uc

pushd /tmp/nvidia
mv ucx_1.21.e5d9887_amd64.deb "$OUTDIR"/ucx/

# shellcheck disable=SC2046
tar czf "$OUTDIR-$DRIVER_VERSION-$KERNEL_TYPE-$KERNEL_NAME".tar.gz --directory $(dirname "$OUTDIR") $(basename "$OUTDIR") && rm -rf "$OUTDIR"
