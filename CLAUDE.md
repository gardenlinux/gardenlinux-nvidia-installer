# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repo builds and packages NVIDIA GPU drivers for Garden Linux, enabling GPU support in Kubernetes clusters via the [NVIDIA GPU Operator](https://github.com/NVIDIA/gpu-operator). Two deployment modes exist: **precompiled** (driver compiled at CI time, embedded in image) and **runtime compilation** (driver compiled on the node at container startup from a `.run` package downloaded off the internet).

**Image registry:** `ghcr.io/gardenlinux/gardenlinux-nvidia-installer/{kernel_type}/driver`

## Build Commands

All builds require environment variables set beforehand:

```bash
export GL_VERSION=1877.3
export DRIVER_VERSION=590.48.01
export KERNEL_TYPE=proprietary      # or 'open'
export TARGET_ARCH=amd64            # or 'arm64' (default: amd64)
export KERNEL_FLAVOR=cloud          # or 'metal' (default: cloud)
```

| Command | Description |
|---------|-------------|
| `make build` | Full build: compile driver modules then build Docker image |
| `make build-driver` | Compile kernel modules only (output: `out/nvidia/`) |
| `make build-image` | Build Docker image from pre-compiled driver archive |
| `make clean` | Remove specific driver archive |
| `make clean-all` | Remove all output |

## Testing

Integration tests run on real Gardener clusters with GPU nodes (see `tests/`):

```bash
helm install gpu-test ./tests -n gpu-test
helm test gpu-test -n gpu-test --timeout 3m
```

Linting: ShellCheck is run differentially on changed shell scripts in CI (`differential-shellcheck.yml`).

## Architecture

### Two-Stage Build

**Stage 1 – Driver compilation (`make build-driver`):**
- Spins up a `ghcr.io/gardenlinux/gardenlinux/kmodbuild` container for the target GL version/arch
- `resources/compile.sh` downloads the NVIDIA `.run` installer and compiles kernel modules against Garden Linux kernel headers
- Output: `out/nvidia/driver-${DRIVER_VERSION}-${KERNEL_TYPE}-${KERNEL_NAME}.tar.gz`

**Stage 2 – Image packaging (`make build-image`):**
- Starts from `ghcr.io/gardenlinux/gardenlinux:${GL_VERSION}` base
- Copies the compiled driver archive into the image
- Dockerfile strips large/vulnerable packages (libgnutls30, apt, openssl, dpkg, ncurses) to reduce CVE surface
- Final image is multi-stage with a scratch base

### Runtime (Kubernetes)

The container entrypoint `nvidia-driver` runs `load_install_gpu_driver.sh`, then `install_containerd_path_dropin.sh`, then `install_fabricmanager.sh`.

**Two deployment modes, selected by `usePrecompiled` in the Helm values:**

**Precompiled mode** (`usePrecompiled: true`, `Dockerfile`, `gpu-operator-values.yaml`):
- `resources/load_install_gpu_driver.sh` resolves `KERNEL_MODULE_TYPE` (open/proprietary/auto), locates the pre-compiled tarball embedded at `/opt/nvidia-installer/drivers/`, extracts it to `/run/nvidia/driver`, then runs `resources/install.sh` to load kernel modules and call `nvidia-modprobe`.

**Runtime compilation mode** (`usePrecompiled: false`, `Dockerfile_Runtime`, `gpu-operator-values-runtime.yaml` / `gpu-operator-gvisor-values.yaml`):
- `Dockerfile_Runtime` copies `resources/*` then **overwrites** `compile.sh` and `load_install_gpu_driver.sh` with the `dynamic_compilation/` versions. The `resources/` versions of those two files are unused in this mode.
- `dynamic_compilation/load_install_gpu_driver.sh` orchestrates the full flow:
  1. Guards against already-loaded modules (`lsmod` via nsenter)
  2. `resolve_driver_version`: if `DRIVER_VERSION` is a plain integer (e.g. `580`) and `runsc` is on the host, calls `runsc nvproxy list-supported-drivers` to resolve the latest patch version (e.g. `580.178.04`) — required for gVisor compatibility
  3. `resolve_kernel_module_type`: chooses open/proprietary based on driver major version (≥560 → open) and GPU architecture (pre-Turing → proprietary regardless)
  4. Calls `dynamic_compilation/compile.sh`, which: installs kernel headers from the Garden Linux package repo, downloads `NVIDIA-Linux-{arch}-{version}.run` from `$BASE_URL`, extracts and runs `nvidia-installer --utility-prefix=/run/nvidia/{version}/driver`, then stages output to `/run/nvidia/.staging-driver/`
  5. Promotes staging to `/run/nvidia/driver/`
  6. Copies utilities to pod `/usr/bin` so the startup probe can find `nvidia-smi`
  7. Runs `resources/install.sh` to load modules via `modprobe -d` and call `nvidia-modprobe`
  8. Final `nvidia-smi` verification

