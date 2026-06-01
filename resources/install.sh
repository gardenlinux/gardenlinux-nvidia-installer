#!/bin/bash
#set -euo pipefail

NVIDIA_MODULE_PARAMS=()
NVIDIA_UVM_MODULE_PARAMS=()

# Read optional kernel module parameters from conf files mounted at /drivers/.
# Each line in the file is one parameter token, e.g. "NVreg_DeviceFileMode=0666".
# Multiple parameters: one per line.
_get_module_params() {
    local base_path="/drivers"
    if [ -f "${base_path}/nvidia.conf" ]; then
        while read -r param || [ -n "$param" ]; do
            [[ -z "$param" || "$param" == \#* ]] && continue
            NVIDIA_MODULE_PARAMS+=("$param")
        done <"${base_path}/nvidia.conf"
        echo "Module parameters provided for nvidia: ${NVIDIA_MODULE_PARAMS[*]}"
    fi
    if [ -f "${base_path}/nvidia-uvm.conf" ]; then
        while read -r param || [ -n "$param" ]; do
            [[ -z "$param" || "$param" == \#* ]] && continue
            NVIDIA_UVM_MODULE_PARAMS+=("$param")
        done <"${base_path}/nvidia-uvm.conf"
        echo "Module parameters provided for nvidia-uvm: ${NVIDIA_UVM_MODULE_PARAMS[*]}"
    fi
}

echo "Installing NVIDIA modules for driver version $DRIVER_VERSION"
echo "INSTALL_DIR: $INSTALL_DIR"
echo "DRIVER_NAME: $DRIVER_NAME"
echo "NVIDIA_BIN: $NVIDIA_BIN"

# Build dep maps relative to the alt root (your INSTALL_DIR/DRIVER_NAME)
error_out=$(depmod -b "$INSTALL_DIR/$DRIVER_NAME" 2>&1 )
# filter harmless depmod warnings
echo "$error_out" | grep -v 'depmod: WARNING:'

# Copy local nvidia-uvm.conf files to /drivers, but don't overwrite.
# (existing files may have been configured by GPU Operator - see driver.kernelModuleConfig Helm value)
# This disables High Memory Mode (hmm) which fixes an issue with B200 GPUs.
cp nvidia-uvm.conf --no-clobber {} /drivers

_get_module_params
echo -n "/run/nvidia/driver/lib/firmware" > /sys/module/firmware_class/parameters/path
modprobe -d "$INSTALL_DIR/$DRIVER_NAME" nvidia "${NVIDIA_MODULE_PARAMS[@]}"; rc=$?
[ $rc -ne 0 ] && { echo "[ERROR] modprobe nvidia failed: $rc"; exit 1; }
modprobe -d "$INSTALL_DIR/$DRIVER_NAME" nvidia-uvm "${NVIDIA_UVM_MODULE_PARAMS[@]}"; rc=$?
[ $rc -ne 0 ] && { echo "[ERROR] modprobe nvidia-uvm failed: $rc"; exit 1; }

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
if [[ "${GPU_NAME:-}" == *"A100"* ]]; then
  nsenter -t 1 -m -u -n -i ${NVIDIA_BIN}/nvidia-modprobe --unified-memory --nvlink || true
  for c in 0 1 2 3 4 5; do
    nsenter -t 1 -m -u -n -i ${NVIDIA_BIN}/nvidia-modprobe --nvswitch -c "$c" || true
  done
fi

echo "NVIDIA driver installed OK"
