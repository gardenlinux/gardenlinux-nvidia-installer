#!/bin/bash

# This helper script assumes you have the garden linux repository in your /etc/apt/sources.list configured
#
# This script checks the /usr/src folder for linux-headers-* folders and then figure out the right one to use

kernel_type=$1
if [ "${kernel_type}" == "cloud" ]; then
  grep_args="cloud"
else
  grep_args="-v cloud"
fi

kernel_arch=$2
# shellcheck disable=SC2010,SC2086
#                List the linux-headers folders for the arch & kernel type ------------------- | Sort by line length (shortest first) ---------------- | Pick the first line
kernel_headers=$(ls /usr/src | grep "linux-headers-" | grep "${kernel_arch}" | grep $grep_args | awk '{ print length, $0 }' | sort -n | cut -d" " -f2- | head -n 1)

kernel_name=${kernel_headers//linux-headers-/}

echo "$kernel_name"
