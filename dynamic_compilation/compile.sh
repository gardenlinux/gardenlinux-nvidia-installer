#!/bin/bash

KERNEL_NAME=$(uname -r)
KERNEL_VERSION=$(uname -r | cut -d'-' -f1)
ARCH_TYPE=$(uname -m)
KERNEL_MODULE_TYPE=$1
DRIVER_VERSION=$2

COMPILE_DIR="/tmp/compile_dir"
# Directory the NVIDIA .run installer unpacks into (set in download_driver).
DRIVER_SRC_DIR="$COMPILE_DIR/NVIDIA-Linux-$ARCH_TYPE-$DRIVER_VERSION"

# Where compiled modules and libraries are assembled before staging.
OUTDIR="/run/nvidia/${DRIVER_VERSION}/driver"


install_kernel_headers() {
    local host_gl_version
    host_gl_version=$(nsenter -t 1 -m sh -c "grep GARDENLINUX_VERSION /etc/os-release | cut -d= -f2")

    cat <<EOF > /etc/apt/sources.list.d/gardenlinux_host.sources
Types: deb
URIs: https://packages.gardenlinux.io/gardenlinux
Suites: $host_gl_version
Components: main
Enabled: yes
Signed-By: /etc/apt/trusted.gpg.d/keyring.asc
EOF

    apt-get update
    apt install -y -qq linux-headers-"$KERNEL_NAME"
    apt install -y -qq linux-headers-"$KERNEL_VERSION"-common
    apt install -y -qq linux-kbuild-"$KERNEL_VERSION"
}


download_driver() {
    local driver_url="$BASE_URL/$DRIVER_VERSION/NVIDIA-Linux-$ARCH_TYPE-$DRIVER_VERSION.run"
    echo "Downloading $driver_url"

    local attempt=0
    local max_attempts=3
    while (( attempt < max_attempts )); do
        wget -qO "$COMPILE_DIR/nvidia.run" "$driver_url" && break
        echo "Attempt $attempt failed. Retrying..."
        (( attempt++ ))
        sleep 2
    done

    if (( attempt >= max_attempts )); then
        echo "Download failed after $max_attempts attempts."
        exit 1
    fi

    # `.run -x` extracts into the current directory, so cd into COMPILE_DIR
    # first to make sure the driver source lands at DRIVER_SRC_DIR.
    chmod +x "$COMPILE_DIR/nvidia.run"
    (cd "$COMPILE_DIR" && ./nvidia.run -x -s --tmpdir "$COMPILE_DIR")
}


compile_nvidia() {
    export IGNORE_MISSING_MODULE_SYMVERS=1

    # nvidia-modeset.ko (open modules) requires acpi_video symbols exported by the
    # video module (CONFIG_ACPI_VIDEO=m). On headless cloud nodes the module exists
    # on disk but is never auto-loaded. nsenter into the host mount namespace so
    # modprobe can find /lib/modules on the host (not the container). Non-fatal:
    # kernels with acpi_video built-in or already loaded will simply no-op.
    nsenter -t 1 -m -- modprobe wmi 2>/dev/null || true
    nsenter -t 1 -m -- modprobe video 2>/dev/null || true

    local installer_flags=(
        --no-libglx-indirect
        --no-install-libglvnd
        --kernel-name="$KERNEL_NAME"
        --kernel-module-type="$KERNEL_MODULE_TYPE"
        --no-drm
        --no-opengl-files
        --no-kernel-module-source
        --ui=none --no-questions --silent
        --no-systemd
        --skip-depmod
        --log-file-name="$DRIVER_SRC_DIR/nvidia-installer.log"
        --utility-prefix="$OUTDIR"
        --utility-libdir=lib
        --kernel-install-path="$OUTDIR/lib/modules/$KERNEL_NAME"
    )

    case $ARCH_TYPE in
        x86_64)  installer_flags+=(--no-install-compat32-libs) ;;
        aarch64) ;;
        *)
            echo "Unsupported architecture $ARCH_TYPE. Expected x86_64 or aarch64"
            exit 3
            ;;
    esac

    local log="$DRIVER_SRC_DIR/nvidia-installer.log"
    if (cd "$DRIVER_SRC_DIR" && ./nvidia-installer "${installer_flags[@]}") \
        && test -e "$OUTDIR/lib/modules/$KERNEL_NAME/nvidia.ko"
    then
        echo "Successfully compiled NVIDIA $KERNEL_MODULE_TYPE modules"
    else
        echo "[ERROR] Failed to compile NVIDIA $KERNEL_MODULE_TYPE modules"
        cat "$log"
        exit 1
    fi
}


# read_nvidia_fs_version reads the pinned nvidia-fs version from versions.yaml,
# which is copied into the image next to this script. Used as a fallback when
# NVIDIA_FS_VERSION is not set. versions.yaml holds a single-item list:
#   nvidia_fs_versions:
#   - 2.30.2
read_nvidia_fs_version() {
    local versions_file="/opt/nvidia-installer/versions.yaml"
    awk '
        /^nvidia_fs_versions:/ { in_block=1; next }
        in_block && /^[[:space:]]*-/ { gsub(/[-[:space:]]/, ""); print; exit }
    ' "$versions_file"
}


