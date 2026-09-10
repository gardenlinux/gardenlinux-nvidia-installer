#!/usr/bin/env python3
import yaml
from datetime import date

versions_file = "versions.yaml" 
history_file = "history.yaml"

def load_yaml(path):
    with open(path, "r") as f:
        return yaml.safe_load(f)

def save_history(history):
    with open(history_file, "w") as f:
        yaml.safe_dump(history, f, sort_keys=True)

def tracked_os_versions(versions):
    """Return active + non-expired deprecated OS version strings."""
    today = date.today()
    tracked = [str(v) for v in versions.get("os_versions", [])]
    for entry in versions.get("deprecated_os_versions", []):
        if date.fromisoformat(entry["expires"]) > today:
            tracked.append(str(entry["version"]))
    return tracked

def main():
    versions = load_yaml(versions_file)
    history = load_yaml(history_file)

    tracked = tracked_os_versions(versions)

    # Add current drivers to each tracked version
    for os_ver in tracked:
        history.setdefault(os_ver, [])
        for drv in versions.get("nvidia_drivers", []):
            if drv not in history[os_ver]:
                history[os_ver].append(drv)

    # Remove history entries for versions no longer tracked
    tracked_set = set(tracked)
    history = {ver: drivers for ver, drivers in history.items() if ver in tracked_set}

    save_history(history)

if __name__ == "__main__":
    main()

