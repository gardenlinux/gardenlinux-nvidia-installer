#!/bin/bash

#Install kernel headers in a custom path

KERNEL_NAME=$(uname -r)
KERNEL_VERSION=$(uname -r | cut -d'-' -f1)
#TODO
DRIVER_VERSION="590.48.01"
ARCH_TYPE=$(uname -m)
KERNEL_MODULE_TYPE=$1
DRIVER_VERSION=$2

mkdir -p /run/nvidia/compile_dir
cd /run/nvidia/compile_dir
HOST_GL_VERSION=$(nsenter -t 1 -m sh -c "grep GARDENLINUX_VERSION /etc/os-release | cut -d= -f2")

cat <<EOF > /etc/apt/sources.list.d/gardenlinux_host.sources
Types: deb
URIs: https://packages.gardenlinux.io/gardenlinux
Suites: $HOST_GL_VERSION
Components: main
Enabled: yes
Signed-By: /etc/apt/trusted.gpg.d/keyring.asc
EOF

apt-get update

apt install -y -qq linux-headers-"$KERNEL_NAME" 
apt install -y -qq linux-headers-"$KERNEL_VERSION"-common
apt install -y -qq linux-kbuild-$KERNEL_VERSION


DRIVER_URL="https://uk.download.nvidia.com/tesla/$DRIVER_VERSION/NVIDIA-Linux-$ARCH_TYPE-$DRIVER_VERSION.run"

echo $DRIVER_URL

wget -qO /run/nvidia/compile_dir/nvidia.run "${DRIVER_URL}"
WGET_EXIT=$?
if [ $WGET_EXIT -ne 0 ]; then
  echo "Failed to download ${DRIVER_URL} (wget exit code: ${WGET_EXIT})"
  exit 1
fi

chmod +x nvidia.run
./nvidia.run -x -s --tmpdir /run/nvidia/compile_dir
      
export IGNORE_MISSING_MODULE_SYMVERS=1

export OUTDIR="/run/nvidia/driver"

cd NVIDIA-Linux-$ARCH_TYPE-$DRIVER_VERSION
#TODO
KERNEL_TYPE="open"
export PATH="/run/headers/usr/bin:$PATH"

./nvidia-installer --no-libglx-indirect --no-install-libglvnd \
    --kernel-name="$KERNEL_NAME" \
    --kernel-module-type=open -no-drm --no-install-compat32-libs --no-opengl-files \
    --ui=none --no-questions --silent --no-kernel-module-source --no-systemd --skip-depmod  \
    --log-file-name=/run/nvidia/nvidia-installer.log   --utility-prefix=/run/nvidia/driver/ \
    --utility-libdir=lib   --kernel-install-path="/run/nvidia/driver/lib/modules/$KERNEL_NAME"

cp -a  /run/nvidia/driver/ /run/nvidia/.staging-driver/