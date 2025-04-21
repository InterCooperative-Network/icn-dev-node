#!/bin/bash
set -euo pipefail

# ICN AgoraNet Proposal Sync
# This script synchronizes proposals between AgoraNet and CoVM execution

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Default values
AGORANET_API="http://localhost:8080/api"
NODE_URL="http://localhost:26657"
DATA_DIR="${HOME}/.icn"
LOG_FILE="${DATA_DIR}/logs/agoranet-sync.log"
QUEUE_DIR="${DATA_DIR}/queue"
COOP_NAME="default"
WEBHOOK_TOKEN=""
SYNC_INTERVAL=0  # 0 means run once, >0 means sync every X seconds
VERBOSE=false

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Synchronize proposals between AgoraNet and CoVM execution.

Options:
  --agoranet-api URL    AgoraNet API URL (default: http://localhost:8080/api)
  --node-url URL        ICN node RPC URL (default: http://localhost:26657)
  --data-dir DIR        Data directory (default: ~/.icn)
  --coop NAME           Cooperative name (default: default)
  --webhook-token TOKEN Token for webhook authentication
  --sync-interval SEC   Sync continuously every SEC seconds (default: 0 = once)
  --verbose             Enable verbose logging
  --help                Display this help message and exit

Examples:
  # Run a one-time sync
  $(basename "$0")
  
  # Run continuous sync every 5 minutes
  $(basename "$0") --sync-interval 300
  
  # Sync proposals from a specific AgoraNet instance
  $(basename "$0") --agoranet-api "http://example.com:8080/api"
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agoranet-api)
        AGORANET_API="$2"
        shift 2
        ;;
      --node-url)
        NODE_URL="$2"
        shift 2
        ;;
      --data-dir)
        DATA_DIR="$2"
        LOG_FILE="${DATA_DIR}/logs/agoranet-sync.log"
        QUEUE_DIR="${DATA_DIR}/queue"
        shift 2
        ;;
      --coop)
        COOP_NAME="$2"
        shift 2
        ;;
      --webhook-token)
        WEBHOOK_TOKEN="$2"
        shift 2
        ;;
      --sync-interval)
        SYNC_INTERVAL="$2"
        shift 2
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
  # Create necessary directories
  mkdir -p "$(dirname "$LOG_FILE")"
  mkdir -p "$QUEUE_DIR"
  
  # Check if node is running
  if ! curl -s "${NODE_URL}/status" > /dev/null; then
    log_error "Node is not running at ${NODE_URL}"
    exit 1
  fi
  
  # Check if AgoraNet is accessible
  if ! curl -s --head "${AGORANET_API}/status" > /dev/null; then
    log_error "AgoraNet API not accessible at ${AGORANET_API}"
    exit 1
  fi
}

# Fetch pending proposals from AgoraNet
fetch_pending_proposals() {
  log_info "Fetching pending proposals from AgoraNet"
  
  local proposals_url="${AGORANET_API}/proposals?status=approved"
  local proposals_json
  
  if [[ -n "$WEBHOOK_TOKEN" ]]; then
    proposals_json=$(curl -s -H "Authorization: Bearer ${WEBHOOK_TOKEN}" "$proposals_url")
  else
    proposals_json=$(curl -s "$proposals_url")
  fi
  
  # Check if we got a valid response
  if ! echo "$proposals_json" | jq -e . > /dev/null 2>&1; then
    log_error "Failed to get valid response from AgoraNet"
    return 1
  fi
  
  echo "$proposals_json"
}

# Validate a DSL proposal to ensure it's properly structured
validate_proposal() {
  local proposal_file="$1"
  local proposal_content
  
  proposal_content=$(cat "$proposal_file")
  
  # Check for basic DSL syntax (this is a simple validation)
  if ! grep -q "{" "$proposal_file" || ! grep -q "}" "$proposal_file"; then
    log_error "Proposal file has invalid syntax: $proposal_file"
    return 1
  fi
  
  # Check for required fields in governance proposals
  if grep -q "proposal" "$proposal_file"; then
    if ! grep -q "title:" "$proposal_file"; then
      log_error "Governance proposal missing required 'title' field: $proposal_file"
      return 1
    fi
    
    if ! grep -q "description:" "$proposal_file"; then
      log_error "Governance proposal missing required 'description' field: $proposal_file"
      return 1
    fi
  fi
  
  # If we have the CoVM binary available, use it to validate the DSL
  local covm_path="../deps/icn-covm/target/debug/icn-covm"
  if [[ -x "$covm_path" ]]; then
    log_info "Validating proposal with CoVM: $proposal_file"
    
    if ! "$covm_path" validate "$proposal_file" > /dev/null 2>&1; then
      log_error "Proposal validation failed with CoVM: $proposal_file"
      return 1
    fi
  else
    log_warn "CoVM binary not found, skipping deep validation"
  fi
  
  return 0
}

