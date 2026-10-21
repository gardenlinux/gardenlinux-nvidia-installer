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
    local OUTDIR="/out/nvidia/driver"

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
        arm64)
          if ./nvidia-installer \
              --no-libglx-indirect \
              --no-install-libglvnd \
              --kernel-name="$KERNEL_NAME" \
              --kernel-module-type="$KERNEL_TYPE" \
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

    echo "Copy GSP Firmware binary"
    mkdir -p "$OUTDIR"/lib/firmware/nvidia/"$DRIVER_VERSION"/
    find /tmp/nvidia -type f -name '*gsp*.bin' -exec cp -a {} "$OUTDIR/lib/firmware/nvidia/$DRIVER_VERSION/" \;

    echo "Copy supported-gpus and license files"
    local NVIDIA_DIR="/tmp/nvidia/NVIDIA-Linux-${ARCH_TYPE}-${DRIVER_VERSION}"
    mkdir -p "${OUTDIR}/License/supported-gpus"
    cp -a "${NVIDIA_DIR}/supported-gpus/supported-gpus.json" "${OUTDIR}/License/supported-gpus/"
    cp -a "${NVIDIA_DIR}/supported-gpus/LICENSE" "${OUTDIR}/License/supported-gpus/"
    cp -a "${NVIDIA_DIR}/LICENSE" "${OUTDIR}/License"
    
    echo "Archiving assets"
    # Archive library .so files
    mkdir -p "$OUTDIR"/usr/lib/"$ARCH_TYPE"-linux-gnu "$OUTDIR"/usr/bin
    cp -a /usr/lib/"$ARCH_TYPE"-linux-gnu/*nvidia* /usr/lib/"$ARCH_TYPE"-linux-gnu/*cuda* "$OUTDIR"/usr/lib/"$ARCH_TYPE"-linux-gnu
    cp -a /usr/bin/nvidia* "$OUTDIR"/usr/bin
    # We don't need the installer binaries, or the icons/desktop files in /share
    rm -rf "$OUTDIR"/bin/*install* "$OUTDIR"/share

    # shellcheck disable=SC2046
    tar czf "$OUTDIR-$DRIVER_VERSION-$KERNEL_TYPE-$KERNEL_NAME".tar.gz --directory $(dirname "$OUTDIR") $(basename "$OUTDIR") && rm -rf "$OUTDIR"

    set +x
}


# extract_nvidia_fs_source downloads the nvidia-fs local-repo .deb and extracts
# the kernel module source into /tmp/nvidia-fs/src. The local-repo .deb is a
# wrapper that contains a second inner .deb (nvidia-fs-dkms) with the actual
# source under /usr/src/nvidia-fs-<version>/.
#
# nvidia-fs source is not available as plain source — NVIDIA only ships it inside
# this local-repo package, which is free to use once extracted.
extract_nvidia_fs_source() {
    local DEB_URL="https://developer.download.nvidia.com/compute/nvidia-fs/${NVIDIA_FS_VERSION}/local_installers/nvidia-fs-local-repo-ubuntu2204-${NVIDIA_FS_VERSION}_1.0-1_amd64.deb"
    local WORK_DIR="/tmp/nvidia-fs"

    echo "Extracting nvidia-fs ${NVIDIA_FS_VERSION} source"

    mkdir -p "${WORK_DIR}"
    wget -qO "${WORK_DIR}/local-repo.deb" "${DEB_URL}"

    # The outer .deb sets up a local apt repo. Extract it to get at the inner .deb.
    dpkg-deb --extract "${WORK_DIR}/local-repo.deb" "${WORK_DIR}/local-repo"

    local INNER_DEB
    INNER_DEB=$(find "${WORK_DIR}/local-repo" -name "nvidia-fs-dkms_*.deb" | head -1)
    if [ -z "${INNER_DEB}" ]; then
        echo "[ERROR] nvidia-fs-dkms inner deb not found inside local-repo"
        exit 1
    fi

    # The inner .deb contains the kernel module source under /usr/src/nvidia-fs-<version>/
    dpkg-deb --extract "${INNER_DEB}" "${WORK_DIR}/src"

    local GDS_INNER_VERSION
    GDS_INNER_VERSION=$(basename "${INNER_DEB}" | sed 's/nvidia-fs-dkms_\([^_]*\)_.*/\1/')
    # Export so callers know the exact source directory
    NVIDIA_FS_SRC_DIR="${WORK_DIR}/src/usr/src/nvidia-fs-${GDS_INNER_VERSION}"
}

