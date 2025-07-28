#!/usr/bin/env python3
import yaml, json

with open("versions.yaml") as f:
    data = yaml.safe_load(f)

matrix = []
for os in data["os_versions"]:
    for arch in os["cpu_arch"]:
        for flavour in os["kernel_flavour"]:
            for driver in os["nvidia_drivers"]:
                matrix.append(
                    {
                        "os_name": os["name"],
                        "os_version": os["version"],
                        "driver_version": driver,
                        "arch": arch,
                        "kernel_flavour": flavour,
                    }
                )

print(json.dumps({"include": matrix}))
