#!/bin/bash
set -euo pipefail

# ICN CoVM Execution Script
# This script handles the execution of CoVM DSL files

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/node-state.sh" # For state tracking

# Default values
DATA_DIR="${HOME}/.icn"
COVM_BIN="${SCRIPT_DIR}/../deps/covm/bin/covm"
DSL_DIR="${DATA_DIR}/dsl"
QUEUE_DIR="${DATA_DIR}/queue"
OUTPUT_DIR="${DATA_DIR}/output"
LOG_FILE="${DATA_DIR}/logs/covm-exec.log"
PROPOSAL_ID=""
PROPOSAL_PATH=""
AUTO_APPROVE=false
VERBOSE=false
SHOW_OUTPUT=true

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [DSL_FILE]

Execute CoVM DSL files directly or from the proposal queue.

Options:
  --data-dir DIR        Data directory (default: ${DATA_DIR})
  --covm-bin PATH       Path to CoVM binary (default: ${COVM_BIN})
  --proposal ID         Execute a specific proposal by ID
  --auto-approve        Automatically approve proposals (default: ${AUTO_APPROVE})
  --no-output           Don't display execution output
  --verbose             Enable verbose logging
  --help                Display this help message and exit

Examples:
  # Execute a DSL file directly
  $(basename "$0") path/to/file.dsl
  
  # Execute a specific proposal
  $(basename "$0") --proposal 123
  
  # Execute the next queued proposal
  $(basename "$0")
EOF
}

parse_args() {
  DSL_FILE=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --data-dir)
        DATA_DIR="$2"
        DSL_DIR="${DATA_DIR}/dsl"
        QUEUE_DIR="${DATA_DIR}/queue"
        OUTPUT_DIR="${DATA_DIR}/output"
        LOG_FILE="${DATA_DIR}/logs/covm-exec.log"
        shift 2
        ;;
      --covm-bin)
        COVM_BIN="$2"
        shift 2
        ;;
      --proposal)
        PROPOSAL_ID="$2"
        shift 2
        ;;
      --auto-approve)
        AUTO_APPROVE=true
        shift
        ;;
      --no-output)
        SHOW_OUTPUT=false
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
      -*)
        log_error "Unknown option: $1"
        print_usage
        exit 1
        ;;
      *)
        DSL_FILE="$1"
        shift
        ;;
    esac
  done
}

validate_args() {
  # Create necessary directories
  mkdir -p "$DSL_DIR" "$QUEUE_DIR" "$OUTPUT_DIR" "$(dirname "$LOG_FILE")"

  # Validate CoVM binary
  if [[ ! -x "$COVM_BIN" ]]; then
    log_error "CoVM binary not found or not executable: $COVM_BIN"
    log_info "You may need to install CoVM or specify a different path with --covm-bin"
    return 1
  fi

  # Determine what to execute
  if [[ -n "$DSL_FILE" ]]; then
    # Execute a specific DSL file
    if [[ ! -f "$DSL_FILE" ]]; then
      log_error "DSL file not found: $DSL_FILE"
      return 1
    fi
  elif [[ -n "$PROPOSAL_ID" ]]; then
    # Execute a specific proposal by ID
    PROPOSAL_PATH=$(find_proposal_by_id "$PROPOSAL_ID")
    if [[ -z "$PROPOSAL_PATH" ]]; then
      log_error "Proposal not found with ID: $PROPOSAL_ID"
      return 1
    fi
  else
    # Execute next queued proposal if any
    PROPOSAL_PATH=$(find_next_proposal)
    if [[ -z "$PROPOSAL_PATH" ]]; then
      log_warn "No pending proposals found in queue"
      return 0
    fi
    PROPOSAL_ID=$(extract_proposal_id "$PROPOSAL_PATH")
  fi

  return 0
}

find_proposal_by_id() {
  local id="$1"
  local proposal_file
  
  proposal_file=$(find "$QUEUE_DIR" -name "proposal_${id}_*.dsl" -type f 2>/dev/null | head -n 1)
  
  echo "$proposal_file"
}

find_next_proposal() {
  local next_proposal
  
  # Find the proposal with the lowest ID
  next_proposal=$(find "$QUEUE_DIR" -name "proposal_*_pending.dsl" -type f 2>/dev/null | sort | head -n 1)
  
  echo "$next_proposal"
}