# Process a single proposal
process_proposal() {
  local proposal="$1"
  local proposal_id
  local proposal_title
  local proposal_content
  
  # Extract proposal information
  proposal_id=$(echo "$proposal" | jq -r '.id')
  proposal_title=$(echo "$proposal" | jq -r '.title')
  proposal_content=$(echo "$proposal" | jq -r '.content')
  
  log_info "Processing proposal: $proposal_id - $proposal_title"
  
  # Create DSL file in queue directory
  local dsl_file="${QUEUE_DIR}/proposal_${proposal_id}.dsl"
  
  # Check if the proposal already exists in queue
  if [[ -f "$dsl_file" ]]; then
    log_info "Proposal already in queue: $proposal_id"
    return 0
  fi
  
  # Write proposal content to DSL file
  echo "$proposal_content" > "$dsl_file"
  
  # Validate the proposal
  if validate_proposal "$dsl_file"; then
    log_success "Proposal validated and added to queue: $proposal_id"
    
    # Update proposal status in AgoraNet
    if [[ -n "$WEBHOOK_TOKEN" ]]; then
      local update_url="${AGORANET_API}/proposals/${proposal_id}/status"
      local update_status
      
      update_status=$(curl -s -X PUT \
        -H "Authorization: Bearer ${WEBHOOK_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"status":"queued"}' \
        "$update_url")
      
      if [[ "$VERBOSE" == true ]]; then
        log_info "Status update response: $update_status"
      fi
    fi
  else
    log_error "Proposal validation failed, rejecting: $proposal_id"
    
    # Update proposal status in AgoraNet
    if [[ -n "$WEBHOOK_TOKEN" ]]; then
      local update_url="${AGORANET_API}/proposals/${proposal_id}/status"
      
      curl -s -X PUT \
        -H "Authorization: Bearer ${WEBHOOK_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"status":"rejected", "reason":"Validation failed"}' \
        "$update_url" > /dev/null
    fi
    
    # Remove invalid proposal from queue
    rm -f "$dsl_file"
    return 1
  fi
  
  return 0
}

# Sync proposals from AgoraNet to local queue
sync_proposals() {
  log_info "Syncing proposals from AgoraNet to local queue"
  
  # Fetch pending proposals
  local proposals_json
  proposals_json=$(fetch_pending_proposals)
  
  if [[ $? -ne 0 ]]; then
    log_error "Failed to fetch proposals"
    return 1
  fi
  
  # Process each proposal
  local proposal_count
  proposal_count=$(echo "$proposals_json" | jq -r '.proposals | length')
  
  if [[ "$proposal_count" -eq 0 ]]; then
    log_info "No pending proposals found in AgoraNet"
    return 0
  fi
  
  log_info "Found $proposal_count pending proposals"
  
  local success_count=0
  for i in $(seq 0 $((proposal_count - 1))); do
    local proposal
    proposal=$(echo "$proposals_json" | jq -r ".proposals[$i]")
    
    if process_proposal "$proposal"; then
      success_count=$((success_count + 1))
    fi
  done
  
  log_info "Successfully processed $success_count of $proposal_count proposals"
  
  # Trigger proposal execution if we have the exec-covm.sh script
  if [[ -x "${SCRIPT_DIR}/exec-covm.sh" ]]; then
    if [[ "$success_count" -gt 0 ]]; then
      log_info "Triggering execution of queued proposals"
      "${SCRIPT_DIR}/exec-covm.sh" > /dev/null
    fi
  else
    log_warn "exec-covm.sh script not found, cannot trigger execution"
  fi
  
  return 0
}

# Main function for running the sync
run_sync() {
  if [[ "$SYNC_INTERVAL" -le 0 ]]; then
    # Run once
    sync_proposals
  else
    # Run continuously
    log_info "Starting continuous sync with interval of $SYNC_INTERVAL seconds"
    
    while true; do
      sync_proposals
      sleep "$SYNC_INTERVAL"
    done
  fi
}

main() {
  parse_args "$@"
  validate_args
  run_sync
}

main "$@" 