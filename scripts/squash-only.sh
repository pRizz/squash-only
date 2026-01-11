#!/usr/bin/env bash

set -uo pipefail

SLEEP_SECS=0.1
SHOULD_EXIT=0

# Temporary files for tracking counts across subshells
SUCCESS_COUNT_FILE=$(mktemp)
SKIP_COUNT_FILE=$(mktemp)
FAILED_COUNT_FILE=$(mktemp)
ALREADY_SQUASH_ONLY_COUNT_FILE=$(mktemp)

# Flag to force processing all repos even if they already have squash-only enabled
FORCE_FLAG=0

cleanup() {
  rm -f "$SUCCESS_COUNT_FILE" "$SKIP_COUNT_FILE" "$FAILED_COUNT_FILE" "$ALREADY_SQUASH_ONLY_COUNT_FILE"
}
trap cleanup EXIT

# Handle termination signals
handle_exit() {
  if [ "$SHOULD_EXIT" -eq 1 ]; then
    # Second Ctrl-C: bail immediately.
    exit 130
  fi

  SHOULD_EXIT=1
  echo ""
  echo "⚠️  Interrupted. Finishing current step then stopping..."
}
trap handle_exit INT TERM

require_cmd() {
  local cmd=$1
  if ! command -v "$cmd" &> /dev/null; then
    echo "❌ Error: Required command not found: $cmd"
    return 1
  fi
}

warn_if_old_bash() {
  # Some platforms (notably older macOS installs) default to bash 3.2.
  # This script should still work on bash 3+, but warn to reduce surprises.
  if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "⚠️  Warning: detected bash < 4 (${BASH_VERSION:-unknown}). If you hit issues, run with bash 4+."
  fi
}

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

is_squash_only() {
  local allow_squash_merge=$1
  local allow_merge_commit=$2
  local allow_rebase_merge=$3

  # Treat empty, "null", or missing values as false
  [ -z "$allow_squash_merge" ] && allow_squash_merge="false"
  [ "$allow_squash_merge" = "null" ] && allow_squash_merge="false"
  [ -z "$allow_merge_commit" ] && allow_merge_commit="false"
  [ "$allow_merge_commit" = "null" ] && allow_merge_commit="false"
  [ -z "$allow_rebase_merge" ] && allow_rebase_merge="false"
  [ "$allow_rebase_merge" = "null" ] && allow_rebase_merge="false"

  # Normalize case (in case of unexpected casing)
  allow_squash_merge=$(echo "$allow_squash_merge" | tr '[:upper:]' '[:lower:]')
  allow_merge_commit=$(echo "$allow_merge_commit" | tr '[:upper:]' '[:lower:]')
  allow_rebase_merge=$(echo "$allow_rebase_merge" | tr '[:upper:]' '[:lower:]')

  if [ "$allow_squash_merge" = "true" ] && [ "$allow_merge_commit" = "false" ] && [ "$allow_rebase_merge" = "false" ]; then
    return 0
  fi
  return 1
}

