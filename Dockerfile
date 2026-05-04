# syntax=docker/dockerfile:1.4

FROM ghcr.io/gardenlinux/gardenlinux:latest AS packager
ARG DRIVER_VERSION

COPY resources/* /opt/nvidia-installer/

RUN apt-get update -qq && apt-get install -qq --no-install-recommends -y \
    kmod \
    pciutils \
    ca-certificates \
    xz-utils \
    wget \
    && rm -rf /var/lib/apt/lists/*

RUN echo "${DRIVER_VERSION}" > /tmp/driver-version

RUN /opt/nvidia-installer/download_fabricmanager.sh

# Make this image compatible with the NVIDIA GPU Operator by using "nvidia-driver" as entrypoint
COPY nvidia-driver /usr/local/bin

ENV LD_LIBRARY_PATH=/run/nvidia/driver/lib:/run/nvidia/driver/usr/lib/x86_64-linux-gnu

ENTRYPOINT ["nvidia-driver"]
