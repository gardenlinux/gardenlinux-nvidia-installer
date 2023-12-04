#!/bin/bash
set -x
set -o errexit
set -o nounset
set -o pipefail

DATESTAMP=$(echo ${LINUX_DATE} | sed 's/-//g') && rm -f /etc/apt/sources.list && \
  echo "deb [ trusted=true ] http://snapshot.debian.org/archive/debian/${DATESTAMP}T000000Z testing main" >> /etc/apt/sources.list

apt-get -o Acquire::Check-Valid-Until=false -o Acquire::AllowInsecureRepositories=true update
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
      "python3" \
      "python3-pip" \
      "python3-venv" \
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
