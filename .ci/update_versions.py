#!/usr/bin/env python3
from urllib.request import urlopen
import html2text
import re
import yaml
import sys
import requests

def update_versions():
    with open("versions.yaml", 'r') as version_file:
        data = yaml.safe_load(version_file)
        get_latest_gl_tag(data)
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
        for i, driver in enumerate(elements['nvidia_drivers']):
            old_version = driver
            for line in lines:
                if old_version.split('.')[0] in line:
                    match = version_pattern.search(line)
                    if match:
                        if (int(old_version.split('.')[1]) < int(match.group(0).split('.')[1])):
                            elements['nvidia_drivers'][i] = match.group(0)
                            update = True 
                            old_version = match.group(0)
                        elif ((int(old_version.split('.')[1]) == int(match.group(0).split('.')[1])) &
                              (int(old_version.split('.')[2]) < int(match.group(0).split('.')[2]))):
                            elements['nvidia_drivers'][i] = match.group(0)
                            update = True
                            old_version = match.group(0)
            if update == True:
                print(f"Driver Version update : {match.group(0)}")

def get_latest_gl_tag(data):
    url = f"https://api.github.com/repos/gardenlinux/gardenlinux/tags"
    response = requests.get(url)

    if response.status_code != 200:
        print("Failed to fetch tags:", response.status_code)
        return []

    tags = [tag['name'] for tag in response.json()]
    number_tags = [tag for tag in tags if re.fullmatch(r'\d+\.\d+', tag)]

    # Get major version from version.yml
    for elements in data.get('os_versions', []):
        gl_major, gl_minor = elements['version'].split('.')
        for tag in number_tags:
            gl_major, gl_minor = elements['version'].split('.')
            major, minor = tag.split('.')
            if(int(major) == int(gl_major)):
                if(int(minor) > int(gl_minor)):
                    elements['version'] = tag
                    print(f"GL Version update : {tag}")

def main():
    update_versions()

if __name__ == "__main__":
    main()
