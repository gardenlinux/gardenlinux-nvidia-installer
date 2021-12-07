#! /bin/bash

set -o errexit
set -o pipefail


# wget 18.185.215.86/packages/{linux-headers-5.4.0-5-amd64_5.4.68-1_amd64.deb,linux-headers-5.4.0-5-cloud-amd64_5.4.68-1_amd64.deb,linux-headers-5.4.0-5-common_5.4.68-1_all.deb,linux-compiler-gcc-10-x86_5.4.68-1_amd64.deb}

# packages available on the gardenlinux build server:
# bpftool-dbgsym_5.4.68-1_amd64.deb                     linux-headers-5.4.0-5-common_5.4.68-1_all.deb
# bpftool_5.4.68-1_amd64.deb                            linux-headers-5.4.0-5-rt-amd64_5.4.68-1_amd64.deb
# hyperv-daemons-dbgsym_5.4.68-1_amd64.deb              linux-image-5.4.0-5-amd64-unsigned_5.4.68-1_amd64.deb
# hyperv-daemons_5.4.68-1_amd64.deb                     linux-image-5.4.0-5-cloud-amd64-unsigned_5.4.68-1_amd64.deb
# libcpupower-dev_5.4.68-1_amd64.deb                    linux-image-5.4.0-5-rt-amd64-unsigned_5.4.68-1_amd64.deb
# libcpupower1-dbgsym_5.4.68-1_amd64.deb                linux-image-amd64-dbg_5.4.68-1_amd64.deb
# libcpupower1_5.4.68-1_amd64.deb                       linux-image-amd64-signed-template_5.4.68-1_amd64.deb
# libtraceevent-dev_5.4.68-1_amd64.deb                  linux-image-cloud-amd64-dbg_5.4.68-1_amd64.deb
# libtraceevent1-dbgsym_5.4.68-1_amd64.deb              linux-image-rt-amd64-dbg_5.4.68-1_amd64.deb
# libtraceevent1-plugin-dbgsym_5.4.68-1_amd64.deb       linux-kbuild-5.4-dbgsym_5.4.68-1_amd64.deb
# libtraceevent1-plugin_5.4.68-1_amd64.deb              linux-kbuild-5.4_5.4.68-1_amd64.deb
# libtraceevent1_5.4.68-1_amd64.deb                     linux-libc-dev_5.4.68-1_amd64.deb
# linux-build-deps_5.4.68-1_amd64.buildinfo             linux-perf-5.4-dbgsym_5.4.68-1_amd64.deb
# linux-build-deps_5.4.68-1_amd64.changes               linux-perf-5.4_5.4.68-1_amd64.deb
# linux-build-deps_5.4.68-1_amd64.deb                   linux-perf_5.4.68-1_amd64.deb
# linux-compiler-gcc-10-x86_5.4.68-1_amd64.deb          linux-source_5.4.68-1_all.deb
# linux-config-5.4_5.4.68-1_amd64.deb                   linux-support-5.4.0-5_5.4.68-1_all.deb
# linux-cpupower-dbgsym_5.4.68-1_amd64.deb              linux_5.4.68-1.debian.tar.xz
# linux-cpupower_5.4.68-1_amd64.deb                     linux_5.4.68-1.dsc
# linux-doc-5.4_5.4.68-1_all.deb                        linux_5.4.68-1_amd64.buildinfo
# linux-doc_5.4.68-1_all.deb                            linux_5.4.68-1_amd64.changes
# linux-headers-5.4.0-5-amd64_5.4.68-1_amd64.deb        usbip-dbgsym_2.0+5.4.68-1_amd64.deb
# linux-headers-5.4.0-5-cloud-amd64_5.4.68-1_amd64.deb  usbip_2.0+5.4.68-1_amd64.deb
# linux-headers-5.4.0-5-common-rt_5.4.68-1_all.deb


main() {
  # Garden Linux 184
#  gardenlinux_build_server="http://18.185.215.86"
#  gardenlinux_package_root="packages"
#  kernel_version="5.4.0-5"
#  linux_version="5.4.68-1"
#  gcc_version="10.2.0-9"

  # Garden Linux 318
  gardenlinux_build_server="http://45.86.152.1"
  gardenlinux_package_root="gardenlinux/pool/main/l/linux"
  kernel_version="5.4.0-6"
  linux_version="5.4.93-1"
  gcc_version="10.2.1-6"

  # OpenStack Swift
  container="gardenlinux-packages"
  export OS_PROJECT_DOMAIN_NAME=hcp03
  export OS_USER_DOMAIN_NAME=hcp03
  export OS_PROJECT_NAME=sapclea
  export OS_PASSWORD=userpassword
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

  gcc_major=$(echo $gcc_version | cut -d '.' -f1)
  kernel_version_major_minor=$(echo $kernel_version | cut -d '.' -f1,2)

  folder=kernel_${kernel_version}_linux_${linux_version}

  # download "linux-headers-${kernel_version}-amd64_${linux_version}_amd64.deb"
  debs=( \
    "linux-headers-${kernel_version}-common_${linux_version}_all.deb" \
    "linux-headers-${kernel_version}-cloud-amd64_${linux_version}_amd64.deb" \
    "linux-compiler-gcc-${gcc_major}-x86_${linux_version}_amd64.deb" \
    "linux-kbuild-${kernel_version_major_minor}_${linux_version}_amd64.deb" \
    )

  for file in debs; do
    download $file
    upload $container $folder $file
  done

  if [ -z "${DEBUG}" ]; then
    rm -r "${tmp_dir}"
  fi

  echo "[INFO] packages moved to s3"

}

download() {
  local -r name=$1
  if [ ! -f "${tmp_dir}/${name}" ]; then
      wget -O "${tmp_dir}/${name}" "${gardenlinux_build_server}/${gardenlinux_package_root}/${name}"
  fi
}

# $1=container $2=folder $3=file
upload() {
  openstack object create --name $2/$3 $1 $3
}

main "${@}"

