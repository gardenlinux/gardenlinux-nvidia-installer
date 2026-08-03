#!/usr/bin/env bats
#
# Tests for functions in .ci/image_folder.sh
#
# Run from repo root: test/bats/bin/bats test/bats/test_image_folder.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/.ci/image_folder.sh"

load "${REPO_ROOT}/test/test_helper/bats-support/load"
load "${REPO_ROOT}/test/test_helper/bats-assert/load"

setup() {
    git() { echo ""; }
    gh() { echo ""; }
    GH_REPO="test/repo"
    # shellcheck disable=SC1090
    . "${SCRIPT}"
}

# ---------------------------------------------------------------------------
# resolve_image_folders
# ---------------------------------------------------------------------------

@test "resolve_image_folders: same MAJOR.MINOR sets IMAGE_FOLDER_OLD" {
    run resolve_image_folders "1.5.1" "1.5.0"
    assert_success
    assert_output --partial "image_folder_old=/1.5.0"
    assert_output --partial "image_folder=/1.5.1"
}

@test "resolve_image_folders: different MINOR clears IMAGE_FOLDER_OLD" {
    run resolve_image_folders "1.6.0" "1.5.9"
    assert_success
    assert_output --partial "image_folder_old="
    assert_output --partial "image_folder=/1.6.0"
    # Confirm image_folder_old is truly empty (not set to the old path)
    refute_output --partial "image_folder_old=/1.5"
}

@test "resolve_image_folders: different MAJOR clears IMAGE_FOLDER_OLD" {
    run resolve_image_folders "2.0.0" "1.9.3"
    assert_success
    refute_output --partial "image_folder_old=/1"
    assert_output --partial "image_folder=/2.0.0"
}

@test "resolve_image_folders: tag is lowercased in IMAGE_FOLDER" {
    run resolve_image_folders "1.5.0-RC1" "1.4.9"
    assert_success
    assert_output --partial "image_folder=/1.5.0-rc1"
    refute_output --partial "image_folder=/1.5.0-RC1"
}

@test "resolve_image_folders: same tag (exact rebuild) sets IMAGE_FOLDER_OLD" {
    run resolve_image_folders "1.5.0" "1.5.0"
    assert_success
    assert_output --partial "image_folder_old=/1.5.0"
    assert_output --partial "image_folder=/1.5.0"
}

# ---------------------------------------------------------------------------
# get_tag_from_release_update_branch
# ---------------------------------------------------------------------------

@test "get_tag_from_release_update_branch: extracts version from branch ref" {
    git() {
        echo "abc123	refs/heads/release-update/1.6.0"
    }
    run get_tag_from_release_update_branch
    assert_success
    assert_output "1.6.0"
}

@test "get_tag_from_release_update_branch: uses only first line when multiple branches" {
    git() {
        printf "abc123\trefs/heads/release-update/1.6.0\n"
        printf "def456\trefs/heads/release-update/1.5.1\n"
    }
    run get_tag_from_release_update_branch
    assert_success
    assert_output "1.6.0"
}

@test "get_tag_from_release_update_branch: returns empty when no release-update branch" {
    git() { echo ""; }
    run get_tag_from_release_update_branch
    assert_success
    assert_output ""
}
