#!/usr/bin/env bash
set -euo pipefail

# Default settings
RELEASE_MODE=false
LOG_LEVEL="info"
NODE_NAME="testnet-node-$(date +%s)"
DATA_DIR="$HOME/.icn-testnet"
CONFIG_FILE="../config/testnet-config.toml"
BOOTSTRAP_PEERS_FILE="../config/bootstrap-peers.toml"
VALIDATE_PEERS=true
RETRY_COUNT=3

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
    --bootstrap-peers)
      BOOTSTRAP_PEERS_FILE="$2"
      shift 2
      ;;
    --no-validate-peers)
      VALIDATE_PEERS=false
      shift
      ;;
    --retry)
      RETRY_COUNT="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--release] [--log-level <level>] [--node-name <name>] [--data-dir <dir>] [--config <file>] [--bootstrap-peers <file>] [--no-validate-peers] [--retry <count>]"
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
    
    # Apply testnet configuration if config file exists
    if [[ -f "$CONFIG_FILE" ]]; then
      echo "Applying testnet configuration from $CONFIG_FILE..."
      cp "$CONFIG_FILE" "$DATA_DIR/config/config.toml"
    else
      echo "⚠️ Testnet configuration file not found at $CONFIG_FILE"
      echo "Will use default configuration, but peer connections may not work correctly."
    fi
  else
    echo "Node already initialized at $DATA_DIR"
    
    # Update testnet configuration if requested
    if [[ -f "$CONFIG_FILE" ]]; then
      echo "Updating testnet configuration from $CONFIG_FILE..."
      cp "$CONFIG_FILE" "$DATA_DIR/config/config.toml"
    fi
  fi
}

# Parse the bootstrap peers from the TOML file
parse_bootstrap_peers() {
  local peers_file="$1"
  
  if [[ ! -f "$peers_file" ]]; then
    echo "⚠️ Bootstrap peers file not found at $peers_file"
    return 1
  fi
  
  # Extract peers from bootstrap-peers.toml using grep and sed
  # This is a basic parser for TOML arrays; for more complex TOML parsing, consider using a dedicated tool
  local peers
  peers=$(grep -A 10 '^\[bootstrap\]' "$peers_file" | grep -o 'peers = \[.*\]' | sed 's/peers = \[\(.*\)\]/\1/' | tr -d ' "')
  
  # Split the comma-separated list
  local IFS=','
  read -ra PEERS_ARRAY <<< "$peers"
  
  # Join with commas for the output format
  local joined_peers
  joined_peers=$(IFS=,; echo "${PEERS_ARRAY[*]}")
  
  echo "$joined_peers"
}

# Validate if peers are reachable
validate_peers() {
  local peer_list="$1"
  local validated_peers=()
  local success_count=0
  
  echo "Validating bootstrap peers..."
  
  # Split the peer list by commas
  IFS=',' read -ra PEER_ARRAY <<< "$peer_list"
  
  for peer in "${PEER_ARRAY[@]}"; do
    # Extract host and port from peer (format: node_id@host:port)
    local host
    local port
    host=$(echo "$peer" | cut -d '@' -f2 | cut -d ':' -f1)
    port=$(echo "$peer" | cut -d ':' -f2)
    
    echo -n "  - Testing connection to $host:$port... "
    
    # Try to establish a TCP connection to check if the peer is reachable
    if timeout 5 bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null; then
      echo "✅ Success"
      validated_peers+=("$peer")
      ((success_count++))
    else
      echo "❌ Failed"
    fi
    
    # Close the file descriptor if it was opened
    exec 3>&- 2>/dev/null || true
  done
  
  if [[ ${#validated_peers[@]} -eq 0 ]]; then
    echo "❌ No reachable bootstrap peers found!"
    return 1
  fi
  
  echo "✅ Found $success_count reachable bootstrap peers"
  
  # Join the validated peers with commas
  local result
  result=$(IFS=,; echo "${validated_peers[*]}")
  echo "$result"
}

# Get bootstrap peers from multiple sources
get_bootstrap_peers() {
  local bootstrap_peers="${BOOTSTRAP_PEERS:-}"
  
  # If BOOTSTRAP_PEERS is set in .env, use that
  if [[ -n "$bootstrap_peers" ]]; then
    echo "Using bootstrap peers from environment: $bootstrap_peers"
    echo "$bootstrap_peers"
    return 0
  fi
  
  # Try to get peers from bootstrap-peers.toml
  if [[ -f "$BOOTSTRAP_PEERS_FILE" ]]; then
    bootstrap_peers=$(parse_bootstrap_peers "$BOOTSTRAP_PEERS_FILE")
    if [[ -n "$bootstrap_peers" ]]; then
      echo "Using bootstrap peers from $BOOTSTRAP_PEERS_FILE"
      
      # Validate peers if requested
      if [[ "$VALIDATE_PEERS" = true ]]; then
        bootstrap_peers=$(validate_peers "$bootstrap_peers") || {
          echo "Peer validation failed, but continuing with the available list."
          # Use the original list if validation fails completely
          bootstrap_peers=$(parse_bootstrap_peers "$BOOTSTRAP_PEERS_FILE")
        }
      fi
      
      echo "$bootstrap_peers"
      return 0
    fi
  fi
  
  # Try to extract from config file as a last resort
  if [[ -f "$CONFIG_FILE" ]]; then
    bootstrap_peers=$(grep -oP 'persistent_peers\s*=\s*"\K[^"]+' "$CONFIG_FILE" || echo "")
    if [[ -n "$bootstrap_peers" ]]; then
      echo "Using bootstrap peers from $CONFIG_FILE"
      echo "$bootstrap_peers"
      return 0
    fi
  fi
  
  echo "⚠️ No bootstrap peers found in any configuration source."
  echo "The node may not connect to the testnet without peers."
  echo ""
  return 1
}

# Start the node
start_node() {
  local peers=""
  local peers_flag=""
  
  # Try to get bootstrap peers with retry logic
  for ((i=1; i<=RETRY_COUNT; i++)); do
    echo "Attempt $i/$RETRY_COUNT to get bootstrap peers..."
    if peers=$(get_bootstrap_peers); then
      break
    elif [[ $i -lt $RETRY_COUNT ]]; then
      echo "Retrying in 5 seconds..."
      sleep 5
    fi
  done
  
  if [[ -n "$peers" ]]; then
    peers_flag="--p2p.persistent_peers $peers"
  fi
  
  echo "Starting ICN node to join testnet..."
  echo "  - Name: $NODE_NAME"
  echo "  - Data directory: $DATA_DIR"
  echo "  - Log level: $LOG_LEVEL"
  
  # shellcheck disable=SC2086
  "$NODE_BINARY" start --home "$DATA_DIR" --federation --storage --log-level "$LOG_LEVEL" $peers_flag
}

# Main script execution
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

check_node_binary
create_data_dir
init_node
start_node 