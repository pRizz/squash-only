# squash-only

A bash script to automatically configure all your GitHub repositories to use squash-only merge strategy.

## What it does

This script updates all repositories you own on GitHub to:
- ✅ Enable squash merges
- ❌ Disable merge commits
- ❌ Disable rebase merges

It automatically skips repositories you don't own and provides a summary of the results.

## Requirements

- `bash` (version 4+)
- `curl`
- `jq`
- GitHub authentication (see below)

**Note:** If using the Node.js binary wrapper, you'll also need Node.js installed.

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

### Option 3: Install Globally via npm/pnpm

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

# Or using the bash script directly
./scripts/squash-only.sh
```

### Custom sleep interval
Control the delay between API requests (default: 0.2 seconds):
```bash
# Using npx
npx github:pRizz/squash-only --sleep 0.5

# Or using the bash script
./scripts/squash-only.sh --sleep 0.5
# or
./scripts/squash-only.sh -s 1.0
```

## Options

- `-s, --sleep SECONDS` - Set the sleep interval between API requests (must be a number)

## Features

- 🔐 **Automatic authentication** - Tries multiple authentication methods
- 📄 **Pagination support** - Handles users with 100+ repositories
- 🔍 **Ownership filtering** - Only updates repositories you own
- 📊 **Progress tracking** - Shows success, skipped, and failed counts
- ⏱️ **Performance metrics** - Displays elapsed time
- 🛡️ **Error handling** - Validates inputs and provides clear error messages

## Output

The script provides:
- Real-time progress updates for each repository
- Success/failure status for each update
- A summary at the end showing:
  - Number of successfully updated repositories
  - Number of skipped repositories (not owned by you)
  - Number of failed updates (if any)
  - Total elapsed time

Example output:
```
────────────────────────────────────
Summary:
  ✅ Successfully updated: 15
  ⏭️  Skipped: 3
  ⏱️  Elapsed time: 2m 30s
```

## Examples

Update all your repos with default settings:
```bash
# Using npx (recommended)
npx github:pRizz/squash-only

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

Use with environment variable:
```bash
# Using npx
GITHUB_TOKEN=ghp_xxxxx npx github:pRizz/squash-only

# Or using the bash script
GITHUB_TOKEN=ghp_xxxxx ./scripts/squash-only.sh
```
