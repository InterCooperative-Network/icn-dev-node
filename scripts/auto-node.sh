#!/bin/bash
set -euo pipefail

# ICN Auto Node
# A unified script that sets up and runs a fully autonomous ICN node

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Default values
NODE_TYPE="dev"
COOP_NAME="default"
AUTO_REGISTER=false
ENABLE_EVENTS=true
ENABLE_AGORANET=true
AUTO_UPDATE=false
VERBOSE=false

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Set up and run a fully autonomous ICN node with all features enabled.

Options:
  --node-type TYPE       Node type: 'dev', 'testnet', or 'livenet' (default: dev)
  --coop NAME            Cooperative name (default: default)
  --auto-register        Automatically register DNS and DID
  --no-events            Disable event monitoring
  --no-agoranet          Disable AgoraNet integration
  --auto-update          Enable automatic updates
  --verbose              Enable verbose logging
  --help                 Display this help message and exit

Example:
  $(basename "$0") --node-type testnet --coop "my-cooperative" --auto-register
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --node-type)
        NODE_TYPE="$2"
        shift 2
        ;;
      --coop)
        COOP_NAME="$2"
        shift 2
        ;;
      --auto-register)
        AUTO_REGISTER=true
        shift
        ;;
      --no-events)
        ENABLE_EVENTS=false
        shift
        ;;
      --no-agoranet)
        ENABLE_AGORANET=false
        shift
        ;;
      --auto-update)
        AUTO_UPDATE=true
        shift
        ;;
      --verbose)
        VERBOSE=true
        shift
        ;;
      --help)
        print_usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1"
        print_usage
        exit 1
        ;;
    esac
  done
}

setup_auto_node() {
  log_info "Setting up autonomous ICN node"
  
  # 1. Check dependencies
  log_info "Checking dependencies..."
  check_dependencies || {
    log_error "Missing dependencies, please install them first"
    exit 1
  }
  
  # 2. Build/update node if needed or requested
  if [[ "$AUTO_UPDATE" == true ]] || ! is_binary_built "icn-node"; then
    log_info "Building/updating ICN node..."
    "${SCRIPT_DIR}/install.sh" --verbose || {
      log_error "Failed to build/update ICN node"
      exit 1
    }
  fi
  
  # 3. Start the daemon
  log_info "Starting ICN node daemon..."
  local daemon_cmd="${SCRIPT_DIR}/daemon.sh"
  daemon_cmd+=" --node-type ${NODE_TYPE}"
  [[ "$AUTO_REGISTER" == true ]] && daemon_cmd+=" --auto-register"
  [[ "$VERBOSE" == true ]] && daemon_cmd+=" --verbose"
  
  eval "$daemon_cmd" || {
    log_error "Failed to start ICN node daemon"
    exit 1
  }
  
  # 4. Wait for node to start
  log_info "Waiting for node to start..."
  local retries=0
  while ! is_node_running && [[ $retries -lt 30 ]]; do
    sleep 2
    retries=$((retries + 1))
  done
  
  if ! is_node_running; then
    log_error "Node failed to start within the timeout period"
    exit 1
  fi
  
  log_info "Node started successfully"
  
  # 5. Start event listener if enabled
  if [[ "$ENABLE_EVENTS" == true ]]; then
    log_info "Starting event listener..."
    local events_cmd="${SCRIPT_DIR}/event-listener.sh"
    events_cmd+=" --daemon"
    [[ "$VERBOSE" == true ]] && events_cmd+=" --verbose"
    
    eval "$events_cmd" || log_warn "Failed to start event listener"
  fi
  
  # 6. Start AgoraNet if enabled
  if [[ "$ENABLE_AGORANET" == true ]]; then
    log_info "Starting AgoraNet integration..."
    local agoranet_cmd="${SCRIPT_DIR}/agoranet-integration.sh"
    agoranet_cmd+=" --coop \"${COOP_NAME}\""
    agoranet_cmd+=" --daemon --start"
    [[ "$VERBOSE" == true ]] && agoranet_cmd+=" --verbose"
    
    eval "$agoranet_cmd" || log_warn "Failed to start AgoraNet integration"
  fi
  
  # 7. Display status
  log_info "Autonomous node setup complete!"
  get_node_status
  
  # 8. Display helpful information
  cat <<EOF

Your autonomous ICN node is now running!

Node type:    ${NODE_TYPE}
Cooperative:  ${COOP_NAME}
Events:       $(if [[ "$ENABLE_EVENTS" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)
AgoraNet:     $(if [[ "$ENABLE_AGORANET" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)

To view node logs:
  tail -f ~/.icn/logs/node.log

To stop the node:
  ${SCRIPT_DIR}/daemon.sh stop
  
To check node status:
  ${SCRIPT_DIR}/daemon.sh status

EOF
}

main() {
  parse_args "$@"
  setup_auto_node
}

main "$@" 