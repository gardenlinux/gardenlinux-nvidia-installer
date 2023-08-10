#!/bin/bash
echo "Compiling NVIDIA modules for driver version $DRIVER_VERSION on kernel $KERNEL_VERSION"

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

case $TARGET_ARCH in
    amd64)
      if ./nvidia-installer \
          --no-opengl-files \
          --no-libglx-indirect \
          --no-install-libglvnd \
          --kernel-name="$KERNEL_VERSION" \
          --no-drm \
          --no-install-compat32-libs \
          --no-opengl-files \
          --no-kernel-module-source \
          --log-file-name="$PWD"/nvidia-installer.log \
        && test -e kernel/nvidia.ko
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
          --kernel-name="$KERNEL_VERSION" \
          --no-drm \
          --no-opengl-files \
          --no-kernel-module-source \
          --log-file-name="$PWD"/nvidia-installer.log \
        && test -e kernel/nvidia.ko
      then
        echo "Successfully compiled NVIDIA modules"
      else 
        echo "[ERROR] Failed to compile NVIDIA modules"
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
OUTDIR="/out/nvidia/$DRIVER_VERSION"
mkdir -p "$OUTDIR"/lib/modules/"$KERNEL_VERSION" "$OUTDIR"/bin

# Archive driver files
cp ./*.so* "$OUTDIR"/lib
pushd "$OUTDIR"/lib ; ln -s ./libcuda.so.* libcuda.so.1 ; popd
cp kernel/*.ko /lib/modules/"$KERNEL_VERSION"/modules.* "$OUTDIR"/lib/modules/"$KERNEL_VERSION"

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
    cp "$f" "$OUTDIR"/bin/;
done

# shellcheck disable=SC2046
tar czf "$OUTDIR".tar.gz --directory $(dirname "$OUTDIR") $(basename "$OUTDIR") && rm -rf "$OUTDIR"
