# nvidia-installer

Compile NVIDIA kernel modules for Gardenlinux in a Docker image. Running the image in a cluster installs the GPU driver.

## TL;DR - How to create a new version?

### New Garden Linux version

See [system-services/gardenlinux-dev/README.md](../gardenlinux-dev/README.md) for details, but in short:

* Make sure the required Garden Linux DEB files are copied to the Swift container `gardenlinux-packages` in Converged Cloud
  project [hcp03/SAPCLEA](https://dashboard.eu-de-1.cloud.sap/hcp03/sapclea/home).
* Update the values in the `context` section of `gardenlinux-dev/component.yaml`, then release a new version of 
`nvidia-installer`.

### New NVIDIA driver (CUDA) version

Update the `driverVersion` value in the `context` section of `component.yaml`, then release a new version of 
`nvidia-installer`.

### For both of the above

Make sure to update `mlf-gitops` according to the new release version.

## High level structure of the Dockerfile

The first stage uses the gardenlinux-dev image (which contains the needed compilers & kernel headers) to download
the NVIDIA driver files and compile the kernel modules.

The second (main) stage copies the kernel modules into the image and contains the runtime script to install
the modules into the running kernel as part of a Daemonset.

For new versions of Garden Linux, update the required values in gardenlinux-dev.
For new versions of the NVIDIA driver, update the required `driverVersion` value in `component.yaml`.

### Background

Compiling drivers on Container Linux is typically non-trivial because the OS ships
without build tools and no obvious way to access the kernel sources. Modulus works
by compiling your kernel modules inside of a Garden Linux developer container,
which contains the kernel headers and compiler.

### Compiling NVIDIA Kernel Modules

Modulus makes it easy to automatically compile kernel modules for NVIDIA GPUs. See the [NVIDIA README](nvidia/README.md) for detailed instructions.

## Build and releases

The normal build and release is triggered via the normal mono repo pipeline.

[nvidia-installer](README.md)

[gardenlinux-dev](./../gardenlinux-dev/README.md)

### Local Build and release the installer image

To locally build the nvidia-installer image run the following

```bash
mono run build
```

## Productive setup

The nvidia-installer conceptually fullfils 2 distinct roles: it compiles a gpu-driver during image building
and it installs said driver into the host gardenlinux operating system.

### Practical setup

For a new Garden Linux or NVIDIA driver version:
- create a new set of GPU node pools (increment the version number in the node pool name, e.g. `infer-s-v1` becomes
 `infer-s-v2` for the new pool)

All instances of the nvidia-installer must run in a namespace that is allowed to
spawn pods with `priorityClassName: system-node-critical` - this is e.g. the case
for the `kube-system` namespace.

In addition, the gpu nodepools must have appropriate node labels so that the
compiler and the installer instances can target the correct nodes.

In general, the compiler nodepool can be scaled to zero once the desired drivers
have been compiled.
