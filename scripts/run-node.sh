#!/usr/bin/env bash
set -euo pipefail

# Default settings
RELEASE_MODE=false
LOG_LEVEL="info"
NODE_NAME="local-node-$(date +%s)"
DATA_DIR="$HOME/.icn-node"
CONFIG_FILE="../config/dev-config.toml"
FEDERATION_ENABLED=true
STORAGE_ENABLED=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --release)
      RELEASE_MODE=true
      shift
      ;;
    --log-level)
      LOG_LEVEL="$2"
      shift 2
      ;;
    --node-name)
      NODE_NAME="$2"
      shift 2
      ;;
    --data-dir)
      DATA_DIR="$2"
      shift 2
      ;;
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    --no-federation)
      FEDERATION_ENABLED=false
      shift
      ;;
    --no-storage)
      STORAGE_ENABLED=false
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--release] [--log-level <level>] [--node-name <n>] [--data-dir <dir>] [--config <file>] [--no-federation] [--no-storage]"
      exit 1
      ;;
  esac
done

# Load environment variables if .env exists
if [[ -f ../.env ]]; then
  # shellcheck disable=SC1091
  source ../.env
fi

# Function to check if the node binary exists
check_node_binary() {
  local binary_path
  if [[ "$RELEASE_MODE" = true ]]; then
    binary_path="../target/release/icn-node"
  else
    binary_path="../target/debug/icn-node"
  fi

  if [[ ! -f "$binary_path" ]]; then
    echo "❌ Node binary not found at $binary_path"
    echo "Please run 'cargo build' first or check that the build completed successfully."
    exit 1
  fi

  echo "✅ Node binary found at $binary_path"
  echo "NODE_BINARY=$binary_path"
  export NODE_BINARY="$binary_path"
}

# Create data directory if it doesn't exist
create_data_dir() {
  if [[ ! -d "$DATA_DIR" ]]; then
    echo "Creating data directory at $DATA_DIR..."
    mkdir -p "$DATA_DIR"
  fi
}

# Initialize the node if needed
init_node() {
  if [[ ! -d "$DATA_DIR/config" ]]; then
    echo "Initializing node with name '$NODE_NAME'..."
    "$NODE_BINARY" init --home "$DATA_DIR" --moniker "$NODE_NAME"
    
    # Apply custom configuration if config file exists
    if [[ -f "$CONFIG_FILE" ]]; then
      echo "Applying custom configuration from $CONFIG_FILE..."
      cp "$CONFIG_FILE" "$DATA_DIR/config/config.toml"
    fi
  else
    echo "Node already initialized at $DATA_DIR"
  fi
}

# Start the node
start_node() {
  local federation_flag=""
  local storage_flag=""
  
  if [[ "$FEDERATION_ENABLED" = true ]]; then
    federation_flag="--federation"
  fi
  
  if [[ "$STORAGE_ENABLED" = true ]]; then
    storage_flag="--storage"
  fi
  
  echo "Starting ICN node with integrated CoVM..."
  echo "  - Name: $NODE_NAME"
  echo "  - Data directory: $DATA_DIR"
  echo "  - Federation enabled: $FEDERATION_ENABLED"
  echo "  - Storage enabled: $STORAGE_ENABLED"
  echo "  - Log level: $LOG_LEVEL"
  
  # shellcheck disable=SC2086
  "$NODE_BINARY" start --home "$DATA_DIR" $federation_flag $storage_flag --log-level "$LOG_LEVEL"
}

# Main script execution
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

check_node_binary
create_data_dir
init_node
start_node 