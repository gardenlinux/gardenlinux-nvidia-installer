.PHONY: extract-kernel-name build-driver build-image build
WORKSPACE_DIR ?= $(shell pwd)
TARGET_ARCH ?= amd64
IMAGE_PATH ?= ghcr.io/gardenlinux/gardenlinux-nvidia-installer/driver
DRIVER_MAJOR_VERS = $(firstword $(subst ., ,$(DRIVER_VERSION)))
build: build-image

echo $(DRIVER_VERSION)


ifndef DRIVER_VERSION
$(error DRIVER_VERSION is not set. Please set it before running make.)
endif

# build-image compiles both open and proprietary tarballs then builds the container image.
# Both tarballs are embedded in the image so that the correct one can be selected at runtime.
# KERNEL_NAME already contains flavour and arch (e.g. 6.12.72-cloud-amd64), so tags do not
# append KERNEL_FLAVOR or TARGET_ARCH separately.
build-image:
	$(eval TAG1 := "$(DRIVER_MAJOR_VERS)-gardenlinux0")
	$(eval TAG2 := "$(DRIVER_VERSION)-gardenlinux0")
	@DOCKER_BUILDKIT=1 docker build \
           --build-arg DRIVER_VERSION=$(DRIVER_VERSION) \
           --build-arg TARGET_ARCH=$(TARGET_ARCH) \
           --platform=linux/${TARGET_ARCH} \
           -t $(IMAGE_PATH):$(TAG1) \
           -t $(IMAGE_PATH):$(TAG2) \
           -f Dockerfile $(WORKSPACE_DIR)
	@echo $(TAG1) > $(WORKSPACE_DIR)/tag1
	@echo $(TAG2) > $(WORKSPACE_DIR)/tag2
