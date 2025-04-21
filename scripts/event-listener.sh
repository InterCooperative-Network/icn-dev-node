#!/bin/bash
set -euo pipefail

# ICN Node Event Listener
# Listens for events from the node and triggers actions based on them

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Default values
NODE_URL="http://localhost:26657"
EVENT_TYPES="tm.event='NewBlock'"
HOOKS_DIR="${HOME}/.icn/hooks"
LOG_FILE="${HOME}/.icn/logs/events.log"
MAX_RECONNECT_ATTEMPTS=10
RECONNECT_DELAY=5
RUN_AS_DAEMON=false

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Listen for events from an ICN node and trigger actions based on them.

Options:
  --node-url URL        Node RPC URL (default: http://localhost:26657)
  --events EVENTS       Event types to subscribe to (default: tm.event='NewBlock')
                        Multiple events can be specified with commas
  --hooks-dir DIR       Directory containing event hook scripts (default: ~/.icn/hooks)
  --log-file FILE       Log file path (default: ~/.icn/logs/events.log)
  --daemon              Run as a daemon in the background
  --max-reconnects N    Maximum reconnection attempts (default: 10, 0 for infinite)
  --reconnect-delay N   Delay between reconnection attempts in seconds (default: 5)
  --help                Display this help message and exit

Examples:
  # Listen for new blocks
  $(basename "$0") 
  
  # Listen for governance and federation events with custom hooks
  $(basename "$0") --events "tm.event='Tx' AND tx.type='governance',tm.event='Tx' AND tx.type='federation'" --hooks-dir "/path/to/hooks"
  
  # Run as a daemon with logging
  $(basename "$0") --daemon --log-file "/var/log/icn/events.log"
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --node-url)
        NODE_URL="$2"
        shift 2
        ;;
      --events)
        EVENT_TYPES="$2"
        shift 2
        ;;
      --hooks-dir)
        HOOKS_DIR="$2"
        shift 2
        ;;
      --log-file)
        LOG_FILE="$2"
        shift 2
        ;;
      --daemon)
        RUN_AS_DAEMON=true
        shift
        ;;
      --max-reconnects)
        MAX_RECONNECT_ATTEMPTS="$2"
        shift 2
        ;;
      --reconnect-delay)
        RECONNECT_DELAY="$2"
        shift 2
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
  # Create necessary directories
  mkdir -p "$HOOKS_DIR"
  mkdir -p "$(dirname "$LOG_FILE")"
  
  # Check if we can connect to the node
  if ! curl -s "$NODE_URL/status" >/dev/null; then
    log_error "Cannot connect to node at $NODE_URL"
    exit 1
  fi
}

