#!/bin/bash
if [ -z "$DRIVER_VERSION" ]; then
    echo "Error: DRIVER_VERSION is not set."
    exit 1
fi
if [ -z "$KERNEL_NAME" ]; then
    echo "Error: KERNEL_NAME is not set."
    exit 1
fi
if [ -z "$TARGET_ARCH" ]; then
    echo "Error: TARGET_ARCH is not set."
    exit 1
fi

set -x
mkdir -p /tmp/nvidia

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
curl -Ls "${DRIVER_URL}" -o nvidia.run
CURL_EXIT=$?
if [ $CURL_EXIT -ne 0 ]; then
  echo "Failed to download ${DRIVER_URL} (curl exit code: ${CURL_EXIT})"
  exit 1
fi
chmod +x nvidia.run
./nvidia.run -x -s

# shellcheck disable=SC2164
pushd "./NVIDIA-Linux-$ARCH_TYPE-$DRIVER_VERSION"
export IGNORE_MISSING_MODULE_SYMVERS=1

compile_kernel_type() {
    local KERNEL_TYPE=$1
    local OUTDIR="/out/nvidia/driver/$KERNEL_TYPE"

    echo "Compiling NVIDIA modules for $KERNEL_TYPE driver version $DRIVER_VERSION on kernel $KERNEL_NAME"

    case $TARGET_ARCH in
        amd64)
          if ./nvidia-installer \
              --no-libglx-indirect \
              --no-install-libglvnd \
              --kernel-name="$KERNEL_NAME" \
              --kernel-module-type="$KERNEL_TYPE" \
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
            echo "Successfully compiled NVIDIA $KERNEL_TYPE modules"
          else
            echo "[ERROR] Failed to compile NVIDIA $KERNEL_TYPE modules"
            cat "$PWD"/nvidia-installer.log
            exit 1
          fi
            ;;
        arm64)
          if ./nvidia-installer \
              --no-libglx-indirect \
              --no-install-libglvnd \
              --kernel-name="$KERNEL_NAME" \
              --kernel-module-type="$KERNEL_TYPE" \
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
            echo "Successfully compiled NVIDIA $KERNEL_TYPE modules"
          else
            echo "[ERROR] Failed to compile NVIDIA $KERNEL_TYPE modules"
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

    echo "Fetching GSP Firmware"
    mkdir -p "$OUTDIR"/lib/firmware/nvidia/"$DRIVER_VERSION"/
    find /tmp/nvidia -type f -name '*gsp*.bin' -exec cp -a {} "$OUTDIR/lib/firmware/nvidia/$DRIVER_VERSION/" \;

    echo "Archiving assets"

    # Archive library .so files
    mkdir -p "$OUTDIR"/usr/lib/"$ARCH_TYPE"-linux-gnu "$OUTDIR"/usr/bin
    cp -a /usr/lib/"$ARCH_TYPE"-linux-gnu/*nvidia* /usr/lib/"$ARCH_TYPE"-linux-gnu/*cuda* "$OUTDIR"/usr/lib/"$ARCH_TYPE"-linux-gnu
    cp -a /usr/bin/nvidia* "$OUTDIR"/usr/bin
    # We don't need the installer binaries, or the icons/desktop files in /share
    rm -rf "$OUTDIR"/bin/*install* "$OUTDIR"/share

    # shellcheck disable=SC2046
    tar czf "$OUTDIR-$DRIVER_VERSION-$KERNEL_NAME".tar.gz --directory $(dirname "$OUTDIR") $(basename "$OUTDIR") && rm -rf "$OUTDIR"
}

compile_kernel_type open
compile_kernel_type proprietary