### Version Management
- `versions.yaml` — declarative matrix of supported GL versions × architectures × kernel flavors/types × NVIDIA driver versions
- `history.yaml` — all historical driver/kernel combinations ever built
- `.ci/generate_matrix.py` — expands `versions.yaml` into a GitHub Actions build matrix
- `.ci/update_versions.py` — daily cron job scrapes GitHub/NVIDIA for new minor/patch releases and opens a PR

**Support policy:** Two most recent NVIDIA major driver versions; latest two Garden Linux major versions with all minor versions.

### Key Scripts

| Script | Mode | Purpose |
|--------|------|---------|
| `resources/compile.sh` | Precompiled (CI) | Downloads NVIDIA driver, compiles modules, archives output |
| `resources/load_install_gpu_driver.sh` | Precompiled | Extracts embedded tarball, loads modules |
| `resources/install.sh` | Both | Loads kernel modules via `modprobe -d`, calls `nvidia-modprobe` to create device nodes |
| `resources/extract_kernel_name.sh` | Precompiled (CI) | Detects kernel name from kmodbuild container |
| `resources/set_env_vars.sh` | Both | Sets `NVIDIA_ROOT`, `KERNEL_NAME`, `ARCH_TYPE`, etc. |
| `resources/download_fabricmanager.sh` | Both | Downloads optional Fabric Manager |
| `dynamic_compilation/compile.sh` | Runtime | Installs kernel headers, downloads `.run`, compiles with `nvidia-installer`, stages output |
| `dynamic_compilation/load_install_gpu_driver.sh` | Runtime | Orchestrates the full runtime compilation + install flow (overwrites `resources/` version) |
| `dynamic_compilation/resolve_driver_version.sh` | Runtime | Resolves major driver version to full patch version via `runsc nvproxy list-supported-drivers` |
| `nvidia-driver` | Both | Container entrypoint (GPU Operator compatibility) |

### CI/CD Workflows (`.github/workflows/`)

| Workflow | Trigger |
|----------|---------|
| `release.yml` | Push to `main` or manual dispatch; orchestrates full release |
| `build_driver.yml` | Called by release; matrix build of all driver combinations |
| `build_image.yml` | Called by release; builds/pushes images and multi-arch manifests |
| `update_version.yml` | Daily cron; auto-updates `versions.yaml`, opens PR on changes |
| `test_installer.yml` | Weekday cron (Mon–Fri 18:00 UTC); integration test on Gardener cluster |
| `differential-shellcheck.yml` | PR; lints changed shell scripts |

### Artifact Naming
`driver-${os_version}-${arch}-${kernel_flavour}-${kernel_type}-${driver_version}.tar.gz`

Image tags (three per build):
- `{DRIVER_MAJOR}-{KERNEL_VERSION}-gardenlinux{GL_VERSION}`
- `{DRIVER_MAJOR}-{KERNEL_VERSION}-gardenlinux0`
- `{DRIVER_VERSION}-{KERNEL_VERSION}-gardenlinux0`

## Quirks & Gotchas

- **GL_VERSION format**: Use two-part version (`1877.17`, `2150.3`), NOT three-part (`1877.17.0`). The kmodbuild image tag is `kmodbuild:amd64-{GL_VERSION}` and will fail with `manifest unknown` if you use a three-part version.
- **`make build` vs `make build-image`**: If no pre-compiled tarball exists in `out/nvidia/` for the target GL version, run `make build` (not `make build-image`) to compile + package. `make build-image` alone will fail if the tarball is missing.
- **Mixed-kernel clusters**: During GL version upgrades, different nodes may run different kernels. The GPU Operator creates one DaemonSet per kernel version — both the old and new kernel images may need to be pushed.
- **B200 node recovery**: After a cluster node replacement, the B200 node may stay `NotReady` for 10–20+ minutes before NFD labels it and the GPU Operator creates a driver DaemonSet for it.
- **`acpi_video` symbols missing on headless nodes (GardenLinux 6.18+, open modules)**: `nvidia-modeset.ko` (open kernel modules) hard-depends on `acpi_video_register_backlight` / `__acpi_video_get_backlight_type` exported by the `video` module (`CONFIG_ACPI_VIDEO=m`). On headless cloud VMs the module exists on disk but is never auto-loaded. `compile.sh` pre-loads it via `nsenter -t 1 -m -- modprobe wmi && modprobe video` before calling `nvidia-installer`. Both calls are `|| true` so kernels with `acpi_video` built-in are unaffected.
- **`usr/bin` copy in `load_install_gpu_driver.sh` is non-fatal**: `nvidia-installer` places `nvidia-smi` and other utilities in `$NVIDIA_BIN` (`/run/nvidia/driver/bin/`) via `--utility-prefix`, but only places `nvidia-modprobe` in `$NVIDIA_USR_BIN` (`/run/nvidia/driver/usr/bin/`). The `cp "${NVIDIA_USR_BIN}"/* "${NVIDIA_BIN}"` step is guarded with `2>/dev/null || true` because `usr/bin/` can be empty; without this guard the script exits under `set -e` before copying anything to `/usr/bin`, leaving the startup probe without `nvidia-smi`.

# Coding guidelines

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.