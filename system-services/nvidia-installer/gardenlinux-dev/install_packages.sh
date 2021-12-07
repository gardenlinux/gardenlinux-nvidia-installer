#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

export $(./read_image_versions.sh | xargs)

printf "\n-------------\ninputs:\nPACKAGE_FOLDER=%s\nLINUX_VERSION=%s\nLINUX_DATE=%s\nKERNEL_VERSION=%s\nGCC_VERSION=%s\nGARDENLINUX_PACKAGES_URL=%s\n-------------" \
  "${PACKAGE_FOLDER}" \
  "${LINUX_VERSION}" \
  "${LINUX_DATE}" \
  "${KERNEL_VERSION}" \
  "${GCC_VERSION}" \
  "${GARDENLINUX_PACKAGES_URL}"

DATESTAMP=$(echo ${LINUX_DATE} | sed 's/-//g') && rm -f /etc/apt/sources.list && \
  echo "deb http://snapshot.debian.org/archive/debian/${DATESTAMP}T000000Z testing main" >> /etc/apt/sources.list

apt-get -o Acquire::Check-Valid-Until=false update
GCC_MAJOR=$(echo $GCC_VERSION | cut -d '.' -f1) && \
    apt-get install -y --allow-downgrades --no-install-recommends \
      gcc-${GCC_MAJOR}-base=${GCC_VERSION} \
      cpp-${GCC_MAJOR}=${GCC_VERSION} \
      gcc-${GCC_MAJOR}=${GCC_VERSION} \
      libgcc-${GCC_MAJOR}-dev=${GCC_VERSION} \
      build-essential \
      ca-certificates \
      curl \
      kmod \
      libelf-dev \
      binutils \
      wget
apt autoremove -y

# Add packages from private gardenlinux source
# If you add packages to the following installation procedure, make sure these
# files exist in the public package mirror. Files must be added manually to this
# mirror by adding them via the script:
# ./tooling/upload_gardenlinux_packages.sh

GCC_MAJOR=$(echo $GCC_VERSION | cut -d '.' -f1) && \
    KERNEL_VERSION_PLAIN=$(echo $KERNEL_VERSION | cut -d '-' -f1,2) && \
    KERNEL_VERSION_MAJOR_MINOR=$(echo $KERNEL_VERSION_PLAIN | cut -d '.' -f1,2) && \
    DEBS_URL=${GARDENLINUX_PACKAGES_URL}/kernel_${KERNEL_VERSION_PLAIN}_linux_${LINUX_VERSION} && \
    mkdir -p "/tmp/pkg" && \
    files=( \
      linux-compiler-gcc-${GCC_MAJOR}-x86_${LINUX_VERSION}_amd64.deb \
      linux-headers-${KERNEL_VERSION_PLAIN}-common_${LINUX_VERSION}_all.deb \
      linux-kbuild-${KERNEL_VERSION_MAJOR_MINOR}_${LINUX_VERSION}_amd64.deb \
      linux-headers-${KERNEL_VERSION}_${LINUX_VERSION}_amd64.deb \
    ) && \
    for debfile in ${files[@]}; do \
      wget -O "/tmp/pkg/${debfile}" "${DEBS_URL}/${debfile}" ; \
      apt install "/tmp/pkg/${debfile}" ; \
    done

rm -rf /var/lib/apt/lists/*