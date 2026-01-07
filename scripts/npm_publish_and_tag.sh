#!/usr/bin/env bash

# Internal script for publishing the npm package and tagging the current version.

set -e

# Get the script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Publishing npm package..."
cd "$PROJECT_ROOT"

# Publish the npm package to npm
npm publish

# Call the git tag script to tag the release
"$SCRIPT_DIR/git_tag_current_version.sh"
