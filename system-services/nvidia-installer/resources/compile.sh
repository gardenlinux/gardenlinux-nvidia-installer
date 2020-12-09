#!/bin/bash
echo "Compiling NVIDIA modules for driver version $DRIVER_VERSION"
set -e
set -x
mkdir -p /tmp/nvidia
# shellcheck disable=SC2164
pushd /tmp/nvidia
curl -Ls "https://download.nvidia.com/XFree86/Linux-x86_64/$DRIVER_VERSION/NVIDIA-Linux-x86_64-$DRIVER_VERSION.run" -o nvidia.run
chmod +x nvidia.run
./nvidia.run -x -s || cat nvidia.run
# shellcheck disable=SC2164
pushd "./NVIDIA-Linux-x86_64-$DRIVER_VERSION"
export IGNORE_MISSING_MODULE_SYMVERS=1
./nvidia-installer --silent \
    --no-questions \
    --ui=none \
    --no-opengl-files \
    --no-libglx-indirect \
    --no-install-libglvnd \
    --log-file-name="$PWD"/nvidia-installer.log

./nvidia-smi

if [[ "$?" != "0" ]]; then
echo "[ERROR] Failed to verify NVIDIA modules: nvidia-smi execution failed." \
  && cat "$PWD"/nvidia-installer.log \
  && exit 1 ; 
fi

if [ -e kernel/nvidia.ko ] ; then 
  echo "Successfully compiled NVIDIA modules" ; 
else 
  echo "[ERROR] Failed to compile NVIDIA modules" \
  && cat "$PWD"/nvidia-installer.log \
  && exit 1 ; 
fi

echo "Archiving assets"
KERNEL_VERSION=$(uname -r)
mkdir -p /out/lib/modules/"$KERNEL_VERSION" /out/bin
cp ./*.so* /out/lib
cp kernel/*.ko /lib/modules/"$KERNEL_VERSION"/modules.* /out/lib/modules/"$KERNEL_VERSION"

files=(\
  nvidia-debugdump \
  nvidia-cuda-mps-control \
  nvidia-xconfig \
  nvidia-modprobe \
  nvidia-smi \
  nvidia-cuda-mps-server \
  nvidia-persistenced \
  nvidia-settings 
)
for f in "${files[@]}"; do \
    cp "$f" /out/bin/;
done
