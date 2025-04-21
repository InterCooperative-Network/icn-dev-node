#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Parse command line arguments
FORCE=false
COVM_PATH=""

# Process arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -f|--force)
      FORCE=true
      shift
      ;;
    -p|--path)
      COVM_PATH="$2"
      shift 2
      ;;
    *)
      if [ -z "$COVM_PATH" ] && [ -d "$1" ]; then
        COVM_PATH="$1"
      fi
      shift
      ;;
  esac
done

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
DEV_NODE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPS_DIR="$DEV_NODE_DIR/deps"
LINK_TARGET="$DEPS_DIR/icn-covm"
COVM_VERSION_FILE="$DEV_NODE_DIR/.covm-version"

# Check for icn-covm repo in various possible locations if not provided
if [ -z "$COVM_PATH" ]; then
  POSSIBLE_LOCATIONS=(
    "$DEV_NODE_DIR/../icn-covm"
    "$(cd ~ && pwd)/dev/icn-covm"
    "$(cd ~ && pwd)/icn-covm"
  )

  for loc in "${POSSIBLE_LOCATIONS[@]}"; do
    if [ -d "$loc" ] && [ -d "$loc/.git" ]; then
      COVM_PATH="$loc"
      break
    fi
  done
fi

# Verify the path exists and is a git repo
if [ -z "$COVM_PATH" ] || [ ! -d "$COVM_PATH" ] || [ ! -d "$COVM_PATH/.git" ]; then
  echo -e "${RED}Error: Could not find a valid icn-covm repository.${NC}"
  echo "Please provide the path to the icn-covm repository using the -p option:"
  echo "  $0 -p /path/to/icn-covm"
  echo ""
  echo "Searched locations:"
  for loc in "${POSSIBLE_LOCATIONS[@]}"; do
    echo "  - $loc"
  done
  exit 1
fi

echo -e "${GREEN}Found icn-covm repository at:${NC} $COVM_PATH"

# Check if both repos are clean (skipped if force is true)
if [ "$FORCE" != "true" ]; then
  echo "Checking repository status..."

  # Check dev-node status
  cd "$DEV_NODE_DIR"
  if [ -n "$(git status --porcelain)" ]; then
    echo -e "${YELLOW}Warning: icn-dev-node repository has uncommitted changes.${NC}"
    echo "Use --force to ignore uncommitted changes."
    exit 1
  fi

  # Check covm status
  cd "$COVM_PATH"
  if [ -n "$(git status --porcelain)" ]; then
    echo -e "${YELLOW}Warning: icn-covm repository has uncommitted changes.${NC}"
    echo "Use --force to ignore uncommitted changes."
    exit 1
  fi
fi

# Get current covm commit hash
cd "$COVM_PATH"
CURRENT_COVM_COMMIT=$(git rev-parse HEAD)

# Get back to dev-node directory
cd "$DEV_NODE_DIR"

# Check if .covm-version exists and compare
if [ -f "$COVM_VERSION_FILE" ]; then
  VERSION_COMMIT=$(cat "$COVM_VERSION_FILE")
  if [ "$VERSION_COMMIT" != "$CURRENT_COVM_COMMIT" ]; then
    echo -e "${YELLOW}⚠️ Warning: Local CoVM commit does not match .covm-version.${NC}"
    echo "Current commit: $CURRENT_COVM_COMMIT"
    echo "Version file:   $VERSION_COMMIT"
  else
    echo -e "${GREEN}CoVM commit matches .covm-version file.${NC}"
  fi
fi

# Remove existing directory or symlink if it exists
if [ -e "$LINK_TARGET" ]; then
  echo "Removing existing icn-covm in deps directory..."
  rm -rf "$LINK_TARGET"
fi

# Create deps directory if it doesn't exist
mkdir -p "$DEPS_DIR"

# Create the symlink
echo "Creating symlink to icn-covm repository..."
ln -s "$COVM_PATH" "$LINK_TARGET"

# Check if link creation was successful
if [ -L "$LINK_TARGET" ] && [ -e "$LINK_TARGET" ]; then
  echo -e "${GREEN}✓ Successfully linked CoVM for development!${NC}"
  echo -e "Changes made to ${YELLOW}$COVM_PATH${NC} will be immediately available in ${YELLOW}$DEV_NODE_DIR${NC}"
  echo ""
  echo -e "To build and test with your linked CoVM, run: ${GREEN}cargo build${NC} or ${GREEN}cargo test${NC}"
else
  echo -e "${RED}Failed to create symlink!${NC}"
  exit 1
fi

echo -e "${GREEN}Setup complete!${NC}" 