compile_nvidia_fs() {
    local fs_version="${NVIDIA_FS_VERSION:-$(read_nvidia_fs_version)}"
    if [ -z "$fs_version" ]; then
        echo "[ERROR] Could not determine an nvidia-fs version"
        exit 1
    fi

    local major_minor
    major_minor=$(echo "$fs_version" | cut -d. -f1-2)

    local work_dir="/tmp/nvidia-fs"
    local tarball_url="https://developer.download.nvidia.com/compute/nvidia-fs/redist/nvidia_fs/linux-x86_64/nvidia_fs-linux-x86_64-${fs_version}-archive.tar.xz"

    echo "Downloading nvidia-fs $fs_version"
    mkdir -p "$work_dir"
    wget -qO "$work_dir/nvidia-fs.tar.xz" "$tarball_url"
    tar xf "$work_dir/nvidia-fs.tar.xz" -C "$work_dir" --strip-components=1

    local src_dir="$work_dir/src/nvidia-fs-$major_minor"

    local nvidia_src_dir
    nvidia_src_dir=$(find "$DRIVER_SRC_DIR" -name "nv-p2p.h" | head -1 | xargs dirname)
    if [ -z "$nvidia_src_dir" ]; then
        echo "[ERROR] nv-p2p.h not found — NVIDIA driver .run must be extracted first"
        exit 1
    fi

    echo "Configuring nvidia-fs $fs_version for kernel $KERNEL_NAME"
    (cd "$src_dir" && ./configure "$KERNEL_NAME")

    # NVIDIA's open nvidia.ko is built without CONFIG_MODVERSIONS, so it exports
    # nvidia_p2p_* with no symbol CRCs. Build nvidia-fs without supplying symbol
    # versions (no KBUILD_EXTRA_SYMBOLS); KBUILD_MODPOST_WARN=1 downgrades the
    # missing-version warning so the symbols resolve by name against nvidia.ko.
    echo "Compiling nvidia-fs $fs_version"
    KCPPFLAGS="-DCONFIG_NVFS_STATS=y -DGDS_VERSION=$(cat "$src_dir/GDS_VERSION") -DNVFS_BATCH_SUPPORT=y" \
    CONFIG_NVFS_BATCH_SUPPORT=y \
    CONFIG_NVFS_STATS=y \
    make -j"$(nproc)" \
        -C "/lib/modules/$KERNEL_NAME/build" \
        M="$src_dir" \
        KVER="$KERNEL_NAME" \
        NVIDIA_SRC_DIR="$nvidia_src_dir" \
        KBUILD_MODPOST_WARN=1 \
        modules

    if [ ! -f "$src_dir/nvidia-fs.ko" ]; then
        echo "[ERROR] nvidia-fs.ko was not produced by the build"
        exit 1
    fi

    cp "$src_dir/nvidia-fs.ko" "$OUTDIR/lib/modules/$KERNEL_NAME/"
    echo "nvidia-fs.ko compiled successfully"
}


copy_artifacts() {
    local host_out_dir="/run/nvidia/.staging-driver/driver"

    # Stage all firmware the driver ships (GSP images + GPU microcode/ucodes).
    # Copying only gsp_*.bin omits ucodes_*.bin, which newer GPUs need to init —
    # without it nvidia.ko fails probe (RmInitAdapter failed) and never exports
    # its symbols. Scope to the driver's firmware/ dir to avoid installer cruft.
    echo "Copying driver firmware"
    mkdir -p "$OUTDIR/lib/firmware/nvidia/$DRIVER_VERSION/"
    find "$DRIVER_SRC_DIR/firmware" -type f -name '*.bin' -exec cp -a {} "$OUTDIR/lib/firmware/nvidia/$DRIVER_VERSION/" \;

    mkdir -p "$host_out_dir/usr/lib/$ARCH_TYPE-linux-gnu" "$host_out_dir/usr/bin"
    cp -a /usr/lib/"$ARCH_TYPE"-linux-gnu/*nvidia* /usr/lib/"$ARCH_TYPE"-linux-gnu/*cuda* "$host_out_dir/usr/lib/$ARCH_TYPE-linux-gnu"
    cp -a /usr/bin/nvidia* "$host_out_dir/usr/bin"

    cp -a "$OUTDIR" /run/nvidia/.staging-driver/
}


mkdir -p "$COMPILE_DIR"
install_kernel_headers
download_driver
compile_nvidia
# Build nvidia-fs (GDS) only for open modules, and only when explicitly requested:
# either by pinning NVIDIA_FS_VERSION or by setting ENABLE_GDS=true (which falls
# back to the version pinned in versions.yaml).
if [[ "$KERNEL_MODULE_TYPE" == "open" && ( -n "$NVIDIA_FS_VERSION" || "$ENABLE_GDS" == "true" ) ]]; then
    compile_nvidia_fs
fi
copy_artifacts
