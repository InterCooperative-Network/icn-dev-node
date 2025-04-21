#!/bin/bash
set -euo pipefail

# ICN Mobile Agent Stub
# Provides JSON state for mobile agent integration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Default values
NODE_URL="http://localhost:26657"
DATA_DIR="${HOME}/.icn"
LOG_FILE="${DATA_DIR}/logs/mobile-agent.log"
IDENTITY_PATH="${HOME}/.wallet/identities"
SOCKET_PORT=8099
API_PORT=9001
COOP_NAME="default"
WATCH_INTERVAL=5  # Seconds between state updates
ENABLE_SOCKET=true
ENABLE_API=true
ENABLE_IDENTITY=true
ENABLE_PROPOSALS=true
RUN_AS_DAEMON=false
VERBOSE=false

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

ICN Mobile Agent Stub - Provides state data for mobile integrations.

Options:
  --node-url URL        ICN node RPC URL (default: http://localhost:26657)
  --socket-port PORT    WebSocket port for state updates (default: 8099)
  --api-port PORT       REST API port (default: 9001)
  --coop NAME           Default cooperative name (default: default)
  --watch-interval SEC  Seconds between state updates (default: 5)
  --no-socket           Disable WebSocket server
  --no-api              Disable REST API server
  --no-identity         Disable identity monitoring
  --no-proposals        Disable proposal monitoring
  --daemon              Run as a daemon in the background
  --verbose             Enable verbose logging
  --help                Display this help message and exit

Examples:
  # Start with default settings
  $(basename "$0")
  
  # Run as daemon with custom watch interval
  $(basename "$0") --daemon --watch-interval 10
  
  # Only monitor proposals with REST API (no WebSocket)
  $(basename "$0") --no-socket --no-identity
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --node-url)
        NODE_URL="$2"
        shift 2
        ;;
      --socket-port)
        SOCKET_PORT="$2"
        shift 2
        ;;
      --api-port)
        API_PORT="$2"
        shift 2
        ;;
      --coop)
        COOP_NAME="$2"
        shift 2
        ;;
      --watch-interval)
        WATCH_INTERVAL="$2"
        shift 2
        ;;
      --no-socket)
        ENABLE_SOCKET=false
        shift
        ;;
      --no-api)
        ENABLE_API=false
        shift
        ;;
      --no-identity)
        ENABLE_IDENTITY=false
        shift
        ;;
      --no-proposals)
        ENABLE_PROPOSALS=false
        shift
        ;;
      --daemon)
        RUN_AS_DAEMON=true
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
  # Create log directory
  mkdir -p "$(dirname "$LOG_FILE")"
  
  # Check if either socket or API is enabled
  if [[ "$ENABLE_SOCKET" == false && "$ENABLE_API" == false ]]; then
    log_error "At least one of WebSocket or REST API must be enabled"
    exit 1
  fi
  
  # Check if essential tools are available
  for cmd in nc curl jq; do
    if ! command_exists "$cmd"; then
      log_warn "Command '$cmd' not found. Some features may not work correctly."
    fi
  done
  
  # If socket is enabled, check if the port is available
  if [[ "$ENABLE_SOCKET" == true ]]; then
    if is_port_in_use "$SOCKET_PORT"; then
      log_error "Socket port $SOCKET_PORT is already in use"
      exit 1
    fi
  fi
  
  # If API is enabled, check if the port is available
  if [[ "$ENABLE_API" == true ]]; then
    if is_port_in_use "$API_PORT"; then
      log_error "API port $API_PORT is already in use"
      exit 1
    fi
  fi
}

