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

def main():
    history = load_yaml()
    display(history)

if __name__ == "__main__":
    main()
