#!/usr/bin/env python3
import yaml
import json

with open("versions.yaml") as f:
    data = yaml.safe_load(f)

build_matrix = []
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
                    manifest_set.add((os["version"], flavour, kernel, driver))

manifest_matrix = [
        {"os_version": v, "kernel_flavour": k, "kernel_type":t, "driver_version": d}
    for v, k, t, d in sorted(manifest_set)
]

print(
    json.dumps(
        {"build": {"include": build_matrix}, "manifest": {"include": manifest_matrix}}
    )
)
