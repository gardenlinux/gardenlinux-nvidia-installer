#!/usr/bin/env python3
import yaml
import json

with open("versions.yaml") as f:
    data = yaml.safe_load(f)

# build_matrix: one entry per (os, arch, flavour, kernel_type, driver).
# Used by build_driver.yml to compile one tarball per kernel type.
build_matrix = []

# image_set: deduplicated (os, driver) tuples — no arch, no flavour, no kernel_type.
# Used by build_image.yml to build one image per (os, driver) combination.
# The image downloads the correct tarball at runtime based on uname -r and KERNEL_MODULE_TYPE.
image_set = set()

# manifest_set: deduplicated (os, driver) tuples — same as image_set for now.
# Used by the manifest job to create multi-arch manifests.
manifest_set = set()

for os in data["os_versions"]:
    for arch in os["cpu_arch"]:
        for flavour in os["kernel_flavour"]:
            for kernel in os["kernel_type"]:
                for driver in os["nvidia_drivers"]:
                    build_matrix.append(
                        {
                            "os_name": os["name"],
                            "os_version": os["version"],
                            "driver_version": driver,
                            "arch": arch,
                            "kernel_flavour": flavour,
                            "kernel_type": kernel,
                        }
                    )
                    image_set.add((os["version"], driver))
                    manifest_set.add((os["version"], driver))

image_matrix = [
    {"os_version": v, "driver_version": d}
    for v, d in sorted(image_set)
]

manifest_matrix = [
    {"os_version": v, "driver_version": d}
    for v, d in sorted(manifest_set)
]

print(
    json.dumps(
        {
            "build": {"include": build_matrix},
            "image": {"include": image_matrix},
            "manifest": {"include": manifest_matrix},
        }
    )
)
