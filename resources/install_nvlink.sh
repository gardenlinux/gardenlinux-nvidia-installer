#!/bin/bash
#set -euo pipefail

wget -O /tmp/keyring.deb https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/cuda-keyring_1.1-1_all.deb && dpkg -i /tmp/keyring.deb

apt-get update

NVLINK_PKG="nvlink5-590"

echo "Installing nvlink"

dpkg -i /run/nvidia/driver/ucx/ucx*.deb
echo 'deb http://deb.debian.org/debian bookworm testing' > /etc/apt/sources.list.d/sources.list
apt-get update

mkdir -p /usr/lib/python3/dist-packages/
ln -sf /usr/lib/python3.13/venv /usr/lib/python3/dist-packages/venv

ln -sf /usr/bin/python3.13 /usr/bin/python3

# Create a fake package entry
mkdir -p /var/lib/dpkg/info
echo "python3.13-venv" | tee /var/lib/dpkg/info/python3-venv.list

apt-get install ocl-icd-libopencl1

apt-get install -y -V "${NVLINK_PKG}"
