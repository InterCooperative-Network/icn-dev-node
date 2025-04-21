#!/bin/bash
set -euo pipefail

# ICN Node TUI Interface
# Interactive terminal UI for managing and monitoring ICN nodes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Default values
NODE_URL="http://localhost:26657"
DATA_DIR="${HOME}/.icn"
LOG_FILE="${DATA_DIR}/logs/node-ui.log"
IDENTITY_PATH="${HOME}/.wallet/identities"
COOP_NAME="default"
TEMP_DIR="/tmp/icn-ui-$$"
REFRESH_INTERVAL=5  # seconds

# Ensure dialog is installed
ensure_dialog() {
  if ! command_exists dialog; then
    log_error "dialog is not installed. Please install it first."
    echo "On Ubuntu/Debian: sudo apt-get install dialog"
    echo "On CentOS/RHEL: sudo yum install dialog"
    echo "On macOS: brew install dialog"
    exit 1
  fi
}

# Create temp directory for UI data
setup_temp() {
  mkdir -p "$TEMP_DIR"
  mkdir -p "$(dirname "$LOG_FILE")"
  # Clean up temp directory on exit
  trap 'rm -rf "$TEMP_DIR"' EXIT
}

# Check if node is running
check_node_running() {
  if ! is_node_running; then
    dialog --title "ICN Node Status" --msgbox "Node is not running! Please start the node first using:\n\n./scripts/daemon.sh start" 10 60
    return 1
  fi
  return 0
}

# Get DAG statistics
get_dag_stats() {
  local stats_file="$TEMP_DIR/dag_stats.txt"
  
  if ! is_node_running; then
    echo "Node is not running" > "$stats_file"
    return 1
  fi
  
  # Get basic node info
  local node_info
  node_info=$(get_node_status 26657 json)
  
  # Extract useful information
  local latest_block_height
  local network
  local node_id
  if command_exists jq; then
    latest_block_height=$(echo "$node_info" | jq -r '.result.sync_info.latest_block_height // "unknown"')
    network=$(echo "$node_info" | jq -r '.result.node_info.network // "unknown"')
    node_id=$(echo "$node_info" | jq -r '.result.node_info.id // "unknown"')
  else
    latest_block_height="unknown (jq not installed)"
    network="unknown (jq not installed)"
    node_id="unknown (jq not installed)"
  fi
  
  # Get DAG stats (using replay-dag.sh)
  local dag_output
  if [[ -x "${SCRIPT_DIR}/replay-dag.sh" ]]; then
    dag_output=$("${SCRIPT_DIR}/replay-dag.sh" --json 2>/dev/null || echo '{"vertices": 0, "proposals": 0, "votes": 0}')
    local vertex_count
    local proposal_count
    local vote_count
    
    if command_exists jq; then
      vertex_count=$(echo "$dag_output" | jq -r '.vertices // 0')
      proposal_count=$(echo "$dag_output" | jq -r '.proposals // 0')
      vote_count=$(echo "$dag_output" | jq -r '.votes // 0')
    else
      vertex_count="unknown (jq not installed)"
      proposal_count="unknown (jq not installed)"
      vote_count="unknown (jq not installed)"
    fi
  else
    vertex_count="unknown (replay-dag.sh not found)"
    proposal_count="unknown (replay-dag.sh not found)"
    vote_count="unknown (replay-dag.sh not found)"
  fi
  
  # Save to file for display
  cat > "$stats_file" <<EOF
Node Status: Running
Network: $network
Node ID: $node_id
Latest Block Height: $latest_block_height
DAG Vertices: $vertex_count
Proposals: $proposal_count
Votes: $vote_count
EOF
}

# Get federation peer information
get_federation_peers() {
  local peers_file="$TEMP_DIR/peers.txt"
  
  if ! is_node_running; then
    echo "Node is not running" > "$peers_file"
    return 1
  fi
  
  # Get net_info from node
  local net_info
  net_info=$(curl -s "$NODE_URL/net_info")
  
  if command_exists jq; then
    local peers
    peers=$(echo "$net_info" | jq -r '.result.peers[] | "\(.node_info.id) - \(.node_info.moniker) (\(.remote_ip):\(.node_info.listen_addr | split(":") | .[2]))"')
    local peers_count
    peers_count=$(echo "$net_info" | jq -r '.result.n_peers')
    
    if [[ -z "$peers" ]]; then
      echo "No peers connected" > "$peers_file"
    else
      echo "Connected Peers: $peers_count" > "$peers_file"
      echo "$peers" >> "$peers_file"
    fi
  else
    echo "Connected peers information not available (jq not installed)" > "$peers_file"
  fi
}

