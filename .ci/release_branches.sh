#!/usr/bin/env bash
# Release branch management for the create-gh-release CI job.
# Sourced by CI steps — not executed directly.
set -euo pipefail

# update_release_branches MAJOR MINOR
# Merges main into the MAJOR.MINOR and MAJOR release branches and pushes both.
update_release_branches() {
    local major="$1"
    local minor="$2"
    local branch

    branch="${major}.${minor}"
    git checkout -B "$branch" "origin/${branch}" || git checkout -b "$branch"
    git merge main --no-edit
    git push origin "$branch"

    branch="${major}"
    git checkout -B "$branch" "origin/${branch}" || git checkout -b "$branch"
    git merge main --no-edit
    git push origin "$branch"
}
