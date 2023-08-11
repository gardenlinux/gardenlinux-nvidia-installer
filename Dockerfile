# TODO: We need to publish garden linux container with tags for supported versions.
#       new releases will have these tags, but still need to backport them.
# However, working with nightly should be fine as long as we setup the apt repository to the correct Garden Linux version
FROM ghcr.io/gardenlinux/gardenlinux:nightly

# TODO: verify if we (still) need to support 32bit compat
#RUN dpkg --add-architecture i386

COPY gardenlinux-dev .
COPY resources/compile.sh resources/compile.sh

# This version is used to get the matching apt repository.
# The apt repository contains the packages required to build nvidia for the targeted GL
ARG GARDENLINUX_VERSION
ARG TARGET_ARCH

COPY gardenlinux-dev/gardenlinux.pref gardenlinux.pref
# Set the appropriate apt priorities.
RUN sed "s/__GARDENLINUX_VERSION__/${GARDENLINUX_VERSION}/g" gardenlinux.pref >  gardenlinux.pref.versioned && \
    sed "s/__TARGET_ARCH__/${TARGET_ARCH}/g" gardenlinux.pref.versioned > /etc/apt/preferences.d/gardenlinux && \
    echo "deb http://repo.gardenlinux.io/gardenlinux ${GARDENLINUX_VERSION} main" > /etc/apt/sources.list && \
    echo "deb http://repo.gardenlinux.io/gardenlinux today main" >> /etc/apt/sources.list && \
    echo "deb http://deb.debian.org/debian trixie main" >> /etc/apt/sources.list && \
    apt update && apt policy


RUN chmod a+w /tmp

# Install nvidia kernel module build dependencies
# NOTE: GCC, kernel header and kernel tools must match the versions used in the targeted Garden Linux version.
# Install Kernel Headers
RUN sudo apt-get update && \
    sudo apt-get install -y \
        kmod \
        linux-headers-cloud-$TARGET_ARCH \
        curl \
        devscripts \
        git \
        pristine-lfs \
        libncursesw6 libncurses6 libncurses-dev \
        rsync \
        ca-certificates \
        sudo \
        quilt \
        dwarves \
        kernel-wedge \
        python3-debian \
        python3-jinja2 \
        build-essential

ARG DRIVER_VERSION

RUN export KERNEL_VERSION=$(./extract_kernel_version.sh) && resources/compile.sh

#FROM public.int.repositories.cloud.sap/debian:11.2-slim

RUN apt-get update && apt-get install --no-install-recommends -y \
    kmod \
    pciutils \
    ca-certificates \
    wget \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# COPY --from=builder /out /out
COPY resources/* /opt/nvidia-installer/

ARG DRIVER_VERSION
RUN /opt/nvidia-installer/download_fabricmanager.sh

ENTRYPOINT ["/opt/nvidia-installer/load_install_gpu_driver.sh"]
