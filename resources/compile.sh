#!/bin/bash

#Install kernel headers in a custom path

KERNEL_NAME=$(uname -r)
KERNEL_VERSION=$(uname -r | cut -d'-' -f1)
#TODO
DRIVER_VERSION="590.48.01"
ARCH_TYPE=$(uname -m)

mkdir -p /run/nvidia/compile_dir
cd /run/nvidia/compile_dir

#mkdir -p /run/headers/

apt install linux-headers-"$KERNEL_NAME" 
apt install linux-headers-"$KERNEL_VERSION"-common
apt install linux-kbuild-$KERNEL_VERSION

#apt-get download build-essential gcc g++ make libc6-dev dpkg-dev binutils binutils-common binutils-x86-64-linux-gnu gcc-14 gcc-14-x86-64-linux-gnu cpp cpp-14 cpp-14-x86-64-linux-gnu cpp-x86-64-linux-gnu g++-14 g++-14-x86-64-linux-gnu g++-x86-64-linux-gnu libjansson4 binutils-x86-64-linux-gnu libc-dev-bin linux-libc-dev libstdc++-14-dev dpkg-dev libdpkg-perl patch libcc1-0 libctf-nobfd0 libctf0 libgcc-14-dev libbinutils

#for deb in /run/nvidia/compile_dir/*.deb; do
#    dpkg -x "$deb" /run/headers/
#done


DRIVER_URL="https://uk.download.nvidia.com/tesla/$DRIVER_VERSION/NVIDIA-Linux-$ARCH_TYPE-$DRIVER_VERSION.run"

echo $DRIVER_URL


#export SYSROOT=/run/headers
#export CC="$SYSROOT/usr/bin/gcc --sysroot=$SYSROOT"
#export CXX="$SYSROOT/usr/bin/g++ --sysroot=$SYSROOT"
#export CPPFLAGS="--sysroot=$SYSROOT -I$SYSROOT/usr/include -I$SYSROOT/usr/include/x86_64-linux-gnu"
#export CFLAGS="--sysroot=$SYSROOT"
#export CXXFLAGS="--sysroot=$SYSROOT"
#export LDFLAGS="--sysroot=$SYSROOT -L$SYSROOT/usr/lib/x86_64-linux-gnu -Wl,-rpath-link,$SYSROOT/usr/lib/x86_64-linux-gnu"

curl -Ls "${DRIVER_URL}" -o /run/nvidia/compile_dir/nvidia.run
CURL_EXIT=$?
if [ $CURL_EXIT -ne 0 ]; then
  echo "Failed to download ${DRIVER_URL} (curl exit code: ${CURL_EXIT})"
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