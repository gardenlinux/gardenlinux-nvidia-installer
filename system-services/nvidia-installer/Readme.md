# nvidia-installer

Automatically compile kernel modules for Gardenlinux.

## High level structure of the daemonset

The daemonset has two containers which share several mounts. The first, `modulus`,
coordinates data transfer to/from the host filesystem and sends commands to the other container.
The second, `dev` is responsible for compiling & installing the kernel module.
`modulus` sends a command via a named pipe which triggers `dev` to perform the compilation.
`dev` puts the binaries and libraries into `/out/bin` and `/out/lib`, where `/out`
is `/opt/modulus/cache` on the host filesystem, and mounts the host's `/dev` to
ensure the device files are created. A third emptydir mount, `/cmd` is used
for holding the named pipes, and also to transfer a tarfile of the modulus folder to the `dev` container.

```md
 +------------+            +-------+
 |  modulus   |            |  dev  |
 +---+--+--+--+            +-+-+-+-+
     |  ^  ^                 | | ^
     |  |  |    +-------+    | | |
     |  |  +----+ cache +<---+ | |
     |  |       +-------+      | |
     |  |                      | |
     |  |       +-------+      | |
     |  +-------+  dev  +<-----+ |
     |          +-------+        |
     |                           |
     |          +-------+        |
     +--------->+  cmd  +--------+
                +-------+
```

### Background

Compiling drivers on Container Linux is typically non-trivial because the OS ships
without build tools and no obvious way to access the kernel sources. Modulus works
by compiling your kernel modules inside of a Garden Linux developer container,
which contains the kernel headers and compiler.

### Compiling NVIDIA Kernel Modules

Modulus makes it easy to automatically compile kernel modules for NVIDIA GPUs. See the [NVIDIA README](nvidia/README.md) for detailed instructions.


## Build and releases

The normal build and release is triggered via the normal mono repo pipeline.

[nvidia-installer](README.md)

[gardenlinux-dev](./../gardenlinux-dev/README.md)

### Local Build and release the installer image

To locally build the nvidia-installer image run the following

```bash
mono run build
```

## Productive setup

The nvidia-installer conceptually fullfils 2 distinct roles: it compiles a gpu-driver
and it installs said driver into the host gardenlinux operating system.

For the compile phase to succeed, the `modulus` and the `dev` container described
in section [High level structure of the daemonset](#high-level-structure-of-the-daemonset)
both must run in parallel. In kubernetes this can only be achieved when both run
as `main` containers and not as `init` containers.

In a productive environment this poses a potential security risk since the
**priviledged** `dev` container then runs permanently on the gpu node.

To prevent this we recommend a setup in which the compilation phase happens in a
dedicated secured environment and is triggered manually. The resulting compiled
driver is uploaded to an `s3` bucket from which it can be consumed by all productive
systems.

### Practical setup

- Setup one specific compiler instance of the `nvidia-installer` in a specific devOps
  cluster, `ìnfra-tests`
- Setup an installer instance of the `nvidia-installer` for all normal gpu nodepools
  in all clusters, using a new node pool for each new Garden Linux or NVIDIA driver version for production.

For a new Garden Linux or NVIDIA driver version:
- create a new set of GPU node pools (increment the version number in the node pool name, e.g. `infer-s-v1` becomes
 `infer-s-v2` for the new pool)

All instances of the nvidia-installer must run in a namespace that is allowed to
spawn pods with `priorityClassName: system-node-critical` - this is e.g. the case
for the `kube-system` namespace.

In addition, the gpu nodepools must have appropriate node labels so that the
compiler and the installer instances can target the correct nodes.

In general, the compiler nodepool can be scaled to zero once the desired drivers
have been compiled.

#### Compiler instance

The compiler instance helm values must/should be set appropriately to allow the following:

- compilation
- restriction to a dedicated nvidia-compiler nodepool, e.g. `driver-compile-node`
- setting the nvidia driver version
- setting the gardenlinux version
- setting a target s3 bucket where the compiled driver is uploaded to

These parameters can be set by the following helm `values.yaml`:
use the following helm values to allow compilations:

```yaml
allowCompilation: true
forceCompile: true
# For compilation debug must be set to true 
# Reason: in debug mode the containers do not run as init containers and can start in parallel
# Since init containers are serial, this does not work with the dev- and installer-container setup.
debug: true 

driverBucketSecret: nvidia-driver-bucket-write-prod
gardenlinuxVersion: 184.0.0

nvidiaInstaller:
  driverVersion: "450.80.02"
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: gpu
          operator: In
          values:
          - driver-compile-node
```

In this setup, the compiler instance assumes there exists a kubernetes secret in
the daemonset namespace with entries

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: nvidia-driver-bucket-write-prod
  namespace: kube-system
stringData:
  accessKeyId: <aws access key id>
  secretAccessKey: <aws secret access key>
  bucket: <s3 bucket name>
type: Opaque
```

The aws access key must grant write access to the target s3 bucket, e.g. via the policy

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "1",
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject"
            ],
            "Resource": [
                "arn:aws:s3:::aicore-nvidia-driver-prod/*",
                "arn:aws:s3:::aicore-nvidia-driver-prod"
            ]
        },
        {
            "Sid": "",
            "Effect": "Allow",
            "Action": "s3:ListBucket",
            "Resource": "arn:aws:s3:::aicore-nvidia-driver-prod"
        },
        {
            "Sid": "",
            "Effect": "Allow",
            "Action": "s3:GetBucketLocation",
            "Resource": "arn:aws:s3:::aicore-nvidia-driver-prod"
        }
    ]
}
```

#### Installer instance

The installer instance helm values must/should be set appropriately to allow the following:

- restriction to correct nvidia nodepools
- setting the nvidia driver version
- setting the gardenlinux version
- setting a target s3 bucket where the compiled driver is downloaded from
- run the priviledged installer container only temporarily

These parameters can be set by the following helm `values.yaml`:
use the following helm values to allow compilations:

```yaml
driverBucketSecret: nvidia-driver-bucket-read

nvidiaInstaller:
  driverVersion: "450.80.02"
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: gpu
          operator: Exists
        # - key: gpu
        #   operator: In
        #   values:
        #   - nvidia-tesla-t4
        #   - nvidia-tesla-v100
        #   - nvidia-tesla-k80
        - key: os-version
          operator: In
          values:
          - 184.0.0
gardenlinuxVersion: 184.0.0
```

In this setup, the installer instance assumes there exists a kubernetes secret in
the daemonset namespace with entries

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: nvidia-driver-bucket-read
  namespace: kube-system
stringData:
  accessKeyId: <aws access key id>
  secretAccessKey: <aws secret access key>
  bucket: <s3 bucket name>
type: Opaque
```

The aws access key must grant read access to the target s3 bucket, e.g. via the policy

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "1",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject"
            ],
            "Resource": [
                "arn:aws:s3:::aicore-nvidia-driver-prod/*",
                "arn:aws:s3:::aicore-nvidia-driver-prod"
            ]
        },
        {
            "Sid": "",
            "Effect": "Allow",
            "Action": "s3:ListBucket",
            "Resource": "arn:aws:s3:::aicore-nvidia-driver-prod"
        },
        {
            "Sid": "",
            "Effect": "Allow",
            "Action": "s3:GetBucketLocation",
            "Resource": "arn:aws:s3:::aicore-nvidia-driver-prod"
        }
    ]
}
```
