#!/bin/bash
set -euo pipefail

# ICN Node Daemon Script
# Runs an ICN node as a service with auto-join capability

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Default values
NODE_TYPE="dev"  # Options: dev, testnet, livenet
DATA_DIR="${HOME}/.icn"
NODE_NAME="icn-node-$(hostname)"
LOG_FILE="${DATA_DIR}/logs/node.log"
PID_FILE="${DATA_DIR}/node.pid"
CONFIG_FILE=""
BOOTSTRAP_PEERS=""
AUTO_REGISTER=false
FEDERATION=true
STORAGE=true
VERBOSE=false
RESTART_DELAY=30

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Run the ICN node as a daemon service with auto-join capability.

Options:
  --node-type TYPE       Node type: 'dev', 'testnet', or 'livenet' (default: dev)
  --data-dir DIR         Data directory (default: ~/.icn)
  --node-name NAME       Node name (default: icn-node-HOSTNAME)
  --log-file FILE        Log file path (default: DATA_DIR/logs/node.log)
  --config FILE          Custom config file path
  --bootstrap-peers FILE Bootstrap peers file for testnet/livenet
  --auto-register        Automatically register DNS and DID
  --no-federation        Disable federation
  --no-storage           Disable storage
  --no-restart           Don't automatically restart on failure
  --verbose              Enable verbose logging
  --help                 Display this help message and exit

Example:
  $(basename "$0") --node-type testnet --auto-register
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --node-type)
        NODE_TYPE="$2"
        shift 2
        ;;
      --data-dir)
        DATA_DIR="$2"
        LOG_FILE="${DATA_DIR}/logs/node.log"
        PID_FILE="${DATA_DIR}/node.pid"
        shift 2
        ;;
      --node-name)
        NODE_NAME="$2"
        shift 2
        ;;
      --log-file)
        LOG_FILE="$2"
        shift 2
        ;;
      --config)
        CONFIG_FILE="$2"
        shift 2
        ;;
      --bootstrap-peers)
        BOOTSTRAP_PEERS="$2"
        shift 2
        ;;
      --auto-register)
        AUTO_REGISTER=true
        shift
        ;;
      --no-federation)
        FEDERATION=false
        shift
        ;;
      --no-storage)
        STORAGE=false
        shift
        ;;
      --no-restart)
        RESTART_DELAY=0
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

validate_args() {
  if [[ ! "$NODE_TYPE" =~ ^(dev|testnet|livenet)$ ]]; then
    echo "Error: Node type must be 'dev', 'testnet', or 'livenet'"
    exit 1
  fi
  
  # Create necessary directories
  mkdir -p "$(dirname "$LOG_FILE")"
  mkdir -p "${DATA_DIR}/config"
  
  # Set default config file if not specified
  if [[ -z "$CONFIG_FILE" ]]; then
    case "$NODE_TYPE" in
      dev)
        CONFIG_FILE="${SCRIPT_DIR}/../config/dev-config.toml"
        ;;
      testnet)
        CONFIG_FILE="${SCRIPT_DIR}/../config/testnet-config.toml"
        ;;
      livenet)
        CONFIG_FILE="${SCRIPT_DIR}/../config/livenet-config.toml"
        ;;
    esac
  fi
  
  # Set default bootstrap peers file if not specified and needed
  if [[ -z "$BOOTSTRAP_PEERS" && "$NODE_TYPE" != "dev" ]]; then
    BOOTSTRAP_PEERS="${SCRIPT_DIR}/../config/bootstrap-peers.toml"
  fi
  
  # Validate files exist
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Config file not found: $CONFIG_FILE"
    exit 1
  fi
  
  if [[ "$NODE_TYPE" != "dev" && ! -f "$BOOTSTRAP_PEERS" ]]; then
    echo "Error: Bootstrap peers file not found: $BOOTSTRAP_PEERS"
    exit 1
  fi
}

