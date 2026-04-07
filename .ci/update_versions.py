#!/usr/bin/env python3
import re
from urllib.request import urlopen

import html2text
import requests
import yaml


def update_versions():
    updates = {
        'gardenlinux': False,
        'nvidia': False
    }
    
    with open("versions.yaml", 'r') as version_file:
        data = yaml.safe_load(version_file)
        updates['gardenlinux'] = get_latest_gardenlinux_tags(data)
        updates['nvidia'] = update_nvidia_driver_version(data)
    
    with open("versions.yaml", 'w') as version_file:
        yaml.dump(data, version_file, default_flow_style=False, sort_keys=False)
    
    print(f"GARDENLINUX_VERSION_UPDATE={'true' if updates['gardenlinux'] else 'false'}")
    print(f"NVIDIA_DRIVER_VERSION_UPDATE={'true' if updates['nvidia'] else 'false'}")

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

    # Any versions removed from the end of the old versions file, make sure they are removed from the new versions file
    ancient_versions = []
    for i in reversed(new_os_versions):
        if i not in data['os_versions']:
            ancient_versions.append(i)
        else:
            break

    if sorted(data['os_versions']) != sorted(new_os_versions):
        data['os_versions'] = [x for x in new_os_versions if x not in ancient_versions]
        return True
    return False

def main():
    update_versions()

if __name__ == "__main__":
    main()