# Get node status
get_node_status() {
  if ! curl -s "${NODE_URL}/status" >/dev/null 2>&1; then
    echo '{"status":"offline"}'
    return 1
  fi
  
  local node_info
  node_info=$(curl -s "${NODE_URL}/status")
  
  if command_exists jq; then
    # Extract relevant node information
    local status
    status=$(jq -n \
      --argjson full_info "$node_info" \
      '{
        status: "online",
        node_id: ($full_info.result.node_info.id // "unknown"),
        network: ($full_info.result.node_info.network // "unknown"),
        latest_block_height: ($full_info.result.sync_info.latest_block_height // "0" | tonumber),
        latest_block_time: ($full_info.result.sync_info.latest_block_time // null),
        catching_up: ($full_info.result.sync_info.catching_up // false),
        timestamp: "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"
      }')
    echo "$status"
  else
    # Fallback if jq is not available
    echo '{"status":"online", "raw_data":true}'
  fi
}

# Get identity information
get_identity_info() {
  if [[ "$ENABLE_IDENTITY" == false ]]; then
    echo '{"identities":[]}'
    return 0
  fi
  
  # Check if identity directory exists
  if [[ ! -d "$IDENTITY_PATH" ]]; then
    echo '{"identities":[]}'
    return 0
  fi
  
  if command_exists jq; then
    local identities_json="[]"
    local coops=()
    
    # Find all cooperatives
    for coop_dir in "$IDENTITY_PATH"/*; do
      if [[ -d "$coop_dir" ]]; then
        coops+=("$(basename "$coop_dir")")
      fi
    done
    
    # Process each cooperative
    for coop in "${coops[@]}"; do
      for identity_file in "$IDENTITY_PATH/$coop"/*.json; do
        if [[ -f "$identity_file" ]]; then
          local identity_name
          identity_name=$(basename "$identity_file" .json)
          
          # Read identity JSON
          local identity_json
          identity_json=$(cat "$identity_file")
          
          # Add cooperative and name to the identity JSON
          local enhanced_json
          enhanced_json=$(echo "$identity_json" | jq \
            --arg coop "$coop" \
            --arg name "$identity_name" \
            '. + {cooperative: $coop, name: $name}')
          
          # Append to identities array
          identities_json=$(echo "$identities_json" | jq \
            --argjson identity "$enhanced_json" \
            '. += [$identity]')
        fi
      done
    done
    
    echo "{\"identities\":$identities_json}"
  else
    # Fallback if jq is not available
    echo '{"identities":[], "error":"jq not available"}'
  fi
}

# Get active proposals
get_proposals() {
  if [[ "$ENABLE_PROPOSALS" == false ]]; then
    echo '{"proposals":[]}'
    return 0
  fi
  
  # Check if node is running
  if ! curl -s "${NODE_URL}/status" >/dev/null 2>&1; then
    echo '{"proposals":[], "error":"node offline"}'
    return 1
  fi
  
  # Check if replay-dag.sh is available
  if [[ ! -x "${SCRIPT_DIR}/replay-dag.sh" ]]; then
    echo '{"proposals":[], "error":"replay-dag.sh not available"}'
    return 1
  fi
  
  local proposals_json
  proposals_json=$("${SCRIPT_DIR}/replay-dag.sh" --proposals --json 2>/dev/null || echo '[]')
  
  echo "{\"proposals\":$proposals_json}"
}

# Generate the complete state object
generate_state() {
  local node_status
  local identities
  local proposals
  
  # Get individual components
  node_status=$(get_node_status)
  identities=$(get_identity_info)
  proposals=$(get_proposals)
  
  if command_exists jq; then
    # Combine all data into a single JSON object
    local state
    state=$(jq -n \
      --argjson node "$node_status" \
      --argjson identities "$identities" \
      --argjson proposals "$proposals" \
      '{
        node: $node,
        identities: $identities.identities,
        proposals: $proposals.proposals,
        agent: {
          version: "0.1.0",
          timestamp: "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"
        }
      }')
    echo "$state"
  else
    # Fallback if jq is not available
    echo "{\"node\":$node_status, \"identities\":${identities}, \"proposals\":${proposals}}"
  fi
}

# --------------------------
# WebSocket Server Functions
# --------------------------

start_socket_server() {
  log_info "Starting WebSocket server on port $SOCKET_PORT"
  
  # Create a FIFO for communication
  local fifo_path="/tmp/icn-mobile-agent-$$.fifo"
  mkfifo "$fifo_path"
  
  # Clean up FIFO on exit
  trap 'rm -f "$fifo_path"' EXIT
  
  # Start socket server in background
  (
    # Simple WebSocket server using netcat
    while true; do
      nc -l "$SOCKET_PORT" < "$fifo_path" | while read -r line; do
        # Simple WebSocket handshake
        if [[ "$line" == *"Upgrade: websocket"* ]]; then
          local key
          key=$(echo "$line" | grep -o "Sec-WebSocket-Key: [^$]+" | cut -d' ' -f2)
          if [[ -n "$key" ]]; then
            log_debug "WebSocket handshake detected, key: $key"
            
            # Send WebSocket handshake response
            local response="HTTP/1.1 101 Switching Protocols\r\n"
            response+="Upgrade: websocket\r\n"
            response+="Connection: Upgrade\r\n"
            response+="Sec-WebSocket-Accept: $(echo -n "$key" | openssl dgst -sha1 -binary | base64)\r\n"
            response+="\r\n"
            
            echo -e "$response" > "$fifo_path"
            
            # Start sending state updates
            while true; do
              local state
              state=$(generate_state)
              echo -e "$state" > "$fifo_path"
              sleep "$WATCH_INTERVAL"
            done
          fi
        fi
      done
    done
  ) &
  
  log_info "WebSocket server started on port $SOCKET_PORT"
}

# ------------------------
# REST API Server Functions
# ------------------------

start_api_server() {
  log_info "Starting REST API server on port $API_PORT"
  
  # Check if socat is available (required for REST API)
  if ! command_exists socat; then
    log_error "socat is required for the REST API server but not found"
    return 1
  fi
  
  # Start API server in background
  (
    # Simple HTTP server using socat
    socat TCP-LISTEN:"$API_PORT",fork,reuseaddr EXEC:"${SCRIPT_DIR}/mobile-agent-api-handler.sh"
  ) &
  
  log_info "REST API server started on port $API_PORT"
  
  # Create API handler script
  create_api_handler_script
}

create_api_handler_script() {
  local handler_script="${SCRIPT_DIR}/mobile-agent-api-handler.sh"
  
  cat > "$handler_script" <<'EOF'
#!/bin/bash
set -euo pipefail

# ICN Mobile Agent API Handler
# This script handles HTTP requests for the mobile agent API

# Read the HTTP request
read -r request_line
read -r request_method request_path request_proto <<< "$request_line"

# Read all headers
declare -A headers
while IFS=": " read -r key value; do
  # Break on empty line (end of headers)
  [[ -z "$key" ]] && break
  # Remove carriage return
  value="${value//$'\r'/}"
  headers["$key"]="$value"
done

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Call the appropriate handler based on the path
case "$request_path" in
  "/state" | "/status")
    # Get the full state
    response=$("$SCRIPT_DIR/mobile-agent.sh" --get-state 2>/dev/null || echo '{"error":"Failed to get state"}')
    ;;
  "/node")
    # Get just node status
    response=$("$SCRIPT_DIR/mobile-agent.sh" --get-node 2>/dev/null || echo '{"error":"Failed to get node status"}')
    ;;
  "/identities")
    # Get identities
    response=$("$SCRIPT_DIR/mobile-agent.sh" --get-identities 2>/dev/null || echo '{"error":"Failed to get identities"}')
    ;;
  "/proposals")
    # Get proposals
    response=$("$SCRIPT_DIR/mobile-agent.sh" --get-proposals 2>/dev/null || echo '{"error":"Failed to get proposals"}')
    ;;
  "/health")
    # Simple health check
    response='{"status":"ok"}'
    ;;
  *)
    # Default to 404
    echo -e "HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nContent-Length: 27\r\n\r\n{\"error\":\"Endpoint not found\"}"
    exit 0
    ;;
esac

# Calculate content length
content_length=${#response}

# Send HTTP response
echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: $content_length\r\n\r\n$response"
EOF

  chmod +x "$handler_script"
}

# Run as daemon
run_as_daemon() {
  log_info "Starting mobile agent in daemon mode"
  
  # Create a wrapper script
  local wrapper_script="/tmp/icn-mobile-agent-$$.sh"
  cat > "$wrapper_script" <<EOF
#!/bin/bash
set -euo pipefail
exec "$0" --node-url "$NODE_URL" --socket-port "$SOCKET_PORT" --api-port "$API_PORT" --coop "$COOP_NAME" --watch-interval "$WATCH_INTERVAL" $(if [[ "$ENABLE_SOCKET" == false ]]; then echo "--no-socket"; fi) $(if [[ "$ENABLE_API" == false ]]; then echo "--no-api"; fi) $(if [[ "$ENABLE_IDENTITY" == false ]]; then echo "--no-identity"; fi) $(if [[ "$ENABLE_PROPOSALS" == false ]]; then echo "--no-proposals"; fi) $(if [[ "$VERBOSE" == true ]]; then echo "--verbose"; fi)
EOF
  chmod +x "$wrapper_script"
  
  # Start in background
  nohup "$wrapper_script" > "$LOG_FILE" 2>&1 &
  echo $! > "${DATA_DIR}/mobile-agent.pid"
  log_info "Mobile agent started in daemon mode with PID $(cat "${DATA_DIR}/mobile-agent.pid")"
}

# Direct state query mode - used for API handlers
handle_direct_query() {
  case "$1" in
    --get-state)
      generate_state
      ;;
    --get-node)
      get_node_status
      ;;
    --get-identities)
      get_identity_info
      ;;
    --get-proposals)
      get_proposals
      ;;
    *)
      log_error "Unknown query command: $1"
      exit 1
      ;;
  esac
  exit 0
}

# Main function for running the agent
run_agent() {
  log_info "Starting ICN mobile agent"
  
  # Start socket server if enabled
  if [[ "$ENABLE_SOCKET" == true ]]; then
    start_socket_server
  fi
  
  # Start API server if enabled
  if [[ "$ENABLE_API" == true ]]; then
    start_api_server
  fi
  
  log_info "ICN mobile agent started"
  
  # Print server information
  if [[ "$ENABLE_SOCKET" == true ]]; then
    log_info "WebSocket server running on ws://localhost:$SOCKET_PORT"
  fi
  if [[ "$ENABLE_API" == true ]]; then
    log_info "REST API server running on http://localhost:$API_PORT"
    log_info "API endpoints: /state, /node, /identities, /proposals, /health"
  fi
  
  # Main loop - generate and display state periodically
  if [[ "$VERBOSE" == true ]]; then
    while true; do
      log_info "Generating state update..."
      local state
      state=$(generate_state)
      echo "$state" | jq '.'
      sleep "$WATCH_INTERVAL"
    done
  else
    # Just keep the script running
    while true; do
      sleep 60
    done
  fi
}

main() {
  # First, check for direct query mode
  if [[ $# -eq 1 && "$1" == --get-* ]]; then
    handle_direct_query "$1"
  fi
  
  parse_args "$@"
  validate_args
  
  # Run as daemon or foreground
  if [[ "$RUN_AS_DAEMON" == true ]]; then
    run_as_daemon
  else
    run_agent
  fi
}

main "$@" 