start_node() {
  log_info "Starting ICN node in daemon mode..."
  
  # Build the run command based on node type
  local cmd
  if [[ "$NODE_TYPE" == "dev" ]]; then
    cmd="${SCRIPT_DIR}/run-node.sh"
    cmd+=" --node-name \"${NODE_NAME}\""
    cmd+=" --data-dir \"${DATA_DIR}\""
    
    # Add optional flags
    [[ "$FEDERATION" == false ]] && cmd+=" --no-federation"
    [[ "$STORAGE" == false ]] && cmd+=" --no-storage"
    [[ "$VERBOSE" == true ]] && cmd+=" --verbose"
  else
    cmd="${SCRIPT_DIR}/join-testnet.sh"
    [[ "$NODE_TYPE" == "livenet" ]] && cmd+=" --livenet"
    cmd+=" --node-name \"${NODE_NAME}\""
    cmd+=" --data-dir \"${DATA_DIR}\""
    cmd+=" --config \"${CONFIG_FILE}\""
    cmd+=" --bootstrap-peers \"${BOOTSTRAP_PEERS}\""
    
    # Add optional flags
    [[ "$FEDERATION" == false ]] && cmd+=" --no-federation"
    [[ "$STORAGE" == false ]] && cmd+=" --no-storage"
    [[ "$VERBOSE" == true ]] && cmd+=" --verbose"
  fi
  
  # Start the node as a background process
  log_info "Executing: $cmd"
  mkdir -p "$(dirname "$LOG_FILE")"
  
  # Create a wrapper script to ensure proper execution with eval
  local wrapper_script="${DATA_DIR}/node_wrapper.sh"
  cat > "$wrapper_script" <<EOF
#!/bin/bash
set -euo pipefail
exec $cmd
EOF
  chmod +x "$wrapper_script"
  
  # Run in background, redirecting output to log file
  nohup "$wrapper_script" > "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
  
  log_info "Node started with PID $(cat "$PID_FILE")"
  
  # Register DNS and DID if requested
  if [[ "$AUTO_REGISTER" == true ]]; then
    log_info "Auto-registering DNS and DID entries..."
    # Wait a bit for the node to initialize
    sleep 5
    "${SCRIPT_DIR}/register-dns.sh" --node-name "$NODE_NAME" --coop "default" || \
      log_error "Failed to register DNS and DID entries"
  fi
}

stop_node() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid=$(cat "$PID_FILE")
    if ps -p "$pid" > /dev/null; then
      log_info "Stopping ICN node (PID: $pid)..."
      kill "$pid"
      # Wait for process to terminate
      for i in {1..30}; do
        if ! ps -p "$pid" > /dev/null; then
          break
        fi
        sleep 1
      done
      # Force kill if still running
      if ps -p "$pid" > /dev/null; then
        log_warn "Node did not terminate gracefully, force killing..."
        kill -9 "$pid" || true
      fi
    fi
    rm -f "$PID_FILE"
    log_info "Node stopped"
  else
    log_warn "No PID file found, node may not be running"
  fi
}

check_node() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid=$(cat "$PID_FILE")
    if ps -p "$pid" > /dev/null; then
      log_info "ICN node is running (PID: $pid)"
      return 0
    else
      log_warn "PID file exists but process is not running"
      rm -f "$PID_FILE"
      return 1
    fi
  else
    log_info "ICN node is not running"
    return 1
  fi
}

monitor_node() {
  log_info "Starting node monitoring..."
  while true; do
    if ! check_node; then
      if [[ "$RESTART_DELAY" -gt 0 ]]; then
        log_warn "Node is not running, restarting in $RESTART_DELAY seconds..."
        sleep "$RESTART_DELAY"
        start_node
      else
        log_info "Node is not running, automatic restart disabled"
        break
      fi
    fi
    sleep 60
  done
}

main() {
  parse_args "$@"
  validate_args
  
  case "${1:-}" in
    start)
      stop_node || true  # Stop any existing instance
      start_node
      ;;
    stop)
      stop_node
      ;;
    restart)
      stop_node || true
      start_node
      ;;
    status)
      check_node
      ;;
    monitor)
      monitor_node
      ;;
    *)
      # Default: start and monitor
      stop_node || true
      start_node
      monitor_node
      ;;
  esac
}

main "$@" 