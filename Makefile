.PHONY: extract-kernel-name build-driver build-image build
WORKSPACE_DIR ?= $(shell pwd)
KERNEL_TYPE ?= cloud
TARGET_ARCH ?= amd64
DOCKER_CONTEXT ?= $(shell pwd)
DRIVER_MAJOR_VERS = $(firstword $(subst ., ,$(DRIVER_VERSION)))
build: build-driver build-image

extract-kernel-name:
	$(eval KERNEL_NAME := $(shell docker run --rm \
           -v "$(PWD):/workspace" \
           -w /workspace \
           -e KERNEL_TYPE="$(KERNEL_TYPE)" \
           ghcr.io/gardenlinux/gardenlinux/kmodbuild:$(TARGET_ARCH)-$(GL_VERSION) \
           ./resources/extract_kernel_name.sh "$KERNEL_TYPE"))

build-driver: extract-kernel-name
	mkdir $(WORKSPACE_DIR)/out
	docker run --rm \
           -v $(WORKSPACE_DIR):/workspace \
           -v $(WORKSPACE_DIR)/out:/out \
           -w /workspace \
           --env TARGET_ARCH=$(TARGET_ARCH) \
           --env GL_VERSION=$(GL_VERSION) \
	   --env DRIVER_VERSION=$(DRIVER_VERSION) \
           --env KERNEL_NAME=$(KERNEL_NAME) \
           ghcr.io/gardenlinux/gardenlinux/kmodbuild:${TARGET_ARCH}-${GL_VERSION} \
           bash ./resources/compile.sh

build-image: extract-kernel-name
	$(eval TAG1 := "$(DRIVER_MAJOR_VERS)-$(KERNEL_NAME)-gardenlinux$(GL_VERSION)")
	$(eval TAG2 := "$(DRIVER_MAJOR_VERS)-$(KERNEL_NAME)-gardenlinux0")
	@docker build \
           --build-arg DRIVER_VERSION=$(DRIVER_VERSION) \
           --build-arg TARGET_ARCH=$(TARGET_ARCH) \
	   -t $(IMAGE_PATH):$(TAG1) \
	   -t $(IMAGE_PATH):$(TAG2) \
           -f Dockerfile $(DOCKER_CONTEXT) > /dev/null
	@echo $(TAG1)
	@echo $(TAG2)
    


