#!/bin/bash

#Install kernel headers in a custom path

KERNEL_NAME=$(uname -r)
KERNEL_VERSION=$(uname -r | cut -d'-' -f1)

mkdir -p /run/headers/"$KERNEL_VERSION"

apt download linux-headers-"$KERNEL_NAME" 
apt download linux-headers-"$KERNEL_VERSION"-common


for deb in /run/nvidia/.staging-driver/linux-headers-"$KERNEL_VERSION"-*.deb; do
    echo $deb
    dpkg -x "$deb" /run/headers/"$KERNEL_VERSION"
done


DRIVER_URL="https://uk.download.nvidia.com/tesla/$DRIVER_VERSION/NVIDIA-Linux-$ARCH_TYPE-$DRIVER_VERSION.run"

echo $DRIVER_URL

curl -Ls "${DRIVER_URL}" -o /run/nvidia/nvidia.run
CURL_EXIT=$?
if [ $CURL_EXIT -ne 0 ]; then
  echo "Failed to download ${DRIVER_URL} (curl exit code: ${CURL_EXIT})"
  exit 1
fi
chmod +x nvidia.run
./nvidia.run -x -s 
      
export IGNORE_MISSING_MODULE_SYMVERS=1

export OUTDIR="/run/nvidia/driver"

case $ARCH_TYPE in
  x86_64)
    if ./nvidia-installer \
        --no-libglx-indirect \
        --no-install-libglvnd \
        --kernel-name="$KERNEL_NAME" \
        --kernel-module-type="$KERNEL_TYPE" \
        --no-drm \
        --no-install-compat32-libs \
        --no-opengl-files \
        --ui=none --no-questions --silent \
        --no-kernel-module-source \
        --no-systemd \
        --skip-depmod \
        --log-file-name="$PWD"/nvidia-installer.log \
        --utility-prefix="$OUTDIR" \
        --utility-libdir=lib \
        --kernel-install-path="$OUTDIR"/lib/modules/"$KERNEL_NAME" \
    && test -e "$OUTDIR"/lib/modules/"$KERNEL_NAME"/nvidia.ko
    then
      echo "Successfully compiled NVIDIA $KERNEL_TYPE modules"
    else
      echo "[ERROR] Failed to compile NVIDIA $KERNEL_TYPE modules"
      cat "$PWD"/nvidia-installer.log
      exit 1
    fi
    ;;
  aarch64)
    if ./nvidia-installer \
        --no-libglx-indirect \
        --no-install-libglvnd \
        --kernel-name="$KERNEL_NAME" \
        --kernel-module-type="$KERNEL_MODULE_TYPE" \
        --no-drm \
        --no-opengl-files \
        --no-kernel-module-source \
        --ui=none --no-questions --silent \
        --no-systemd \
        --skip-depmod \
        --log-file-name="$PWD"/nvidia-installer.log \
        --utility-prefix="$OUTDIR" \
        --utility-libdir=lib \
        --kernel-install-path="$OUTDIR"/lib/modules/"$KERNEL_NAME" \
    && test -e "$OUTDIR"/lib/modules/"$KERNEL_NAME"/nvidia.ko
    then
      echo "Successfully compiled NVIDIA $KERNEL_MODULE_TYPE modules"
    else
      echo "[ERROR] Failed to compile NVIDIA $KERNEL_MODULE_TYPE modules"
      cat /tmp/nvidia/NVIDIA-Linux-aarch64-"$DRIVER_VERSION"/nvidia-installer.log
      cat "$PWD"/nvidia-installer.log
      exit 1
    fi
    ;;
  *)
    echo "Unsupported architecture"
    exit 3
    ;;
esac
