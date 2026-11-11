#!/usr/bin/env python3
import yaml

versions_file = "versions.yaml"

def load_yaml():
    with open(versions_file, "r") as f:
        return yaml.safe_load(f)

def display(versions):
    os_versions = versions.get("os_versions", [])
    drivers = versions.get("nvidia_drivers", [])

    print("\nSupported OS ↔ Driver Versions")
    print("-" * 45)
    for os_ver in os_versions:
        print(f"OS {os_ver}: {', '.join(str(d) for d in drivers)}")
    print()
    print("\nLifecycle for Driver and supported GL version depends on Garden Linux Release and Driver Release")
    print("\nRefer below links for Garden Linux and driver releases")
    print("\nGarden Linux Release: https://github.com/gardenlinux/gardenlinux/releases")
    print("\nDriver Release: https://www.nvidia.com/en-us/drivers/ --> Select Data Center/Tesla")


def main():
    versions = load_yaml()
    display(versions)

if __name__ == "__main__":
    main()
