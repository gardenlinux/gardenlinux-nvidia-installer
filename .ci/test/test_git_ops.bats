#!/usr/bin/env bats
#
# Tests for functions in .ci/git_ops.sh
#
# Run from repo root: test/bats/bin/bats test/bats/test_git_ops.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/.ci/git_ops.sh"

load "${REPO_ROOT}/test/test_helper/bats-support/load"
load "${REPO_ROOT}/test/test_helper/bats-assert/load"

setup() {
    GIT_CALLS=()
    git() { GIT_CALLS+=("$*"); }
    gh() { echo "https://github.com/test/repo/pull/1"; }
    # shellcheck disable=SC1090
    . "${SCRIPT}"
}

# ---------------------------------------------------------------------------
# configure_git_identity
# ---------------------------------------------------------------------------

@test "configure_git_identity: calls git config user.name" {
    configure_git_identity "Garden Linux Builder" "builder@example.com"
    local found=false
    for call in "${GIT_CALLS[@]}"; do
        [[ "$call" == "config user.name Garden Linux Builder" ]] && found=true
    done
    assert_equal "$found" "true"
}

@test "configure_git_identity: calls git config user.email" {
    configure_git_identity "Garden Linux Builder" "builder@example.com"
    local found=false
    for call in "${GIT_CALLS[@]}"; do
        [[ "$call" == "config user.email builder@example.com" ]] && found=true
    done
    assert_equal "$found" "true"
}

@test "configure_git_identity: does not use --global flag" {
    configure_git_identity "Garden Linux Builder" "builder@example.com"
    for call in "${GIT_CALLS[@]}"; do
        if [[ "$call" == *"--global"* ]]; then
            fail "git config was called with --global: $call"
        fi
    done
}

# ---------------------------------------------------------------------------
# commit_and_push_branch
# ---------------------------------------------------------------------------

@test "commit_and_push_branch: exits 0 with message when nothing staged" {
    # git add is a no-op; git diff --cached --quiet exits 0 (nothing staged)
    git() {
        case "$*" in
            "add some-file.yaml") ;;
            "diff --cached --quiet --exit-code") return 0 ;;
            *) ;;
        esac
    }
    run commit_and_push_branch "my-branch" "some-file.yaml"
    assert_success
    assert_output --partial "No changes to commit"
}

@test "commit_and_push_branch: commits and force-pushes when changes are staged" {
    PUSH_CALLED=false
    git() {
        case "$*" in
            "add file-a.yaml file-b.yaml") ;;
            "diff --cached --quiet --exit-code") return 1 ;;
            "checkout -b release-update/1.2.0") ;;
            "commit -m Update release references for release-update/1.2.0") ;;
            "push -f origin release-update/1.2.0") PUSH_CALLED=true ;;
            *) ;;
        esac
    }
    commit_and_push_branch "release-update/1.2.0" "file-a.yaml" "file-b.yaml"
    assert_equal "$PUSH_CALLED" "true"
}
