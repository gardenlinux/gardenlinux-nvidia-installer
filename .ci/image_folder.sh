#!/usr/bin/env bash
# Resolves IMAGE_FOLDER and IMAGE_FOLDER_OLD for the build_image CI job.
# Sourced by CI steps and bats tests — not executed directly.
#
# Required env:
#   GH_REPO          github.repository (e.g. "gardenlinux/gardenlinux-nvidia-installer")
#   GH_TOKEN         for gh cli
#   GITHUB_OUTPUT    path to GHA output file; defaults to /dev/null when unset
set -euo pipefail

# get_tag_from_release_update_branch
# Prints the version tag from the latest release-update/* branch, or empty if none exists.
get_tag_from_release_update_branch() {
    git ls-remote --heads origin 'release-update*' | head -n 1 | cut -f2 | cut -d/ -f4
}

# get_latest_release_tag
# Queries GitHub releases and prints the latest X.Y.Z tag, or empty if none exists.
get_latest_release_tag() {
    gh release list --repo "$GH_REPO" --json tagName \
        --jq '[.[] | select(.tagName | test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))] | first | .tagName // empty'
}

# resolve_image_folders TAG OLD_TAG
# Prints IMAGE_FOLDER and IMAGE_FOLDER_OLD as KEY=VALUE lines.
# IMAGE_FOLDER_OLD is only set for patch releases (same MAJOR.MINOR); empty otherwise.
resolve_image_folders() {
    local tag="$1"
    local old_tag="$2"
    local major minor old_major old_minor image_folder image_folder_old

    major=$(echo "$tag" | cut -d. -f1)
    minor=$(echo "$tag" | cut -d. -f2)
    old_major=$(echo "$old_tag" | cut -d. -f1)
    old_minor=$(echo "$old_tag" | cut -d. -f2)

    image_folder=$(echo "/${tag}" | tr '[:upper:]' '[:lower:]')

    if [[ "$major" == "$old_major" && "$minor" == "$old_minor" ]]; then
        image_folder_old=$(echo "/${old_tag}" | tr '[:upper:]' '[:lower:]')
    else
        image_folder_old=""
    fi

    echo "image_folder=${image_folder}"
    echo "image_folder_old=${image_folder_old}"
}

# main
# Orchestrates the above and writes outputs to ${GITHUB_OUTPUT:-/dev/null}.
main() {
    local tag old_tag
    tag=$(get_tag_from_release_update_branch)
    old_tag=$(get_latest_release_tag)

    local image_folder image_folder_old
    while IFS='=' read -r key value; do
        case "$key" in
            image_folder)     image_folder="$value" ;;
            image_folder_old) image_folder_old="$value" ;;
        esac
    done < <(resolve_image_folders "$tag" "$old_tag")

    echo "image_folder_old: ${image_folder_old}"
    echo "image_folder: ${image_folder}"

    echo "image_folder_old=${image_folder_old}" >> "${GITHUB_OUTPUT:-/dev/null}"
    echo "image_folder=${image_folder}" >> "${GITHUB_OUTPUT:-/dev/null}"
}
