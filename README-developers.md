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

### Semantic versioning

We follow semantic versioning for releases. The version number is in the format `MAJOR.MINOR.PATCH`, where:
- `MAJOR` version is incremented when there are breaking changes in the image or the Helm chart.
- `MINOR` version is incremented when functionality is added in a backwards-compatible manner or when there are updates 
   to the NVIDIA driver minor/patch versions in precompiled images.
- `PATCH` version is incremented when new versions of Garden Linux are supported without any other changes to the 
  image or the Helm chart.
- The version is not updated if there are only changes to the CI workflows, documentation or other 
  non-functional changes that do not affect the built image or Helm chart.

The CI process will automatically create a new release when changes are merged to `main` for minor and patch versions. 
Major versions will be released manually when needed. If follows that **breaking changes should be merged to a separate 
branch** and released manually as a major release when ready, after which the branch can be merged to `main` to trigger 
the release process for minor and patch releases.

### Release process

When a PR or commit is merged to main, the workflow in `.github/workflows/release.yml` runs and the 
following steps are performed:
1. Determine the new version number based on the commits merged to `main` since the last release according to the 
   semantic versioning rules described above.
2. Update the version in the `driver.repository` field in `helm/gpu-operator-values.yaml` to the new image registry 
   path, for example `ghcr.io/gardenlinux/gardenlinux-nvidia-installer/1.2.1/driver`.
3. Update the version in `README.md` to the new version number in the Helm command and registry path examples.
4. Update the "Supported versions" section in `README.md` by running `python3 list_versions.py` and replacing the output
   in the README with the new output.
5. Commit the changes to `helm/gpu-operator-values.yaml` and `README.md` and create a pull request. 
6. Generate a build matrix based on the dimensions in `versions.yaml`.
7. For each combination of dimensions in the build matrix:

   * If this is a patch release, check if the image for that combination already exists in the registry for the 
      previous release. If it does: pull that image, tag with the current release and push.

   * Otherwise, build the driver tarballs and container image, tag with the current release and push the image to the 
      registry.
8. Once the image building and pushing is complete (which may require some retries if there are many combinations in 
    the build matrix), an admin can merge the PR created in step 5 to `main` to update the Helm values and README with 
    the new version number and supported versions, and users looking at `main` will now see examples with the new 
    version number. Note that the release process will not trigger from this PR merge because the release workflow 
    ignores changes to these files.
9. When the version update PR from the previous step is merged, create a new GitHub release from `main` using the new 
   version number.

### Version update nightly job

Each night the workflow in `.github/workflows/update-version.yaml` runs. It checks for new NVIDIA driver versions and
new Garden Linux versions. The `versions.yaml` and `history.yaml` files are updated and a pull request is then 
created to merge those changes back to `main`. Once the PR is merged, the release process described above will be 
triggered, which will create and push new images if needed.
