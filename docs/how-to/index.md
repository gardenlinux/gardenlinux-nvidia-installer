---
title: "NVIDIA Installer"
description: "Learn how to install NVIDIA kernel modules in Garden Linux."
github_target_path: "docs/how-to/nvidia_installer/index.md"
github_org: gardenlinux
github_repo: gardenlinux-nvidia-installer
github_source_path: docs/how-to/index.md
---
# Garden Linux NVIDIA Installer 

This component installs NVIDIA kernel modules on Garden Linux nodes at runtime via the NVIDIA GPU Operator. Pre-compiled
kernel modules are baked into the image at build time.

<SectionIndex />

## Driver lifecycle

This project tracks the **three** most recent NVIDIA driver major versions. Minor driver releases and Garden Linux 
version updates are applied automatically via CI; major driver version bumps are handled manually.

- **Garden Linux versions** are tracked from https://github.com/gardenlinux/gardenlinux/releases
- **NVIDIA driver versions** are tracked from https://www.nvidia.com/en-us/drivers/

## Runtime Driver compilation

This project also supports compilation of kernel during runtime. With this feature, the operator automatically 
detects the host’s kernel version and builds the required driver modules using the host’s kernel headers.
To enable runtime driver compilation, apply the Helm values provided in helm/gpu-operator-values-runtime.yaml.

::: tip Note
When using the runtime image, please be aware that driver availability may take approximately 4 minutes.
:::

## gVisor (runsc) support

For clusters running workloads inside gVisor sandboxes, driver images are published at a separate `gvisor/driver`
registry path. These images use nvproxy-qualified driver versions pinned by the gVisor project.

```bash
helm upgrade --install -n gpu-operator gpu-operator nvidia/gpu-operator \
  --values https://raw.githubusercontent.com/gardenlinux/gardenlinux-nvidia-installer/refs/tags/1.15.0/helm/gpu-operator-gvisor-values.yaml
```

gVisor driver images are published at:

```
ghcr.io/gardenlinux/gardenlinux-nvidia-installer/<release>/gvisor/driver:<driver_major>-<kernel_version>-gardenlinux0
```

The `driver.version` in `gpu-operator-gvisor-values.yaml` tracks the gVisor-pinned major, which may differ from the
mainstream driver major when the latest mainstream release is not yet qualified by gVisor’s nvproxy.

## Background

Garden Linux ships without build tools and without accessible kernel sources on the running node. This project solves
that by compiling kernel modules at image-build time inside the Garden Linux `kmodbuild` developer container (which
contains the correct kernel headers and compiler toolchain). The compiled modules are packaged into tarballs, published
to GitHub Releases, and downloaded by the installer container at runtime immediately before installation.

## Development

For instructions on building the driver tarballs and container images locally and working with the build system, 
see [Building NVIDIA Kernel Modules](./building_nvidia_modules.md) guide.

## Disclaimer

Drivers built with this project are only supported on Garden Linux. Only data center (non-consumer) graphics cards are
supported.