# Function to handle events
handle_event() {
  local event="$1"
  local event_type
  local event_data
  
  # Extract event type and data
  if command_exists jq; then
    event_type=$(echo "$event" | jq -r '.result.query // "unknown"')
    event_data=$(echo "$event" | jq -r '.result.data // {}')
  else
    # Fallback if jq is not available
    event_type=$(echo "$event" | grep -o '"query":"[^"]*"' | sed 's/"query":"//;s/"//')
    event_data="$event"
  fi
  
  log_info "Received event of type: $event_type"
  log_debug "Event data: $event_data"
  
  # Look for hook scripts to execute
  for hook in "$HOOKS_DIR"/*; do
    if [[ -x "$hook" ]]; then
      log_debug "Executing hook: $hook"
      # Execute hook with event data
      "$hook" "$event_type" "$event_data" 2>&1 | tee -a "$LOG_FILE" || log_warn "Hook execution failed: $hook"
    fi
  done
}

# Function to subscribe to events
subscribe_to_events() {
  local reconnect_count=0
  
  while true; do
    log_info "Subscribing to events: $EVENT_TYPES"
    
    # Use curl to make a WebSocket connection
    if ! curl -s --no-buffer -N \
      -H "Connection: Upgrade" \
      -H "Upgrade: websocket" \
      -H "Sec-WebSocket-Key: SGVsbG8sIHdvcmxkIQ==" \
      -H "Sec-WebSocket-Version: 13" \
      "$NODE_URL/subscribe?query=$EVENT_TYPES" | while read -r line; do
        handle_event "$line"
      done; then
      
      reconnect_count=$((reconnect_count + 1))
      
      if [[ "$MAX_RECONNECT_ATTEMPTS" -gt 0 && "$reconnect_count" -ge "$MAX_RECONNECT_ATTEMPTS" ]]; then
        log_error "Failed to reconnect after $reconnect_count attempts, exiting."
        exit 1
      fi
      
      log_warn "Connection lost, reconnecting in $RECONNECT_DELAY seconds (attempt $reconnect_count)..."
      sleep "$RECONNECT_DELAY"
    fi
  done
}

run_as_daemon() {
  log_info "Starting event listener in daemon mode..."
  
  # Create a wrapper script
  local wrapper_script="/tmp/icn-event-listener-$$.sh"
  cat > "$wrapper_script" <<EOF
#!/bin/bash
set -euo pipefail
exec "$0" --node-url "$NODE_URL" --events "$EVENT_TYPES" --hooks-dir "$HOOKS_DIR" --log-file "$LOG_FILE" --max-reconnects "$MAX_RECONNECT_ATTEMPTS" --reconnect-delay "$RECONNECT_DELAY"
EOF
  chmod +x "$wrapper_script"
  
  # Start the process in the background
  nohup "$wrapper_script" > /dev/null 2>&1 &
  echo $! > "${HOME}/.icn/event-listener.pid"
  log_info "Event listener started in daemon mode with PID $(cat "${HOME}/.icn/event-listener.pid")"
}

create_default_hooks() {
  log_info "Creating default event hook examples in $HOOKS_DIR"
  
  # Create governance hook
  local gov_hook="${HOOKS_DIR}/governance-hook.sh"
  cat > "$gov_hook" <<EOF
#!/bin/bash
# Governance event hook for ICN node
set -euo pipefail

EVENT_TYPE="\$1"
EVENT_DATA="\$2"

echo "[$(date)] Received governance event: \$EVENT_TYPE"

# Process only governance-related events
if [[ "\$EVENT_TYPE" == *"governance"* ]]; then
  # Extract proposal ID and status (customize based on your event format)
  PROPOSAL_ID=\$(echo "\$EVENT_DATA" | jq -r '.proposal_id // empty')
  STATUS=\$(echo "\$EVENT_DATA" | jq -r '.status // empty')
  
  if [[ -n "\$PROPOSAL_ID" ]]; then
    echo "Processing governance proposal: \$PROPOSAL_ID (Status: \$STATUS)"
    
    # Example: If proposal passes, take some action
    if [[ "\$STATUS" == "passed" ]]; then
      echo "Proposal passed! Executing proposal actions..."
      # Add your custom actions here
    fi
  fi
fi
EOF
  chmod +x "$gov_hook"
  
  # Create federation hook
  local fed_hook="${HOOKS_DIR}/federation-hook.sh"
  cat > "$fed_hook" <<EOF
#!/bin/bash
# Federation event hook for ICN node
set -euo pipefail

EVENT_TYPE="\$1"
EVENT_DATA="\$2"

echo "[$(date)] Received federation event: \$EVENT_TYPE"

# Process only federation-related events
if [[ "\$EVENT_TYPE" == *"federation"* ]]; then
  # Extract peer ID and action (customize based on your event format)
  PEER_ID=\$(echo "\$EVENT_DATA" | jq -r '.peer_id // empty')
  ACTION=\$(echo "\$EVENT_DATA" | jq -r '.action // empty')
  
  if [[ -n "\$PEER_ID" && -n "\$ACTION" ]]; then
    echo "Federation event: Peer \$PEER_ID, Action: \$ACTION"
    
    # Example: If a new peer joins, update your peer list
    if [[ "\$ACTION" == "joined" ]]; then
      echo "New peer joined the federation: \$PEER_ID"
      # Add your custom actions here
    fi
  fi
fi
EOF
  chmod +x "$fed_hook"
  
  # Create DAG event hook
  local dag_hook="${HOOKS_DIR}/dag-hook.sh"
  cat > "$dag_hook" <<EOF
#!/bin/bash
# DAG state event hook for ICN node
set -euo pipefail

EVENT_TYPE="\$1"
EVENT_DATA="\$2"

echo "[$(date)] Received DAG event: \$EVENT_TYPE"

# Process only DAG-related events
if [[ "\$EVENT_TYPE" == *"NewBlock"* ]]; then
  # Extract block height and timestamp
  HEIGHT=\$(echo "\$EVENT_DATA" | jq -r '.block.header.height // empty')
  
  if [[ -n "\$HEIGHT" ]]; then
    echo "New block added to DAG: Height \$HEIGHT"
    
    # Example: Every 100 blocks, generate a DAG state report
    if [[ \$((HEIGHT % 100)) -eq 0 ]]; then
      echo "Generating DAG state report at height \$HEIGHT"
      # Add your custom actions here, e.g. call replay-dag.sh
    fi
  fi
fi
EOF
  chmod +x "$dag_hook"
  
  log_info "Default hooks created successfully"
}

main() {
  parse_args "$@"
  validate_args
  
  # Create default hooks if directory is empty
  if [[ -z "$(ls -A "$HOOKS_DIR" 2>/dev/null)" ]]; then
    create_default_hooks
  fi
  
  if [[ "$RUN_AS_DAEMON" == true ]]; then
    run_as_daemon
  else
    subscribe_to_events
  fi
}

main "$@" 