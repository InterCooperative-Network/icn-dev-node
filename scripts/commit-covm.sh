#!/bin/bash
set -euo pipefail

# Check if a commit message was provided
if [ $# -eq 0 ]; then
  echo "Usage: $0 \"Commit message\""
  echo "Example: $0 \"Add scoped identity enforcement\""
  exit 1
fi

MESSAGE="$1"
UPDATE_PARENT_REPO=${2:-"true"}  # Default to updating parent repo's .covm-version

# Check if deps/icn-covm exists
if [ ! -d "deps/icn-covm" ]; then
  echo "❌ Error: deps/icn-covm directory does not exist."
  echo "Please run ./scripts/install.sh first to set up dependencies."
  exit 1
fi

# Check if deps/icn-covm is a git repository
if [ ! -d "deps/icn-covm/.git" ]; then
  echo "❌ Error: deps/icn-covm is not a Git repository."
  exit 1
fi

# Commit changes in the CoVM repository
echo "📍 Committing changes to CoVM repository:"
cd deps/icn-covm

# Show what's going to be committed
git status --short

# Confirm with the user
read -p "Continue with commit? (y/n) " -n 1 -r
echo    # Move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "❌ Commit aborted."
  exit 1
fi

# Proceed with the commit
git add .
git commit -m "$MESSAGE"

# Get the new commit hash
COMMIT_HASH=$(git rev-parse HEAD)
echo "✅ Changes committed to CoVM repository. Commit hash: $COMMIT_HASH"

# Optionally push the changes
read -p "Push changes to remote repository? (y/n) " -n 1 -r
echo    # Move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]; then
  git push
  echo "✅ Changes pushed to remote repository."
fi

# Update the parent repository's .covm-version file
if [ "$UPDATE_PARENT_REPO" = "true" ]; then
  cd ../..
  echo "$COMMIT_HASH" > .covm-version
  echo "✅ Updated .covm-version file in parent repository."
  
  # Ask if they want to commit the .covm-version file in the parent repo
  read -p "Commit .covm-version in parent repository? (y/n) " -n 1 -r
  echo    # Move to a new line
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    git add .covm-version
    git commit -m "Track CoVM commit: $COMMIT_HASH"
    echo "✅ Committed .covm-version in parent repository."
  else
    echo "ℹ️  .covm-version updated but not committed."
  fi
fi

echo "✅ All done!" 