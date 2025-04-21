#!/bin/bash
set -euo pipefail

# AgoraNet Integration Script
# Manages the integration between ICN node and AgoraNet

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Default values
COOP_NAME="default"
NODE_URL="http://localhost:26657"
AGORANET_PORT=8080
DAG_PATH="${HOME}/.icn/data/dag"
IDENTITY_PATH="${HOME}/.wallet/identities"
ENABLE_API=true
RUN_AS_DAEMON=false
LOG_FILE="${HOME}/.icn/logs/agoranet.log"
PID_FILE="${HOME}/.icn/agoranet.pid"

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Manage the integration between ICN node and AgoraNet.

Options:
  --coop NAME           Cooperative name (default: default)
  --node-url URL        ICN node RPC URL (default: http://localhost:26657)
  --port PORT           AgoraNet API port (default: 8080)
  --dag-path PATH       Path to DAG data (default: ~/.icn/data/dag)
  --identity-path PATH  Path to identities directory (default: ~/.wallet/identities)
  --no-api              Disable AgoraNet API server
  --daemon              Run AgoraNet as a daemon
  --log-file FILE       Log file path (default: ~/.icn/logs/agoranet.log)
  --start               Start AgoraNet service
  --stop                Stop AgoraNet service
  --status              Check AgoraNet service status
  --restart             Restart AgoraNet service
  --help                Display this help message and exit

Examples:
  # Start AgoraNet for a specific cooperative
  $(basename "$0") --coop "my-cooperative" --start
  
  # Run AgoraNet as a daemon with custom port
  $(basename "$0") --coop "my-cooperative" --port 9090 --daemon --start
  
  # Stop the AgoraNet service
  $(basename "$0") --stop
EOF
}

parse_args() {
  local action=""
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --coop)
        COOP_NAME="$2"
        shift 2
        ;;
      --node-url)
        NODE_URL="$2"
        shift 2
        ;;
      --port)
        AGORANET_PORT="$2"
        shift 2
        ;;
      --dag-path)
        DAG_PATH="$2"
        shift 2
        ;;
      --identity-path)
        IDENTITY_PATH="$2"
        shift 2
        ;;
      --no-api)
        ENABLE_API=false
        shift
        ;;
      --daemon)
        RUN_AS_DAEMON=true
        shift
        ;;
      --log-file)
        LOG_FILE="$2"
        shift 2
        ;;
      --start)
        action="start"
        shift
        ;;
      --stop)
        action="stop"
        shift
        ;;
      --status)
        action="status"
        shift
        ;;
      --restart)
        action="restart"
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
  
  # Default action is start if no action specified
  if [[ -z "$action" ]]; then
    action="start"
  fi
  
  COMMAND="$action"
}

validate_args() {
  # Ensure cooperative directory exists
  mkdir -p "${IDENTITY_PATH}/${COOP_NAME}"
  
  # Create log directory
  mkdir -p "$(dirname "$LOG_FILE")"
  
  # Validate node connection
  if ! curl -s "${NODE_URL}/status" >/dev/null; then
    log_warn "Cannot connect to ICN node at ${NODE_URL}"
    # Not failing as we might want to start AgoraNet before the node
  fi
  
  # Validate DAG path
  if [[ ! -d "$DAG_PATH" && "$COMMAND" == "start" ]]; then
    log_warn "DAG path does not exist: $DAG_PATH"
    log_info "Creating DAG directory"
    mkdir -p "$DAG_PATH"
  fi
}

start_agoranet() {
  log_info "Starting AgoraNet for cooperative: $COOP_NAME"
  
  # Check if already running
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid=$(cat "$PID_FILE")
    if ps -p "$pid" > /dev/null; then
      log_warn "AgoraNet is already running with PID $pid"
      return 0
    else
      log_warn "Stale PID file found, removing"
      rm -f "$PID_FILE"
    fi
  fi
  
  # Prepare AgoraNet command
  local cmd="${SCRIPT_DIR}/run-agoranet.sh"
  cmd+=" --coop \"${COOP_NAME}\""
  cmd+=" --port ${AGORANET_PORT}"
  cmd+=" --dag-path \"${DAG_PATH}\""
  [[ "$ENABLE_API" == false ]] && cmd+=" --no-api"
  
  if [[ "$RUN_AS_DAEMON" == true ]]; then
    # Run as daemon
    log_info "Running AgoraNet as daemon"
    
    # Create wrapper script
    local wrapper_script="/tmp/agoranet-wrapper-$$.sh"
    cat > "$wrapper_script" <<EOF
#!/bin/bash
set -euo pipefail
exec $cmd
EOF
    chmod +x "$wrapper_script"
    
    # Start in background
    nohup "$wrapper_script" > "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    log_info "AgoraNet started with PID $(cat "$PID_FILE")"
  else
    # Run in foreground
    log_info "Running AgoraNet in foreground"
    eval "$cmd"
  fi
}

