# Do not edit FROM line - it is created from a component.yaml patch rule
FROM docker.wdf.sap.corp:51022/com.sap.ai/gardenlinux-dev:318.8.0-sap5 AS builder
# TODO: update Gardenlinux version & fold into main build
COPY resources/compile.sh /tmp/compile

ARG DRIVER_VERSION

# Do not edit KERNEL_VERSION - master value is in gardenlinux-dev/component.yaml context section.
ARG KERNEL_VERSION=5.4.0-6-cloud-amd64

RUN /tmp/compile


FROM docker.wdf.sap.corp:50000/debian:11.1-slim

RUN apt-get update && apt-get install --no-install-recommends -y \
    kmod \
    pciutils \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /out /out

COPY resources/load_install_gpu_driver.sh /opt/modulus/load_install_gpu_driver
COPY resources/install.sh /opt/modulus/nvidia/install.sh
ENTRYPOINT ["/opt/modulus/load_install_gpu_driver"]
