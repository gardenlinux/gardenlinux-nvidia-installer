#! /bin/bash

set -o errexit
set -o pipefail

main() {

  if [ -z $KERNEL_VERSION ]; then
    echo "Please set KERNEL_VERSION - see image_versions"
    badargs=1
  fi
  kernel_version="${KERNEL_VERSION/-cloud-amd64/}"
  kernel_version_major_minor=$(echo $kernel_version | cut -d '.' -f1,2)

  if [ -z $LINUX_VERSION ]; then
    echo "Please set LINUX_VERSION - see image_versions"
    badargs=1
  fi
  linux_version=${LINUX_VERSION}

  if [ -z $GCC_VERSION ]; then
    echo "Please set GCC_VERSION - see image_versions"
    badargs=1
  fi
  gcc_version=${GCC_VERSION}
  gcc_major=$(echo $gcc_version | cut -d '.' -f1)

  if [ -z $GCC_LINUX_VERSION ]; then
    gcc_linux_version=${linux_version}
  else
    gcc_linux_version=${GCC_LINUX_VERSION}
  fi

  # Garden Linux - from 576.10
  gardenlinux_build_server="https://repo.gardenlinux.io"
  gardenlinux_package_root="gardenlinux/pool/main/l/linux-${kernel_version_major_minor}"

  # OpenStack Swift
  container="gardenlinux-packages"
  export OS_PROJECT_DOMAIN_NAME=hcp03
  export OS_USER_DOMAIN_NAME=hcp03
  export OS_PROJECT_NAME=sapclea
  export OS_AUTH_URL=https://identity-3.eu-de-1.cloud.sap:443/v3
  export OS_IDENTITY_API_VERSION=3

  if [ -z $OS_USERNAME ]; then
    echo "Please set OS_USERNAME to your SAP user ID"
    badargs=1
  fi
  if [ -z $OS_PASSWORD ]; then
    echo "Please set OS_PASSWORD to your SAP password"
    badargs=1
  fi
  if [ ! -z $badargs ] ; then
    exit $badargs
  fi

  # Let's go...
  tmp_dir="tmp/upload"
  mkdir -p "${tmp_dir}"

  folder=kernel_${kernel_version}_linux_${linux_version}

#  echo "kernel_version is ${kernel_version}"
#  echo "linux_version is ${linux_version}"
#  echo "gcc_major is ${gcc_major}"
#  echo "gcc_linux_version is ${gcc_linux_version}"
#  echo "kernel_version_major_minor is ${kernel_version_major_minor}"

  debs=( \
    "linux-headers-${kernel_version}-common_${linux_version}_all.deb" \
    "linux-headers-${kernel_version}-cloud-amd64_${linux_version}_amd64.deb" \
    "linux-compiler-gcc-${gcc_major}-x86_${gcc_linux_version}_amd64.deb" \
    "linux-kbuild-${kernel_version_major_minor}_${linux_version}_amd64.deb" \
    )

  for file in "${debs[@]}"; do
    download $file && upload $container $folder $file
  done

  if [ -z "${DEBUG}" ]; then
    rm -r "${tmp_dir}"
  fi

  echo "[INFO] packages moved to s3"

}

download() {
  local -r name=$1
  echo "Downloading ${name}"
  if [ ! -f "${tmp_dir}/${name}" ]; then
      wget -O "${tmp_dir}/${name}" "${gardenlinux_build_server}/${gardenlinux_package_root}/${name}" || return 1
  fi
  return 0
}

# $1=container $2=folder $3=file
upload() {
  openstack object create --name $2/$3 $1 ${tmp_dir}/$3
}

main "${@}"
