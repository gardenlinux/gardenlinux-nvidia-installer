#!/bin/bash
set -euo pipefail

echo "Installing NVIDIA modules for driver version $DRIVER_VERSION"

# Build dep maps relative to the alt root (your INSTALL_DIR/DRIVER_NAME)
error_out=$(depmod -b "$INSTALL_DIR/$DRIVER_NAME" 2>&1 || true)
# filter harmless depmod warnings
echo "$error_out" | grep -v 'depmod: WARNING:' || true

# Load modules into the host kernel from our alt rootfs
modprobe -q -d "$INSTALL_DIR/$DRIVER_NAME" nvidia
modprobe -q -d "$INSTALL_DIR/$DRIVER_NAME" nvidia-uvm

# Ensure device nodes exist on the host (idempotent, preferred over manual mknod)
# -u: create /dev/nvidia-uvm
# -c=0: create /dev/nvidia0..N and /dev/nvidiactl
# nvidia-modprobe was created in the location /usr/bin location it is 
# not installed part of NVIDIA_BIN by default unless we copy it there.
nsenter -t 1 -m -u -n -i ${NVIDIA_BIN}/nvidia-modprobe -u -m -c 0 || true


# A100 / NVSwitch extras — run in host namespaces as they affect host devices
GPU_NAME=$("${NVIDIA_BIN}/nvidia-smi" -i 0 --query-gpu=name --format=csv,noheader || true)
if [[ "${GPU_NAME:-}" == *"A100"* ]]; then
  nsenter -t 1 -m -u -n -i ${NVIDIA_BIN}/nvidia-modprobe --unified-memory --nvlink || true
  for c in 0 1 2 3 4 5; do
    nsenter -t 1 -m -u -n -i ${NVIDIA_BIN}/nvidia-modprobe --nvswitch -c "$c" || true
  done
fi

echo "NVIDIA driver installed OK"
