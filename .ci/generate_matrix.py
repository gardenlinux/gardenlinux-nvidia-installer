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
            for driver in os["nvidia_drivers"]:
                build_matrix.append(
                    {
                        "os_name": os["name"],
                        "os_version": os["version"],
                        "driver_version": driver,
                        "arch": arch,
                        "kernel_flavour": flavour,
                    }
                )
                manifest_set.add((os["version"], flavour, driver))

manifest_matrix = [
    {"os_version": v, "kernel_flavour": k, "driver_version": d}
    for v, k, d in sorted(manifest_set)
]

print(
    json.dumps(
        {"build": {"include": build_matrix}, "manifest": {"include": manifest_matrix}}
    )
)
