# squash-only

A hybrid Node.js/bash script to automatically configure all your GitHub repositories to use squash-only merge strategy, which is obviously the best merge strategy.

## Quick start

```bash
npx squash-only
```

## What it does

This script updates all repositories you own on GitHub to:
- ✅ Enable squash merges
- ❌ Disable merge commits
- ❌ Disable rebase merges

It automatically:
- Skips repositories you don't own
- Skips repositories that are already configured for squash-only (efficient reruns; no unnecessary network requests)
- Only processes repositories that need updating
- Provides a summary of the results

## Requirements

- `bash` (version 3+; 4+ recommended)
- `curl`
- `jq`
- GitHub authentication (see below)

**Note:** If using the Node.js binary wrapper, you'll also need Node.js installed.

**macOS note:** Some macOS installations default to bash 3.2. The script should still work, but if you hit shell-related issues, try running with bash 4+.

## Authentication

The script supports three methods for GitHub authentication (in order of preference):

### 1. Environment Variable
Set `GITHUB_TOKEN` in your environment:
```bash
export GITHUB_TOKEN=your_token_here
./scripts/squash-only.sh
```

### 2. GitHub CLI (`gh`)
If you have the GitHub CLI installed and authenticated:
```bash
gh auth login
./scripts/squash-only.sh
```

### 3. Personal Access Token (PAT)
If neither of the above are available, the script will display instructions for creating a PAT with the required permissions.

**Required PAT permissions:**
- `repo` (Full control of private repositories)

## Installation & Usage

You can run this tool in several ways:

### Option 1: Using npx (Recommended - No Installation Required)

Run directly from the GitHub repository without installing:
```bash
npx github:pRizz/squash-only
```

With custom sleep interval:
```bash
npx github:pRizz/squash-only --sleep 0.5
```

With force flag (process all repos, including already squash-only):
```bash
npx github:pRizz/squash-only --force
```

**Note:** If the package is published to npm, you can also use:
```bash
npx squash-only
```

### Option 2: Using the Bash Script Directly

Run the bash script directly:
```bash
./scripts/squash-only.sh
```

With custom sleep interval:
```bash
./scripts/squash-only.sh --sleep 0.5
# or
./scripts/squash-only.sh -s 1.0
```

With force flag (process all repos, including already squash-only):
```bash
./scripts/squash-only.sh --force
# or
./scripts/squash-only.sh -f
```

### Option 3: Run Locally with npm (Development)

If you've cloned the repository, you can run it locally using npm scripts:
```bash
npm start
# or
npm run squash-only
```

With custom sleep interval:
```bash
npm start -- --sleep 0.5
```

With force flag:
```bash
npm start -- --force
```

You can also use `npx` to run the local version:
```bash
npx .
```

### Option 4: Install Globally via npm/pnpm

Install the package globally:
```bash
npm install -g squash-only
# or
pnpm install -g squash-only
```

Then run it from anywhere:
```bash
squash-only
```

## Usage Examples

### Basic usage
```bash
# Using npx (recommended)
npx github:pRizz/squash-only

# Or run locally with npm
npm start

# Or using the bash script directly
./scripts/squash-only.sh
```

### Custom sleep interval
Control the delay between API requests (default: 0.2 seconds):
```bash
# Using npx
npx github:pRizz/squash-only --sleep 0.5

# Or run locally with npm
npm start -- --sleep 0.5

# Or using the bash script
./scripts/squash-only.sh --sleep 0.5
# or
./scripts/squash-only.sh -s 1.0
```

### Force mode
Process all repositories, including those already configured for squash-only:
```bash
# Using npx
npx github:pRizz/squash-only --force

# Or run locally with npm
npm start -- --force

# Or using the bash script
./scripts/squash-only.sh --force
# or
./scripts/squash-only.sh -f
```

Combine options:
```bash
npx github:pRizz/squash-only --force --sleep 0.5
```

## Options

- `-s, --sleep SECONDS` - Set the sleep interval between API requests (default: 0.1 seconds). This delay helps prevent triggering GitHub's rate limits. Authenticated requests (OAuth or PAT) are limited to ~5,000 requests per hour per user or app. See [GitHub's API rate limits documentation](https://github.com/orgs/community/discussions/163553) for more details.
- `-f, --force` - Process all repositories, including those already configured for squash-only (default: skip already configured repos)

## Features

- 🔐 **Automatic authentication** - Tries multiple authentication methods
- 📄 **Pagination support** - Handles users with 100+ repositories
- 🔍 **Ownership filtering** - Only updates repositories you own
- ⚡ **Smart skipping** - Automatically skips repositories already configured for squash-only (efficient reruns and new repo handling)
- 📊 **Progress tracking** - Shows success, skipped, already configured, and failed counts
- ⏱️ **Performance metrics** - Displays elapsed time
- 🛡️ **Error handling** - Validates inputs and provides clear error messages

## Technical Details

This script uses a hybrid approach for GitHub API access:

- **GraphQL API** - Used to fetch repositories and their merge strategies in a single, efficient query with cursor-based pagination. This allows us to retrieve all repository information and merge strategy settings in fewer API calls.

- **REST API** - Used to update repository merge strategies. As of January 11, 2026, the GitHub GraphQL API does not support mutations for repository merge strategy settings, so the REST API is required for this operation. Therefore, we must call the REST endpoint for each repository individually to update its merge strategy settings.

- **Rate Limiting** - To avoid hitting GitHub's API rate limits, the script includes a configurable sleep interval between REST API requests (default: 0.1 seconds). Authenticated requests (OAuth or PAT) are limited to ~5,000 requests per hour per user or app. The sleep delay helps ensure we stay well below this limit when processing large numbers of repositories. See [GitHub's API rate limits documentation](https://github.com/orgs/community/discussions/163553) for more details.

## Output

The script provides:
- Real-time progress updates for each repository
- Success/failure status for each update
- A summary at the end showing:
  - Number of successfully updated repositories
  - Number of repositories already configured for squash-only (skipped)
  - Number of skipped repositories (not owned by you)
  - Number of failed updates (if any)
  - Total elapsed time

Example output:
```
────────────────────────────────────
Summary:
  ✅ Successfully updated: 5
  ⏭️  Already squash-only (skipped): 10
  ⏭️  Skipped (not owned by you): 3
  ⏱️  Elapsed time: 1m 15s
```

## Examples

Update all your repos with default settings:
```bash
# Using npx (recommended)
npx github:pRizz/squash-only

# Or run locally with npm
npm start

# Or using the bash script
./scripts/squash-only.sh
```

Update with a longer delay between requests:
```bash
# Using npx
npx github:pRizz/squash-only --sleep 1.0

# Or using the bash script
./scripts/squash-only.sh --sleep 1.0
```

Force update all repositories (including already configured):
```bash
# Using npx
npx github:pRizz/squash-only --force

# Or using the bash script
./scripts/squash-only.sh --force
```

Use with environment variable:
```bash
# Using npx
GITHUB_TOKEN=ghp_xxxxx npx github:pRizz/squash-only

# Or run locally with npm
GITHUB_TOKEN=ghp_xxxxx npm start

# Or using the bash script
GITHUB_TOKEN=ghp_xxxxx ./scripts/squash-only.sh
```
