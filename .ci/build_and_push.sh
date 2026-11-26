#!/usr/bin/env bash
# build_and_push.sh IMAGE_SUBFOLDER MAKE_TARGET IMAGE_FOLDER IMAGE_FOLDER_OLD
#
# Shared logic for the build and build-gvisor CI jobs.
# Reads GL_VERSION, DRIVER_VERSION, KERNEL_FLAVOR, TARGET_ARCH, REGISTRY,
# FOLDER_NAME, BRANCH_FOLDER, GITHUB_WORKSPACE, GITHUB_ENV from the environment.
set -euo pipefail

# Retry a docker push up to 5 times with exponential backoff.
# GHCR can return permission_denied transiently when multiple jobs race to
# push to the same package for the first time (package creation race).
docker_push_with_retry() {
  local image="$1"
  local attempt delay
  for attempt in 1 2 3 4 5; do
    if docker push "$image"; then
      return 0
    fi
    if [[ "$attempt" -eq 5 ]]; then
      echo "docker push failed after 5 attempts: $image" >&2
      return 1
    fi
    delay=$(( 2 ** attempt ))
    echo "docker push failed (attempt $attempt), retrying in ${delay}s..."
    sleep "$delay"
  done
}

IMAGE_SUBFOLDER="$1"
MAKE_TARGET="$2"
IMAGE_FOLDER="$3"
IMAGE_FOLDER_OLD="${4:-}"

IMAGE_PATH="$REGISTRY/$FOLDER_NAME$BRANCH_FOLDER$IMAGE_FOLDER/$IMAGE_SUBFOLDER"

KERNEL_NAME=$(make extract-kernel-name \
  TARGET_ARCH="$TARGET_ARCH" \
  GL_VERSION="$GL_VERSION" \
  KERNEL_FLAVOR="$KERNEL_FLAVOR")

echo "KERNEL_NAME=${KERNEL_NAME}" >> "$GITHUB_ENV"

TAG1="$DRIVER_VERSION-$KERNEL_NAME-gardenlinux0"
DRIVER_MAJOR_VERS="${DRIVER_VERSION%%.*}"
TAG2="$DRIVER_MAJOR_VERS-$KERNEL_NAME-gardenlinux0"

BUILD_IMAGE=true

if [[ -n "$IMAGE_FOLDER_OLD" ]]; then
  BUILD_IMAGE=false
  OLD_IMAGE_PATH="$REGISTRY/$FOLDER_NAME$BRANCH_FOLDER$IMAGE_FOLDER_OLD/$IMAGE_SUBFOLDER"
  if docker manifest inspect "$OLD_IMAGE_PATH:$TAG1" 2>/dev/null; then
    echo "Image $OLD_IMAGE_PATH:$TAG1 already exists, skipping build"
    docker pull "$OLD_IMAGE_PATH:$TAG1"
    docker tag "$OLD_IMAGE_PATH:$TAG1" "$IMAGE_PATH:$TAG1"
    docker tag "$OLD_IMAGE_PATH:$TAG1" "$IMAGE_PATH:$TAG2"
    docker_push_with_retry "$IMAGE_PATH:$TAG1"
    docker_push_with_retry "$IMAGE_PATH:$TAG2"
  else
    echo "Image $OLD_IMAGE_PATH:$TAG1 does not exist - triggering a build"
    BUILD_IMAGE=true
  fi
fi

if [[ "$BUILD_IMAGE" == "true" ]]; then
  make "$MAKE_TARGET" \
    WORKSPACE_DIR="$GITHUB_WORKSPACE" \
    GL_VERSION="$GL_VERSION" \
    DRIVER_VERSION="$DRIVER_VERSION" \
    NVIDIA_FS_VERSION="$NVIDIA_FS_VERSION" \
    KERNEL_FLAVOR="$KERNEL_FLAVOR" \
    TARGET_ARCH="$TARGET_ARCH" \
    IMAGE_PATH="$IMAGE_PATH"

  TAG1=$(cat "$GITHUB_WORKSPACE/tag1")
  TAG2=$(cat "$GITHUB_WORKSPACE/tag2")

  docker_push_with_retry "$IMAGE_PATH:$TAG1"
  docker_push_with_retry "$IMAGE_PATH:$TAG2"
fi
