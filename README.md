# nvidia-installer

This component compiles NVIDIA kernel modules for Garden Linux in a Docker image at build time.
Running the image in a cluster as part of a DaemonSet installs the GPU driver on the required nodes.

## Deploying NVIDIA GPU Operator with Helm

```bash
helm upgrade --install -n gpu-operator gpu-operator nvidia/gpu-operator --values \
  https://raw.githubusercontent.com/gardenlinux/gardenlinux-nvidia-installer/refs/heads/main/helm/gpu-operator-values.yaml
```

If you have built the images yourself, you can use the `--set` option to specify the image repository and tag:
```bash
helm upgrade --install -n gpu-operator gpu-operator nvidia/gpu-operator --values \
  https://raw.githubusercontent.com/gardenlinux/gardenlinux-nvidia-installer/refs/heads/main/helm/gpu-operator-values.yaml \
  --set driver.repository=$REGISTRY/$FOLDER \
  --set driver.image=$IMAGE
```

## Building the Docker image

To build the image for NVIDIA driver version `560.35.03` on Garden Linux `1592.10` for `amd64`-based CPUs:
```bash
docker build . --platform=linux/amd64 --build-arg TARGET_ARCH=amd64 --build-arg DRIVER_VERSION=560.35.03 --build-arg GARDENLINUX_VERSION=1592.10 \
    --tag $REGISTRY/$FOLDER/$IMAGE:560.35.03-gardenlinux-1592.10
docker push $REGISTRY/$FOLDER/$IMAGE:560.35.03-gardenlinux-1592.10
```
If you need to build for a baremetal node (as opposed to a cloud VM) then add `--build-arg KERNEL_TYPE=baremetal` 
to the above command.

# Further reading

## High level structure of the Dockerfile

The first stage installs the needed compilers & kernel headers, then calls
a script to download the NVIDIA driver files and compile the kernel modules, and finally creates a
compressed tar archive of the required files.

The second (main) stage copies the tarball into the image along with the runtime scripts to
extract the tarball and install
the modules into the running kernel as part of a Daemonset.

### Background

Compiling drivers for Garden Linux is typically non-trivial because the OS ships
without build tools and no obvious way to access the kernel sources. This project works
by compiling the kernel modules at build-time inside a Garden Linux developer container
(which contains the kernel headers and compiler) and then placing the resulting files
into a Docker image from which they can be installed at runtime.

## Disclaimer 

Drivers built with this project are only supported on Garden Linux, the open source operating system. 
Furthermore, only drivers for non consumer graphics cards are supported.
