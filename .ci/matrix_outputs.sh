#!/usr/bin/env bash
# Runs generate_matrix.py and writes all matrix outputs to GITHUB_OUTPUT.
# Must be run from repo root (generate_matrix.py reads ./versions.yaml).
# Sourced by CI steps — not executed directly.
#
# Required env:
#   GITHUB_OUTPUT    path to GHA output file; defaults to /dev/null when unset
set -euo pipefail

# write_matrix_outputs
# Generates the build/manifest matrices and driver versions, writing all to GITHUB_OUTPUT.
write_matrix_outputs() {
    local matrix_json driver_versions
    matrix_json=$(python3 .ci/generate_matrix.py)
    driver_versions=$(yq -o=json '.nvidia_drivers' versions.yaml | jq -c '.')

    echo "build_matrix=$(echo "$matrix_json" | jq -c '.build')" >> "${GITHUB_OUTPUT:-/dev/null}"
    echo "manifest_matrix=$(echo "$matrix_json" | jq -c '.manifest')" >> "${GITHUB_OUTPUT:-/dev/null}"
    echo "gvisor_build_matrix=$(echo "$matrix_json" | jq -c '.gvisor_build')" >> "${GITHUB_OUTPUT:-/dev/null}"
    echo "gvisor_manifest_matrix=$(echo "$matrix_json" | jq -c '.gvisor_manifest')" >> "${GITHUB_OUTPUT:-/dev/null}"
    echo "driver_versions=${driver_versions}" >> "${GITHUB_OUTPUT:-/dev/null}"
    echo "Driver versions: ${driver_versions}"
}
