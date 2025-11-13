#!/usr/bin/env python3
import yaml

history_file = "history.yaml"

def load_yaml():
    with open(history_file, "r") as f:
        return yaml.safe_load(f)

def display(history):
    print("\nSupported OS ↔ Driver Versions")
    print("-" * 45)
    for os_ver, drivers in sorted(history.items()):
        if drivers:
            print(f"OS {os_ver}: {', '.join(sorted(drivers, reverse=True))}")
        else:
            print(f"OS {os_ver}: (no drivers listed yet)")
    print()
    print("\nLifecycle for Driver and supported GL version depends on Garden Linux Release and Driver Release")
    print("\nRefer below links for Garden Linux and driver releases")
    print("\nGarden Linux Release: https://github.com/gardenlinux/gardenlinux/releases")
    print("\nDriver Release: https://www.nvidia.com/en-us/drivers/ --> Select Data Center/Tesla")


def main():
    history = load_yaml()
    display(history)

if __name__ == "__main__":
    main()
