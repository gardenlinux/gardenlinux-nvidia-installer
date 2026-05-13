# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repo builds and packages NVIDIA GPU drivers for Garden Linux, enabling GPU support in Kubernetes clusters via the [NVIDIA GPU Operator](https://github.com/NVIDIA/gpu-operator). Drivers are compiled at build time inside Garden Linux developer containers and packaged into production images that the GPU Operator installs at runtime.

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
The container entrypoint `nvidia-driver` script (executed by GPU Operator):
1. Checks for already-loaded kernel modules
2. Extracts driver archive to `/run/nvidia/driver`
3. Configures library loader via `resources/install.sh`
4. Optionally installs Fabric Manager (`resources/download_fabricmanager.sh`)
5. Verifies installation with `nvidia-smi`

### Version Management
- `versions.yaml` — declarative matrix of supported GL versions × architectures × kernel flavors/types × NVIDIA driver versions
- `history.yaml` — all historical driver/kernel combinations ever built
- `.ci/generate_matrix.py` — expands `versions.yaml` into a GitHub Actions build matrix
- `.ci/update_versions.py` — daily cron job scrapes GitHub/NVIDIA for new minor/patch releases and opens a PR

**Support policy:** Two most recent NVIDIA major driver versions; latest two Garden Linux major versions with all minor versions.

### Key Scripts

| Script | Purpose |
|--------|---------|
| `resources/compile.sh` | Downloads NVIDIA driver, compiles modules, archives output |
| `resources/extract_kernel_name.sh` | Detects kernel name from kmodbuild container |
| `resources/load_install_gpu_driver.sh` | Runtime installer executed by GPU Operator |
| `resources/set_env_vars.sh` | Sets environment variables for container runtime |
| `resources/download_fabricmanager.sh` | Downloads optional Fabric Manager |
| `nvidia-driver` | Container entrypoint (GPU Operator compatibility) |

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