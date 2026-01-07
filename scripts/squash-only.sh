#!/usr/bin/env bash

set -uo pipefail

SLEEP_SECS=0.2
SHOULD_EXIT=0

# Temporary files for tracking counts across subshells
SUCCESS_COUNT_FILE=$(mktemp)
SKIP_COUNT_FILE=$(mktemp)
FAILED_COUNT_FILE=$(mktemp)

cleanup() {
  rm -f "$SUCCESS_COUNT_FILE" "$SKIP_COUNT_FILE" "$FAILED_COUNT_FILE"
}
trap cleanup EXIT

# Handle termination signals
handle_exit() {
  SHOULD_EXIT=1
  echo ""
  echo "⚠️  Interrupted. Cleaning up..."
  cleanup
  exit 130
}
trap handle_exit INT TERM

get_github_token() {
  # Check if GITHUB_TOKEN is already in environment
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "$GITHUB_TOKEN"
    return 0
  fi

  # Check if gh CLI is installed
  if ! command -v gh &> /dev/null; then
    print_pat_instructions
    return 1
  fi

  # Try to get token from gh CLI
  local maybeToken
  maybeToken=$(gh auth token 2>/dev/null)
  if [ -n "$maybeToken" ]; then
    echo "$maybeToken"
    return 0
  fi

  # gh is installed but no token available
  print_pat_instructions
  return 1
}

print_pat_instructions() {
  cat << 'EOF'

To use this script, you need a GitHub Personal Access Token (PAT).

1. Go to https://github.com/settings/tokens/new
2. Give your token a descriptive name (e.g., "Squash Only Script")
3. Set an expiration (recommended: 90 days or custom)
4. Select the following permissions:
   - repo (Full control of private repositories)
     - This includes: repo:status, repo_deployment, public_repo, repo:invite, security_events
5. Click "Generate token"
6. Copy the token and run this script with:
   GITHUB_TOKEN=your_token_here ./scripts/squash-only.sh

Alternatively, you can install the GitHub CLI (gh) and authenticate:
  brew install gh
  gh auth login

EOF
}

increment_counter() {
  local counter_file=$1
  local current
  current=$(cat "$counter_file")
  echo $((current + 1)) > "$counter_file"
}

process_repo() {
  local repo=$1
  local owner=$2

  # Check if we should exit
  [ "$SHOULD_EXIT" -eq 1 ] && return 1

  if [ -z "$repo" ] || [ "$repo" = "null" ]; then
    return 0
  fi

  if [ "$owner" != "$GITHUB_USER" ]; then
    echo "────────────────────────────────────"
    echo "⏭️  Skipping repo: $repo (owned by $owner)"
    increment_counter "$SKIP_COUNT_FILE"
    return 0
  fi

  echo "────────────────────────────────────"
  echo "Updating repo: $repo"

  local http_code
  http_code=$(curl -s --max-time 30 -o /dev/null -w "%{http_code}" \
    -X PATCH \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/$repo \
    -d '{
      "allow_merge_commit": false,
      "allow_rebase_merge": false,
      "allow_squash_merge": true
    }')

  # Check if we should exit after curl
  [ "$SHOULD_EXIT" -eq 1 ] && return 1

  if [ "$http_code" -eq 200 ]; then
    echo "✅ Success ($http_code)"
    echo "   https://github.com/$repo"
    increment_counter "$SUCCESS_COUNT_FILE"
  else
    echo "❌ Failed ($http_code)"
    increment_counter "$FAILED_COUNT_FILE"
  fi

  # Check again before sleeping
  [ "$SHOULD_EXIT" -eq 1 ] && return 1

  echo "Sleeping ${SLEEP_SECS}s…"
  sleep "$SLEEP_SECS"
}

