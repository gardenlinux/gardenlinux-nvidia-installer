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

attempt=0
MAX_ATTEMPTS=3

while (( attempt < MAX_ATTEMPTS )); do
    wget -qO /run/nvidia/compile_dir/nvidia.run "${DRIVER_URL}" && break
    echo "Attempt $attempt failed. Retrying..."
    ((attempt++))
    sleep 2 
done

if (( attempt >= MAX_ATTEMPTS )); then
    echo "Download failed after $MAX_ATTEMPTS attempts."
    exit 1
else
    echo "Download succeeded."
fi

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
export PATH="/run/headers/usr/bin:$PATH"
OUTDIR="/run/nvidia/driver"
case $ARCH_TYPE in
    amd64)
      if ./nvidia-installer \
          --no-libglx-indirect \
          --no-install-libglvnd \
          --kernel-name="$KERNEL_NAME" \
          --kernel-module-type="$KERNEL_MODULE_TYPE" \
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
          --kernel-install-path="$OUTDIR"/lib/modules/$KERNEL_NAME" \
        && test -e "$OUTDIR"/lib/modules/"$KERNEL_NAME"/nvidia.ko
      then
        echo "Successfully compiled NVIDIA $KERNEL_MODULE_TYPE modules"
      else
        echo "[ERROR] Failed to compile NVIDIA $KERNEL_MODULE_TYPE modules"
        cat "$PWD"/nvidia-installer.log
        exit 1
      fi
        ;;
    arm64)
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
          --kernel-install-path="$OUTDIR"/lib/modules/$KERNEL_NAME" \
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

cp -a  /run/nvidia/driver/ /run/nvidia/.staging-driver/