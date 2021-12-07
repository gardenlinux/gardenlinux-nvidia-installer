# nvidia-installer

Compile NVIDIA kernel modules for Garden Linux in a Docker image. Running the image in a cluster installs the GPU driver.

## TL;DR - How to create a new version?

### New Garden Linux version

See [system-services/gardenlinux-dev/README.md](../gardenlinux-dev/README.md) for details, but in short:

* Make sure the required Garden Linux DEB files are copied to the Swift container `gardenlinux-packages` in Converged Cloud
  project [hcp03/SAPCLEA](https://dashboard.eu-de-1.cloud.sap/hcp03/sapclea/home).
* Update the values in the `image_versions` file, and in the `context` section of `component.yaml`
* Add required xmake entries in the `config/services` branch 
* [Release the new versions of `nvidia-installer`](#release-a-new-version-of-nvidia-installer).

### New NVIDIA driver (CUDA) version

* In the `config/services` branch, in `config/services/production-services/build-service/config.yml` add a variant 
  for `nvidia-installer-<gardenlinux version>-<driver version>` for each Garden Linux version for which you want 
  the new driver to be available.
* Add the driver version value to the `driverVersion` list in the `context` section of `component.yaml`
* [Release the new version of `nvidia-installer`](#release-a-new-version-of-nvidia-installer).

### Release a new version of nvidia-installer

* Commit any changes for this release & push to GitHub, check that PR validation runs OK
* Merge the PR to `main` & pull/fetch to update your local copy
* Checkout a new branch `release-nvidia-installer-<version>`
* From the `nvidia-installer-<version>` folder run `mono release` (if this is for a new Garden Linux version, do this once 
  per `nvidia-installer` folder) and **increment the release version** (for example, from `1.5.0` to `1.5.1`.
* Commit the changes with message `"[release] updating nvidia-installer to version X"` and push the commit to GitHub
* In order not to release unnecessary components, stop the PR build and restart it with "Release" checked, and the
  components list set to `system-services/nvidia-installer`
* Once everything is green & approved, merge the commit and then restart the `main` build the same way as in the 
  previous step 

### For both of the above

Make sure to update `mlf-gitops` according to the new release version.

## High level structure of the Dockerfile

The first stage installs the needed compilers & kernel headers, then calls 
a script to download the NVIDIA driver files and compile the kernel modules, and finally creates a
compressed tar archive of the required files.

The second (main) stage copies the tarball into the image along with the runtime scripts to
extract the tarball and install
the modules into the running kernel as part of a Daemonset.

### Background

Compiling drivers on Container Linux is typically non-trivial because the OS ships
without build tools and no obvious way to access the kernel sources. Modulus works
by compiling your kernel modules inside of a Garden Linux developer container,
which contains the kernel headers and compiler.

### Compiling NVIDIA Kernel Modules

Modulus makes it easy to automatically compile kernel modules for NVIDIA GPUs. See the [NVIDIA README](nvidia/README.md) for detailed instructions.

### Local Build and release the installer image

To locally build the nvidia-installer image run the following

```bash
mono run build
```

### Practical setup

For a new Garden Linux or NVIDIA driver version:
- create a new set of GPU node pools (increment the version number in the node pool name, e.g. `infer-s-v1` becomes
 `infer-s-v2` for the new pool)

All instances of the nvidia-installer must run in a namespace that is allowed to
spawn pods with `priorityClassName: system-node-critical` - this is e.g. the case
for the `kube-system` namespace.

In addition, the gpu nodepools must have appropriate node labels so that the
the nvidia-installer instances can target the correct nodes.
