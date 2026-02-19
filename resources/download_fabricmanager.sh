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
wget -O /tmp/keyring.deb https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/cuda-keyring_1.1-1_all.deb && dpkg -i /tmp/keyring.deb

#Allow sha1 to avoid error 

# W: OpenPGP signature verification failed: https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64  InRelease: Sub-process /usr/bin/sqv returned an error code (1), error message is: Signing key on EB693B3035CD5710E231E123A4B469963BF863CC is not bound:            No binding signature at time 2026-01-29T20:38:07Z   because: Policy rejected non-revocation signature (PositiveCertification) requiring second pre-image resistance   because: SHA1 is not considered secure since 2026-02-01T00:00:00Z
# TBD: Move to debian13 when latest 2 major version is available in that and remove the workaround

mkdir -p /etc/crypto-policies/back-ends
echo '[hash_algorithms]
sha1 = "always"' | tee /etc/crypto-policies/back-ends/apt-sequoia.config

# In testing apt-get update failed.  This is because the Packages file was not updated to reflect the current size of the file.
# A ticket was filed with the git repo as this is not the first time this has happened.  There was a comment that the flow had
# changed and hopefully this is the last time we see this issue, but leaving this here for reference.
#
# Need to open a github issue about this here.
# https://github.com/NVIDIA/cuda-repo-management/issues/27
#
# Get:6 https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64  Packages [1128 kB]
# Err:6 https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64  Packages
#   File has unexpected size (1157413 != 1127921). Mirror sync in progress? [IP: 23.217.201.113 443]
#   Hashes of expected file:
#    - Filesize:1127921 [weak]
#    - SHA256:d4765ad6e9e2bd1d24a63ecbd8759054b33361c20426ea90406fc5624f29ba1a
#    - SHA1:dde0211e2acfc9bbdc91c4657deef218298f5e39 [weak]
#    - MD5Sum:4c6ea7dd7dd7de501e7907adc9b60e1e [weak]
#   Release file created at: Thu, 28 Aug 2025 20:09:04 +0000
#
# Running the following command I could see the size of Packages.gz
# 1127921 Packages.gz
# curl -s https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/InRelease
#
# Use a bash script to hit all the IPs retured by the DNS entry for developer.download.nvidia.com
#
# URL="https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/Packages.gz"

# for IP in 23.217.201.113 23.217.201.115; do
#   echo "=== $IP ==="
#   curl -sSI --http1.1 \
#     --resolve developer.download.nvidia.com:443:$IP \
#     "$URL" | awk '
#       BEGIN{print "Status/Headers:"}
#       /^HTTP/{print $0}
#       tolower($1)=="content-length:"{print "Content-Length:", $2}
#       tolower($1)=="etag:"{print "ETag:", $0}
#       tolower($1)=="last-modified:"{print "Last-Modified:", $0}
#     '
#   echo
# done
# =====
# Output 
# === 23.217.201.113 ===
# Status/Headers:
# HTTP/1.1 200 OK
# Content-Length: 1157413
# ETag: ETag: "8948ace4176d58e5ac9e6caa3b5b3775:1756834806.016545"
# Last-Modified: Last-Modified: Tue, 02 Sep 2025 17:01:53 GMT

# === 23.217.201.115 ===
# Status/Headers:
# HTTP/1.1 200 OK
# Content-Length: 1157413
# ETag: ETag: "8948ace4176d58e5ac9e6caa3b5b3775:1756834806.016545"
# Last-Modified: Last-Modified: Tue, 02 Sep 2025 17:01:53 GMT
#
# Based on the dates it looks like the file was udpated on  Tue, 02 Sep 2025
# but the Packages.gz was not updated to reflect the new size.



apt-get update 

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
apt-get install -y -V nvlsm
apt-get install -y -V infiniband-diags
