#!/usr/bin/env bash
set -euo pipefail

# Default settings
IDENTITY_NAME="user-$(date +%s)"
COOP_NAME="default-coop"
ROLE="member"
OUTPUT_DIR="../.wallet/identities"
VERBOSE=false
RELEASE_MODE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --name)
      IDENTITY_NAME="$2"
      shift 2
      ;;
    --coop)
      COOP_NAME="$2"
      shift 2
      ;;
    --role)
      ROLE="$2"
      if [[ ! "$ROLE" =~ ^(admin|member|observer)$ ]]; then
        echo "❌ Invalid role: $ROLE"
        echo "Valid roles: admin, member, observer"
        exit 1
      fi
      shift 2
      ;;
    --output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    --release)
      RELEASE_MODE=true
      shift
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo "Generate a scoped identity for ICN"
      echo ""
      echo "Options:"
      echo "  --name <name>       Identity name (default: user-timestamp)"
      echo "  --coop <coop>       Cooperative name (default: default-coop)"
      echo "  --role <role>       Identity role [admin|member|observer] (default: member)"
      echo "  --output <dir>      Output directory (default: ../.wallet/identities)"
      echo "  --verbose           Show detailed output"
      echo "  --release           Use release build of icn-node"
      echo "  --help              Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Run '$0 --help' for usage information"
      exit 1
      ;;
  esac
done

# Load environment variables if .env exists
if [[ -f ../.env ]]; then
  # shellcheck disable=SC1091
  source ../.env
fi

# Output directory setup
IDENTITY_DIR="$OUTPUT_DIR/$COOP_NAME"
IDENTITY_FILE="$IDENTITY_DIR/$IDENTITY_NAME.json"

# Function to check if the node binary exists
check_node_binary() {
  local binary_path
  if [[ "$RELEASE_MODE" = true ]]; then
    binary_path="../deps/icn-covm/target/release/icn-node"
  else
    binary_path="../deps/icn-covm/target/debug/icn-node"
  fi

  if [[ ! -f "$binary_path" ]]; then
    echo "❌ Node binary not found at $binary_path"
    echo "Please run install.sh first or check that the build completed successfully."
    exit 1
  fi

  echo "✅ Node binary found at $binary_path"
  NODE_BINARY="$binary_path"
}

# Create a scoped identity
generate_identity() {
  echo "Generating scoped identity..."
  echo "  - Identity: $IDENTITY_NAME"
  echo "  - Cooperative: $COOP_NAME"
  echo "  - Role: $ROLE"
  
  # Create output directory if it doesn't exist
  mkdir -p "$IDENTITY_DIR"
  
  # Check if identity already exists
  if [[ -f "$IDENTITY_FILE" ]]; then
    echo "⚠️ Identity already exists at $IDENTITY_FILE"
    read -p "Overwrite? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "Exiting without overwriting."
      exit 0
    fi
  fi
  
  # Generate identity using icn-node CLI
  # This is a placeholder for the actual command - adjust based on actual CLI
  local create_output
  
  # Log the command if verbose
  if [[ "$VERBOSE" = true ]]; then
    echo "Executing: $NODE_BINARY identity create --name $IDENTITY_NAME --scope $COOP_NAME --role $ROLE --output $IDENTITY_FILE"
  fi
  
  # Example of calling the binary - replace with actual CLI command for identity creation
  create_output=$("$NODE_BINARY" identity create \
                  --name "$IDENTITY_NAME" \
                  --scope "$COOP_NAME" \
                  --role "$ROLE" \
                  --output "$IDENTITY_FILE" 2>&1) || {
    echo "❌ Failed to create identity"
    if [[ "$VERBOSE" = true ]]; then
      echo "Error: $create_output"
    fi
    exit 1
  }
  
  # Print result
  if [[ "$VERBOSE" = true ]]; then
    echo "$create_output"
  fi
  
  # Verify the identity was created
  if [[ -f "$IDENTITY_FILE" ]]; then
    echo "✅ Identity created successfully at $IDENTITY_FILE"
    
    # Display basic info from the identity file (assumes JSON format)
    if command -v jq >/dev/null 2>&1; then
      echo "Identity Info:"
      jq -r '. | {id, scope, role, created_at}' "$IDENTITY_FILE" 2>/dev/null || echo "Could not parse identity file"
    else
      echo "Install 'jq' to view identity details"
    fi
  else
    echo "❌ Identity file not found after creation"
    exit 1
  fi
}

# Main script execution
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

check_node_binary
generate_identity 