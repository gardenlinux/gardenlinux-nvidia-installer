# nvidia-installer

This component compiles NVIDIA kernel modules for Garden Linux in a Container image at build time.
Running the image in a cluster via the NVIDIA GPU Operator installs the GPU driver on the required nodes.

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

To build the image for NVIDIA driver version `570.172.08` on Garden Linux (GL) `1877.3` for `amd64`-based CPUs:

```
    export DRIVER_VERSION=570.172.08
    export GL_VERSION=1877.3
    make build
```
This builds a container image with an image name like 
`ghcr.io/gardenlinux/gardenlinux-nvidia-installer/driver:<driver_major_version>-<GL_kernel_version>-<arch>-gardenlinux0`
and 
`ghcr.io/gardenlinux/gardenlinux-nvidia-installer/driver:<driver_major_version>-<GL_kernel_version>-<arch>-gardenlinux<GL_version>`

Notes:
1. The image is built by default for **amd64**. If **arm64** architecture needs to be built then `export TARGET_ARCH=arm64`

2. If a bare-metal kernel module needs to be built then `export KERNEL_FLAVOR=baremetal`

# Further reading

## High level structure of the Makefile

The Makefile compiles the driver modules and builds the container image in 2 stages.
To build only the driver modules:
```
    export GL_VERSION=1877.3
    export DRIVER_VERSION=570.172.08
    make build-driver
```
This builds the driver modules and stores them in current working directory under the `out` folder

To build only the container image: 
```
    export GL_VERSION=1877.3
    export DRIVER_VERSION=570.172.08
    make build-image
```
Note: Make sure driver modules are first available under the `out` folder before building the image.

### Background

Compiling drivers for Garden Linux is typically non-trivial because the OS ships
without build tools and no obvious way to access the kernel sources. This project works
by compiling the kernel modules at build-time inside a Garden Linux developer container
(which contains the kernel headers and compiler) and then placing the resulting files
into a container image from which they can be installed at runtime.

## Disclaimer 

Drivers built with this project are only supported on Garden Linux, the open source operating system. 
Furthermore, only drivers for data center (i.e. non-consumer) graphics cards are supported.
