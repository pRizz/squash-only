#!/usr/bin/env bash

# Internal script for tagging the current version of the npm package.

set -e

# Get the script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Extract version from package.json
VERSION=$(jq -r '.version' "$PROJECT_ROOT/package.json")

if [ -z "$VERSION" ]; then
    echo "Error: Could not extract version from package.json" >&2
    exit 1
fi

TAG_NAME="release/v$VERSION"

# Check if tag already exists
if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
    echo "Error: Tag '$TAG_NAME' already exists" >&2
    exit 1
fi

echo "Creating git tag: $TAG_NAME"

# Create the tag
git tag "$TAG_NAME"

echo "Tag created successfully: $TAG_NAME"
echo "Pushing all tags..."

# Push all tags
git push --tags

echo "All tags pushed successfully!"
