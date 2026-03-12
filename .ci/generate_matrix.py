#!/usr/bin/env python3
import itertools
import yaml
import json

with open("versions.yaml") as f:
    data = yaml.safe_load(f)

# build_matrix: one entry per (os_version, arch, kernel_flavour, kernel_type, driver).
# Used by build_driver.yml and build_image.yml to compile one tarball / build one image
# per combination.
build_matrix = [
    {
        "os_version": os_version,
        "driver_version": driver,
        "arch": arch,
        "kernel_flavour": flavour,
        "kernel_type": kernel,
    }
    for os_version, arch, flavour, kernel, driver in itertools.product(
        data["os_versions"],
        data["cpu_arch"],
        data["kernel_flavour"],
        data["kernel_type"],
        data["nvidia_drivers"],
    )
]

# manifest_matrix: one entry per (os_version, kernel_flavour, kernel_type, driver) — no arch.
# Used by the manifest job in build_image.yml to create multi-arch manifests that combine
# the per-arch images produced by the build matrix above.
manifest_matrix = [
    {
        "os_version": os_version,
        "driver_version": driver,
        "kernel_flavour": flavour,
        "kernel_type": kernel,
    }
    for os_version, flavour, kernel, driver in itertools.product(
        data["os_versions"],
        data["kernel_flavour"],
        data["kernel_type"],
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