extract_proposal_id() {
  local proposal_path="$1"
  local proposal_name
  
  proposal_name=$(basename "$proposal_path")
  
  # Extract ID from filename format "proposal_ID_STATUS.dsl"
  echo "$proposal_name" | sed -E 's/proposal_([0-9]+)_.*/\1/'
}

confirm_execution() {
  local file="$1"
  local id="${2:-unknown}"
  
  echo
  log_info "About to execute CoVM proposal:"
  echo "-------------------------------------"
  echo "File: $file"
  echo "ID: $id"
  echo "-------------------------------------"
  echo
  
  if [[ "$AUTO_APPROVE" == true ]]; then
    return 0
  fi
  
  read -r -p "Do you want to proceed with execution? [y/N] " response
  
  if [[ "${response,,}" =~ ^y(es)?$ ]]; then
    return 0
  else
    log_warn "Execution cancelled by user"
    return 1
  fi
}

execute_dsl() {
  local file="$1"
  local proposal_id="${2:-unknown}"
  local output_file="${OUTPUT_DIR}/execution_${proposal_id}_$(date +%Y%m%d_%H%M%S).json"
  local temp_output
  local status_code=0
  
  log_info "Executing DSL file: $file"
  log_info "Output will be saved to: $output_file"
  
  # Update status to executing
  if [[ -n "$PROPOSAL_ID" && -n "$PROPOSAL_PATH" ]]; then
    update_proposal_status "$PROPOSAL_PATH" "executing"
  fi
  
  # Create a temporary file for output
  temp_output=$(mktemp)
  
  # Execute CoVM with the DSL file
  if "$COVM_BIN" "$file" > "$temp_output" 2>&1; then
    status_code=0
    log_success "Execution completed successfully"
  else
    status_code=$?
    log_error "Execution failed with exit code: $status_code"
  fi
  
  # Save output to final location
  mkdir -p "$(dirname "$output_file")"
  cat > "$output_file" <<EOF
{
  "proposal_id": "$proposal_id",
  "timestamp": "$(date --iso-8601=seconds)",
  "status_code": $status_code,
  "output": $(cat "$temp_output" | jq -R -s '.')
}
EOF
  
  # Display output if requested
  if [[ "$SHOW_OUTPUT" == true ]]; then
    echo
    echo "CoVM Execution Output:"
    echo "-------------------------------------"
    cat "$temp_output"
    echo "-------------------------------------"
    echo
  fi
  
  # Clean up the temporary file
  rm -f "$temp_output"
  
  # Update proposal status based on execution result
  if [[ -n "$PROPOSAL_ID" && -n "$PROPOSAL_PATH" ]]; then
    if [[ $status_code -eq 0 ]]; then
      update_proposal_status "$PROPOSAL_PATH" "completed"
      record_execution "$PROPOSAL_ID" "success"
    else
      update_proposal_status "$PROPOSAL_PATH" "failed"
      record_execution "$PROPOSAL_ID" "failed"
    fi
  fi
  
  return $status_code
}

update_proposal_status() {
  local proposal_path="$1"
  local new_status="$2"
  local new_path
  
  # Rename the file with the new status
  new_path="${proposal_path/%_*\.dsl/_${new_status}.dsl}"
  
  if [[ "$proposal_path" != "$new_path" ]]; then
    mv "$proposal_path" "$new_path"
    log_info "Updated proposal status to: $new_status"
    
    # Return the new path
    echo "$new_path"
  else
    # Return the original path if no change
    echo "$proposal_path"
  fi
}

main() {
  parse_args "$@"
  
  if ! validate_args; then
    exit 1
  fi
  
  # Execute DSL file directly if specified
  if [[ -n "$DSL_FILE" ]]; then
    if confirm_execution "$DSL_FILE"; then
      execute_dsl "$DSL_FILE"
      exit $?
    else
      exit 0
    fi
  fi
  
  # Execute proposal if found
  if [[ -n "$PROPOSAL_PATH" ]]; then
    if confirm_execution "$PROPOSAL_PATH" "$PROPOSAL_ID"; then
      execute_dsl "$PROPOSAL_PATH" "$PROPOSAL_ID"
      exit $?
    else
      exit 0
    fi
  fi
  
  # If we got here, nothing was executed
  log_info "No execution performed"
  exit 0
}

main "$@" 