# TODO: We need to publish garden linux container with tags for supported versions.
#       new releases will have these tags, but still need to backport them.
# However, working with nightly should be fine as long as we setup the apt repository to the correct Garden Linux version
FROM ghcr.io/gardenlinux/gardenlinux:nightly AS builder

# Target NVIDIA Driver 
ARG DRIVER_VERSION
# This version is used to get the matching apt repository.
# The apt repository contains the packages required to build nvidia for the targeted GL
ARG GARDENLINUX_VERSION
# Target architecture. 
# WARNING: the fabric manager does currently not exist for arm64
ARG TARGET_ARCH
# Linux headers
# Set to "linux-headers" if compiling for a baremetal (non-cloud) kernel version
ARG LINUX_HEADERS=linux-headers-cloud

RUN \
    : "${TARGET_ARCH:?Build argument needs to be set and non-empty.}" \
    : "${DRIVER_VERSION:?Build argument needs to be set and non-empty.}" \
    : "${GARDENLINUX_VERSION:?Build argument needs to be set and non-empty.}"

ENV LINUX_HEADERS=${LINUX_HEADERS}-$TARGET_ARCH

# TODO: verify if we (still) need to support 32bit compat
#RUN dpkg --add-architecture i386

COPY gardenlinux-dev .
COPY resources/compile.sh resources/compile.sh


COPY gardenlinux-dev/gardenlinux.pref gardenlinux.pref
# Set the appropriate apt priorities.
RUN sed "s/__GARDENLINUX_VERSION__/${GARDENLINUX_VERSION}/g" gardenlinux.pref >  gardenlinux.pref.versioned && \
    sed "s/__TARGET_ARCH__/${TARGET_ARCH}/g" gardenlinux.pref.versioned > /etc/apt/preferences.d/gardenlinux && \
    echo "deb http://repo.gardenlinux.io/gardenlinux ${GARDENLINUX_VERSION} main" > /etc/apt/sources.list && \
    echo "deb http://repo.gardenlinux.io/gardenlinux today main" >> /etc/apt/sources.list && \
    echo "deb http://deb.debian.org/debian trixie main" >> /etc/apt/sources.list && \
    apt -o Acquire::AllowInsecureRepositories=true update && apt policy

RUN apt-get -o Acquire::AllowInsecureRepositories=true update && \
    apt-get install --allow-unauthenticated -y \
        kmod \
        $LINUX_HEADERS \
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

# RUN export $(./read_image_versions.sh | xargs) && ./install_debian_packages.sh
# RUN export $(./read_image_versions.sh | xargs) && ./install_gardenlinux_packages.sh

RUN export KERNEL_VERSION=$(./extract_kernel_version.sh ${LINUX_HEADERS}) && resources/compile.sh

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
