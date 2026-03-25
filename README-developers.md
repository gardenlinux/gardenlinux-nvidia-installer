# Development and build process

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

## CI and release process

At the time of writing we support only [precompiled drivers](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/precompiled-drivers.html)
and therefore `helm/gpu-operator-values.yaml` sets `driver.usePrecompiled: true`.

Work is in progress to support compile-at-runtime drivers (`driver.usePrecompiled: true`) - see branch 
[`refactor_compilation`](https://github.com/gardenlinux/gardenlinux-nvidia-installer/tree/refactor_compilation).

### Release process [WIP]

When a new release is made, the workflow in `.github/workflows/release.yml` runs and the following steps are performed:
1. Create a new release branch from `main` named `release/<version>`, for example `release/1.2.1`.
2. Update the `version` field in `helm/gpu-operator-values.yaml` to the new image tag, for example `1.2.1`.
4. Update the `image` field in `helm/gpu-operator-values.yaml` to the new image tag, for example `ghcr.io/gardenlinux/gardenlinux-nvidia-installer/driver:590-6.12.72-cloud-amd64-gardenlinux0`.
5. Build and push the new image to the registry.
6. Create a pull request from the release branch to `main` and merge it after review. 

### Version update nightly job

Each night the workflow in `.github/workflows/update-version.yaml` runs. It checks for new NVIDIA driver versions and
new Garden Linux versions. The `versions.yaml` file is updated on the release branch and any new images that need to be 
built are built and pushed to the registry in the folder for that release branch.
A pull request is then created to merge the `versions.yaml` changes back to `main`.

### Develpoment on `main` branch

TODO