stop_agoranet() {
  log_info "Stopping AgoraNet service"
  
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid=$(cat "$PID_FILE")
    if ps -p "$pid" > /dev/null; then
      log_info "Stopping AgoraNet (PID: $pid)"
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
        log_warn "AgoraNet did not terminate gracefully, force killing"
        kill -9 "$pid" || true
      fi
    fi
    rm -f "$PID_FILE"
    log_info "AgoraNet stopped"
  else
    log_warn "No PID file found, AgoraNet may not be running"
  fi
}

check_agoranet_status() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid=$(cat "$PID_FILE")
    if ps -p "$pid" > /dev/null; then
      log_info "AgoraNet is running with PID $pid"
      
      # Check if API is accessible
      if [[ "$ENABLE_API" == true ]]; then
        if curl -s "http://localhost:${AGORANET_PORT}/api/status" >/dev/null; then
          log_info "AgoraNet API is accessible at http://localhost:${AGORANET_PORT}"
        else
          log_warn "AgoraNet process is running but API is not accessible"
        fi
      fi
      
      return 0
    else
      log_warn "PID file exists but process is not running"
      rm -f "$PID_FILE"
      return 1
    fi
  else
    log_info "AgoraNet is not running"
    return 1
  fi
}

restart_agoranet() {
  stop_agoranet
  sleep 2
  start_agoranet
}

# Function to synchronize proposals between AgoraNet and ICN node
sync_proposals() {
  log_info "Synchronizing proposals between AgoraNet and ICN node"
  
  # This is a placeholder - actual implementation would:
  # 1. Fetch existing proposals from the ICN node
  # 2. Fetch proposals from AgoraNet
  # 3. Compare and update as needed
  # 4. Submit any missing proposals to the blockchain
  
  # For now we'll just display a message
  log_info "Proposal synchronization not implemented yet"
}

# Function to manage webhook integrations
setup_webhooks() {
  log_info "Setting up webhooks for AgoraNet integration"
  
  # Create webhook directory
  local webhook_dir="${HOME}/.icn/webhooks"
  mkdir -p "$webhook_dir"
  
  # Create proposal webhook
  local proposal_hook="${webhook_dir}/agoranet-proposal.sh"
  cat > "$proposal_hook" <<EOF
#!/bin/bash
# AgoraNet proposal webhook
set -euo pipefail

# This webhook is called when a new proposal is created in AgoraNet
# It submits the proposal to the ICN blockchain

# Get webhook payload from stdin
read -r PAYLOAD

# Extract proposal details
PROPOSAL_ID=\$(echo "\$PAYLOAD" | jq -r '.proposal_id // empty')
PROPOSAL_TITLE=\$(echo "\$PAYLOAD" | jq -r '.title // empty')
PROPOSAL_CONTENT=\$(echo "\$PAYLOAD" | jq -r '.content // empty')
PROPOSAL_TYPE=\$(echo "\$PAYLOAD" | jq -r '.type // empty')

echo "[$(date)] Received proposal webhook: \$PROPOSAL_ID - \$PROPOSAL_TITLE"

# Submit to blockchain (implementation depends on your ICN node API)
# This is a placeholder for the actual implementation
echo "Submitting proposal to blockchain: \$PROPOSAL_ID"
EOF
  chmod +x "$proposal_hook"
  
  # Create vote webhook
  local vote_hook="${webhook_dir}/agoranet-vote.sh"
  cat > "$vote_hook" <<EOF
#!/bin/bash
# AgoraNet vote webhook
set -euo pipefail

# This webhook is called when a vote is cast in AgoraNet
# It submits the vote to the ICN blockchain

# Get webhook payload from stdin
read -r PAYLOAD

# Extract vote details
PROPOSAL_ID=\$(echo "\$PAYLOAD" | jq -r '.proposal_id // empty')
VOTER_ID=\$(echo "\$PAYLOAD" | jq -r '.voter_id // empty')
VOTE_DECISION=\$(echo "\$PAYLOAD" | jq -r '.decision // empty')

echo "[$(date)] Received vote webhook: Proposal \$PROPOSAL_ID, Voter \$VOTER_ID, Decision \$VOTE_DECISION"

# Submit to blockchain (implementation depends on your ICN node API)
# This is a placeholder for the actual implementation
echo "Submitting vote to blockchain: \$VOTER_ID on proposal \$PROPOSAL_ID"
EOF
  chmod +x "$vote_hook"
  
  log_info "Webhooks set up successfully"
}

main() {
  parse_args "$@"
  validate_args
  
  case "$COMMAND" in
    start)
      start_agoranet
      ;;
    stop)
      stop_agoranet
      ;;
    status)
      check_agoranet_status
      ;;
    restart)
      restart_agoranet
      ;;
    *)
      log_error "Unknown command: $COMMAND"
      print_usage
      exit 1
      ;;
  esac
}

main "$@" 