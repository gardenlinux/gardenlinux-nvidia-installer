#!/bin/bash
#set -euo pipefail

echo "Unloading NVIDIA modules for driver version $DRIVER_VERSION"

modprobe -r nvidia_uvm nvidia_drm nvidia_modeset nvidia

if lsmod | grep -qE '^(nvidia|nvidia_uvm|nvidia_modeset) '; then
	return 0
else
	return 1
