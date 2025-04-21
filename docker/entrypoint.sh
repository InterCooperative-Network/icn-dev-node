#!/bin/bash
set -euo pipefail

# Default node name
NODE_NAME=${NODE_NAME:-"docker-node-$(date +%s)"}
# Default values
DATA_DIR=${DATA_DIR:-"/data"}
FEDERATION_ENABLED=${FEDERATION_ENABLED:-"true"}
STORAGE_ENABLED=${STORAGE_ENABLED:-"true"}
LOG_LEVEL=${LOG_LEVEL:-"info"}

# Initialize the node if needed
if [[ ! -d "$DATA_DIR/config" ]]; then
  echo "Initializing node with name '$NODE_NAME'..."
  icn-node init --home "$DATA_DIR" --moniker "$NODE_NAME"
  
  # Apply custom configuration from environment
  if [[ -n "${BOOTSTRAP_PEERS:-}" ]]; then
    echo "Setting persistent peers: $BOOTSTRAP_PEERS"
    sed -i "s/^persistent_peers *=.*/persistent_peers = \"$BOOTSTRAP_PEERS\"/" "$DATA_DIR/config/config.toml"
  fi
  
  # Apply other custom config options
  if [[ -n "${P2P_PORT:-}" ]]; then
    sed -i "s/^laddr *=.*/laddr = \"tcp:\/\/0.0.0.0:$P2P_PORT\"/" "$DATA_DIR/config/config.toml"
  fi
  
  if [[ -n "${RPC_PORT:-}" ]]; then
    sed -i "s/^laddr *=.*/laddr = \"tcp:\/\/0.0.0.0:$RPC_PORT\"/" "$DATA_DIR/config/config.toml"
  fi
fi

# Build command line arguments
ARGS=("$@")

# Add federation flag if enabled
if [[ "$FEDERATION_ENABLED" == "true" ]]; then
  ARGS+=("--federation")
fi

# Add storage flag if enabled
if [[ "$STORAGE_ENABLED" == "true" ]]; then
  ARGS+=("--storage")
fi

# Add log level
ARGS+=("--log-level" "$LOG_LEVEL")

# Execute the command
echo "Starting ICN node with args: ${ARGS[*]}"
exec icn-node "${ARGS[@]}" 