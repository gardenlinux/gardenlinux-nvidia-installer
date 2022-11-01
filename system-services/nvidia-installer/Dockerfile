# Do not edit DEBIAN_BASE_IMAGE_TAG - master value is in component.yaml context section.
ARG DEBIAN_BASE_IMAGE_TAG=bullseye-20200224-slim
FROM debian:$DEBIAN_BASE_IMAGE_TAG as builder

RUN dpkg --add-architecture i386

# This URL is a link to the publicly-readable OpenStack Swift container "gardenlinux-packages" in the
# Converged Cloud project https://dashboard.eu-de-1.cloud.sap/hcp03/sapclea/home
# This container is NOT an official gardenlinux one but a mirror maintained by aicore.
# The content can be updated following the documentation in ./README.md
ARG GARDENLINUX_PACKAGES_URL="https://objectstore-3.eu-de-1.cloud.sap:443/v1/AUTH_535c582484f44532aa5e21b2bb5cb471/gardenlinux-packages"

COPY gardenlinux-dev .
COPY resources resources

# Make sure GARDENLINUX_VERSION is set, then download & install the required deb files
ARG GARDENLINUX_VERSION
RUN chmod a+w /tmp
RUN ./install_packages.sh $GARDENLINUX_VERSION

# Make sure DRIVER_VERSION & KERNEL_VERSION are set, then compile the kernel modules
ARG DRIVER_VERSION
RUN export $(./read_image_versions.sh | grep KERNEL_VERSION) && resources/compile.sh


FROM public.int.repositories.cloud.sap/debian:11.1-slim

RUN apt-get update && apt-get install --no-install-recommends -y \
    kmod \
    pciutils \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /out /out

COPY resources/load_install_gpu_driver.sh /opt/modulus/load_install_gpu_driver
COPY resources/install.sh /opt/modulus/nvidia/install.sh
ENTRYPOINT ["/opt/modulus/load_install_gpu_driver"]
