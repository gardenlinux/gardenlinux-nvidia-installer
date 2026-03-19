# nvidia-installer

This component installs NVIDIA kernel modules on Garden Linux nodes at runtime via the NVIDIA GPU Operator. Pre-compiled
kernel modules are baked into the image at build time.

## Deploying NVIDIA GPU Operator with Helm

```bash
helm upgrade --install -n gpu-operator gpu-operator nvidia/gpu-operator \
  --values https://raw.githubusercontent.com/gardenlinux/gardenlinux-nvidia-installer/refs/tags/1.2.1/helm/gpu-operator-values.yaml
```

Built images are published at:

```
ghcr.io/gardenlinux/gardenlinux-nvidia-installer/<release>/driver:<driver_major>-<kernel_version>-gardenlinux0
```

For example: `ghcr.io/gardenlinux/gardenlinux-nvidia-installer/1.2.1/driver:590-6.12.72-cloud-amd64-gardenlinux0`

If you have built the images yourself, override the registry and image name:

```bash
helm upgrade --install -n gpu-operator gpu-operator nvidia/gpu-operator \
  --values https://raw.githubusercontent.com/gardenlinux/gardenlinux-nvidia-installer/refs/tags/1.2.1/helm/gpu-operator-values.yaml \
  --set driver.repository=$REGISTRY/$FOLDER \
  --set driver.image=$IMAGE
```

## Building locally (without GitHub Actions)

There are two make targets as part of "make build" which use a workspace directory (`out`) as a shared volume to 
exchange 
build artifacts:

1. **build-driver** — compiles kernel module and creates tar archives, one per kernel type (`open`, `proprietary`) for 
   the `(driver version, kernel version)` being built.
2. **build-image** — builds a container image that includes the driver tarballs installs the correct driver on the
   host according to the determined kernel type.

Both are built with `make`. The required variables are:

| Variable         | Description                                             | Default                                                   |
|------------------|---------------------------------------------------------|-----------------------------------------------------------|
| `GL_VERSION`     | Garden Linux version (e.g. `1877.13`)                   | *(required)*                                              |
| `DRIVER_VERSION` | Full NVIDIA driver version (e.g. `590.48.01`)           | *(required)*                                              |
| `KERNEL_FLAVOR`  | Kernel flavour: `cloud` or `metal`                      | `cloud`                                                   |
| `TARGET_ARCH`    | CPU architecture: `amd64` or `arm64`                    | `amd64`                                                   |
| `IMAGE_PATH`     | Registry path for the container image                   | `ghcr.io/gardenlinux/gardenlinux-nvidia-installer/driver` |

### Build a driver tarball

Compiles the kernel modules inside the Garden Linux `kmodbuild` container and writes the tarball to `./out/nvidia/`:

```bash
export GL_VERSION=1877.13
export DRIVER_VERSION=590.48.01
make build-driver
```

The output tarballs are named `driver-<DRIVER_VERSION>-<KERNEL_TYPE>-<KERNEL_NAME>.tar.gz`, for example:

```
out/nvidia/driver-590.48.01-open-6.12.72-cloud-amd64.tar.gz
out/nvidia/driver-590.48.01-proprietary-6.12.72-cloud-amd64.tar.gz
```

To build for bare-metal nodes add `KERNEL_FLAVOR=metal`. To cross-compile for arm64 add `TARGET_ARCH=arm64`.

### Build the container image

Builds and tags the installer image. `KERNEL_NAME` is extracted automatically from the `kmodbuild` container:

```bash
export GL_VERSION=1877.13
export DRIVER_VERSION=590.48.01
make build-image
```

This produces two tags:

```
<IMAGE_PATH>:<driver_major>-<kernel_name>-gardenlinux0
<IMAGE_PATH>:<driver_version>-<kernel_name>-gardenlinux0
```

For example:

```
ghcr.io/gardenlinux/gardenlinux-nvidia-installer/driver:590-6.12.72-cloud-amd64-gardenlinux0
ghcr.io/gardenlinux/gardenlinux-nvidia-installer/driver:590.48.01-6.12.72-cloud-amd64-gardenlinux0
```

To push the image, `docker push` each tag printed by `make build-image`.

### Build both tarballs and image in one step

```bash
export GL_VERSION=1877.13
export DRIVER_VERSION=590.48.01
make build
```

### Kernel module type selection at runtime

The `KERNEL_MODULE_TYPE` environment variable controls which pre-compiled tarball the container downloads:

| Value              | Behaviour                                       |
|--------------------|-------------------------------------------------|
| `auto` *(default)* | Detects the correct type at runtime (see below) |
| `open`             | Always use open kernel modules                  |
| `proprietary`      | Always use proprietary kernel modules           |

In `auto` mode the container picks the module type based on two checks:

1. **Driver version** — driver branches older than 560 ship proprietary modules only.
2. **GPU architecture** — NVIDIA open kernel modules require Turing (2018) or newer. GPUs from the Maxwell (e.g. M40),
   Pascal (e.g. P100), or Volta (e.g. V100) architectures are only supported by the proprietary modules. The container
   detects this at runtime by reading PCI device IDs from the host.

Set `KERNEL_MODULE_TYPE` explicitly as a container environment variable when deploying via the GPU Operator to override
the auto-detection.

## Supported versions

```bash
python3 list_versions.py
```

Example output:

<!-- list_versions_output_start -->
```

Supported OS ↔ Driver Versions
---------------------------------------------
OS 1592.14: 570.195.03, 565.57.01, 550.163.01
OS 1592.15: 580.126.09, 580.105.08, 570.211.01, 570.195.03
OS 1592.16: 590.48.01, 580.126.16, 580.126.09, 570.211.01
OS 1592.17: 590.48.01, 580.126.20
OS 1592.18: 590.48.01, 580.126.20, 570.211.01
OS 1877.10: 590.48.01, 580.126.09
OS 1877.11: 590.48.01, 580.126.16
OS 1877.13: 590.48.01, 580.126.20, 570.211.01
OS 1877.8: 580.105.08, 570.195.03
OS 1877.9: 580.126.09, 580.105.08, 570.211.01, 570.195.03
OS 2150.0.0: 590.48.01, 580.126.20, 570.211.01


Lifecycle for Driver and supported GL version depends on Garden Linux Release and Driver Release

Refer below links for Garden Linux and driver releases

Garden Linux Release: https://github.com/gardenlinux/gardenlinux/releases

Driver Release: https://www.nvidia.com/en-us/drivers/ --> Select Data Center/Tesla
```
<!-- list_versions_output_end -->

## Driver lifecycle

This project tracks the **three** most recent NVIDIA driver major versions. Minor driver releases and Garden Linux 
version updates are applied automatically via CI; major driver version bumps are handled manually.

- **Garden Linux versions** are tracked from https://github.com/gardenlinux/gardenlinux/releases
- **NVIDIA driver versions** are tracked from https://www.nvidia.com/en-us/drivers/

## Background

Garden Linux ships without build tools and without accessible kernel sources on the running node. This project solves
that by compiling kernel modules at image-build time inside the Garden Linux `kmodbuild` developer container (which
contains the correct kernel headers and compiler toolchain). The compiled modules are packaged into tarballs, published
to GitHub Releases, and downloaded by the installer container at runtime immediately before installation.

## Disclaimer

Drivers built with this project are only supported on Garden Linux. Only data center (non-consumer) graphics cards are
supported.
