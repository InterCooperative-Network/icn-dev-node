#!/bin/bash
set -euo pipefail

# ICN Node State Manager
# This script manages a persistent state file for the ICN node

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Default values
DATA_DIR="${HOME}/.icn"
STATE_FILE="${DATA_DIR}/state/node_state.json"
BACKUP_DIR="${DATA_DIR}/state/backups"
VERBOSE=false
ROTATE_BACKUPS=10  # Number of backups to keep

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [COMMAND] [OPTIONS]

Manage ICN node state.

Commands:
  get KEY              Get value for a specific key
  set KEY VALUE        Set value for a specific key
  list                 List all state entries
  backup               Create a backup of the current state
  restore BACKUP       Restore state from a backup file
  clean                Remove old backups keeping only ${ROTATE_BACKUPS} most recent

Options:
  --data-dir DIR       Data directory (default: ~/.icn)
  --verbose            Enable verbose logging
  --help               Display this help message and exit

Examples:
  # Get a specific state value
  $(basename "$0") get lastProposalId
  
  # Set a state value
  $(basename "$0") set lastExecutedBlock 1000
  
  # List all state entries
  $(basename "$0") list
  
  # Backup the current state
  $(basename "$0") backup
EOF
}

parse_args() {
  COMMAND=""
  KEY=""
  VALUE=""
  BACKUP_FILE=""

  # Parse command if present
  if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
    COMMAND="$1"
    shift
  fi

  # Parse command arguments
  case "$COMMAND" in
    get)
      if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
        KEY="$1"
        shift
      else
        log_error "Missing key for 'get' command"
        print_usage
        exit 1
      fi
      ;;
    set)
      if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
        KEY="$1"
        shift
      else
        log_error "Missing key for 'set' command"
        print_usage
        exit 1
      fi
      
      if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
        VALUE="$1"
        shift
      else
        log_error "Missing value for 'set' command"
        print_usage
        exit 1
      fi
      ;;
    restore)
      if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
        BACKUP_FILE="$1"
        shift
      else
        log_error "Missing backup file for 'restore' command"
        print_usage
        exit 1
      fi
      ;;
    list|backup|clean)
      # These commands don't require additional arguments
      ;;
    "")
      log_error "Command required"
      print_usage
      exit 1
      ;;
    *)
      log_error "Unknown command: $COMMAND"
      print_usage
      exit 1
      ;;
  esac
  
  # Parse options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --data-dir)
        DATA_DIR="$2"
        STATE_FILE="${DATA_DIR}/state/node_state.json"
        BACKUP_DIR="${DATA_DIR}/state/backups"
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
        log_error "Unknown option: $1"
        print_usage
        exit 1
        ;;
    esac
  done
}

initialize_state() {
  # Create state directories if they don't exist
  mkdir -p "$(dirname "$STATE_FILE")"
  mkdir -p "$BACKUP_DIR"
  
  # Create initial state file if it doesn't exist
  if [[ ! -f "$STATE_FILE" ]]; then
    log_info "Initializing node state file"
    
    # Initialize with default values
    cat > "$STATE_FILE" <<EOF
{
  "nodeId": "$(uuidgen || echo "unknown-$(date +%s)")",
  "initialized": "$(date --iso-8601=seconds)",
  "lastUpdated": "$(date --iso-8601=seconds)",
  "lastExecutedBlock": 0,
  "lastProposalId": 0,
  "executedProposals": [],
  "activeConnection": "",
  "peers": [],
  "systemVersion": "$(git -C "$SCRIPT_DIR/.." describe --tags --always 2>/dev/null || echo "unknown")"
}
EOF
  fi
}

get_state_value() {
  local key="$1"
  
  if [[ ! -f "$STATE_FILE" ]]; then
    log_error "State file not found: $STATE_FILE"
    return 1
  fi
  
  # Try to get the value
  local value
  value=$(jq -r ".$key // \"\"" "$STATE_FILE")
  
  if [[ -z "$value" || "$value" == "null" ]]; then
    if [[ "$VERBOSE" == true ]]; then
      log_warn "Key not found in state: $key"
    fi
    echo ""
    return 1
  fi
  
  echo "$value"
  return 0
}

