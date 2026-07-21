#!/usr/bin/env python3
import re
import sys
import warnings
from urllib.request import urlopen

import html2text
import requests
import yaml

GVISOR_VERSION_GO_URL = (
    "https://raw.githubusercontent.com/google/gvisor/master/"
    "pkg/sentry/devices/nvproxy/version.go"
)


def parse_gvisor_qualified_versions(version_go_content):
    """Return the set of driver version strings from addDriverABI calls in version.go.

    Only addDriverABI entries (not addUnsupportedDriverABI) are nvproxy-qualified.
    Version strings are zero-padded to two digits in the patch field to match
    the canonical format used in versions.yaml (e.g. "570.195.03").
    """
    pattern = re.compile(
        r"\baddDriverABI\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)"
    )
    versions = set()
    for major, minor, patch in pattern.findall(version_go_content):
        versions.add(f"{int(major)}.{int(minor)}.{int(patch):02d}")
    return versions


def select_gvisor_pin(mainstream_version, qualified_versions):
    """Return the highest qualified version ≤ mainstream_version for the same major.

    Raises ValueError when no qualified version exists for the mainstream major.
    """
    def ver(s):
        return tuple(int(x) for x in s.split("."))

    major = mainstream_version.split(".")[0]
    candidates = [
        v for v in qualified_versions
        if v.split(".")[0] == major and ver(v) <= ver(mainstream_version)
    ]
    if not candidates:
        raise ValueError(
            f"No nvproxy-qualified driver version found for major {major} "
            f"at or below {mainstream_version}"
        )
    return max(candidates, key=ver)


def update_gvisor_driver_pins(data, version_go_content):
    """Update gvisor_driver_pins in data using version.go content.

    Returns True if any pin was changed, False otherwise.
    Logs a warning (and skips) for mainstream drivers with no qualified gVisor version.
    """
    qualified = parse_gvisor_qualified_versions(version_go_content)
    pins = data.setdefault("gvisor_driver_pins", {})
    changed = False

    for driver in data.get("nvidia_drivers", []):
        try:
            best = select_gvisor_pin(driver, qualified)
        except ValueError as exc:
            warnings.warn(str(exc))
            continue

        if pins.get(driver) != best:
            pins[driver] = best
            changed = True

    nvidia_drivers = set(data.get("nvidia_drivers", []))
    stale_keys = [k for k in list(pins) if k not in nvidia_drivers]
    for k in stale_keys:
        del pins[k]
        changed = True

    return changed


def update_versions():
    updates = {
        'gardenlinux': False,
        'nvidia': False,
        'gvisor': False,
    }

    with open("versions.yaml", 'r') as version_file:
        data = yaml.safe_load(version_file)
        updates['gardenlinux'] = get_latest_gardenlinux_tags(data)
        updates['nvidia'] = update_nvidia_driver_version(data)
        updates['gvisor'] = _fetch_and_update_gvisor_pins(data)

    with open("versions.yaml", 'w') as version_file:
        yaml.dump(data, version_file, default_flow_style=False, sort_keys=False)

    print(f"GARDENLINUX_VERSION_UPDATE={'true' if updates['gardenlinux'] else 'false'}")
    print(f"NVIDIA_DRIVER_VERSION_UPDATE={'true' if updates['nvidia'] else 'false'}")
    print(f"GVISOR_VERSION_UPDATE={'true' if updates['gvisor'] else 'false'}")


def _fetch_and_update_gvisor_pins(data):
    try:
        with urlopen(GVISOR_VERSION_GO_URL) as response:
            content = response.read().decode("utf-8", errors="ignore")
        return update_gvisor_driver_pins(data, content)
    except Exception as exc:
        print(f"Warning: failed to fetch gVisor version.go: {exc}", file=sys.stderr)
        return False


def update_nvidia_driver_version(data):
    has_update = False
    with urlopen("https://developer.download.nvidia.com/compute/nvidia-driver/redist/nvidia_driver/linux-x86_64/") as response:
        html_data = html2text.html2text(response.read().decode('utf-8', errors='ignore'))
        lines = html_data.splitlines()
        version_pattern = re.compile(r"\b\d{3,}\.\d+\.\d+\b")

    for i, driver in enumerate(data.get('nvidia_drivers', [])):
        old_version = driver
        for line in lines:
            if old_version.split('.')[0] in line:
                match = version_pattern.search(line)
                if match:
                    if (int(old_version.split('.')[1]) < int(match.group(0).split('.')[1])):
                        data['nvidia_drivers'][i] = match.group(0)
                        old_version = match.group(0)
                        has_update = True
                    elif ((int(old_version.split('.')[1]) == int(match.group(0).split('.')[1])) &
                          (int(old_version.split('.')[2]) < int(match.group(0).split('.')[2]))):
                        data['nvidia_drivers'][i] = match.group(0)
                        old_version = match.group(0)
                        has_update = True
    return has_update

def get_latest_gardenlinux_tags(data):
    url = f"https://api.github.com/repos/gardenlinux/gardenlinux/tags"
    response = requests.get(url)

    if response.status_code != 200:
        print("Failed to fetch tags:", response.status_code, file=__import__('sys').stderr)
        return False

    tags = [tag['name'] for tag in response.json()]
    new_os_versions = [tag for tag in tags if re.fullmatch(r'\d+\.\d+(\.\d+)?', tag)]

    # Any older versions of Garden Linux removed from the old versions file should not appear in the new versions file
    major_versions = {}
    for tag in new_os_versions:
        major = tag.split('.')[0]
        major_versions.setdefault(major, []).append(tag)

    # For each major version group, remove versions older than the oldest one tracked in data
    ancient_versions = []
    for major, versions in major_versions.items():
        for i in reversed(versions):
            if i not in data['os_versions']:
                ancient_versions.append(i)
            else:  # Stop when we get a match, so we avoid also removing new versions at the top
                break

    filtered_os_versions = [x for x in new_os_versions if x not in ancient_versions] + ['1592.18'] # remove 1592.18 after gardener stops supporting it 2026-09

    if sorted(data['os_versions']) != sorted(filtered_os_versions):
        data['os_versions'] = filtered_os_versions
        return True
    return False

def main():
    update_versions()

if __name__ == "__main__":
    main()
