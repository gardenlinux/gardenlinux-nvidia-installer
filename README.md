# nvidia-installer


This component compiles NVIDIA kernel modules for Garden Linux in a Docker image at build time.
Running the image in a cluster as part of a DaemonSet installs the GPU driver on the required nodes.

Normally 2 to 3 versions should be maintained of Garden Linux and NVIDIA drivers:
always previous & current versions, and a future/canary version when
the related Garden Linux or NVIDIA driver version is released.
Older versions should be commented out accordingly in order to avoid
combinatorial explosion when building images. as we build an image for each combination of Garden Linux & NVIDIA driver.

## TL;DR - How to create a new version?

### New Garden Linux version

See [gardenlinux-dev/README.md](gardenlinux-dev/README.md) for details, but in short:

* Update the values in the `image_versions` file, and in the `context.gardenLinux` section of `component.yaml`
* Make sure the required Garden Linux DEB files are copied to the Swift container `gardenlinux-packages` in Converged Cloud
  project [hcp03/SAPCLEA](https://dashboard.eu-de-1.cloud.sap/hcp03/sapclea/home).
* [Release the new versions of `nvidia-installer`](#release-a-new-version-of-nvidia-installer).

### New NVIDIA driver (CUDA) version

* Add the driver version value to the `driverVersion` list in the `context.nvidiaDriverVersion` section of `component.yaml`
* [Release the new version of `nvidia-installer`](#release-a-new-version-of-nvidia-installer).

### Release a new version of nvidia-installer

* Commit any changes for this release & push to GitHub, check that PR validation runs OK
* Merge the PR to `main` & check the main build runs OK
* This should be done automatically, but in case it has not worked:

  Build "with Parameters" the [AI Core Release job](https://jenkins.ml.only.sap/job/AI-Foundation/job/berlin-jenkins/job/AI-Core/job/Release/job/main/)
  in Jenkins, specifying the component `system-services/nvidia-installer`.

  This job will take care of incrementing the
  version number in `component.yaml`, adding a message to `CHANGELOG.md`, building the images and pushing it to a Docker
  registry.
* When this job is complete, Xmake will have published the images using the form:

  `deploy-releases.common.repositories.cloud.sap/com.sap.ai/nvidia-installer-<GardenLinux-version>-<NVIDIA-version>:<component-version>`

  For example,

  `deploy-releases.common.repositories.cloud.sap/com.sap.ai/nvidia-installer-576.1.0-470.82.01:1.5.3`

* Within a few minutes (max 1 hour), the images will be synced to GCR and will be available via image URIs of the form

  `eu.gcr.io/sap-ml-mlf-dev/com.sap.ai/nvidia-installer-<GardenLinux-version>-<NVIDIA-version>:<component-version>`


### For both of the above

Once released & published, make sure to update `mlf-gitops` values according to the new release version.
See for example `mlf-gitops/cluster-service-list/templates/nvidia-installer-GL184.yaml`

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
by compiling the kernel modules at build-time inside of a Garden Linux developer container
(which contains the kernel headers and compiler) and then placing the resulting files
into a Docker image from which they can be installed at runtime.

### Local Build and release the installer image

To locally build the nvidia-installer image run the following

```bash
docker build . --build-arg TARGET_ARCH=amd64 --build-arg DRIVER_VERSION=535.86.10 --build-arg GARDENLINUX_VERSION=934.11
```
To build for a bare-metal version of Garden Linux, add `--build-arg LINUX_HEADERS=linux-headers`.

### Practical setup

For a new Garden Linux or NVIDIA driver version:
- create a new set of GPU node pools (increment the version number in the node pool name, e.g. `infer-s-v1` becomes
 `infer-s-v2` for the new pool)

All instances of the nvidia-installer must run in a namespace that is allowed to
spawn pods with `priorityClassName: system-node-critical` - this is e.g. the case
for the `kube-system` namespace.

In addition, the gpu nodepools must have appropriate node labels so that
the nvidia-installer instances can target the correct nodes.
