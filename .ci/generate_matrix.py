#!/usr/bin/env python3
import itertools
import yaml
import json

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

print(
    json.dumps(
        {
            "build": {"include": build_matrix},
            "manifest": {"include": manifest_matrix},
        }
    )
)