set_state_value() {
  local key="$1"
  local value="$2"
  
  initialize_state
  
  # Update the value
  log_info "Setting state: $key = $value"
  
  # Try to detect if value is a JSON object/array or a simple value
  if [[ "$value" =~ ^\{.*\}$ || "$value" =~ ^\[.*\]$ ]]; then
    # Value appears to be JSON, don't wrap in quotes
    jq --arg key "$key" --argjson value "$value" \
      '. + {($key): $value, "lastUpdated": now | todate}' "$STATE_FILE" > "${STATE_FILE}.tmp"
  else
    # Value is a simple value, treat as string
    jq --arg key "$key" --arg value "$value" \
      '. + {($key): $value, "lastUpdated": now | todate}' "$STATE_FILE" > "${STATE_FILE}.tmp"
  fi
  
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

list_state() {
  if [[ ! -f "$STATE_FILE" ]]; then
    log_error "State file not found: $STATE_FILE"
    return 1
  fi
  
  log_info "Node state:"
  
  # Pretty print state
  jq '.' "$STATE_FILE"
}

backup_state() {
  if [[ ! -f "$STATE_FILE" ]]; then
    log_error "State file not found: $STATE_FILE"
    return 1
  }
  
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_file="${BACKUP_DIR}/node_state_${timestamp}.json"
  
  cp "$STATE_FILE" "$backup_file"
  log_success "State backup created: $backup_file"
  
  # Clean old backups if needed
  clean_old_backups
}

restore_state() {
  local backup_file="$1"
  
  if [[ ! -f "$backup_file" ]]; then
    log_error "Backup file not found: $backup_file"
    return 1
  }
  
  # Backup current state before restore
  backup_state
  
  # Restore from backup
  mkdir -p "$(dirname "$STATE_FILE")"
  cp "$backup_file" "$STATE_FILE"
  log_success "State restored from: $backup_file"
}

clean_old_backups() {
  # Keep only the last ROTATE_BACKUPS backups
  local backups
  
  if [[ ! -d "$BACKUP_DIR" ]]; then
    return 0
  fi
  
  backups=$(find "$BACKUP_DIR" -name "node_state_*.json" -type f | sort -r)
  
  local count=0
  while read -r backup; do
    count=$((count + 1))
    
    if [[ $count -gt $ROTATE_BACKUPS ]]; then
      if [[ "$VERBOSE" == true ]]; then
        log_info "Removing old backup: $backup"
      fi
      rm -f "$backup"
    fi
  done <<< "$backups"
}

add_to_array() {
  local key="$1"
  local value="$2"
  
  initialize_state
  
  # Add value to array and ensure uniqueness
  log_info "Adding to array: $key += $value"
  
  # Check if key exists and is an array
  local is_array
  is_array=$(jq ".$key | type == \"array\"" "$STATE_FILE")
  
  if [[ "$is_array" != "true" ]]; then
    # Create empty array if key doesn't exist or isn't an array
    jq --arg key "$key" '. + {($key): []}' "$STATE_FILE" > "${STATE_FILE}.tmp"
    mv "${STATE_FILE}.tmp" "$STATE_FILE"
  fi
  
  # Add value to array if not already present
  jq --arg key "$key" --arg value "$value" \
    '. + {($key): (.[($key)] + [$value] | unique), "lastUpdated": now | todate}' "$STATE_FILE" > "${STATE_FILE}.tmp"
  
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

remove_from_array() {
  local key="$1"
  local value="$2"
  
  if [[ ! -f "$STATE_FILE" ]]; then
    log_error "State file not found: $STATE_FILE"
    return 1
  }
  
  # Remove value from array
  log_info "Removing from array: $key -= $value"
  
  # Check if key exists and is an array
  local is_array
  is_array=$(jq ".$key | type == \"array\"" "$STATE_FILE")
  
  if [[ "$is_array" != "true" ]]; then
    log_warn "Key is not an array: $key"
    return 1
  fi
  
  # Remove value from array
  jq --arg key "$key" --arg value "$value" \
    '. + {($key): (.[($key)] - [$value]), "lastUpdated": now | todate}' "$STATE_FILE" > "${STATE_FILE}.tmp"
  
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

record_execution() {
  local proposal_id="$1"
  local status="$2"
  local timestamp
  timestamp=$(date --iso-8601=seconds)
  
  # Create JSON for execution record
  local execution_record
  execution_record=$(cat <<EOF
{
  "id": "$proposal_id",
  "status": "$status",
  "timestamp": "$timestamp"
}
EOF
)
  
  # Add to executedProposals array
  jq --argjson record "$execution_record" \
    '. + {"executedProposals": (.executedProposals + [$record]), "lastUpdated": now | todate}' "$STATE_FILE" > "${STATE_FILE}.tmp"
  
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
  
  # Update lastProposalId if needed
  local current_id
  current_id=$(get_state_value "lastProposalId" || echo "0")
  
  if [[ "$proposal_id" =~ ^[0-9]+$ && "$proposal_id" -gt "$current_id" ]]; then
    set_state_value "lastProposalId" "$proposal_id"
  fi
}

main() {
  parse_args "$@"
  
  case "$COMMAND" in
    get)
      get_state_value "$KEY"
      ;;
    set)
      set_state_value "$KEY" "$VALUE"
      ;;
    list)
      list_state
      ;;
    backup)
      backup_state
      ;;
    restore)
      restore_state "$BACKUP_FILE"
      ;;
    clean)
      clean_old_backups
      ;;
    *)
      log_error "Unknown command: $COMMAND"
      print_usage
      exit 1
      ;;
  esac
}

main "$@" 