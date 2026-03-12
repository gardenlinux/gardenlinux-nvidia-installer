# nvidia-installer

This component installs NVIDIA kernel modules on Garden Linux nodes at runtime via the NVIDIA GPU Operator. Pre-compiled
kernel module tarballs are downloaded from GitHub Releases when the container starts — nothing is baked into the image
at build time.

## Deploying NVIDIA GPU Operator with Helm

```bash
helm upgrade --install -n gpu-operator gpu-operator nvidia/gpu-operator \
  --values https://raw.githubusercontent.com/gardenlinux/gardenlinux-nvidia-installer/refs/heads/main/helm/gpu-operator-values.yaml
```

Built images are published at:

```
ghcr.io/gardenlinux/gardenlinux-nvidia-installer/driver:<driver_major>-<kernel_version>-gardenlinux0
```

For example: `ghcr.io/gardenlinux/gardenlinux-nvidia-installer/driver:590-6.12.72-cloud-amd64-gardenlinux0`

If you have built the images yourself, override the registry and image name:

```bash
helm upgrade --install -n gpu-operator gpu-operator nvidia/gpu-operator \
  --values https://raw.githubusercontent.com/gardenlinux/gardenlinux-nvidia-installer/refs/heads/main/helm/gpu-operator-values.yaml \
  --set driver.repository=$REGISTRY/$FOLDER \
  --set driver.image=$IMAGE
```

## Building locally (without GitHub Actions)

Two artifacts are produced independently:

1. **Driver tarballs** — pre-compiled kernel module archives, one per `(driver version, kernel type, kernel version)`.
   Published to GitHub Releases and downloaded by the container at runtime.
2. **Container image** — a thin installer image that downloads the appropriate tarball at startup and installs it on the
   host.

Both are built with `make`. The required variables are:

| Variable         | Description                                             | Default                                                   |
|------------------|---------------------------------------------------------|-----------------------------------------------------------|
| `GL_VERSION`     | Garden Linux version (e.g. `1877.13`)                   | *(required)*                                              |
| `DRIVER_VERSION` | Full NVIDIA driver version (e.g. `590.48.01`)           | *(required)*                                              |
| `KERNEL_FLAVOR`  | Kernel flavour: `cloud` or `metal`                      | `cloud`                                                   |
| `TARGET_ARCH`    | CPU architecture: `amd64` or `arm64`                    | `amd64`                                                   |
| `KERNEL_TYPE`    | Module type: `open` or `proprietary`                    | *(required for `build-driver`)*                           |
| `RELEASE_TAG`    | GitHub Release tag tarballs are fetched from at runtime | `development`                                             |
| `IMAGE_PATH`     | Registry path for the container image                   | `ghcr.io/gardenlinux/gardenlinux-nvidia-installer/driver` |

### Build a driver tarball

Compiles the kernel modules inside the Garden Linux `kmodbuild` container and writes the tarball to `./out/nvidia/`:

```bash
export GL_VERSION=1877.13
export DRIVER_VERSION=590.48.01
export KERNEL_TYPE=open        # or: proprietary
make build-driver
```

The output tarball is named `driver-<DRIVER_VERSION>-<KERNEL_TYPE>-<KERNEL_NAME>.tar.gz`, for example:

```
out/nvidia/driver-590.48.01-open-6.12.72-cloud-amd64.tar.gz
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

#### Runtime tarball download

The `RELEASE_TAG` build argument is baked into the image at build time. At runtime, the container uses it to download
the matching tarball from:

```
https://github.com/gardenlinux/gardenlinux-nvidia-installer/releases/download/<RELEASE_TAG>/driver-<DRIVER_VERSION>-<KERNEL_TYPE>-<KERNEL_NAME>.tar.gz
```

When building locally, `RELEASE_TAG` defaults to `development`. To test against a real release, set it explicitly:

```bash
make build-image GL_VERSION=1877.13 DRIVER_VERSION=590.48.01 RELEASE_TAG=v1.2.3
```

To point the container at an alternative tarball mirror at runtime, set the `TARBALL_BASE_URL` environment variable when
deploying.

### Build both tarball and image in one step

```bash
export GL_VERSION=1877.13
export DRIVER_VERSION=590.48.01
export KERNEL_TYPE=open
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

```
Supported OS ↔ Driver Versions
---------------------------------------------
OS 1592.18: 590.48.01, 580.126.20
OS 1877.13: 590.48.01, 580.126.20
OS 2150.0.0: 590.48.01, 580.126.20
```

## Driver lifecycle

This project tracks the **two** most recent NVIDIA driver major versions. Minor driver releases and Garden Linux version
updates are applied automatically via CI; major driver version bumps are handled manually.

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
