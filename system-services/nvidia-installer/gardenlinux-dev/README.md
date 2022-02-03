# Gardenlinux developer image

## Build & Release

The normal build and release is triggered via the Jenkins pipeline.

## New Garden Linux version

For each new version of Garden Linux a new developer image must be compiled.

1. Add a line to the table in the `image_versions` file, setting the following parameter values:
   - `version`
   - `kernelVersion`
   - `linuxVersion`
   - `linuxDate`
   - `gccVersion`
   - `debianBaseImageTag`

    For finding the correct values do the following:
    - Open a shell on a node with the new Garden Linux version (e.g. using Lens, or `kubectl exec` to a Pod running on the node)
    - Run the relevant command to get each value:
      - kernelVersion: `uname -r`
      - linuxVersion: `uname -v`
      - linuxDate: `uname -v`
      - gccVersion: `cat /proc/version`

    **WARNING** The value for `DEBIAN_BASE_IMAGE_TAG` must not be changed.
    If you have to change this, you must contact the gardenlinux team (e.g. Andre Russ D061226)
    to get the new valid tag that works for the new gardenlinux version.


2. Set the environment variables `KERNEL_VERSION`, `LINUX_VERSION` and `GCC_VERSION` as determined above,
   and `OS_USERNAME` and `OS_PASSWORD` to your SAP credentials, then run `./tooling/upload_gardenlinux_packages.sh`
   This will copy the required packages from the Garden Linux build server to the Swift container
   `gardenlinux-packages` in Converged Cloud project [hcp03/SAPCLEA](https://dashboard.eu-de-1.cloud.sap/hcp03/sapclea/home).
 

3. **Only if the previous step fails:**
   Locate the relevant private gardenlinux packages (for example "http://45.86.152.1/gardenlinux/pool/main/l/linux")
   by asking in Slack channel #sap-tech-gardenlinux (see [here](https://sap-ml.slack.com/archives/CV1SWRHR6/p1629753024011500)
   for a previous request). 
 
   Mirror the relevant private gardenlinux packages to the publicly accessible OpenStack Swift
   container `gardenlinux-packages` in the Converged Cloud [`sapclea`](https://dashboard.eu-de-1.cloud.sap/hcp03/sapclea/home) project.
   These packages currently are:

     - `linux-headers-${kernel_version}-common_${linux_version}_all.deb`
     - `linux-headers-${kernel_version}-cloud-amd64_${linux_version}_amd64.deb`
     - `linux-compiler-gcc-${gcc_major}-x86_${linux_version}_amd64.deb`
     - `linux-kbuild-${kernel_version_major_minor}_${linux_version}_amd64.deb`


4. Update the `context.gardenLinux` values in `component.yaml`, adding a dictionary to the array similar to this:
    ```
    '184':                                         # Short version name - not actually used, but needs to be present
      version: '184.0.0'                           # Change to the new Garden Linux version
      debianBaseImageTag: 'bullseye-20200224-slim' # Change if needed - see warning above
    ```


5. Run `mono run build` to check if the build goes through locally.


6. Release a new version of `nvidia-installer` - see `system-services/nvidia-installer/README.md` for details.
