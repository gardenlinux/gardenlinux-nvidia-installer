# Future GPU support in Gardener

## What do we want?

We want easy-to-consume support for using GPUs in a Gardener cluster,
    beginning with NVIDIA GPUs
    
Using GPUs in Gardener is possible right now, but involves a lot
    of work. What we want is to create a worker pool of GPU nodes, and to be
    able to then schedule GPU-using Pods to those nodes with as
    little effort as possible.

In a perfect world a user would create a worker pool of GPU instances, 
and everything "just works".

In an almost-perfect world a user would select an NVIDIA GPU option
as "Additional OCI Runtime" (dropdown) in the Gardener UI / `containerRuntime` in the shoot spec.

## How we do it now

We deploy DaemonSets for the following 3 features:

  - NVIDIA driver installer
    
      - Installs the Linux kernel module that creates /dev/nvidia\*
        devices along with NVIDIA-related /bin and /lib folders in the
        host OS filesystem.
    
      - For A100, H100 and similar GPUs, runs the NVIDIA Fabric Manager
        which enables inter-GPU communication.


  - GKE Device Plugin
    
      - This image (used by GKE) makes Kubernetes aware of the GPU
        devices on the node, and takes care of inserting into GPU-using
        pods the /dev, /bin and /lib files from the NVIDIA driver
        installer.


  - DCGM Exporter
    
      - Exposes Prometheus-compatible metrics for the GPUs on each node

The GKE Device Plugin and DCGM Exporter use images created by Google and
NVIDIA, respectively.

