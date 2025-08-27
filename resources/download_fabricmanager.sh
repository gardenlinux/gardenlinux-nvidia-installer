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
#apt-get install -V nvidia-fabricmanager-"$DRIVER_BRANCH"="$DRIVER_VERSION"-1

# As of Aug 27 2025 the 580 version of fabricmanager changed the nameing format
# https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/
# example names
#
#nvidia-fabricmanager-570_570.172.08-1_amd64.deb 7.2MB 2025-07-09 04:20
#nvidia-fabricmanager-575_575.51.03-1_amd64.deb 7.2MB 2025-04-26 19:32
#nvidia-fabricmanager-575_575.57.08-1_amd64.deb 7.2MB 2025-05-29 18:10
#
# However 580 has the following format
# nvidia-fabricmanager_580.65.06-1_amd64.deb 7.3MB 2025-07-28 05:55
#
# So try and handle both cases.
# =${VER} is pinning a package, I was not familiar with this format of referencing a package version.
#
PKG1="nvidia-fabricmanager-${DRIVER_BRANCH}"
PKG2="nvidia-fabricmanager"
VER="${DRIVER_VERSION}-1"

has_exact_ver() { apt-cache madison "$1" 2>/dev/null | awk '{print $3}' | grep -Fx "$2" >/dev/null 2>&1; }

PKG=""
if has_exact_ver "$PKG1" "$VER"; then
  PKG="$PKG1"
elif has_exact_ver "$PKG2" "$VER"; then
  PKG="$PKG2"
fi

if [ -z "$PKG" ]; then
  echo "Not found via APT:"
  echo "  ${PKG1} version ${VER}"
  echo "  ${PKG2} version ${VER}"
  echo "Available for ${PKG1}:"; apt-cache madison "$PKG1" | awk '{print "  " $3}' || true
  echo "Available for ${PKG2}:"; apt-cache madison "$PKG2" | awk '{print "  " $3}' || true
  exit 1
fi

echo "Installing via APT: ${PKG}=${VER}"
apt-get install -y -V "${PKG}=${VER}"
