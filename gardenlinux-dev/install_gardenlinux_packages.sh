#!/bin/bash
set -x
set -o errexit
set -o nounset
set -o pipefail

# Add packages from private gardenlinux source

# URL for Swift (object storage) service in Converged Cloud region eu-de-1, domain hcp03, project sapclea
STORAGE_URL=https://objectstore-3.eu-de-1.cloud.sap:443/v1/AUTH_535c582484f44532aa5e21b2bb5cb471
CONTAINER_NAME=gardenlinux-packages
# Files should be added to this object store using the script: ./tooling/upload_gardenlinux_packages.sh

python3 -m venv /openstack
. /openstack/bin/activate
pip install python-swiftclient

KERNEL_VERSION_PLAIN=$(echo $KERNEL_VERSION | cut -d '-' -f1,2)

mkdir -p "/tmp/pkg"

swift download "${CONTAINER_NAME}" --prefix "kernel_${KERNEL_VERSION_PLAIN}_linux_${LINUX_VERSION}" \
  --os-storage-url "${STORAGE_URL}" --os-auth-token null --output-dir /tmp/pkg --remove-prefix \
  && apt install /tmp/pkg/*.deb

rm -rf /var/lib/apt/lists/*
