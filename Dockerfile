# syntax=docker/dockerfile:1.4
ARG GL_VERSION

FROM ghcr.io/gardenlinux/gardenlinux:${GL_VERSION} AS packager
ARG TARGET_ARCH
ARG DRIVER_VERSION
ARG KERNEL_NAME

COPY resources/* /opt/nvidia-installer/

RUN apt-get update -qq && apt-get install -qq --no-install-recommends -y \
    kmod \
    pciutils \
    ca-certificates \
    xz-utils \
    wget \
    && rm -rf /var/lib/apt/lists/*

RUN /opt/nvidia-installer/download_fabricmanager.sh

# Remove several things that are not needed, some of which raise Black Duck scan vulnerabilities
RUN apt-get remove -y --autoremove --allow-remove-essential --ignore-hold \
      libgnutls30 apt openssl ncurses-base ncurses-bin

RUN rm -rf /var/lib/apt/lists/* /usr/bin/dpkg /sbin/start-stop-daemon /usr/lib/x86_64-linux-gnu/libsystemd.so* \
         /var/lib/dpkg/info/libdb5.3* /usr/lib/x86_64-linux-gnu/libdb-5.3.so* /usr/share/doc/libdb5.3 \
         /usr/bin/chfn /usr/bin/gpasswd

RUN echo "${DRIVER_VERSION}" > /tmp/driver-version
RUN echo "${KERNEL_NAME}" > /tmp/kernel-name

# Embed both open and proprietary pre-compiled driver tarballs into the image.
# The correct one is selected at runtime by load_install_gpu_driver.sh based on
# the GPU architecture and driver version (via KERNEL_MODULE_TYPE / auto-detection).
COPY out/nvidia/driver-${DRIVER_VERSION}-open-${KERNEL_NAME}.tar.gz /opt/nvidia-installer/drivers/
COPY out/nvidia/driver-${DRIVER_VERSION}-proprietary-${KERNEL_NAME}.tar.gz /opt/nvidia-installer/drivers/

RUN mkdir -p /rootfs \
        && cp -ar /bin /boot /etc /home /lib /lib64 /media /mnt /opt /root /run /sbin /srv /tmp /usr /var /rootfs \
        && rm -rf /rootfs/opt/actions-runner

# Clear the library cache so that Whitesource doesn't complain about libdb
RUN rm /etc/ld.so.cache ; ldconfig

FROM scratch

COPY --from=packager /rootfs /

# Make this image compatible with the NVIDIA GPU Operator by using "nvidia-driver" as entrypoint
COPY nvidia-driver /usr/local/bin

ENV LD_LIBRARY_PATH=/run/nvidia/driver/lib:/run/nvidia/driver/usr/lib/x86_64-linux-gnu

ENTRYPOINT ["nvidia-driver"]
s