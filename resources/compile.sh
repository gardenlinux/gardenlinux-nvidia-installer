#!/bin/bash
if [ -z "$DRIVER_VERSION" ]; then
    echo "Error: DRIVER_VERSION is not set."
    exit 1
fi
if [ -z "$KERNEL_NAME" ]; then
    echo "Error: KERNEL_NAME is not set."
    exit 1
fi

echo "Compiling NVIDIA modules for driver version $DRIVER_VERSION on kernel $KERNEL_NAME"

set -x
mkdir -p /tmp/nvidia

if [ -z "$TARGET_ARCH" ]; then
    echo "Error: TARGET_ARCH is not set."
    exit 1
fi

declare -A arch_translation
arch_translation=(["amd64"]="x86_64" ["arm64"]="aarch64")

if [[ ! ${arch_translation[$TARGET_ARCH]+_} ]]; then
    echo "Error: Unsupported TARGET_ARCH value."
    exit 2
fi
ARCH_TYPE=${arch_translation[$TARGET_ARCH]}


# shellcheck disable=SC2164
pushd /tmp/nvidia
DRIVER_URL="https://uk.download.nvidia.com/tesla/$DRIVER_VERSION/NVIDIA-Linux-$ARCH_TYPE-$DRIVER_VERSION.run"
if ! curl -Ls "${DRIVER_URL}" -o nvidia.run ; then
  echo "Failed to download ${DRIVER_URL}"
  exit 1
fi
chmod +x nvidia.run
./nvidia.run -x -s

# shellcheck disable=SC2164
pushd "./NVIDIA-Linux-$ARCH_TYPE-$DRIVER_VERSION"
export IGNORE_MISSING_MODULE_SYMVERS=1
OUTDIR="/out/nvidia/$DRIVER_VERSION"

case $TARGET_ARCH in
    amd64)
      if ./nvidia-installer \
          --no-opengl-files \
          --no-libglx-indirect \
          --no-install-libglvnd \
          --kernel-name="$KERNEL_NAME" \
          --no-drm \
          --no-install-compat32-libs \
          --no-opengl-files \
          --ui=none --no-questions \
          --no-kernel-module-source \
          --no-systemd \
          --skip-depmod \
          --log-file-name="$PWD"/nvidia-installer.log \
          --utility-prefix="$OUTDIR" \
          --utility-libdir=lib \
          --kernel-install-path="$OUTDIR"/lib/modules/"$KERNEL_NAME" \
        && test -e "$OUTDIR"/lib/modules/"$KERNEL_NAME"/nvidia.ko
      then
        echo "Successfully compiled NVIDIA modules"
      else 
        echo "[ERROR] Failed to compile NVIDIA modules"
        cat "$PWD"/nvidia-installer.log
        exit 1
      fi
        ;;
    arm64)
      if ./nvidia-installer \
          --no-opengl-files \
          --no-libglx-indirect \
          --no-install-libglvnd \
          --kernel-name="$KERNEL_NAME" \
          --no-drm \
          --no-opengl-files \
          --no-kernel-module-source \
          --ui=none --no-questions \
          --no-systemd \
          --skip-depmod \
          --log-file-name="$PWD"/nvidia-installer.log \
          --utility-prefix="$OUTDIR" \
          --utility-libdir=lib \
          --kernel-install-path="$OUTDIR"/lib/modules/"$KERNEL_NAME" \
        && test -e "$OUTDIR"/lib/modules/"$KERNEL_NAME"/nvidia.ko
      then
        echo "Successfully compiled NVIDIA modules"
      else 
        echo "[ERROR] Failed to compile NVIDIA modules"
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

echo "Archiving assets"

# Archive library .so files
cp /usr/lib/"$ARCH_TYPE"-linux-gnu/*nvidia* /usr/lib/"$ARCH_TYPE"-linux-gnu/*cuda* "$OUTDIR"/lib

# We don't need the installer binaries, or the icons/desktop files in /share
rm -rf "$OUTDIR"/bin/*install* "$OUTDIR"/share

# shellcheck disable=SC2046
tar czf "$OUTDIR".tar.gz --directory $(dirname "$OUTDIR") $(basename "$OUTDIR") && rm -rf "$OUTDIR"
