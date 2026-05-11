# nvidia-installer

This component installs NVIDIA kernel modules on Garden Linux nodes at runtime via the NVIDIA GPU Operator. Pre-compiled
kernel modules are baked into the image at build time.

## Deploying NVIDIA GPU Operator with Helm

```bash
helm upgrade --install -n gpu-operator gpu-operator nvidia/gpu-operator \
  --values https://raw.githubusercontent.com/gardenlinux/gardenlinux-nvidia-installer/refs/tags/1.7.1/helm/gpu-operator-values.yaml
```

Built images are published at:

```
ghcr.io/gardenlinux/gardenlinux-nvidia-installer/<release>/driver:<driver_major>-<kernel_version>-gardenlinux0
```

For example: `ghcr.io/gardenlinux/gardenlinux-nvidia-installer/1.7.1/driver:590-6.12.72-cloud-amd64-gardenlinux0`

If you have built the images yourself, override the registry and image name:

```bash
helm upgrade --install -n gpu-operator gpu-operator nvidia/gpu-operator \
  --values https://raw.githubusercontent.com/gardenlinux/gardenlinux-nvidia-installer/refs/tags/1.7.1/helm/gpu-operator-values.yaml \
  --set driver.repository=$REGISTRY/$FOLDER \
  --set driver.image=$IMAGE
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

**Important note:** with Garden Linux versions 1592.14 and earlier, only proprietary kernel modules will work. This is
handled by the "auto" logic only in releases 1.2.1 and later.


## Supported versions

```bash
python3 list_versions.py
```

Example output:

<!-- list_versions_output_start -->
```

Supported OS ↔ Driver Versions
---------------------------------------------
OS 1592.14: 590.48.01, 580.159.03, 580.126.20, 570.211.01, 570.195.03, 565.57.01, 550.163.01
OS 1592.15: 590.48.01, 580.159.03, 580.126.20, 580.126.09, 580.105.08, 570.211.01, 570.195.03
OS 1592.16: 590.48.01, 580.159.03, 580.126.20, 580.126.16, 580.126.09, 570.211.01
OS 1592.17: 590.48.01, 580.126.20, 570.211.01
OS 1592.18: 590.48.01, 580.159.03, 580.126.20, 570.211.01
OS 1877.12: 590.48.01, 580.126.20, 570.211.01
OS 1877.13: 590.48.01, 580.159.03, 580.126.20, 570.211.01
OS 1877.14: 590.48.01, 580.159.03, 580.126.20, 570.211.01
OS 1877.15: 590.48.01, 580.159.03, 570.211.01
OS 1877.16: 590.48.01, 580.159.03, 570.211.01
OS 2150.0.0: 590.48.01, 580.159.03, 580.126.20, 570.211.01
OS 2150.1.0: 590.48.01, 580.159.03, 580.126.20, 570.211.01
OS 2150.2.0: 590.48.01, 580.159.03, 570.211.01


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

This project maintains the latest three Garden Linux releases for the precompiled flavor. If support for older 
Garden Linux versions is needed, you can use the runtime build by applying the Helm values from helm/gpu-operator-values-runtime.yaml.
Note: When using the runtime image, please be aware that driver availability may take approximately 4 minutes.

## Background

Garden Linux ships without build tools and without accessible kernel sources on the running node. This project solves
that by compiling kernel modules at image-build time inside the Garden Linux `kmodbuild` developer container (which
contains the correct kernel headers and compiler toolchain). The compiled modules are packaged into tarballs, published
to GitHub Releases, and downloaded by the installer container at runtime immediately before installation.

## Development

For instructions on building the driver tarballs and container images locally and working with the build system, 
see [README-developers.md](README-developers.md).

## Disclaimer

Drivers built with this project are only supported on Garden Linux. Only data center (non-consumer) graphics cards are
supported.

