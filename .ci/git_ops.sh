#!/usr/bin/env bash
# Git commit and PR creation helpers used by the release pipeline.
# Sourced by CI steps and bats tests — not executed directly.
#
# Required env for create_pr:
#   GH_TOKEN    for gh cli
set -euo pipefail

# configure_git_identity NAME EMAIL
# Sets git user.name and user.email (local, not --global).
configure_git_identity() {
    local name="$1"
    local email="$2"
    git config user.name "$name"
    git config user.email "$email"
}

# commit_and_push_branch BRANCH FILES...
# Stages FILES, exits 0 with a message if nothing to commit, otherwise
# checks out BRANCH, commits, and force-pushes to origin.
commit_and_push_branch() {
    local branch="$1"
    shift
    git add "$@"
    if git diff --cached --quiet --exit-code; then
        echo "No changes to commit"
        return 0
    fi
    git checkout -b "$branch"
    git commit -m "Update release references for $branch"
    git push -f origin "$branch"
}

# create_pr BRANCH BASE TITLE BODY
# Creates a GitHub PR from BRANCH into BASE.
create_pr() {
    local branch="$1"
    local base="$2"
    local title="$3"
    local body="$4"
    gh pr create --base "$base" --head "$branch" --title "$title" --body "$body"
}
