ARG GARDENLINUX_VERSION
ARG REGISTRY_PATH=gardenlinux/kmodbuild
FROM ghcr.io/gardenlinux/${REGISTRY_PATH}:${GARDENLINUX_VERSION} AS builder

# Target NVIDIA Driver 
ARG DRIVER_VERSION

# Target architecture - WARNING: the fabric manager does currently not exist for arm64
ARG TARGET_ARCH

# Linux headers
# Set to "linux-headers" if compiling for a baremetal (non-cloud) kernel version
ARG LINUX_HEADERS=linux-headers-cloud

RUN \
    : "${TARGET_ARCH:?Build argument needs to be set and non-empty.}" \
    : "${DRIVER_VERSION:?Build argument needs to be set and non-empty.}" 
    
ENV LINUX_HEADERS=${LINUX_HEADERS}-$TARGET_ARCH

# TODO: verify if we (still) need to support 32bit compat
#RUN dpkg --add-architecture i386

COPY resources/extract_kernel_version.sh .
COPY resources/compile.sh .

RUN export KERNEL_VERSION=$(./extract_kernel_version.sh ${LINUX_HEADERS}) && ./compile.sh

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

RUN apt-get remove -y --autoremove --allow-remove-essential --ignore-hold \
      libgnutls30 apt openssl wget ncurses-base ncurses-bin
RUN rm -rf /var/lib/apt/lists/* /usr/bin/dpkg /sbin/start-stop-daemon /usr/lib/x86_64-linux-gnu/libsystemd.so* \
         /var/lib/dpkg/info/libdb5.3* /usr/lib/x86_64-linux-gnu/libdb-5.3.so* /usr/share/doc/libdb5.3 \
         /usr/bin/chfn /usr/bin/gpasswd

FROM scratch

COPY --from=packager / /

ENTRYPOINT ["/opt/nvidia-installer/load_install_gpu_driver.sh"]
