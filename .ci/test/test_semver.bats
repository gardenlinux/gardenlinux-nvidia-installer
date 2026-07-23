#!/usr/bin/env bats
#
# Tests for functions in .ci/semver.sh
#
# Run from repo root: test/bats/bin/bats test/bats/test_semver.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/.ci/semver.sh"

load "${REPO_ROOT}/test/test_helper/bats-support/load"
load "${REPO_ROOT}/test/test_helper/bats-assert/load"

setup() {
    # Stub external commands; tests override as needed
    git() { echo ""; }
    gh() { echo ""; }
    # shellcheck disable=SC1090
    . "${SCRIPT}"
}

# ---------------------------------------------------------------------------
# parse_semver
# ---------------------------------------------------------------------------

@test "parse_semver: parses 1.0.0" {
    parse_semver "1.0.0"
    assert_equal "$MAJOR" "1"
    assert_equal "$MINOR" "0"
    assert_equal "$PATCH" "0"
}

@test "parse_semver: parses 10.23.456" {
    parse_semver "10.23.456"
    assert_equal "$MAJOR" "10"
    assert_equal "$MINOR" "23"
    assert_equal "$PATCH" "456"
}

@test "parse_semver: parses 0.0.0" {
    parse_semver "0.0.0"
    assert_equal "$MAJOR" "0"
    assert_equal "$MINOR" "0"
    assert_equal "$PATCH" "0"
}

# ---------------------------------------------------------------------------
# count_added
# ---------------------------------------------------------------------------

