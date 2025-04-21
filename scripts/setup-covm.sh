#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Path variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
DEV_NODE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COVM_REPO="$DEV_NODE_DIR/../icn-covm"
DEPS_DIR="$DEV_NODE_DIR/deps"
TARGET_DIR="$DEPS_DIR/icn-covm"
COVM_VERSION_FILE="$DEV_NODE_DIR/.covm-version"

# Ensure we're in the right directory structure
cd "$DEV_NODE_DIR"

if [ ! -f Cargo.toml ]; then
  echo -e "${RED}Error: Not in icn-dev-node root. Please run this script from the repository root.${NC}"
  exit 1
fi

# Check if COVM repository exists
if [ ! -d "$COVM_REPO" ] || [ ! -d "$COVM_REPO/.git" ]; then
  echo -e "${RED}Error: icn-covm repository not found at $COVM_REPO${NC}"
  echo -e "Please clone the CoVM repository:"
  echo -e "  git clone <covm-repo-url> $COVM_REPO"
  exit 1
fi

# Get current CoVM commit hash
cd "$COVM_REPO"
CURRENT_COVM_COMMIT=$(git rev-parse HEAD)
COVM_CHANGES=$(git status --porcelain)

# Check for uncommitted changes in CoVM
if [ -n "$COVM_CHANGES" ]; then
  echo -e "${YELLOW}Warning: icn-covm repository has uncommitted changes.${NC}"
  echo -e "If this is intentional for development, you can proceed."
  echo -e "Run ${YELLOW}git status${NC} in the CoVM repository to see changes."
fi

# Return to the node directory
cd "$DEV_NODE_DIR"

# Check if .covm-version exists and compare
if [ -f "$COVM_VERSION_FILE" ]; then
  VERSION_COMMIT=$(cat "$COVM_VERSION_FILE")
  if [ "$VERSION_COMMIT" != "$CURRENT_COVM_COMMIT" ]; then
    echo -e "${YELLOW}⚠️ Warning: Local CoVM commit does not match .covm-version.${NC}"
    echo -e "Current CoVM commit: ${YELLOW}$CURRENT_COVM_COMMIT${NC}"
    echo -e "Expected version:    ${YELLOW}$VERSION_COMMIT${NC}"
    echo -e "If you're testing new changes, this is fine."
  else
    echo -e "${GREEN}✓ CoVM commit matches .covm-version file.${NC}"
  fi
fi

# Remove existing copy if it exists
if [ -e "$TARGET_DIR" ]; then
  echo "Removing existing icn-covm in deps directory..."
  rm -rf "$TARGET_DIR"
fi

# Create deps directory if it doesn't exist
mkdir -p "$DEPS_DIR"

# Copy CoVM repository (create a fresh copy)
echo "Creating a copy of icn-covm repository..."
cp -r "$COVM_REPO" "$TARGET_DIR"

# Check if the copy was successful
if [ -d "$TARGET_DIR" ] && [ -d "$TARGET_DIR/crates/icn-covm" ]; then
  echo -e "${GREEN}✓ Successfully copied CoVM for development!${NC}"
  echo -e "Changes made to ${YELLOW}$COVM_REPO${NC} will be available in the node after running this script again."
  echo ""
  echo -e "To build and test with the current CoVM, run: ${GREEN}cargo build -p icn-node${NC}"
else
  echo -e "${RED}Failed to copy CoVM repository!${NC}"
  exit 1
fi

# Optionally update .covm-version with current commit
if [ ! -f "$COVM_VERSION_FILE" ] || [ -n "$COVM_CHANGES" ]; then
  echo ""
  echo -e "${YELLOW}Note:${NC} If you want to lock to this version of CoVM, run:"
  echo -e "  echo $CURRENT_COVM_COMMIT > .covm-version"
fi

echo -e "${GREEN}Setup complete!${NC}" 