#!/bin/bash
echo "Installing NVIDIA modules for driver version $DRIVER_VERSION"
set -e

error_out=$(depmod -b "$INSTALL_DIR/$DRIVER_NAME" 2>&1)
# "grep -v ..." removes warnings that do not cause a problem for the gpu driver installation
echo "$error_out" | grep -v 'depmod: WARNING:' || true

modprobe -q -d "$INSTALL_DIR/$DRIVER_NAME" nvidia
modprobe -q -d "$INSTALL_DIR/$DRIVER_NAME" nvidia-uvm
if [ ! -e /dev/nvidia0 ] ; then
    NVDEVS=$(lspci | grep -i NVIDIA)
    N3D=$(echo "$NVDEVS" | grep -c "3D controller") || true
    NVGA=$(echo "$NVDEVS" | grep -c "VGA compatible controller") || true
    N=$((N3D + NVGA - 1)) || true
    for i in $(seq 0 $N); do mknod -m 666 /dev/nvidia"$i" c 195 "$i"; done
fi
if [ ! -e /dev/nvidiactl ] ; then
    mknod -m 666 /dev/nvidiactl c 195 255
fi
if [ ! -e /dev/nvidia-uvm ] ; then
    D=$(grep nvidia-uvm /proc/devices | cut -d " " -f 1)
    mknod -m 666 /dev/nvidia-uvm c "$D" 0
fi

# For A100 GPUs we install additional device files to support Fabric Manager
GPU_NAME=$("${NVIDIA_BIN}"/nvidia-smi -i 0 --query-gpu=name --format=csv,noheader)
if [[ "$GPU_NAME" == *"A100"* ]]; then
  "${NVIDIA_BIN}"/nvidia-modprobe --unified-memory --nvlink
  "${NVIDIA_BIN}"/nvidia-modprobe --nvswitch -c 0
  "${NVIDIA_BIN}"/nvidia-modprobe --nvswitch -c 1
  "${NVIDIA_BIN}"/nvidia-modprobe --nvswitch -c 2
  "${NVIDIA_BIN}"/nvidia-modprobe --nvswitch -c 3
  "${NVIDIA_BIN}"/nvidia-modprobe --nvswitch -c 4
  "${NVIDIA_BIN}"/nvidia-modprobe --nvswitch -c 5
fi

echo "NVIDIA driver installed OK"