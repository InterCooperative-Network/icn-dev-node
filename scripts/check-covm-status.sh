#!/bin/bash
set -e

# Check if deps/icn-covm exists
if [ ! -d "deps/icn-covm" ]; then
  echo "❌ Error: deps/icn-covm directory does not exist."
  echo "Please run ./scripts/install.sh first to set up dependencies."
  exit 1
fi

cd deps/icn-covm

if [ ! -d ".git" ]; then
  echo "❌ Error: deps/icn-covm is not a Git repository."
  echo "It may have been installed without Git history."
  exit 1
fi

echo "📍 CoVM Status:"
echo "Branch: $(git rev-parse --abbrev-ref HEAD)"
echo "Commit: $(git rev-parse HEAD)"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "⚠️  Warning: You have uncommitted changes in icn-covm!"
  echo "🧠 Please commit them from inside deps/icn-covm to keep history clean."
  git status --short
else
  echo "✅ CoVM is clean."
fi

# Check if the commit hash is tracked in the parent repo
cd ../..
if [ -f ".covm-version" ]; then
  TRACKED_HASH=$(cat .covm-version)
  CURRENT_HASH=$(cd deps/icn-covm && git rev-parse HEAD)
  
  if [ "$TRACKED_HASH" = "$CURRENT_HASH" ]; then
    echo "✅ .covm-version matches current commit."
  else
    echo "⚠️  Warning: .covm-version ($TRACKED_HASH) differs from current commit ($CURRENT_HASH)."
    echo "Consider updating .covm-version with ./scripts/commit-covm.sh"
  fi
else
  echo "ℹ️  No .covm-version file found. Consider creating one to track the CoVM commit."
fi 