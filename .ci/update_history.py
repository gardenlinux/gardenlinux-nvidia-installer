#!/usr/bin/env python3
import yaml
from collections import defaultdict

versions_file = "versions.yaml" 
history_file = "history.yaml"

def load_yaml(path):
    with open(path, "r") as f:
        return yaml.safe_load(f)

def save_history(history):
    with open(history_file, "w") as f:
        yaml.safe_dump(history, f, sort_keys=True)

def update_history(versions, history):
    for entry in versions.get("os_versions", []):
        os_ver = str(entry["version"])
        drivers = entry.get("nvidia_drivers", [])
        history.setdefault(os_ver, [])
        for drv in drivers:
            if drv not in history[os_ver]:
                history[os_ver].append(drv)
    return history

def cleanup_old_versions(history):

    # Group versions by major part
    grouped = defaultdict(list)
    for ver in history:
        major = ver.split(".")[0] if "." in ver else ver
        grouped[major].append(ver)

    new_history = {}
    for major, versions in grouped.items():
        sorted_versions = sorted(versions, key=lambda v: [int(x) for x in v.split(".")])
        to_keep = sorted_versions[-5:]
        for ver in to_keep:
            new_history[ver] = history[ver]
    return new_history

def main():
    versions = load_yaml(versions_file)
    history = load_yaml(history_file)
    history = update_history(versions, history)
    history = cleanup_old_versions(history)
    save_history(history)

if __name__ == "__main__":
    main()

