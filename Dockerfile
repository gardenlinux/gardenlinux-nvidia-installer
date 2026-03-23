# syntax=docker/dockerfile:1.4
ARG GL_VERSION

FROM ghcr.io/gardenlinux/gardenlinux:1877.13 AS packager

COPY resources/* /opt/nvidia-installer/
COPY compile.sh /tmp/compile.sh

RUN apt-get update -qq && apt-get install -qq --no-install-recommends -y \
    kmod \
    pciutils \
    ca-certificates \
    xz-utils \
    wget \
    && rm -rf /var/lib/apt/lists/*

RUN /opt/nvidia-installer/download_fabricmanager.sh

# Make this image compatible with the NVIDIA GPU Operator by using "nvidia-driver" as entrypoint
COPY nvidia-driver /usr/local/bin

ENV LD_LIBRARY_PATH=/run/nvidia/driver/lib:/run/nvidia/driver/usr/lib/x86_64-linux-gnu

ENTRYPOINT ["nvidia-driver"]
