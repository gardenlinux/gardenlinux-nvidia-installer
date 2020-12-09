
FROM docker.wdf.sap.corp:50003/debian:10.6-slim as builder

RUN apt-get update && apt-get install --no-install-recommends -y \
    wget \
    ca-certificates 

ARG MINIO_CLIENT="mc.RELEASE.2020-11-25T23-04-07Z"
RUN wget https://dl.min.io/client/mc/release/linux-amd64/$MINIO_CLIENT
RUN mv mc.RELEASE.2020-11-25T23-04-07Z mc
RUN chmod +x mc


FROM docker.wdf.sap.corp:50000/debian:10.6-slim

RUN apt-get update && apt-get install --no-install-recommends -y \
    kmod \
    pciutils \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /mc /usr/local/bin/mc

COPY resources/load_install_gpu_driver.sh /opt/modulus/load_install_gpu_driver
COPY resources/compile.sh /opt/modulus/nvidia/compile
COPY resources/install.sh /opt/modulus/nvidia/install
ENTRYPOINT ["/opt/modulus/load_install_gpu_driver"]
