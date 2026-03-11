.PHONY: extract-kernel-name build-driver build-image build
WORKSPACE_DIR ?= $(shell pwd)
KERNEL_FLAVOR ?= cloud
TARGET_ARCH ?= amd64
DOCKER_CONTEXT ?= $(shell pwd)
IMAGE_PATH ?= ghcr.io/gardenlinux/gardenlinux-nvidia-installer/driver
DRIVER_MAJOR_VERS = $(firstword $(subst ., ,$(DRIVER_VERSION)))
build: build-driver build-image

ifndef GL_VERSION
$(error GL_VERSION is not set. Please set it before running make.)
endif

ifndef DRIVER_VERSION
$(error DRIVER_VERSION is not set. Please set it before running make.)
endif

extract-kernel-name:
	$(eval KERNEL_NAME := $(shell docker run --rm \
           -v "$(PWD):/workspace" \
           -w /workspace \
           ghcr.io/gardenlinux/gardenlinux/kmodbuild:$(TARGET_ARCH)-$(GL_VERSION) \
           ./resources/extract_kernel_name.sh "$(KERNEL_FLAVOR)"))

# build-driver compiles both open and proprietary kernel module tarballs.
# KERNEL_TYPE is required by compile.sh and must be supplied per-invocation.
# The 'build' target invokes build-driver twice (once per type); in CI the
# matrix already supplies KERNEL_TYPE so build-driver can be called directly.
build-driver: extract-kernel-name
ifndef KERNEL_TYPE
	$(error KERNEL_TYPE is not set. Please set it to open or proprietary before running make.)
endif
	mkdir -p $(WORKSPACE_DIR)/out ;\
    if [ ! -f $(WORKSPACE_DIR)/out/nvidia/driver-$(DRIVER_VERSION)-$(KERNEL_TYPE)-$(KERNEL_NAME).tar.gz ]; then \
		docker run --rm \
			   -v $(WORKSPACE_DIR):/workspace \
			   -v $(WORKSPACE_DIR)/out:/out \
		   --platform=linux/${TARGET_ARCH} \
			   -w /workspace \
			   --env TARGET_ARCH=$(TARGET_ARCH) \
			   --env GL_VERSION=$(GL_VERSION) \
			   --env DRIVER_VERSION=$(DRIVER_VERSION) \
			   --env KERNEL_NAME=$(KERNEL_NAME) \
			   --env KERNEL_TYPE=$(KERNEL_TYPE) \
			   ghcr.io/gardenlinux/gardenlinux/kmodbuild:${TARGET_ARCH}-${GL_VERSION} \
			   bash ./resources/compile.sh ;\
	fi

# build-image produces a single image per (GL_VERSION, DRIVER_VERSION).
# No KERNEL_NAME or KERNEL_TYPE is needed — the correct tarball is downloaded
# at container runtime based on uname -r and KERNEL_MODULE_TYPE.
build-image:
	$(eval TAG1 := "$(DRIVER_MAJOR_VERS)-$(TARGET_ARCH)-gardenlinux$(GL_VERSION)")
	$(eval TAG2 := "$(DRIVER_MAJOR_VERS)-gardenlinux0")
	$(eval TAG3 := "$(DRIVER_VERSION)-gardenlinux0")
	@DOCKER_BUILDKIT=1 docker build \
           --build-arg GL_VERSION=$(GL_VERSION) \
           --build-arg DRIVER_VERSION=$(DRIVER_VERSION) \
           --build-arg TARGET_ARCH=$(TARGET_ARCH) \
           --platform=linux/${TARGET_ARCH} \
           -t $(IMAGE_PATH):$(TAG1) \
           -t $(IMAGE_PATH):$(TAG2) \
           -t $(IMAGE_PATH):$(TAG3) \
           -f Dockerfile $(DOCKER_CONTEXT) > /dev/null
	@echo $(TAG1)
	@echo $(TAG2)
	@echo $(TAG3)
    
clean:
	rm -rf $(WORKSPACE_DIR)/out/nvidia/driver-$(DRIVER_VERSION)-open-*.tar.gz
	rm -rf $(WORKSPACE_DIR)/out/nvidia/driver-$(DRIVER_VERSION)-proprietary-*.tar.gz

clean-all:
	rm -rf $(WORKSPACE_DIR)/out/