@test "count_added: identical input returns 0" {
    result=$(count_added "alpha
beta" "alpha
beta")
    assert_equal "$result" "0"
}

@test "count_added: one line added returns 1" {
    result=$(count_added "alpha" "alpha
beta")
    assert_equal "$result" "1"
}

@test "count_added: multiple added returns correct count" {
    result=$(count_added "alpha" "alpha
beta
gamma")
    assert_equal "$result" "2"
}

@test "count_added: empty before returns full count of after" {
    result=$(count_added "" "alpha
beta")
    assert_equal "$result" "2"
}

@test "count_added: empty after returns 0" {
    result=$(count_added "alpha
beta" "")
    assert_equal "$result" "0"
}

# ---------------------------------------------------------------------------
# extract_yaml_section
# ---------------------------------------------------------------------------

@test "extract_yaml_section: extracts nvidia_drivers list" {
    git() {
        printf "nvidia_drivers:\n  - 570\n  - 560\nos_versions:\n  - 1877\n"
    }
    result=$(extract_yaml_section "HEAD" "nvidia_drivers")
    assert_equal "$result" "  - 570
  - 560"
}

@test "extract_yaml_section: extracts os_versions list" {
    git() {
        printf "nvidia_drivers:\n  - 570\nos_versions:\n  - 1877\n  - 2150\n"
    }
    result=$(extract_yaml_section "HEAD" "os_versions")
    assert_equal "$result" "  - 1877
  - 2150"
}

@test "extract_yaml_section: returns all items in a longer list" {
    git() {
        printf "nvidia_drivers:\n  - 570\n  - 560\n  - 550\n  - 535\nos_versions:\n  - 1877\n"
    }
    result=$(extract_yaml_section "HEAD" "nvidia_drivers")
    assert_equal "$result" "  - 570
  - 560
  - 550
  - 535"
}

@test "extract_yaml_section: returns all items when section is last in file" {
    git() {
        printf "nvidia_drivers:\n  - 570\nos_versions:\n  - 1877\n  - 2150\n  - 2200\n"
    }
    result=$(extract_yaml_section "HEAD" "os_versions")
    assert_equal "$result" "  - 1877
  - 2150
  - 2200"
}

@test "extract_yaml_section: stops at next top-level key" {
    git() {
        printf "nvidia_drivers:\n  - 570\nos_versions:\n  - 1877\ngvisor_version: 20240101\n"
    }
    result=$(extract_yaml_section "HEAD" "os_versions")
    assert_equal "$result" "  - 1877"
}

@test "extract_yaml_section: returns empty string for missing section" {
    git() {
        printf "nvidia_drivers:\n  - 570\n"
    }
    result=$(extract_yaml_section "HEAD" "os_versions")
    assert_equal "$result" ""
}

@test "extract_yaml_section: returns empty string when git show fails" {
    git() { return 1; }
    result=$(extract_yaml_section "nosuchref" "nvidia_drivers")
    assert_equal "$result" ""
}

# ---------------------------------------------------------------------------
# bump_semver — no previous release
# ---------------------------------------------------------------------------

@test "bump_semver: no previous release produces 1.0.0" {
    gh() { echo ""; }
    GITHUB_OUTPUT="$(mktemp)"
    GH_REPO="test/repo"
    bump_semver
    run grep "new_tag=1.0.0" "$GITHUB_OUTPUT"
    assert_success
    rm -f "$GITHUB_OUTPUT"
}

@test "bump_semver: no previous release writes to GITHUB_OUTPUT" {
    gh() { echo ""; }
    GITHUB_OUTPUT="$(mktemp)"
    GH_REPO="test/repo"
    bump_semver
    run grep "new_tag=1.0.0" "$GITHUB_OUTPUT"
    assert_success
    rm -f "$GITHUB_OUTPUT"
}

@test "bump_semver: GITHUB_OUTPUT unset falls back to /dev/null without error" {
    gh() { echo ""; }
    unset GITHUB_OUTPUT
    GH_REPO="test/repo"
    run bump_semver
    assert_success
}

# ---------------------------------------------------------------------------
# bump_semver — MINOR bump triggers
# ---------------------------------------------------------------------------

@test "bump_semver: NVIDIA driver added causes MINOR bump" {
    gh() { echo "2.5.3"; }
    git() {
        case "$*" in
            "show 2.5.3:versions.yaml") printf "nvidia_drivers:\n  - 570\n  - 560\n" ;;
            "show HEAD:versions.yaml")  printf "nvidia_drivers:\n  - 570\n  - 560\n  - 550\nos_versions:\n  - 1877\n" ;;
            "diff --name-only 2.5.3..HEAD") echo "versions.yaml" ;;
            *) echo "" ;;
        esac
    }
    GITHUB_OUTPUT="$(mktemp)"
    GH_REPO="test/repo"
    bump_semver
    run grep "new_tag=2.6.0" "$GITHUB_OUTPUT"
    assert_success
    rm -f "$GITHUB_OUTPUT"
}

@test "bump_semver: other files changed causes MINOR bump" {
    gh() { echo "1.3.2"; }
    git() {
        case "$*" in
            "show 1.3.2:versions.yaml") printf "nvidia_drivers:\n  - 570\nos_versions:\n  - 1877\n" ;;
            "show HEAD:versions.yaml")  printf "nvidia_drivers:\n  - 570\nos_versions:\n  - 1877\n" ;;
            "diff --name-only 1.3.2..HEAD") printf "Makefile\nresources/compile.sh\n" ;;
            *) echo "" ;;
        esac
    }
    GITHUB_OUTPUT="$(mktemp)"
    GH_REPO="test/repo"
    bump_semver
    run grep "new_tag=1.4.0" "$GITHUB_OUTPUT"
    assert_success
    rm -f "$GITHUB_OUTPUT"
}

@test "bump_semver: versions.yaml non-os_versions change causes MINOR bump" {
    gh() { echo "1.2.0"; }
    git() {
        case "$*" in
            "show 1.2.0:versions.yaml") printf "nvidia_drivers:\n  - 570\ngvisor_version: 20240101\nos_versions:\n  - 1877\n" ;;
            "show HEAD:versions.yaml")  printf "nvidia_drivers:\n  - 570\ngvisor_version: 20250101\nos_versions:\n  - 1877\n" ;;
            "diff --name-only 1.2.0..HEAD") echo "versions.yaml" ;;
            *) echo "" ;;
        esac
    }
    GITHUB_OUTPUT="$(mktemp)"
    GH_REPO="test/repo"
    bump_semver
    run grep "new_tag=1.3.0" "$GITHUB_OUTPUT"
    assert_success
    rm -f "$GITHUB_OUTPUT"
}

