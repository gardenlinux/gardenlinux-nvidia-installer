#!/usr/bin/env bash
# Semver bump logic for the release pipeline.
# Sourced by CI steps and bats tests — not executed directly.
#
# Required env:
#   GH_REPO          github.repository (e.g. "gardenlinux/gardenlinux-nvidia-installer")
#   GH_TOKEN         for gh cli
#   GITHUB_OUTPUT    path to GHA output file; defaults to /dev/null when unset
set -euo pipefail

# parse_semver TAG
# Sets MAJOR, MINOR, PATCH in the caller's scope.
parse_semver() {
    local tag="$1"
    MAJOR=$(echo "$tag" | cut -d. -f1)
    MINOR=$(echo "$tag" | cut -d. -f2)
    PATCH=$(echo "$tag" | cut -d. -f3)
}

# extract_yaml_section REF SECTION
# Prints the list items under SECTION from versions.yaml at the given git REF.
extract_yaml_section() {
    local ref="$1"
    local section="$2"
    { git show "${ref}:versions.yaml" 2>/dev/null || true; } \
        | awk "/^${section}:/{found=1; next} found && /^[^ -]/{exit} found{print}"
}

# count_added BEFORE AFTER
# Prints the number of lines present in AFTER that are not in BEFORE.
count_added() {
    local before="$1"
    local after="$2"
    local f1 f2 result
    f1=$(mktemp)
    f2=$(mktemp)
    [ -n "$before" ] && printf "%s\n" "$before" > "$f1" || true
    [ -n "$after"  ] && printf "%s\n" "$after"  > "$f2" || true
    result=$(diff "$f1" "$f2" | grep -c '^>' || true)
    rm -f "$f1" "$f2"
    echo "$result"
}

# _versions_yaml_without_os_versions REF
# Prints versions.yaml at REF with the os_versions list stripped out.
_versions_yaml_without_os_versions() {
    local ref="$1"
    { git show "${ref}:versions.yaml" 2>/dev/null || true; } \
        | awk '/^os_versions:/{skip=1; next} skip && !/^  -/{skip=0} !skip'
}

# bump_semver
# Determines and outputs the next semver tag.
# Reads GH_REPO from env; writes new_tag=X.Y.Z to ${GITHUB_OUTPUT:-/dev/null}.
bump_semver() {
    local last_tag new_tag
    local major minor patch
    local nvidia_before nvidia_after os_before os_after
    local nvidia_added versions_yaml_before_no_os versions_yaml_after_no_os
    local versions_yaml_other_changes other_files_changed

    last_tag=$(gh release list --repo "$GH_REPO" --json tagName \
        --jq '[.[] | select(.tagName | test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))] | first | .tagName // empty')

    if [[ -z "$last_tag" ]]; then
        echo "No previous release found, starting at 1.0.0"
        new_tag="1.0.0"
        echo "new_tag=${new_tag}" >> "${GITHUB_OUTPUT:-/dev/null}"
        return 0
    fi

    parse_semver "$last_tag"
    major="$MAJOR"
    minor="$MINOR"
    patch="$PATCH"

    nvidia_before=$(extract_yaml_section "$last_tag" "nvidia_drivers")
    nvidia_after=$(extract_yaml_section "HEAD" "nvidia_drivers")
    os_before=$(extract_yaml_section "$last_tag" "os_versions")
    os_after=$(extract_yaml_section "HEAD" "os_versions")

    nvidia_added=$(count_added "$nvidia_before" "$nvidia_after")

    versions_yaml_before_no_os=$(_versions_yaml_without_os_versions "$last_tag")
    versions_yaml_after_no_os=$(_versions_yaml_without_os_versions "HEAD")
    versions_yaml_other_changes=$(count_added "$versions_yaml_before_no_os" "$versions_yaml_after_no_os")

    other_files_changed=$(git diff --name-only "${last_tag}..HEAD" \
        | grep -cv \
            -e '^versions\.yaml$' \
            -e '^\.github/' \
            -e '^\.ci/' \
            -e '^cdup/' \
            -e '^docs/' \
            -e '^history\.yaml$' \
        || true)

    if [[ "$nvidia_added" -gt 0 ]] || [[ "$other_files_changed" -gt 0 ]] || [[ "$versions_yaml_other_changes" -gt 0 ]]; then
        echo "NVIDIA_ADDED: ${nvidia_added}, OTHER_FILES_CHANGED: ${other_files_changed}, VERSIONS_YAML_OTHER_CHANGES: ${versions_yaml_other_changes}"
        minor=$((minor + 1))
        patch=0
    else
        patch=$((patch + 1))
    fi

    new_tag="${major}.${minor}.${patch}"
    echo "Last tag: ${last_tag} → New tag: ${new_tag}"
    echo "new_tag=${new_tag}" >> "${GITHUB_OUTPUT:-/dev/null}"
}
