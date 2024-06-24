# syntax=docker/dockerfile:1
ARG GARDENLINUX_VERSION
ARG REGISTRY_PATH=gardenlinux/kmodbuild
FROM ghcr.io/gardenlinux/${REGISTRY_PATH}:${GARDENLINUX_VERSION} AS builder

# Target NVIDIA Driver 
ARG DRIVER_VERSION

# Target architecture - WARNING: the fabric manager does currently not exist for arm64
ARG TARGET_ARCH

# kernel type = set to "cloud" for a cloud kernel (default), or empty value for a bare-metal kernel
# Set to "linux-headers" if compiling for a baremetal (non-cloud) kernel version
ARG KERNEL_TYPE=cloud

RUN \
    : "${TARGET_ARCH:?Build argument needs to be set and non-empty.}" \
    : "${DRIVER_VERSION:?Build argument needs to be set and non-empty.}" 
    
COPY resources/extract_kernel_name.sh .
COPY resources/compile.sh .

RUN export KERNEL_NAME=$(./extract_kernel_name.sh ${KERNEL_TYPE} ${TARGET_ARCH}) && ./compile.sh

FROM debian:bookworm-slim AS packager
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

RUN /opt/nvidia-installer/download_fabricmanager.sh

# Remove several things that are not needed, some of which raise Black Duck scan vulnerabilities
RUN apt-get remove -y --autoremove --allow-remove-essential --ignore-hold \
      libgnutls30 apt openssl wget ncurses-base ncurses-bin

RUN rm -rf /var/lib/apt/lists/* /usr/bin/dpkg /sbin/start-stop-daemon /usr/lib/x86_64-linux-gnu/libsystemd.so* \
         /var/lib/dpkg/info/libdb5.3* /usr/lib/x86_64-linux-gnu/libdb-5.3.so* /usr/share/doc/libdb5.3 \
         /usr/bin/chfn /usr/bin/gpasswd

RUN mkdir -p /rootfs \
        && cp -ar /bin /boot /etc /home /lib /lib64 /media /mnt /opt /out /root /run /sbin /srv /tmp /usr /var /rootfs \
        && rm -rf /rootfs/opt/actions-runner

FROM scratch

COPY --from=packager /rootfs /

ENTRYPOINT ["/opt/nvidia-installer/load_install_gpu_driver.sh"]