fetch_all_repos() {
  local page=1
  local per_page=100

  while true; do
    # Check if we should exit
    [ "$SHOULD_EXIT" -eq 1 ] && break

    local body
    body=$(curl -s --max-time 30 -H "Authorization: token $GITHUB_TOKEN" \
      "https://api.github.com/user/repos?per_page=$per_page&page=$page")

    # Check if we should exit after curl
    [ "$SHOULD_EXIT" -eq 1 ] && break

    local repo_count
    repo_count=$(echo "$body" | jq '. | length')
    if [ -z "$repo_count" ] || [ "$repo_count" = "0" ] || [ "$repo_count" = "null" ]; then
      break
    fi

    echo "$body" | jq -r '.[] | "\(.full_name)|\(.owner.login)"' | while IFS='|' read -r repo owner; do
      [ "$SHOULD_EXIT" -eq 1 ] && break
      process_repo "$repo" "$owner" || break
    done

    [ "$SHOULD_EXIT" -eq 1 ] && break

    if [ "$repo_count" -lt "$per_page" ]; then
      break
    fi

    page=$((page + 1))
  done
}

is_number() {
  local value=$1
  if [[ "$value" =~ ^[0-9]+\.?[0-9]*$ ]]; then
    return 0
  fi
  return 1
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -s|--sleep)
        if [ -z "${2:-}" ]; then
          echo "❌ Error: --sleep requires a value"
          exit 1
        fi
        if ! is_number "$2"; then
          echo "❌ Error: --sleep value must be a number (got: $2)"
          exit 1
        fi
        SLEEP_SECS="$2"
        shift 2
        ;;
      *)
        echo "❌ Error: Unknown option: $1"
        echo "Usage: $0 [--sleep SECONDS]"
        exit 1
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  # Initialize counters
  echo "0" > "$SUCCESS_COUNT_FILE"
  echo "0" > "$SKIP_COUNT_FILE"
  echo "0" > "$FAILED_COUNT_FILE"

  echo "Updating all your repos to Squash Only!"
  echo "→ Disables merge commits"
  echo "→ Disables rebase merges"
  echo "→ Enables squash merges"

  echo "→ Logging in to GitHub…"
  GITHUB_TOKEN=$(get_github_token)
  if [ $? -ne 0 ]; then
    exit 1
  fi

  echo "Fetching your username…"
  GITHUB_USER=$(curl -s --max-time 30 -H "Authorization: token $GITHUB_TOKEN" \
    https://api.github.com/user | jq -r '.login')
  
  # Check if we should exit
  [ "$SHOULD_EXIT" -eq 1 ] && exit 130

  if [ -z "$GITHUB_USER" ] || [ "$GITHUB_USER" = "null" ]; then
    echo "❌ Failed to get GitHub username"
    exit 1
  fi

  echo "Fetching your repos…"
  START_TIME=$(date +%s)
  fetch_all_repos
  END_TIME=$(date +%s)

  ELAPSED=$((END_TIME - START_TIME))
  ELAPSED_MIN=$((ELAPSED / 60))
  ELAPSED_SEC=$((ELAPSED % 60))

  echo ""
  echo "────────────────────────────────────"
  echo "Summary:"
  SUCCESS_COUNT=$(cat "$SUCCESS_COUNT_FILE")
  SKIP_COUNT=$(cat "$SKIP_COUNT_FILE")
  FAILED_COUNT=$(cat "$FAILED_COUNT_FILE")
  echo "  ✅ Successfully updated: $SUCCESS_COUNT"
  echo "  ⏭️  Skipped: $SKIP_COUNT"
  if [ "$FAILED_COUNT" -gt 0 ]; then
    echo "  ❌ Failed: $FAILED_COUNT"
  fi
  if [ "$ELAPSED_MIN" -gt 0 ]; then
    echo "  ⏱️  Elapsed time: ${ELAPSED_MIN}m ${ELAPSED_SEC}s"
  else
    echo "  ⏱️  Elapsed time: ${ELAPSED}s"
  fi
}

main "$@"
