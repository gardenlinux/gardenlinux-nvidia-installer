# nvidia-installer

This component compiles NVIDIA kernel modules for Garden Linux in a Docker image at build time.
Running the image in a cluster as part of a DaemonSet installs the GPU driver on the required nodes.

## Building the Docker image

To build the image for NVIDIA driver version `550.127.08` on Garden Linux `1592.4` for `amd64`-based CPUs:
```bash
docker build . --platform=linux/amd64 --build-arg TARGET_ARCH=amd64 --build-arg DRIVER_VERSION=550.127.08 --build-arg GARDENLINUX_VERSION=1592.4
```
If you need to build for a baremetal node (as opposed to a cloud VM) then add `--build-arg KERNEL_TYPE=baremetal` 
to the above command.

## Deploying nvidia-installer with Helm

First build the image as described above, and then push it to your Docker registry.

Next, edit the file `todo-values.yaml` in the `helm` folder to specify the location of the Docker image and the
values of the NVIDIA driver version and Garden Linux version. The Garden Linux version is used to tell the 
DaemonSet which nodes to target - the sample `nodeAffinity` values assume that your GPU nodes have a `gpu` label, 
and also an `os-version` label which is set to the Garden Linux version.

Now you can deploy the DaemonSets for the NVIDIA Driver installer and the NVIDIA Device Plugin along with the related
imagePullSecret with the following command:
```bash
helm install nvidia ./helm --namespace kube-system --values helm/todo-values.yaml
```

Note that the resulting Pods  must run in a namespace that is allowed to
spawn pods with `priorityClassName: system-node-critical` - this is true for example in the case
of the `kube-system` namespace.

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

Drivers build with this project are only supported on Garden Linux, the open source operating system. 
Furthermore, only drivers for non consumer graphics cards are supported.
