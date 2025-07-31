#!/usr/bin/env python3
from urllib.request import urlopen
import html2text
import re
import yaml
import sys

def update_versions(release_tag):
    with open("versions.yaml", 'r') as version_file:
        data = yaml.safe_load(version_file)
        update_new_gl_release(data, release_tag)
        update_driver_version(data)
    with open("versions.yaml", 'w') as version_file:
        yaml.dump(data, version_file, default_flow_style=False, sort_keys=False)

def update_driver_version(data):
    with urlopen("https://developer.nvidia.com/datacenter-driver-archive") as response:
        html_data = html2text.html2text(response.read().decode('utf-8', errors='ignore'))
        lines = html_data.splitlines()
        version_pattern = re.compile(r"\b\d{3,}\.\d{1,2}(\.\d{1,2})?\b")
    for elements in data.get('os_versions', []):
        old_version = elements.get('nvidia_drivers', [])[0]
        for line in lines:
            if old_version.split('.')[0] in line:
                match = version_pattern.search(line)
                if match:
                    elements['nvidia_drivers'] = [old_version.split('.')[0]+'.'+match.group(0)]
                    break;

def update_new_gl_release(data, release_tag):
    for elements in data.get('os_versions', []):
        gl_version = elements.get('version', [])
        if(gl_version != release_tag):
            if(gl_version.split('.')[0] == release_tag.split('.')[0]):
                elements['version'] = release_tag

def main(release_tag):
    update_versions(release_tag)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <GL Release Tag>")
        sys.exit(1)

    main(sys.argv[1])
