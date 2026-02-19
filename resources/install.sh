#!/bin/bash
#set -euo pipefail

echo "Installing NVIDIA modules for driver version $DRIVER_VERSION"
echo "INSTALL_DIR: $INSTALL_DIR"
echo "DRIVER_NAME: $DRIVER_NAME"
echo "NVIDIA_BIN: $NVIDIA_BIN"

# Build dep maps relative to the alt root (your INSTALL_DIR/DRIVER_NAME)
error_out=$(depmod -b "$INSTALL_DIR/$DRIVER_NAME" 2>&1 )
# filter harmless depmod warnings
echo "$error_out" | grep -v 'depmod: WARNING:' 

echo -n "/run/nvidia/driver/lib/firmware" > /sys/module/firmware_class/parameters/path
modprobe -q -d "$INSTALL_DIR/$DRIVER_NAME" nvidia
modprobe -q -d "$INSTALL_DIR/$DRIVER_NAME" nvidia-uvm

# Ensure device nodes exist on the host (idempotent, preferred over manual mknod)
# -u: create /dev/nvidia-uvm
# -m Load the NVIDIA modeset kernel module and create its device file
# -c=0: create /dev/nvidia0..N and /dev/nvidiactl
# nvidia-modprobe was created in the location /usr/bin location it is 
# not installed part of NVIDIA_BIN by default unless we copy it there.
# Without -m I saw instances where the /dev/nvidia0 device was not created.
# When GSP is not used I see errors like this nvidia/<driver version>/gsp_tu10x.bin failed with error -2
# in dmesg and I believe this is preventing nvidia-modprobe from working correctly.
echo "Calling nvidia-modprobe to setup devices"
nsenter -t 1 -m -u -n -i ${NVIDIA_BIN}/nvidia-modprobe -u -m -c 0 
rc=$?
echo "Status calling nvidia-modprobe : $rc"
if [ $rc -ne 0 ]; then
    echo "[ERROR] nvidia-modprobe failed with code $rc"
    echo "dmesg output:"
    nsenter -t 1 -m /bin/sh -lc 'dmesg | grep -i nvidia'
fi

# It seems running nvidia-smi on the host can also create the /dev/nvidia0 device 
echo "Calling nvidia-smi to ensure /dev/nvidia0 exists"
nsenter -t 1 -m -u -n -i ${NVIDIA_BIN}/nvidia-smi
echo "Status or calling nvidia-smi : $?"

echo "List devices found on the host"
nsenter -t 1 -m -u -i /bin/sh -lc 'ls -l /dev/nvidia*'

# A100 / NVSwitch extras — run in host namespaces as they affect host devices
GPU_NAME=$("${NVIDIA_BIN}/nvidia-smi" -i 0 --query-gpu=name --format=csv,noheader || true)
nsenter -t 1 -m -u -n -i ${NVIDIA_BIN}/nvidia-modprobe --unified-memory --nvlink || true
for c in 0 1 2 3 4 5 6 7; do
  nsenter -t 1 -m -u -n -i ${NVIDIA_BIN}/nvidia-modprobe --nvswitch -c "$c" || true
done

echo "List devices found on the host"
nsenter -t 1 -m -u -i /bin/sh -lc 'ls -l /dev/nvidia*'

echo "NVIDIA driver installed OK"
