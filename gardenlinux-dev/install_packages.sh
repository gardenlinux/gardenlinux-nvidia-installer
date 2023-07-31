#!/bin/bash
set -x
set -o errexit
set -o nounset
set -o pipefail

# Given GARDENLINUX_VERSION is set, export variables for each entry in the relevant row of image_versions
export $(GARDENLINUX_VERSION=$1 ./read_image_versions.sh | xargs)

printf "\n-------------\ninputs:\n\nLINUX_VERSION=%s\nLINUX_DATE=%s\nKERNEL_VERSION=%s\nGCC_VERSION=%s\nGCC_LINUX_VERSION=%s\nGARDENLINUX_PACKAGES_URL=%s\n-------------" \
  "${LINUX_VERSION}" \
  "${LINUX_DATE}" \
  "${KERNEL_VERSION}" \
  "${GCC_VERSION}" \
  "${GCC_LINUX_VERSION}" \
  "${GARDENLINUX_PACKAGES_URL}" # This last one is a build arg, and is the location of the Swift container with the package files

if [ -z $GCC_LINUX_VERSION ]; then
  GCC_LINUX_VERSION=${LINUX_VERSION}
fi

#DATESTAMP=$(echo ${LINUX_DATE} | sed 's/-//g') && \
DATESTAMP=$(echo ${LINUX_DATE} | sed 's/-//g') && rm -f /etc/apt/sources.list && \
  echo "deb http://snapshot.debian.org/archive/debian/${DATESTAMP}T000000Z testing main" >> /etc/apt/sources.list

apt-get -o Acquire::Check-Valid-Until=false update
GCC_MAJOR=$(echo $GCC_VERSION | cut -d '.' -f1)

packages=("build-essential" \
      "gcc-${GCC_MAJOR}-base=${GCC_VERSION}" \
      "cpp-${GCC_MAJOR}=${GCC_VERSION}" \
      "gcc-${GCC_MAJOR}=${GCC_VERSION}" \
      "libgcc-${GCC_MAJOR}-dev=${GCC_VERSION}" \
      "ca-certificates" \
      "curl" \
      "kmod" \
      "libelf-dev" \
      "binutils" \
      "wget")

for package in "${packages[@]}"; do
  max_retry=5
  counter=0
  until apt-get install -y --allow-downgrades --no-install-recommends $package
  do
     sleep 1
     [[ counter -eq $max_retry ]] && echo "Failed!" && exit 1
     echo "Trying again. Try #$counter"
     ((counter++)) || true
  done
done


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
      linux-compiler-gcc-${GCC_MAJOR}-x86_${GCC_LINUX_VERSION}_amd64.deb \
      linux-headers-${KERNEL_VERSION_PLAIN}-common_${LINUX_VERSION}_all.deb \
      linux-kbuild-${KERNEL_VERSION_MAJOR_MINOR}_${LINUX_VERSION}_amd64.deb \
      linux-headers-${KERNEL_VERSION}_${LINUX_VERSION}_amd64.deb \
    ) && \
    for debfile in "${files[@]}"; do \
      wget -O "/tmp/pkg/${debfile}" "${DEBS_URL}/${debfile}" ; \
      apt install "/tmp/pkg/${debfile}" ; \
    done

rm -rf /var/lib/apt/lists/*