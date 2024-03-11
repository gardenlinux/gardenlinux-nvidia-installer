#!/bin/bash

# Assuming we are within a driver build container and want the latest kernel headers,
# this line detects the kernel version by looking for the directory name format
# inside /usr/lib/modules. Only the version number is extracted using grep and sorted numerically.


get_depends(){
    ls /usr/lib/modules | grep -Eo '[0-9]+\.[0-9]+.[0-9]+' | sort -V | tail -n 1
}

intermediate_meta_pkg=$(get_depends "$kernel_pkg_name")
kernel_package=$(get_depends "$intermediate_meta_pkg")
kernel_version=${kernel_package//linux-headers-/}

echo "$kernel_version"