# compile_nvidia_fs builds nvidia-fs.ko against the already-compiled nvidia.ko.
#
# nvidia-fs depends on nvidia_p2p_* symbols from nvidia.ko. Normally this is
# resolved by modinfo on a running system, but in the build container we extract
# the symbol versions directly from the compiled nvidia.ko using nm.
#
# Must run after compile_kernel_type (open + proprietary) since it reads nvidia.ko
# from the finished open tarball and then injects nvidia-fs.ko into both tarballs.
compile_nvidia_fs() {
    extract_nvidia_fs_source

    # Pull nvidia.ko out of the already-built open tarball for symbol extraction.
    # (open and proprietary nvidia.ko are identical for the p2p symbols we need.)
    local OPEN_TARBALL="/out/nvidia/driver-${DRIVER_VERSION}-open-${KERNEL_NAME}.tar.gz"
    if [ ! -f "${OPEN_TARBALL}" ]; then
        echo "[ERROR] ${OPEN_TARBALL} not found — compile_kernel_type must run first"
        exit 1
    fi
    local NVIDIA_KO="/tmp/nvidia-fs/nvidia.ko"
    tar xzf "${OPEN_TARBALL}" -C /tmp/nvidia-fs --strip-components=3 \
        "driver/lib/modules/${KERNEL_NAME}/nvidia.ko"

    # Build nv.symvers from the compiled nvidia.ko so the kernel build system
    # can resolve nvidia_p2p_* symbol versions without a live loaded module.
    nm -o "${NVIDIA_KO}" \
        | awk '/(__crc_nvidia_p2p_|T nvidia_p2p_)/ {
            gsub(/\.\//, "", $1); gsub(/\.ko[^:]*/, "", $1)
            if ($2 ~ /^__crc_/) { printf "0x%s\t%s\t%s\tEXPORT_SYMBOL\t\n", $1, gensub(/__crc_/,"","1",$2), $1 }
            else                 { printf "0x0\t%s\t%s\tEXPORT_SYMBOL\t\n", $3, $1 }
          }' > "${NVIDIA_FS_SRC_DIR}/nv.symvers"
    cp "${NVIDIA_FS_SRC_DIR}/nv.symvers" "${NVIDIA_FS_SRC_DIR}/Module.symvers"

    # nv-p2p.h is needed by nvidia-fs; it lives in the kernel source tree that
    # the NVIDIA .run installer unpacked into /tmp/nvidia/.
    local NVIDIA_SRC_DIR
    NVIDIA_SRC_DIR=$(find "/tmp/nvidia/NVIDIA-Linux-${ARCH_TYPE}-${DRIVER_VERSION}" -name "nv-p2p.h" | head -1 | xargs dirname)
    if [ -z "${NVIDIA_SRC_DIR}" ]; then
        echo "[ERROR] nv-p2p.h not found — NVIDIA driver .run must be extracted first"
        exit 1
    fi

    echo "Compiling nvidia-fs ${NVIDIA_FS_VERSION} for kernel ${KERNEL_NAME}"

    KCPPFLAGS="-DCONFIG_NVFS_STATS=y -DGDS_VERSION=$(cat "${NVIDIA_FS_SRC_DIR}/GDS_VERSION") -DNVFS_BATCH_SUPPORT=y" \
    CONFIG_NVFS_BATCH_SUPPORT=y \
    CONFIG_NVFS_STATS=y \
    KBUILD_EXTRA_SYMBOLS="${NVIDIA_FS_SRC_DIR}/nv.symvers" \
    make -j"$(nproc)" \
        -C "/lib/modules/${KERNEL_NAME}/build" \
        M="${NVIDIA_FS_SRC_DIR}" \
        KVER="${KERNEL_NAME}" \
        NVIDIA_SRC_DIR="${NVIDIA_SRC_DIR}" \
        KBUILD_MODPOST_WARN=1 \
        modules

    if [ ! -f "${NVIDIA_FS_SRC_DIR}/nvidia-fs.ko" ]; then
        echo "[ERROR] nvidia-fs.ko was not produced by the build"
        exit 1
    fi
    echo "nvidia-fs compiled successfully"

    # Inject nvidia-fs.ko into both driver tarballs (open and proprietary).
    # We unpack, add the .ko, and repack since .tar.gz doesn't support append.
    for KERNEL_TYPE in open proprietary; do
        local TARBALL="/out/nvidia/driver-${DRIVER_VERSION}-${KERNEL_TYPE}-${KERNEL_NAME}.tar.gz"
        local UNPACK_DIR="/tmp/nvidia-fs-inject-${KERNEL_TYPE}"
        mkdir -p "${UNPACK_DIR}"
        tar xzf "${TARBALL}" -C "${UNPACK_DIR}"
        cp "${NVIDIA_FS_SRC_DIR}/nvidia-fs.ko" "${UNPACK_DIR}/driver/lib/modules/${KERNEL_NAME}/"
        tar czf "${TARBALL}" -C "${UNPACK_DIR}" driver
        rm -rf "${UNPACK_DIR}"
        echo "Injected nvidia-fs.ko into ${TARBALL}"
    done
}

compile_kernel_type open
compile_kernel_type proprietary

if [ -n "$NVIDIA_FS_VERSION" ]; then
    compile_nvidia_fs
fi