# ---------------------------------------------------------------------------
# bump_semver — PATCH bump (os_versions only)
# ---------------------------------------------------------------------------

@test "bump_semver: only os_versions changed causes PATCH bump" {
    gh() { echo "2.5.3"; }
    git() {
        case "$*" in
            "show 2.5.3:versions.yaml") printf "nvidia_drivers:\n  - 570\nos_versions:\n  - 1877\n" ;;
            "show HEAD:versions.yaml")  printf "nvidia_drivers:\n  - 570\nos_versions:\n  - 1877\n  - 2150\n" ;;
            "diff --name-only 2.5.3..HEAD") echo "versions.yaml" ;;
            *) echo "" ;;
        esac
    }
    GITHUB_OUTPUT="$(mktemp)"
    GH_REPO="test/repo"
    bump_semver
    run grep "new_tag=2.5.4" "$GITHUB_OUTPUT"
    assert_success
    rm -f "$GITHUB_OUTPUT"
}

@test "bump_semver: patch increment from 99 does not overflow" {
    gh() { echo "1.0.99"; }
    git() {
        case "$*" in
            "show 1.0.99:versions.yaml") printf "nvidia_drivers:\n  - 570\nos_versions:\n  - 1877\n" ;;
            "show HEAD:versions.yaml")   printf "nvidia_drivers:\n  - 570\nos_versions:\n  - 1877\n  - 2150\n" ;;
            "diff --name-only 1.0.99..HEAD") echo "versions.yaml" ;;
            *) echo "" ;;
        esac
    }
    GITHUB_OUTPUT="$(mktemp)"
    GH_REPO="test/repo"
    bump_semver
    run grep "new_tag=1.0.100" "$GITHUB_OUTPUT"
    assert_success
    rm -f "$GITHUB_OUTPUT"
}

# ---------------------------------------------------------------------------
# bump_semver — MINOR bump resets PATCH
# ---------------------------------------------------------------------------

@test "bump_semver: MINOR bump resets PATCH to 0" {
    gh() { echo "1.5.99"; }
    git() {
        case "$*" in
            "show 1.5.99:versions.yaml") printf "nvidia_drivers:\n  - 570\nos_versions:\n  - 1877\n" ;;
            "show HEAD:versions.yaml")   printf "nvidia_drivers:\n  - 570\n  - 560\nos_versions:\n  - 1877\n" ;;
            "diff --name-only 1.5.99..HEAD") echo "versions.yaml" ;;
            *) echo "" ;;
        esac
    }
    GITHUB_OUTPUT="$(mktemp)"
    GH_REPO="test/repo"
    bump_semver
    run grep "new_tag=1.6.0" "$GITHUB_OUTPUT"
    assert_success
    rm -f "$GITHUB_OUTPUT"
}

# ---------------------------------------------------------------------------
# bump_semver — exclusion list
# ---------------------------------------------------------------------------

@test "bump_semver: changes only in .github/ excluded, causes PATCH bump" {
    gh() { echo "3.1.0"; }
    git() {
        case "$*" in
            "show 3.1.0:versions.yaml") printf "nvidia_drivers:\n  - 570\nos_versions:\n  - 1877\n" ;;
            "show HEAD:versions.yaml")  printf "nvidia_drivers:\n  - 570\nos_versions:\n  - 1877\n  - 2150\n" ;;
            "diff --name-only 3.1.0..HEAD") printf ".github/workflows/release-process.yml\nversions.yaml\n" ;;
            *) echo "" ;;
        esac
    }
    GITHUB_OUTPUT="$(mktemp)"
    GH_REPO="test/repo"
    bump_semver
    run grep "new_tag=3.1.1" "$GITHUB_OUTPUT"
    assert_success
    rm -f "$GITHUB_OUTPUT"
}
