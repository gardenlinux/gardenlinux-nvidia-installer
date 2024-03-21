#!/bin/bash
set -x
BIN_DIR=${BIN_DIR:-/opt/nvidia-installer}
# shellcheck disable=SC1090
source "$BIN_DIR"/set_env_vars.sh

GPU_NAME=$("${NVIDIA_ROOT}"/bin/nvidia-smi -i 0 --query-gpu=name --format=csv,noheader)

if [[ "$GPU_NAME" == *+(A100|H100|H200|B100|B200)* ]]; then
  OUTDIR=/out/nvidia-fabricmanager/$DRIVER_VERSION
  FABRICMANAGER_ARCHIVE="fabricmanager-linux-x86_64-$DRIVER_VERSION-archive"

  # Extract archive
  xz -d -v "${OUTDIR}/${FABRICMANAGER_ARCHIVE}.tar.xz"
  tar xf "${OUTDIR}/${FABRICMANAGER_ARCHIVE}.tar" --directory="${OUTDIR}"

  # Copy files to the right places
  cp "${OUTDIR}"/"${FABRICMANAGER_ARCHIVE}"/bin/* /usr/local/bin
  cp "${OUTDIR}"/"${FABRICMANAGER_ARCHIVE}"/lib/* /usr/local/lib
  cp -ar "${OUTDIR}"/"${FABRICMANAGER_ARCHIVE}"/share/* /usr/share
  sed 's/DAEMONIZE=1/DAEMONIZE=0/g' "${OUTDIR}/${FABRICMANAGER_ARCHIVE}/etc/fabricmanager.cfg" > /etc/fabricmanager.cfg
  sed -i 's/LOG_FILE_NAME=.*$/LOG_FILE_NAME=/g' /etc/fabricmanager.cfg

  # Run Fabric Manager
  nv-fabricmanager -c /etc/fabricmanager.cfg
fi
echo "Sleep infinity"
sleep infinity