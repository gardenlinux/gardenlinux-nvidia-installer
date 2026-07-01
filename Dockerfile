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

# infiniband-diags (provides ibstat) is required by nvidia-fabricmanager-start.sh
# on Blackwell (B200) hosts to detect NVL5+ NVLink topology. It is not present in
# the Garden Linux 2150 main repo, so we pull it from Debian unstable, pinned to
# only the ibstat package set (Garden Linux is Debian-sid based, so ABI matches).
# debian-archive-keyring is installed first so apt can verify the sid Release
# signature. signed-by= scopes the trusted key to this source line only.
# All four packages (incl. transitive deps) are pinned to exact versions so
# rebuilds are deterministic: infiniband-diags=63.0-1 pulls
# libibnetdisc5t64=63.0-1, libibmad5=63.0-1, libibumad3=63.0-1.
RUN apt-get install -qq --no-install-recommends -y debian-archive-keyring \
    && echo "deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian unstable main" \
        > /etc/apt/sources.list.d/debian-unstable.list \
    && apt-get update -qq \
    && apt-get install -qq --no-install-recommends -y \
        infiniband-diags\
        libibnetdisc5t64 \
        libibmad5 \
        libibumad3 \
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
