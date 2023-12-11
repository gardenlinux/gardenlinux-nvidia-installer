#!/bin/bash

# This helper script assumes you have the garden linux repository in your /etc/apt/sources.list configured
#
# Example: linux-headers-amd64 -> linux-headers-5.15-amd64 -> linux-headers-5.15.114-gardenlinux-amd64 
# 
# This script simply unfolds the package dependency until the real linux-header package is found. 
# The real package contains the full kernel version (already in the name).

kernel_pkg_name=$1

get_depends(){
    apt-cache depends "$1" | grep "Depends:" | cut -d':' -f2 | sed 's/^ //'
}

intermediate_meta_pkg=$(get_depends "$kernel_pkg_name")
kernel_package=$(get_depends "$intermediate_meta_pkg")
kernel_version=${kernel_package//linux-headers-/}

echo "$kernel_version"
