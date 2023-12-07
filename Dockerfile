ARG GARDENLINUX_VERSION
FROM ghcr.io/gardenlinux/driver-build:${GARDENLINUX_VERSION} AS builder

# Target NVIDIA Driver 
ARG DRIVER_VERSION

# TODO: check if the fabric manager exists for arm64
ARG TARGET_ARCH
# Linux headers
# Set to "linux-headers" if compiling for a baremetal (non-cloud) kernel version
ARG LINUX_HEADERS=linux-headers-cloud

RUN \
    : "${TARGET_ARCH:?Build argument needs to be set and non-empty.}" \
    : "${DRIVER_VERSION:?Build argument needs to be set and non-empty.}" \
    : "${GARDENLINUX_VERSION:?Build argument needs to be set and non-empty.}"

COPY gardenlinux-dev .
COPY resources/compile.sh resources/compile.sh

RUN export KERNEL_VERSION=$(./extract_kernel_version.sh ${TARGET_ARCH}) && resources/compile.sh

# FROM public.int.repositories.cloud.sap/debian:11.2-slim
FROM debian:bookworm-slim as packager
ARG TARGET_ARCH
ARG DRIVER_VERSION

COPY --from=builder /out /out
COPY resources/* /opt/nvidia-installer/

RUN apt-get update && apt-get install --no-install-recommends -y \
    kmod \
    pciutils \
    ca-certificates \
    wget \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

ARG DRIVER_VERSION
RUN /opt/nvidia-installer/download_fabricmanager.sh

FROM scratch

COPY --from=packager / /

ENTRYPOINT ["/opt/nvidia-installer/load_install_gpu_driver.sh"]
