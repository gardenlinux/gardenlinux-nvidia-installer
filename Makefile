.PHONY: extract-kernel-name build-driver build-image build
WORKSPACE_DIR ?= $(shell pwd)
KERNEL_FLAVOR ?= cloud
TARGET_ARCH ?= amd64
IMAGE_PATH ?= ghcr.io/gardenlinux/gardenlinux-nvidia-installer/driver
DRIVER_MAJOR_VERS = $(firstword $(subst ., ,$(DRIVER_VERSION)))
build: build-driver build-image

ifndef GL_VERSION
$(error GL_VERSION is not set. Please set it before running make.)
endif

ifndef DRIVER_VERSION
$(error DRIVER_VERSION is not set. Please set it before running make.)
endif

# If KERNEL_NAME is already set (e.g. passed by CI after a separate extract step),
# extract-kernel-name is a no-op. Otherwise it runs the kmodbuild container to determine it.
extract-kernel-name:
ifeq ($(KERNEL_NAME),)
	$(eval KERNEL_NAME := $(shell docker run --rm \
           -v "$(PWD):/workspace" \
           -w /workspace \
           ghcr.io/gardenlinux/gardenlinux/kmodbuild:$(TARGET_ARCH)-$(GL_VERSION) \
           ./resources/extract_kernel_name.sh "$(KERNEL_FLAVOR)"))
endif

# build-driver compiles both open and proprietary kernel module tarballs in a
# single kmodbuild container invocation via compile.sh.
build-driver: extract-kernel-name
	mkdir -p $(WORKSPACE_DIR)/out ;\
    if [ ! -f $(WORKSPACE_DIR)/out/nvidia/driver-$(DRIVER_VERSION)-open-$(KERNEL_NAME).tar.gz ] || \
       [ ! -f $(WORKSPACE_DIR)/out/nvidia/driver-$(DRIVER_VERSION)-proprietary-$(KERNEL_NAME).tar.gz ]; then \
		docker run --rm \
			   -v $(WORKSPACE_DIR):/workspace \
			   -v $(WORKSPACE_DIR)/out:/out \
		   --platform=linux/${TARGET_ARCH} \
			   -w /workspace \
			   --env TARGET_ARCH=$(TARGET_ARCH) \
			   --env GL_VERSION=$(GL_VERSION) \
			   --env DRIVER_VERSION=$(DRIVER_VERSION) \
			   --env KERNEL_NAME=$(KERNEL_NAME) \
			   ghcr.io/gardenlinux/gardenlinux/kmodbuild:${TARGET_ARCH}-${GL_VERSION} \
			   bash ./resources/compile.sh ;\
	fi

# build-image compiles both open and proprietary tarballs then builds the container image.
# Both tarballs are embedded in the image so that the correct one can be selected at runtime.
# KERNEL_NAME already contains flavour and arch (e.g. 6.12.72-cloud-amd64), so tags do not
# append KERNEL_FLAVOR or TARGET_ARCH separately.
build-image: extract-kernel-name
	$(eval TAG1 := "$(DRIVER_MAJOR_VERS)-$(KERNEL_NAME)-gardenlinux0")
	$(eval TAG2 := "$(DRIVER_VERSION)-$(KERNEL_NAME)-gardenlinux0")
	@DOCKER_BUILDKIT=1 docker build \
           --build-arg GL_VERSION=$(GL_VERSION) \
           --build-arg DRIVER_VERSION=$(DRIVER_VERSION) \
           --build-arg KERNEL_NAME=$(KERNEL_NAME) \
           --build-arg TARGET_ARCH=$(TARGET_ARCH) \
           --platform=linux/${TARGET_ARCH} \
           -t $(IMAGE_PATH):$(TAG1) \
           -t $(IMAGE_PATH):$(TAG2) \
           -f Dockerfile $(WORKSPACE_DIR)
	@echo $(TAG1) > $(WORKSPACE_DIR)/tag1
	@echo $(TAG2) > $(WORKSPACE_DIR)/tag2

clean:
	rm -rf $(WORKSPACE_DIR)/out/nvidia/driver-$(DRIVER_VERSION)-open-*.tar.gz
	rm -rf $(WORKSPACE_DIR)/out/nvidia/driver-$(DRIVER_VERSION)-proprietary-*.tar.gz

clean-all:
	rm -rf $(WORKSPACE_DIR)/out/