process_repo() {
  local repo=$1
  local owner=$2
  local allow_squash_merge=$3
  local allow_merge_commit=$4
  local allow_rebase_merge=$5

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

  # Check if repo already has squash-only enabled
  if [ "$FORCE_FLAG" -eq 0 ] && is_squash_only "$allow_squash_merge" "$allow_merge_commit" "$allow_rebase_merge"; then
    echo "────────────────────────────────────"
    echo "⏭️  Skipping repo: $repo (already squash-only)"
    increment_counter "$ALREADY_SQUASH_ONLY_COUNT_FILE"
    return 0
  fi

  echo "────────────────────────────────────"
  if [ "$FORCE_FLAG" -eq 1 ] && is_squash_only "$allow_squash_merge" "$allow_merge_commit" "$allow_rebase_merge"; then
    echo "Updating repo: $repo (forced, already squash-only)"
  else
    echo "Updating repo: $repo"
  fi

  local http_code
  http_code=$(curl -s --max-time 30 -o /dev/null -w "%{http_code}" \
    -X PATCH \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$repo" \
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

# Executes a GraphQL query and returns the response
execute_graphql_query() {
  local query=$1
  local variables_json=$2

  local payload
  if [ -n "$variables_json" ]; then
    payload=$(jq -n \
      --arg query "$query" \
      --argjson variables "$variables_json" \
      '{query: $query, variables: $variables}')
  else
    payload=$(jq -n \
      --arg query "$query" \
      '{query: $query}')
  fi

  local response
  response=$(curl -sS --max-time 30 \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Content-Type: application/json" \
    -H "Accept: application/vnd.github+json" \
    https://api.github.com/graphql \
    -d "$payload")

  # Check for GraphQL errors
  local errors
  errors=$(echo "$response" | jq -r '.errors // empty')
  if [ -n "$errors" ]; then
    echo "GraphQL error: $errors" >&2
    return 1
  fi

  echo "$response"
}

# Fetches all repos with merge strategies for a given owner using GraphQL
# Uses repositoryOwner query with pagination
# Returns JSON array with repos and their merge strategy info
fetch_repos_with_strategies() {
  local owner=$1

  read -r -d '' QUERY <<'GRAPHQL'
query($login: String!, $first: Int!, $after: String) {
  repositoryOwner(login: $login) {
    repositories(first: $first, after: $after) {
      pageInfo {
        hasNextPage
        endCursor
      }
      nodes {
        name
        owner {
          login
        }
        mergeCommitAllowed
        squashMergeAllowed
        rebaseMergeAllowed
        autoMergeAllowed
      }
    }
  }
}
GRAPHQL

  local all_repos="[]"
  local after_cursor=""
  local first=100

  while true; do
    [ "$SHOULD_EXIT" -eq 1 ] && break

    # Build variables JSON
    local variables_json
    if [ -n "$after_cursor" ]; then
      variables_json=$(jq -n \
        --arg login "$owner" \
        --argjson first "$first" \
        --arg after "$after_cursor" \
        '{login: $login, first: $first, after: $after}')
    else
      variables_json=$(jq -n \
        --arg login "$owner" \
        --argjson first "$first" \
        '{login: $login, first: $first}')
    fi

    # Execute GraphQL query
    local response
    response=$(execute_graphql_query "$QUERY" "$variables_json")
    if [ $? -ne 0 ]; then
      return 1
    fi

    [ "$SHOULD_EXIT" -eq 1 ] && break

    # Extract repos from response
    local repos
    repos=$(echo "$response" | jq '.data.repositoryOwner.repositories.nodes // []')

    # Check if we got any repos
    local repo_count
    repo_count=$(echo "$repos" | jq '. | length')
    if [ "$repo_count" -eq 0 ]; then
      break
    fi

    # Merge repos into all_repos
    all_repos=$(echo "$all_repos" "$repos" | jq -s 'add')

    # Check pagination info
    local has_next_page
    has_next_page=$(echo "$response" | jq -r '.data.repositoryOwner.repositories.pageInfo.hasNextPage')
    after_cursor=$(echo "$response" | jq -r '.data.repositoryOwner.repositories.pageInfo.endCursor // ""')

    if [ "$has_next_page" != "true" ] || [ -z "$after_cursor" ]; then
      break
    fi
  done

  echo "$all_repos"
}

# Processes repos with their merge strategies
# Takes JSON array of repos with name, owner.login, and merge strategy flags
process_repos_with_strategies() {
  local repos_json=$1

  while IFS= read -r line; do
    [ "$SHOULD_EXIT" -eq 1 ] && break

    # Parse the line: full_name|owner|squash|merge|rebase
    IFS='|' read -r repo owner allow_squash_merge allow_merge_commit allow_rebase_merge <<< "$line"

    # Trim leading/trailing whitespace
    repo=$(echo "$repo" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    owner=$(echo "$owner" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    allow_squash_merge=$(echo "$allow_squash_merge" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    allow_merge_commit=$(echo "$allow_merge_commit" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    allow_rebase_merge=$(echo "$allow_rebase_merge" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    process_repo "$repo" "$owner" "$allow_squash_merge" "$allow_merge_commit" "$allow_rebase_merge" || break
  done < <(echo "$repos_json" | jq -r '.[] | 
    "\(.owner.login)/\(.name)|\(.owner.login)|\(
      if .squashMergeAllowed == null then false else .squashMergeAllowed end
    )|\(
      if .mergeCommitAllowed == null then false else .mergeCommitAllowed end
    )|\(
      if .rebaseMergeAllowed == null then false else .rebaseMergeAllowed end
    )"')
}

fetch_all_repos() {
  # Fetch all repos with merge strategies using GraphQL
  local repos_json
  repos_json=$(fetch_repos_with_strategies "$GITHUB_USER")
  if [ $? -ne 0 ]; then
    echo "❌ Failed to fetch repos" >&2
    return 1
  fi

  if [ -z "$repos_json" ] || [ "$repos_json" = "[]" ]; then
    echo "❌ No repos found" >&2
    return 0
  fi

  # Process repos with their merge strategies
  process_repos_with_strategies "$repos_json"
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
      -f|--force)
        FORCE_FLAG=1
        shift
        ;;
      *)
        echo "❌ Error: Unknown option: $1"
        echo "Usage: $0 [--sleep SECONDS] [--force]"
        exit 1
        ;;
    esac
  done
}

main() {
  warn_if_old_bash
  require_cmd curl || exit 1
  require_cmd jq || exit 1

  parse_args "$@"

  # Initialize counters
  echo "0" > "$SUCCESS_COUNT_FILE"
  echo "0" > "$SKIP_COUNT_FILE"
  echo "0" > "$FAILED_COUNT_FILE"
  echo "0" > "$ALREADY_SQUASH_ONLY_COUNT_FILE"

  echo "Updating all your repos to Squash Only!"
  echo "→ Disables merge commits"
  echo "→ Disables rebase merges"
  echo "→ Enables squash merges"
  if [ "$FORCE_FLAG" -eq 1 ]; then
    echo "→ Force mode: processing all repos (including already squash-only)"
  else
    echo "→ Skipping repos that are already squash-only (use --force to process all)"
  fi

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
  ALREADY_SQUASH_ONLY_COUNT=$(cat "$ALREADY_SQUASH_ONLY_COUNT_FILE")
  echo "  ✅ Successfully updated: $SUCCESS_COUNT"
  if [ "$ALREADY_SQUASH_ONLY_COUNT" -gt 0 ]; then
    echo "  ⏭️  Already squash-only (skipped): $ALREADY_SQUASH_ONLY_COUNT"
  fi
  if [ "$SKIP_COUNT" -gt 0 ]; then
    echo "  ⏭️  Skipped (not owned by you): $SKIP_COUNT"
  fi
  if [ "$FAILED_COUNT" -gt 0 ]; then
    echo "  ❌ Failed: $FAILED_COUNT"
  fi
  if [ "$ELAPSED_MIN" -gt 0 ]; then
    echo "  ⏱️  Elapsed time: ${ELAPSED_MIN}m ${ELAPSED_SEC}s"
  else
    echo "  ⏱️  Elapsed time: ${ELAPSED}s"
  fi

  if [ "$SHOULD_EXIT" -eq 1 ]; then
    exit 130
  fi
}

main "$@"
