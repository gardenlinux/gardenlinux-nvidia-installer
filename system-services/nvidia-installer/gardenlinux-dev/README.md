# Gardenlinux developer image

## Build & Release

The normal build and release is triggered via the normal mono repo pipeline.

## New Garden Linux version

For each new version of Garden Linux a new developer image must be compiled.
This process is **not** straight-forward.

Minimally the following steps must be fulfilled:

1. Locate the relevant private gardenlinux packages (for example "http://45.86.152.1/gardenlinux/pool/main/l/linux")
   by asking in Slack channel #sap-tech-gardenlinux (see [here](https://sap-ml.slack.com/archives/CV1SWRHR6/p1629753024011500)
   for a previous request). 
 
   Mirror the relevant private gardenlinux packages to the publicly accessible OpenStack Swift
   container `gardenlinux-packages` in the Converged Cloud [`sapclea`](https://dashboard.eu-de-1.cloud.sap/hcp03/sapclea/home) project.
   These packages currently are:

     - `linux-headers-${kernel_version}-common_${linux_version}_all.deb`
     - `linux-headers-${kernel_version}-cloud-amd64_${linux_version}_amd64.deb`
     - `linux-compiler-gcc-${gcc_major}-x86_${linux_version}_amd64.deb`
     - `linux-kbuild-${kernel_version_major_minor}_${linux_version}_amd64.deb`

   The packages can be mirrored by logging into aws via terminal and executing
   `./tooling/upload_gardenlinux_packages.sh`. You will need to set `OS_USERNAME` and `OS_PASSWORD` to your SAP
   credentials in order to access Converged Cloud.


2. Add a line to the `image_versions` file setting parameter values according to the comments:
   - `version`
   - `kernelVersion`
   - `linuxVersion`
   - `linuxDate`
   - `gccVersion`
   - `debianBaseImageTag`

    For finding the correct values do the following:
    - Add a nodepool with the new gardenlinux image to your dev cluster
    - Start a pod on this node by using e.g. `./tooling/gpu-pod.yaml`
    - Enter the pod by running `kubectl exec -it gpu-debug -- bash`
    - Retrieve the values by running the relevant commands from `component.yaml`comments inside the pod

      - kernelVersion: `uname -r`
      - linuxVersion: `uname -v`
      - linuxDate: `uname -v`
      - gccVersion: `cat /proc/version`

    **WARNING** The value for `DEBIAN_BASE_IMAGE_TAG` must not be changed.
    If you have to change this, you must contact the gardenlinux team (e.g. Andre Russ D061226)
    to get the new valid tag that works for the new gardenlinux version.


3. Update the `context.gardenLinux` values in `component.yaml`, adding a dictionary to the array similar to this:
    ```
    '184':                                         # Short version name - not actually used, but needs to be present
      version: '184.0.0'                           # Change to the new Garden Linux version
      debianBaseImageTag: 'bullseye-20200224-slim' # Change if needed - see warning above
    ```

4. Run `mono run build` to check if the build goes through.
