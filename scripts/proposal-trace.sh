#!/bin/bash
set -euo pipefail

# ICN Proposal Tracer
# Trace a proposal from creation through voting to execution

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Default values
NODE_URL="http://localhost:26657"
DATA_DIR="${HOME}/.icn"
LOG_FILE="${DATA_DIR}/logs/proposal-trace.log"
PROPOSAL_ID=""
LATEST=false
LIST_PROPOSALS=false
OUTPUT_FORMAT="text"  # text or json
VERBOSE=false

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Trace the full lifecycle of a proposal from creation through voting to execution.

Options:
  --proposal ID        Specific proposal ID to trace
  --latest             Show information about the most recent proposal
  --list               List all proposals in the DAG
  --node-url URL       Node RPC URL (default: http://localhost:26657)
  --json               Output in JSON format
  --verbose            Provide more detailed output
  --help               Display this help message and exit

Examples:
  # Trace a specific proposal
  $(basename "$0") --proposal abc123

  # Show the latest proposal
  $(basename "$0") --latest

  # List all proposals
  $(basename "$0") --list

  # Get detailed JSON output
  $(basename "$0") --proposal abc123 --json --verbose
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --proposal)
        PROPOSAL_ID="$2"
        shift 2
        ;;
      --latest)
        LATEST=true
        shift
        ;;
      --list)
        LIST_PROPOSALS=true
        shift
        ;;
      --node-url)
        NODE_URL="$2"
        shift 2
        ;;
      --json)
        OUTPUT_FORMAT="json"
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
  # Check if the node is running
  if ! curl -s "${NODE_URL}/status" >/dev/null; then
    log_error "Cannot connect to node at ${NODE_URL}"
    exit 1
  fi
  
  # Create log directory
  mkdir -p "$(dirname "$LOG_FILE")"
  
  # Validate arguments
  if [[ -z "$PROPOSAL_ID" && "$LATEST" == false && "$LIST_PROPOSALS" == false ]]; then
    log_error "You must specify either --proposal, --latest, or --list"
    print_usage
    exit 1
  fi
}

# Get a list of all proposals
list_all_proposals() {
  log_info "Listing all proposals in the DAG"
  
  if [[ ! -x "${SCRIPT_DIR}/replay-dag.sh" ]]; then
    log_error "replay-dag.sh script not found or not executable"
    exit 1
  fi
  
  local output
  if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    output=$("${SCRIPT_DIR}/replay-dag.sh" --proposals --json)
    echo "$output"
  else
    output=$("${SCRIPT_DIR}/replay-dag.sh" --proposals)
    
    if [[ "$VERBOSE" == true ]]; then
      echo "$output"
    else
      # Extract just the list of proposals
      echo "$output" | grep -A 1 "ID:" | grep -v "^--$"
    fi
  fi
}

# Get the latest proposal
get_latest_proposal() {
  log_info "Getting the latest proposal"
  
  if [[ ! -x "${SCRIPT_DIR}/replay-dag.sh" ]]; then
    log_error "replay-dag.sh script not found or not executable"
    exit 1
  fi
  
  local proposals_output
  proposals_output=$("${SCRIPT_DIR}/replay-dag.sh" --proposals --json 2>/dev/null || echo '[]')
  
  if [[ "$proposals_output" == "[]" || -z "$proposals_output" ]]; then
    log_error "No proposals found in the DAG"
    exit 1
  fi
  
  # Extract the latest proposal ID
  if command_exists jq; then
    local latest_id
    latest_id=$(echo "$proposals_output" | jq -r 'sort_by(.timestamp) | reverse | .[0].id')
    
    if [[ -z "$latest_id" || "$latest_id" == "null" ]]; then
      log_error "Failed to extract latest proposal ID"
      exit 1
    fi
    
    PROPOSAL_ID="$latest_id"
    log_info "Latest proposal ID: $PROPOSAL_ID"
  else
    log_error "jq is required to process the latest proposal"
    exit 1
  fi
}

# Trace a specific proposal
trace_proposal() {
  log_info "Tracing proposal: $PROPOSAL_ID"
  
  if [[ ! -x "${SCRIPT_DIR}/replay-dag.sh" ]]; then
    log_error "replay-dag.sh script not found or not executable"
    exit 1
  fi
  
  # Get proposal details
  local proposal_output
  proposal_output=$("${SCRIPT_DIR}/replay-dag.sh" --proposal "$PROPOSAL_ID" --json 2>/dev/null)
  local exit_code=$?
  
  if [[ $exit_code -ne 0 || -z "$proposal_output" ]]; then
    log_error "Failed to get details for proposal $PROPOSAL_ID"
    exit 1
  fi
  
  # Process proposal data
  if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    # For JSON output, we'll build a more comprehensive object
    if command_exists jq; then
      # Extract basic proposal info
      local proposal_basic
      proposal_basic=$(echo "$proposal_output" | jq -c '.proposal')
      
      # Get the proposal vertex
      local proposal_vertex
      proposal_vertex=$("${SCRIPT_DIR}/replay-dag.sh" --vertex-by-proposal "$PROPOSAL_ID" --json 2>/dev/null || echo '{}')
      
      # Get all votes for this proposal
      local votes
      votes=$("${SCRIPT_DIR}/replay-dag.sh" --votes-for-proposal "$PROPOSAL_ID" --json 2>/dev/null || echo '[]')
      
      # Get execution result if any
      local execution
      execution=$("${SCRIPT_DIR}/replay-dag.sh" --execution-for-proposal "$PROPOSAL_ID" --json 2>/dev/null || echo '{}')
      
      # Combine all data
      local result
      result=$(jq -n \
        --argjson proposal "$proposal_basic" \
        --argjson vertex "$proposal_vertex" \
        --argjson votes "$votes" \
        --argjson execution "$execution" \
        '{
          proposal: $proposal,
          vertex: $vertex,
          votes: $votes,
          execution: $execution,
          trace_timestamp: "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"
        }')
      
      echo "$result"
    else
      log_error "jq is required for JSON output"
      exit 1
    fi
  else
    # For text output, format a readable report
    format_text_report "$proposal_output"
  fi
}

