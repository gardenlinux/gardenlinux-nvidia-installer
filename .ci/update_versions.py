#!/usr/bin/env python3
from urllib.request import urlopen
import html2text
import re
import yaml
import sys

def update_versions(release_tag):
    with open("versions.yaml", 'r') as version_file:
        data = yaml.safe_load(version_file)
        if release_tag != "no_update":
            update_new_gl_release(data, release_tag)
        update_driver_version(data)
    with open("versions.yaml", 'w') as version_file:
        yaml.dump(data, version_file, default_flow_style=False, sort_keys=False)

def update_driver_version(data):
    with urlopen("https://developer.download.nvidia.com/compute/nvidia-driver/redist/nvidia_driver/linux-x86_64/") as response:
        html_data = html2text.html2text(response.read().decode('utf-8', errors='ignore'))
        lines = html_data.splitlines()
        version_pattern = re.compile(r"\b\d{3,}\.\d+\.\d+\b")
    for elements in data.get('os_versions', []):
        update = False
        old_version = elements.get('nvidia_drivers', [])[0]
        for line in lines:
            if old_version.split('.')[0] in line:
                match = version_pattern.search(line)
                if match:
                    if (int(old_version.split('.')[1]) < int(match.group(0).split('.')[1])):
                        elements['nvidia_drivers'] = [match.group(0)]
                        update = True
                        old_version = match.group(0)
                    elif ((int(old_version.split('.')[1]) == int(match.group(0).split('.')[1])) &
                        (int(old_version.split('.')[2]) < int(match.group(0).split('.')[2]))):
                        elements['nvidia_drivers'] = [match.group(0)]
                        update = True
                        old_version = match.group(0)
        if update == True:
            print(f"Driver Version update : {match.group(0)}")


def update_new_gl_release(data, release_tag):
    for elements in data.get('os_versions', []):
        gl_version = elements.get('version', [])
        if(gl_version != release_tag):
            if(gl_version.split('.')[0] == release_tag.split('.')[0]):
                elements['version'] = release_tag
                print(f"GL Version update : {release_tag}")

def main(release_tag):
    update_versions(release_tag)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <GL Release Tag>")
        sys.exit(1)

    main(sys.argv[1])
