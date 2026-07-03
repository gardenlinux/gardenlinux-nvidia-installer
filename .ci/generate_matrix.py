#!/usr/bin/env python3
import itertools
import yaml
import json
import sys

with open("versions.yaml") as f:
    data = yaml.safe_load(f)

# build_matrix: one entry per (os_version, arch, kernel_flavour, driver).
# Each image embeds both open and proprietary tarballs; kernel_type is no longer
# a separate matrix dimension.
build_matrix = [
    {
        "os_version": os_version,
        "driver_version": driver,
        "arch": arch,
        "kernel_flavour": flavour,
    }
    for os_version, arch, flavour, driver in itertools.product(
        data["os_versions"],
        data["cpu_arch"],
        data["kernel_flavour"],
        data["nvidia_drivers"],
    )
]

# manifest_matrix: one entry per (os_version, kernel_flavour, driver) — no arch, no kernel_type.
# Used by the manifest job in build_image.yml to create multi-arch manifests.
manifest_matrix = [
    {
        "os_version": os_version,
        "driver_version": driver,
        "kernel_flavour": flavour,
    }
    for os_version, flavour, driver in itertools.product(
        data["os_versions"],
        data["kernel_flavour"],
        data["nvidia_drivers"],
    )
]

# gvisor_build_matrix: same dimensions as build_matrix but uses pinned driver
# versions from gvisor_driver_pins and marks entries with image_subfolder=gvisor.
gvisor_pins = data.get("gvisor_driver_pins", {})
for driver in data["nvidia_drivers"]:
    if driver not in gvisor_pins:
        print(
            f"Error: nvidia_drivers entry '{driver}' has no entry in gvisor_driver_pins",
            file=sys.stderr,
        )
        sys.exit(1)

gvisor_build_matrix = [
    {
        "os_version": os_version,
        "driver_version": gvisor_pins[driver],
        "arch": arch,
        "kernel_flavour": flavour,
        "image_subfolder": "gvisor",
    }
    for os_version, arch, flavour, driver in itertools.product(
        data["os_versions"],
        data["cpu_arch"],
        data["kernel_flavour"],
        data["nvidia_drivers"],
    )
]

gvisor_manifest_matrix = [
    {
        "os_version": os_version,
        "driver_version": gvisor_pins[driver],
        "kernel_flavour": flavour,
        "image_subfolder": "gvisor",
    }
    for os_version, flavour, driver in itertools.product(
        data["os_versions"],
        data["kernel_flavour"],
        data["nvidia_drivers"],
    )
]

print(
    json.dumps(
        {
            "build": {"include": build_matrix},
            "manifest": {"include": manifest_matrix},
            "gvisor_build": {"include": gvisor_build_matrix},
            "gvisor_manifest": {"include": gvisor_manifest_matrix},
        }
    )
)
