# nvidia-installer

This component compiles NVIDIA kernel modules for Garden Linux in a Container image at build time.
Running the image in a cluster as part of a DaemonSet installs the GPU driver on the required nodes.

## Deploying NVIDIA GPU Operator with Helm

```bash
helm upgrade --install -n gpu-operator gpu-operator nvidia/gpu-operator --values \
  https://raw.githubusercontent.com/gardenlinux/gardenlinux-nvidia-installer/refs/heads/main/helm/gpu-operator-values.yaml
```
Built images are maintained at ghcr.io/gardenlinux/gardenlinux-nvidia-installer/driver:<driver-major-version>

If you have built the images yourself, you can use the `--set` option to specify the image repository and tag:
```bash
helm upgrade --install -n gpu-operator gpu-operator nvidia/gpu-operator --values \
  https://raw.githubusercontent.com/gardenlinux/gardenlinux-nvidia-installer/refs/heads/main/helm/gpu-operator-values.yaml \
  --set driver.repository=$REGISTRY/$FOLDER \
  --set driver.image=$IMAGE
```

## Building the Container image

To build the image for NVIDIA driver version `570.172.08` on Garden Linux(GL) `1877.3` for `amd64`-based CPUs:

```
    export GL_VERSION=1877.3
    export DRIVER_VERSION=570.172.08
    make build
```
This build docker image with image name as __ghcr.io/gardenlinux/gardenlinux-nvidia-installer/driver:<driver_major_version>-<kernel_version_in_GL>-<arch>-gardenlinux0__ and 
__ghcr.io/gardenlinux/gardenlinux-nvidia-installer/driver:<driver_major_version>-<kernel_version_in_GL>-<arch>-gardenlinux<GL_Version>__
Note by default image is built for amd64, if arm64 architecturte needs to be built then __export TARGET_ARCH=arm64__
and if baremetal needs to be built then __export KERNEL_TYPE=baremetal__
# Further reading

## High level structure of the Makefile

Makefile compiles driver and image in 2 stages
if only driver needs to be built then this can be doone by
```
    export GL_VERSION=1877.3
    export DRIVER_VERSION=570.172.08
    make build-driver
```
This builts the driver and stored in current working directory under out folder

If image needs to be built separately then 
```
    export GL_VERSION=1877.3
    export DRIVER_VERSION=570.172.08
    make build-image
```
Note : Make sure driver is available under out folder before image build

### Background

Compiling drivers for Garden Linux is typically non-trivial because the OS ships
without build tools and no obvious way to access the kernel sources. This project works
by compiling the kernel modules at build-time inside a Garden Linux developer container
(which contains the kernel headers and compiler) and then placing the resulting files
into a Container image from which they can be installed at runtime.

## Disclaimer 

Drivers built with this project are only supported on Garden Linux, the open source operating system. 
Furthermore, only drivers for non consumer graphics cards are supported.
