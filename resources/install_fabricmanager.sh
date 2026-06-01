#!/bin/bash

export DEBUG=${DEBUG:-false}

if ${DEBUG}; then
  set -x
fi

BIN_DIR=${BIN_DIR:-/opt/nvidia-installer}
# shellcheck disable=SC1090
source "$BIN_DIR"/set_env_vars.sh

GPU_NAME=$("${NVIDIA_ROOT}"/bin/nvidia-smi -i 0 --query-gpu=name --format=csv,noheader)

# Typical GPU name is something like "NVIDIA H100 80GB HBM3"
# Fabric manager is required by the newer, bigger GPUs like A100, H100, etc. so we match those GPU types here
if [[ "$GPU_NAME" =~ (A100|H100|H200|B100) ]]; then
  sed 's/DAEMONIZE=1/DAEMONIZE=0/g' "/usr/share/nvidia/nvswitch/fabricmanager.cfg" > /etc/fabricmanager.cfg
  sed -i 's/LOG_FILE_NAME=.*$/LOG_FILE_NAME=/g' /etc/fabricmanager.cfg

  # Run Fabric Manager
  nv-fabricmanager -c /etc/fabricmanager.cfg
  echo "Fabric manager running"
# For Blackwell architecture NVlink needs to be activated. nvidia-fabricmanager-start.sh starts NVLink
elif [[ "$GPU_NAME" =~ B200 ]]; then
  sed 's/DAEMONIZE=1/DAEMONIZE=0/g' "/usr/share/nvidia/nvswitch/fabricmanager.cfg" > /etc/fabricmanager.cfg
  sed -i 's/LOG_FILE_NAME=.*$/LOG_FILE_NAME=/g' /etc/fabricmanager.cfg

  # nvidia-fabricmanager-start.sh's NVL5 detection requires the ib_umad kernel
  # module on the host. Load it via nsenter so it lands on the host kernel.
  nsenter -t 1 -m -u -n -i modprobe ib_umad

  # Mirror the host's /dev/infiniband umad/issm character devices into the
  # container so nvlsm and nv-fabricmanager can open the InfiniBand management
  # ports. Host /dev/infiniband is not propagated into the GPU Operator driver
  # daemonset by default.
  mkdir -p /dev/infiniband
  while IFS= read -r dev_line; do
    name=$(echo "$dev_line" | awk '{print $NF}')
    major=$(echo "$dev_line" | awk '{print $5}' | tr -d ',')
    minor=$(echo "$dev_line" | awk '{print $6}')
    # Validate name, major, and minor before creating any device node.
    [[ "$name" =~ ^(umad|issm)[0-9]+$ ]] || continue
    [[ "$major" =~ ^[0-9]+$ ]] || continue
    [[ "$minor" =~ ^[0-9]+$ ]] || continue
    [ -e "/dev/infiniband/$name" ] && continue
    mknod "/dev/infiniband/$name" c "$major" "$minor" 2>/dev/null \
      || echo "[WARN] mknod /dev/infiniband/$name ($major:$minor) failed — nvlsm may not be able to open InfiniBand management port" >&2
  done < <(nsenter -t 1 -m -u -n -i ls -la /dev/infiniband/ 2>/dev/null | grep -E '^c' | grep -E 'umad|issm')

  # Run Fabric Manager
  /usr/bin/nvidia-fabricmanager-start.sh --mode start --fm-config-file /etc/fabricmanager.cfg
  echo "Fabric manager running"
fi
echo "Sleep infinity"
sleep infinity
