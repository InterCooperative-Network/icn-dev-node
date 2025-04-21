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
COVM_DIR="$DEV_NODE_DIR/deps/icn-covm"
COVM_VERSION_FILE="$DEV_NODE_DIR/.covm-version"

# Helper function to print usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help       Display this help message"
    echo "  --quiet      Only output on error, useful for CI"
    echo "  --update     Update .covm-version to match the current repo"
    echo ""
    exit 1
}

# Parse arguments
QUIET=false
UPDATE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            usage
            ;;
        --quiet)
            QUIET=true
            shift
            ;;
        --update)
            UPDATE=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
    esac
done

# Ensure we're in the right directory
if [ ! -f "$DEV_NODE_DIR/Cargo.toml" ]; then
    echo -e "${RED}Error: Not running from the icn-dev-node repository${NC}"
    exit 1
fi

# Check if .covm-version exists
if [ ! -f "$COVM_VERSION_FILE" ]; then
    if [ "$QUIET" != "true" ]; then
        echo -e "${YELLOW}Warning: .covm-version file not found${NC}"
        echo "You should create this file to lock the CoVM version:"
        echo "  echo \$(cd ../icn-covm && git rev-parse HEAD) > .covm-version"
    fi
    exit 1
fi

# Check if deps/icn-covm exists
if [ ! -d "$COVM_DIR" ] || [ ! -d "$COVM_DIR/.git" ]; then
    if [ "$QUIET" != "true" ]; then
        echo -e "${RED}Error: CoVM not linked in deps/icn-covm${NC}"
        echo "Run the following command to set up CoVM:"
        echo "  make link-covm"
    fi
    exit 1
fi

# Get the expected version from .covm-version
EXPECTED_VERSION=$(cat "$COVM_VERSION_FILE")
if [ -z "$EXPECTED_VERSION" ]; then
    if [ "$QUIET" != "true" ]; then
        echo -e "${RED}Error: .covm-version file is empty${NC}"
    fi
    exit 1
fi

# Get the actual version from deps/icn-covm
cd "$COVM_DIR"
ACTUAL_VERSION=$(git rev-parse HEAD)

# Update .covm-version if requested
if [ "$UPDATE" = "true" ]; then
    if [ "$QUIET" != "true" ]; then
        echo -e "Updating .covm-version to ${GREEN}$ACTUAL_VERSION${NC}"
    fi
    echo "$ACTUAL_VERSION" > "$COVM_VERSION_FILE"
    exit 0
fi

# Compare versions
if [ "$EXPECTED_VERSION" = "$ACTUAL_VERSION" ]; then
    if [ "$QUIET" != "true" ]; then
        echo -e "${GREEN}✓ CoVM version matches .covm-version (${EXPECTED_VERSION:0:8})${NC}"
    fi
    exit 0
else
    if [ "$QUIET" != "true" ]; then
        echo -e "${RED}✗ CoVM version mismatch!${NC}"
        echo -e "Expected: ${YELLOW}$EXPECTED_VERSION${NC}"
        echo -e "Actual:   ${YELLOW}$ACTUAL_VERSION${NC}"
        echo ""
        echo "To fix this, either:"
        echo "  1. Run 'make link-covm' to update the linked CoVM"
        echo "  2. Update .covm-version with the current version:"
        echo "     echo \"$ACTUAL_VERSION\" > .covm-version"
    fi
    exit 1
fi 