# Format a human-readable text report
format_text_report() {
  local proposal_json="$1"
  
  if ! command_exists jq; then
    echo "$proposal_json"
    return
  fi
  
  # Extract proposal details
  local id
  local title
  local description
  local type
  local status
  local proposer
  local submitted_time
  local voting_end_time
  local yes_votes
  local no_votes
  local abstain_votes
  local total_votes
  local quorum
  local vertex_id
  
  id=$(echo "$proposal_json" | jq -r '.proposal.id')
  title=$(echo "$proposal_json" | jq -r '.proposal.title')
  description=$(echo "$proposal_json" | jq -r '.proposal.description')
  type=$(echo "$proposal_json" | jq -r '.proposal.type')
  status=$(echo "$proposal_json" | jq -r '.proposal.status')
  proposer=$(echo "$proposal_json" | jq -r '.proposal.proposer')
  submitted_time=$(echo "$proposal_json" | jq -r '.proposal.submitted_time')
  voting_end_time=$(echo "$proposal_json" | jq -r '.proposal.voting_end_time')
  yes_votes=$(echo "$proposal_json" | jq -r '.proposal.yes_votes')
  no_votes=$(echo "$proposal_json" | jq -r '.proposal.no_votes')
  abstain_votes=$(echo "$proposal_json" | jq -r '.proposal.abstain_votes')
  total_votes=$(echo "$proposal_json" | jq -r '.proposal.total_votes')
  quorum=$(echo "$proposal_json" | jq -r '.proposal.quorum')
  vertex_id=$(echo "$proposal_json" | jq -r '.proposal.vertex_id // "unknown"')
  
  # Print report header
  cat <<EOF
=============================================
PROPOSAL TRACE REPORT
=============================================
ID:             $id
Title:          $title
Type:           $type
Status:         $status
Proposer:       $proposer
Submitted:      $submitted_time
Voting Ends:    $voting_end_time
DAG Vertex ID:  $vertex_id

DESCRIPTION:
$description

VOTING SUMMARY:
Yes:      $yes_votes
No:       $no_votes
Abstain:  $abstain_votes
Total:    $total_votes
Quorum:   $quorum
---------------------------------------------
EOF
  
  # Get votes
  local votes
  votes=$("${SCRIPT_DIR}/replay-dag.sh" --votes-for-proposal "$id" --json 2>/dev/null || echo '[]')
  
  if [[ "$votes" != "[]" ]]; then
    echo "VOTES:"
    # Sort votes by timestamp
    echo "$votes" | jq -r 'sort_by(.timestamp) | .[] | "\(.timestamp): \(.voter) - \(.decision)"'
  else
    echo "VOTES: None recorded"
  fi
  
  # Get execution details if available
  if [[ "$status" == "passed" || "$status" == "executed" ]]; then
    local execution
    execution=$("${SCRIPT_DIR}/replay-dag.sh" --execution-for-proposal "$id" --json 2>/dev/null || echo '{}')
    
    if [[ "$execution" != "{}" ]]; then
      local execution_time
      local executor
      local success
      local result
      
      execution_time=$(echo "$execution" | jq -r '.timestamp // "unknown"')
      executor=$(echo "$execution" | jq -r '.executor // "unknown"')
      success=$(echo "$execution" | jq -r '.success // "unknown"')
      result=$(echo "$execution" | jq -r '.result // "unknown"')
      
      cat <<EOF

EXECUTION:
Time:     $execution_time
Executor: $executor
Success:  $success
Result:   $result
EOF
    else
      echo -e "\nEXECUTION: Not executed yet"
    fi
  fi
  
  # Show DAG path for verbose mode
  if [[ "$VERBOSE" == true ]]; then
    echo -e "\nDAG PATH:"
    # Get the DAG path from proposal to execution
    "${SCRIPT_DIR}/replay-dag.sh" --dag-path-for-proposal "$id" || echo "DAG path not available"
  fi
  
  echo "============================================="
}

main() {
  parse_args "$@"
  validate_args
  
  if [[ "$LIST_PROPOSALS" == true ]]; then
    list_all_proposals
  elif [[ "$LATEST" == true ]]; then
    get_latest_proposal
    trace_proposal
  elif [[ -n "$PROPOSAL_ID" ]]; then
    trace_proposal
  fi
}

main "$@" 