# Get identity information
get_identity_info() {
  local identity_file="$TEMP_DIR/identities.txt"
  
  # Ensure identity directory exists
  if [[ ! -d "$IDENTITY_PATH" ]]; then
    echo "No identities found. Use generate-identity.sh to create one." > "$identity_file"
    return 1
  fi
  
  # List all cooperatives with identities
  local coops=()
  for coop_dir in "$IDENTITY_PATH"/*; do
    if [[ -d "$coop_dir" ]]; then
      coops+=("$(basename "$coop_dir")")
    fi
  done
  
  if [[ ${#coops[@]} -eq 0 ]]; then
    echo "No identities found. Use generate-identity.sh to create one." > "$identity_file"
    return 1
  fi
  
  # Write identity info to file
  echo "Scoped Identities:" > "$identity_file"
  for coop in "${coops[@]}"; do
    echo "Cooperative: $coop" >> "$identity_file"
    
    local found=0
    for identity in "$IDENTITY_PATH/$coop"/*.json; do
      if [[ -f "$identity" ]]; then
        found=1
        local identity_name
        identity_name=$(basename "$identity" .json)
        
        if command_exists jq; then
          local address
          local role
          address=$(jq -r '.address // "unknown"' "$identity")
          role=$(jq -r '.role // "unknown"' "$identity")
          echo "  $identity_name ($role) - $address" >> "$identity_file"
        else
          echo "  $identity_name" >> "$identity_file"
        fi
      fi
    done
    
    if [[ $found -eq 0 ]]; then
      echo "  No identities found" >> "$identity_file"
    fi
    echo "" >> "$identity_file"
  done
}

# Get active proposals
get_active_proposals() {
  local proposals_file="$TEMP_DIR/proposals.txt"
  
  if ! is_node_running; then
    echo "Node is not running" > "$proposals_file"
    return 1
  fi
  
  # Get active proposals using replay-dag.sh
  if [[ -x "${SCRIPT_DIR}/replay-dag.sh" ]]; then
    local proposals_output
    proposals_output=$("${SCRIPT_DIR}/replay-dag.sh" --active-proposals --json 2>/dev/null || echo '[]')
    
    if command_exists jq; then
      if [[ "$proposals_output" == "[]" || -z "$proposals_output" ]]; then
        echo "No active proposals found" > "$proposals_file"
      else
        echo "Active Proposals:" > "$proposals_file"
        echo "$proposals_output" | jq -r '.[] | "ID: \(.id)\nTitle: \(.title)\nStatus: \(.status)\nYes: \(.yes_votes) No: \(.no_votes) Abstain: \(.abstain_votes)\n"' >> "$proposals_file"
      fi
    else
      echo "Proposal information not available (jq not installed)" > "$proposals_file"
    fi
  else
    echo "Proposal information not available (replay-dag.sh not found)" > "$proposals_file"
  fi
}

# Get AgoraNet status
get_agoranet_status() {
  local agoranet_file="$TEMP_DIR/agoranet.txt"
  
  # Check if AgoraNet process is running
  local pid_file="${HOME}/.icn/agoranet.pid"
  if [[ -f "$pid_file" ]]; then
    local pid
    pid=$(cat "$pid_file")
    if ps -p "$pid" > /dev/null; then
      echo "AgoraNet Status: Running (PID: $pid)" > "$agoranet_file"
      
      # Try to get more information from API
      local agoranet_port=8080  # Default port
      if curl -s "http://localhost:${agoranet_port}/api/status" >/dev/null 2>&1; then
        local status_json
        status_json=$(curl -s "http://localhost:${agoranet_port}/api/status")
        
        if command_exists jq; then
          local coop
          local threads
          local users
          coop=$(echo "$status_json" | jq -r '.cooperative // "unknown"')
          threads=$(echo "$status_json" | jq -r '.threads // "0"')
          users=$(echo "$status_json" | jq -r '.users // "0"')
          
          echo "Cooperative: $coop" >> "$agoranet_file"
          echo "Discussion Threads: $threads" >> "$agoranet_file"
          echo "Active Users: $users" >> "$agoranet_file"
        else
          echo "AgoraNet is running, but detailed information not available (jq not installed)" >> "$agoranet_file"
        fi
      else
        echo "AgoraNet API not accessible" >> "$agoranet_file"
      fi
    else
      echo "AgoraNet Status: Not Running (stale PID file)" > "$agoranet_file"
    fi
  else
    echo "AgoraNet Status: Not Running" > "$agoranet_file"
  fi
}

# Refresh all data
refresh_data() {
  get_dag_stats
  get_federation_peers
  get_identity_info
  get_active_proposals
  get_agoranet_status
}

# Display node status
display_node_status() {
  refresh_data
  dialog --title "ICN Node Status" --textbox "$TEMP_DIR/dag_stats.txt" 15 70
}

# Display federation peers
display_federation_peers() {
  get_federation_peers
  dialog --title "Federation Peers" --textbox "$TEMP_DIR/peers.txt" 20 70
}

# Display identity information
display_identities() {
  get_identity_info
  dialog --title "Identity Information" --textbox "$TEMP_DIR/identities.txt" 20 70
}

# Display proposals
display_proposals() {
  get_active_proposals
  dialog --title "Active Proposals" --textbox "$TEMP_DIR/proposals.txt" 20 70
}

# Display AgoraNet status
display_agoranet() {
  get_agoranet_status
  dialog --title "AgoraNet Status" --textbox "$TEMP_DIR/agoranet.txt" 15 70
}

# Create a new identity
create_identity() {
  # Get cooperative name
  local coop
  coop=$(dialog --title "Create Identity" --inputbox "Enter cooperative name:" 8 60 "$COOP_NAME" 3>&1 1>&2 2>&3)
  
  if [[ -z "$coop" ]]; then
    return
  fi
  
  # Get identity name
  local name
  name=$(dialog --title "Create Identity" --inputbox "Enter identity name:" 8 60 "user1" 3>&1 1>&2 2>&3)
  
  if [[ -z "$name" ]]; then
    return
  fi
  
  # Get identity role
  local role
  role=$(dialog --title "Create Identity" --radiolist "Select identity role:" 12 60 3 \
    "member" "Regular member" ON \
    "admin" "Administrative rights" OFF \
    "observer" "Read-only access" OFF 3>&1 1>&2 2>&3)
  
  if [[ -z "$role" ]]; then
    return
  fi
  
  # Create the identity
  dialog --title "Creating Identity" --infobox "Creating identity $name for cooperative $coop with role $role..." 5 70
  
  local output
  output=$("${SCRIPT_DIR}/generate-identity.sh" --name "$name" --coop "$coop" --role "$role" 2>&1)
  local exit_code=$?
  
  if [[ $exit_code -eq 0 ]]; then
    dialog --title "Identity Created" --msgbox "Identity created successfully:\n\n$output" 15 70
  else
    dialog --title "Error" --msgbox "Failed to create identity:\n\n$output" 15 70
  fi
}

# Submit a proposal
submit_proposal() {
  # Check if node is running
  if ! check_node_running; then
    return
  fi
  
  # Get cooperative name
  local coop
  coop=$(dialog --title "Submit Proposal" --inputbox "Enter cooperative name:" 8 60 "$COOP_NAME" 3>&1 1>&2 2>&3)
  
  if [[ -z "$coop" ]]; then
    return
  fi
  
  # Get identity to use
  local identities=()
  local options=()
  
  if [[ -d "$IDENTITY_PATH/$coop" ]]; then
    for identity in "$IDENTITY_PATH/$coop"/*.json; do
      if [[ -f "$identity" ]]; then
        local identity_name
        identity_name=$(basename "$identity" .json)
        identities+=("$identity_name")
        
        if command_exists jq; then
          local role
          role=$(jq -r '.role // "unknown"' "$identity")
          options+=("$identity_name" "$role" OFF)
        else
          options+=("$identity_name" "Unknown role" OFF)
        fi
      fi
    done
  fi
  
  if [[ ${#identities[@]} -eq 0 ]]; then
    dialog --title "Error" --msgbox "No identities found for cooperative $coop. Please create an identity first." 8 60
    return
  fi
  
  # Set the first option to ON
  options[2]="ON"
  
  local identity
  identity=$(dialog --title "Submit Proposal" --radiolist "Select identity to use:" 15 60 8 "${options[@]}" 3>&1 1>&2 2>&3)
  
  if [[ -z "$identity" ]]; then
    return
  fi
  
  # Get proposal title
  local title
  title=$(dialog --title "Submit Proposal" --inputbox "Enter proposal title:" 8 60 "My Proposal" 3>&1 1>&2 2>&3)
  
  if [[ -z "$title" ]]; then
    return
  fi
  
  # Get proposal type
  local proposal_type
  proposal_type=$(dialog --title "Submit Proposal" --radiolist "Select proposal type:" 12 60 3 \
    "TextProposal" "General text proposal" ON \
    "ParameterChange" "Change system parameters" OFF \
    "BudgetAllocation" "Allocate budget" OFF 3>&1 1>&2 2>&3)
  
  if [[ -z "$proposal_type" ]]; then
    return
  fi
  
  # Get proposal description
  local description
  description=$(dialog --title "Submit Proposal" --inputbox "Enter proposal description:" 8 60 "Description of my proposal" 3>&1 1>&2 2>&3)
  
  if [[ -z "$description" ]]; then
    return
  fi
  
  # Submit the proposal
  dialog --title "Submitting Proposal" --infobox "Submitting proposal '$title' with identity $identity..." 5 70
  
  local output
  output=$("${SCRIPT_DIR}/demo-proposals.sh" --scoped-identity "$identity" --coop "$coop" --proposal-title "$title" --proposal-type "$proposal_type" --description "$description" 2>&1)
  local exit_code=$?
  
  if [[ $exit_code -eq 0 ]]; then
    # Extract proposal ID if possible
    local proposal_id
    if command_exists grep; then
      proposal_id=$(echo "$output" | grep -o "Proposal ID: [A-Za-z0-9]*" | sed 's/Proposal ID: //')
      if [[ -n "$proposal_id" ]]; then
        echo "$proposal_id" > "/tmp/icn_last_proposal_id.txt"
      fi
    fi
    
    dialog --title "Proposal Submitted" --msgbox "Proposal submitted successfully:\n\n$output" 15 70
  else
    dialog --title "Error" --msgbox "Failed to submit proposal:\n\n$output" 15 70
  fi
}

# Start AgoraNet
start_agoranet() {
  # Check if node is running
  if ! check_node_running; then
    return
  fi
  
  # Get cooperative name
  local coop
  coop=$(dialog --title "Start AgoraNet" --inputbox "Enter cooperative name:" 8 60 "$COOP_NAME" 3>&1 1>&2 2>&3)
  
  if [[ -z "$coop" ]]; then
    return
  fi
  
  # Get port
  local port
  port=$(dialog --title "Start AgoraNet" --inputbox "Enter port number:" 8 60 "8080" 3>&1 1>&2 2>&3)
  
  if [[ -z "$port" ]]; then
    return
  fi
  
  # Start AgoraNet
  dialog --title "Starting AgoraNet" --infobox "Starting AgoraNet for cooperative $coop on port $port..." 5 70
  
  local output
  output=$("${SCRIPT_DIR}/agoranet-integration.sh" --coop "$coop" --port "$port" --daemon --start 2>&1)
  local exit_code=$?
  
  if [[ $exit_code -eq 0 ]]; then
    dialog --title "AgoraNet Started" --msgbox "AgoraNet started successfully:\n\n$output" 15 70
  else
    dialog --title "Error" --msgbox "Failed to start AgoraNet:\n\n$output" 15 70
  fi
}

# Stop AgoraNet
stop_agoranet() {
  dialog --title "Stopping AgoraNet" --infobox "Stopping AgoraNet..." 5 70
  
  local output
  output=$("${SCRIPT_DIR}/agoranet-integration.sh" --stop 2>&1)
  local exit_code=$?
  
  if [[ $exit_code -eq 0 ]]; then
    dialog --title "AgoraNet Stopped" --msgbox "AgoraNet stopped successfully:\n\n$output" 15 70
  else
    dialog --title "Error" --msgbox "Failed to stop AgoraNet:\n\n$output" 15 70
  fi
}

# View detailed DAG trace
view_dag_trace() {
  # Check if node is running
  if ! check_node_running; then
    return
  fi
  
  local options=()
  
  # Option to view latest DAG state
  options+=("latest" "View latest DAG state" ON)
  
  # Option to view by proposal ID
  options+=("proposal" "View by proposal ID" OFF)
  
  # Option to view by vertex ID
  options+=("vertex" "View by vertex ID" OFF)
  
  local choice
  choice=$(dialog --title "DAG Trace" --radiolist "Select view option:" 12 60 3 "${options[@]}" 3>&1 1>&2 2>&3)
  
  if [[ -z "$choice" ]]; then
    return
  fi
  
  local cmd="${SCRIPT_DIR}/replay-dag.sh"
  local params=""
  
  case "$choice" in
    latest)
      # View latest DAG state
      params=""
      ;;
    proposal)
      # View by proposal ID
      local proposal_id
      
      # Check if we have a saved proposal ID
      if [[ -f "/tmp/icn_last_proposal_id.txt" ]]; then
        local last_id
        last_id=$(cat "/tmp/icn_last_proposal_id.txt")
        proposal_id=$(dialog --title "DAG Trace" --inputbox "Enter proposal ID:" 8 60 "$last_id" 3>&1 1>&2 2>&3)
      else
        proposal_id=$(dialog --title "DAG Trace" --inputbox "Enter proposal ID:" 8 60 "" 3>&1 1>&2 2>&3)
      fi
      
      if [[ -z "$proposal_id" ]]; then
        return
      fi
      
      params="--proposal $proposal_id"
      ;;
    vertex)
      # View by vertex ID
      local vertex_id
      vertex_id=$(dialog --title "DAG Trace" --inputbox "Enter vertex ID:" 8 60 "" 3>&1 1>&2 2>&3)
      
      if [[ -z "$vertex_id" ]]; then
        return
      fi
      
      params="--vertex $vertex_id"
      ;;
  esac
  
  # Run the DAG trace command
  dialog --title "Running DAG Trace" --infobox "Running DAG trace..." 5 70
  
  local output_file="$TEMP_DIR/dag_trace.txt"
  local output
  output=$($cmd $params 2>&1)
  local exit_code=$?
  
  if [[ $exit_code -eq 0 ]]; then
    echo "$output" > "$output_file"
    dialog --title "DAG Trace Result" --textbox "$output_file" 20 78
  else
    dialog --title "Error" --msgbox "Failed to run DAG trace:\n\n$output" 15 70
  fi
}

# Show help information
show_help() {
  dialog --title "ICN Node UI Help" --msgbox "\
ICN Node UI - Interactive terminal interface for ICN nodes

Key features:
- View node and DAG status
- Manage identities
- Submit and track proposals
- Integration with AgoraNet
- Federation peer monitoring

Tips:
- Ensure node is running before using most features
- Use the refresh option to update data
- Identity management requires generate-identity.sh
- Proposal submission requires demo-proposals.sh
- DAG trace requires replay-dag.sh

For more information, visit: https://github.com/your-org/icn-dev-node
" 20 76
}

# Main menu
show_main_menu() {
  while true; do
    local choice
    choice=$(dialog --clear --title "ICN Node UI" --menu "Select an option:" 18 60 10 \
      "1" "Node Status" \
      "2" "Federation Peers" \
      "3" "Identities" \
      "4" "Proposals" \
      "5" "AgoraNet Status" \
      "6" "Create Identity" \
      "7" "Submit Proposal" \
      "8" "Start AgoraNet" \
      "9" "Stop AgoraNet" \
      "10" "DAG Trace" \
      "r" "Refresh Data" \
      "h" "Help" \
      "q" "Quit" 3>&1 1>&2 2>&3)
    
    case $choice in
      1) display_node_status ;;
      2) display_federation_peers ;;
      3) display_identities ;;
      4) display_proposals ;;
      5) display_agoranet ;;
      6) create_identity ;;
      7) submit_proposal ;;
      8) start_agoranet ;;
      9) stop_agoranet ;;
      10) view_dag_trace ;;
      r) refresh_data ;;
      h) show_help ;;
      q) break ;;
      *) ;;
    esac
  done
}

main() {
  ensure_dialog
  setup_temp
  
  # Parse command line arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --node-url)
        NODE_URL="$2"
        shift 2
        ;;
      --coop)
        COOP_NAME="$2"
        shift 2
        ;;
      --help)
        echo "Usage: $(basename "$0") [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --node-url URL       Node RPC URL (default: http://localhost:26657)"
        echo "  --coop NAME          Default cooperative name (default: default)"
        echo "  --help               Show this help message"
        exit 0
        ;;
      *)
        echo "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
    esac
  done
  
  # Start UI
  show_main_menu
}

main "$@" 