The NVIDIA Driver Installer uses images that are built by AI Core.
[These are technically from the Garden Linux
team](https://github.com/gardenlinux/gardenlinux-nvidia-installer), but
in reality are 95% maintained by AI Core.

For each version of Garden Linux and each version of the NVIDIA driver
we want to support, we have to build an image. This image contains the
specified NVIDIA driver compiled for the kernel of that Garden Linux
version.

The [Garden Linux
repo](https://github.com/gardenlinux/gardenlinux-nvidia-installer)
mentioned above tells a user how to build an image for a given driver &
kernel version. AI Core embeds this repo into [its own build
process](https://github.wdf.sap.corp/ICN-ML/aicore/blob/main/system-services/nvidia-installer/component.yaml#L18-L45)
in order to generate the set of images required to support AI Core,
which are hosted in an AI Core registry for use only by AI Core.

### Pros & Cons

#### Pro: It works

For AI Core at least, the current way works fairly well. Every few
months we update the AI Core build list to add support for a new version
of Garden Linux or a new NVIDIA driver, and then configure AI Core to
use the new versions. This is achieved with a few lines of configuration
in our config-as-code repos and takes just a day or two (build, deploy,
test, etc).

#### Con: It requires building an image for every version combination of Garden Linux & NVIDIA driver

For other users of Gardener, all they see is the Garden Linux repo. This
is fine for doing a proof-of-concept to build a driver for a cluster
with a given version, but day 2 operations require the user to create a
build pipeline and deployment system parallel to the one used by AI Core
in order to have the images required for future versions of Garden Linux
& NVIDIA driver. (AI Core's build/deploy system is not easily usable
outside of the AI Core context.) Because such images contain proprietary
NVIDIA code (the driver is not open source), it is legally difficult to
put such images into a publicly-accessible registry for use by all.

#### Con: It's not ideal that we use the GKE Device Plugin

The [GKE Device
Plugin](https://github.com/GoogleCloudPlatform/container-engine-accelerators/blob/master/cmd/nvidia_gpu/README.md)
works well, but is used by only one other organisation (Google) and we
do not have explicit permission to use it - although [it is Apache
open-source
licensed](https://github.com/GoogleCloudPlatform/container-engine-accelerators/blob/master/LICENSE)
so the risk is low. Nevertheless we are tying ourselves to a specific
vendor other than NVIDIA.

#### Con: It requires Gardener users to label GPU nodes

Because the NVIDIA driver installer image is specific to each Garden
Linux version, each GPU node requires a label identifying this version,
for example **os-version: 1592.4.0**. Gardener does not take care of
adding such labels, so this becomes a chore for the operations team.

Note: This can now be automated by deploying the [Node Feature
    Discovery](https://kubernetes-sigs.github.io/node-feature-discovery/v0.17/get-started/index.html)
    operator and creating the following rule:


    apiVersion: nfd.k8s-sigs.io/v1alpha1
    kind: NodeFeatureRule
    metadata:
      name: gardenlinux-version
    spec:
      rules:
        - name: "Garden Linux version"
          labels:
            "node.gardener.cloud/gardenlinux-version": "@system.osrelease.GARDENLINUX_VERSION"
          matchFeatures:
            - feature: system.osrelease
              matchExpressions:
        GARDENLINUX_VERSION: {op: Exists}


This rule will result in a label similar to this:
**`node.gardener.cloud/gardenlinux-version: '1592.9'`**

## NVIDIA GPU Operator

### Pros & Cons

#### Pro: It is the official method supported by NVIDIA

The [NVIDIA GPU Operator](https://github.com/NVIDIA/gpu-operator) takes
care of installing the following:

  - NVIDIA GPU Driver

  - NVIDIA Container Toolkit (a collection of libraries and utilities
    enabling users to build and run GPU-accelerated containers)

  - NVIDIA Device Plugin

  - DCGM Exporter

  - vGPU manager

#### Con: Driver installer by default downloads and compiles at runtime

The default configuration runs a container image that downloads and
installs OS packages and then downloads, compiles and installs the
NVIDIA driver kernel modules - this is all done by the DaemonSet's Pod
when it starts on the GPU node. We used to do something similar for AI
Core, but found the approach to be somewhat fragile as well as adding a
significant amount of time to the node startup phase.

It is possible to tell the operator to use "precompiled" images instead,
which results in a similar approach to how AI Core is installing the
NVIDIA driver. Of course, a build pipeline must be set up to create
these images.

Both types of image (download & compile; precompiled) are built from the
[NVIDIA GPU Driver
Container](https://github.com/NVIDIA/gpu-driver-container) repo. The
root of this repo contains folders for various operating systems.

Only Ubuntu 22.04 and Ubuntu 24.04 are officially supported for
precompiled images, although the repo also contains the required files
and instructions to build precompiled images for RHEL 8 and RHEL 9.

#### Con: Garden Linux is not a supported platform

The NVIDIA GPU Operator supports only Ubuntu and Red Hat operating
systems. In principle, support for Garden Linux could be added
reasonably easily - however NVIDIA might not accept PRs for Garden Linux
support and therefore we might need to use and maintain a fork.

#### Con: NVIDIA Container Runtime requires host OS configuration

See [Installing the NVIDIA Container Toolkit — NVIDIA Container
Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html#configuring-containerd-for-kubernetes)

The NVIDIA Container Toolkit requires a functioning package manager on
the host OS, but the Garden Linux read-only filesystem prevents new
packages from being installed. This is probably the biggest barrier to
getting things working.

## Roadmap for the future

### Step 1 - Add Garden Linux support to the NVIDIA GPU Operator

There are several sub-steps here:

1.  Add support for Garden Linux in the [NVIDIA GPU Driver
    Container](https://github.com/NVIDIA/gpu-driver-container) repo

    It should be possible to use the Ubuntu examples from the [NVIDIA GPU
Driver Container](https://github.com/NVIDIA/gpu-driver-container) repo
in combination with the existing Garden Linux scripts to synthesise
Garden Linux support for both default and precompiled images.


2.  Figure out how to install the NVIDIA Container Toolkit/Runtime on
    Garden Linux

    The toolkit itself is [open-source on
GitHub](https://github.com/NVIDIA/nvidia-container-toolkit) so we
might be able to figure out an alternative way to install it. In the
worst case we would need to build a specific Garden Linux image to
support NVIDIA GPUs.


3. Add support for Garden Linux in the [NVIDIA GPU
    Operator](https://github.com/NVIDIA/gpu-operator)

    Not a great deal needs to be done here - mostly adding a few lines of
config, a few lines of code, and a few tests. The GPU Operator is
mostly concerned with deploying the results of the previous sub-steps.

### Step 2 - Add support for S3 storage to the NVIDIA GPU Operator

The project that served as the basis for the Garden Linux NVIDIA
installer is [squat/modulus](https://github.com/squat/modulus), which
was designed to do something very similar for Flatcar Linux / CoreOS.
This project supports having a S3 bucket, such that kernel modules are
still downloaded & compiled at runtime, but only once - the resulting
files are stored in the S3 bucket and the installer checks this bucket
for pre-built kernel modules. This has the advantages of the
default GPU operator behaviour (no need to build a container image for each
kernel & driver version) along with the advantages of the precompiled
images approach (no need to download & compile for every node in the
cluster). All of a user's clusters could share the same S3 bucket
such that the initial compilation is done in a preproduction cluster
and then production clusters would always have access to prebuilt
kernel modules.

### Step 3 - Add support for NFS PV storage to the NVIDIA GPU Operator

The previous option is almost ideal, but requires the user to set up a
S3 bucket and configure the operator to use it. Another option is for
the operator to use a NFS-based PV in which compiled images are stored
(the hyperscaler's NFS CSI driver would be deployed and take care of PV
provisioning, or alternatively Gardener could take care of setting up a
NFS volume on the hyperscaler). This would mean that the first node
using a particular kernel/driver combination would trigger module
download & compilation, but all future nodes could just get the required
files from the PV. This would deliver exactly the required user
experience, subject to Gardener deploying the required components in
response to the user enabling GPU functionality in the cluster (see next step).

### Step 4 - Enable GPU support in the Gardener UI

Up until this point GPU support is made easier, but is still not automatic - the
user needs to take care of configuring and deploying the GPU operator and the
Node Feature Discovery operator. The next step is to add a checkbox to the Gardener UI
to enable GPU support in a cluster. This would automatically deploy the NVIDIA GPU Operator and
the Node Feature Discovery operator (and associated rule to label nodes with the
Garden Linux version) and would enable the NVIDIA Container runtime as an option
for worker pools.

### Step 5 - Consider extending the NVIDIA GPU Operator to support AMD & Intel GPUs

The principles of the NVIDIA GPU Operator can also be extended to AMD
and Intel GPUs. This is a larger multi-vendor project, but could lead to
a globally better user experience and less maintenance overhead for all
parties involved (Gardener, GPU vendors and end users).