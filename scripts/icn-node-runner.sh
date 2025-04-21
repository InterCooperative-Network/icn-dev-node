#!/bin/bash
set -euo pipefail

# ICN Node Runner Wrapper Script
# This script is a wrapper around the Rust icn-node binary

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Log functions in case common.sh doesn't provide them
if ! declare -f log_success &> /dev/null; then
  log_success() {
    echo -e "\033[32m$(date '+%Y-%m-%d %H:%M:%S') [SUCCESS] $*\033[0m"
  }
fi

if ! declare -f log_warn &> /dev/null; then
  log_warn() {
    echo -e "\033[33m$(date '+%Y-%m-%d %H:%M:%S') [WARN] $*\033[0m"
  }
fi

if ! declare -f log_error &> /dev/null; then
  log_error() {
    echo -e "\033[31m$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*\033[0m" >&2
  }
fi

if ! declare -f log_info &> /dev/null; then
  log_info() {
    echo -e "\033[36m$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*\033[0m"
  }
fi

# Default values
RUST_NODE_BIN="${SCRIPT_DIR}/../target/debug/icn-node"
DATA_DIR="${HOME}/.icn"
LOG_FILE="${DATA_DIR}/logs/icn-node.log"
PID_FILE="${DATA_DIR}/icn-node.pid"
CHECK_INTERVAL=30
RUN_MODE="daemon"
TRACE_PROPOSAL=""
EXECUTE_FILE=""
FORCE_EXECUTE=false
VERBOSE=false

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [COMMAND] [OPTIONS]

Run the Cooperative Node Runner for ICN.

Commands:
  run                   Run the node in daemon mode (default)
  execute FILE          Execute a specific proposal file
  trace PROPOSAL_ID     Trace a proposal execution
  watch                 Watch DAG and proposal queue

Options:
  --data-dir DIR        Data directory (default: ~/.icn)
  --interval SEC        Check interval in seconds (default: 30)
  --force               Force execution without validation
  --verbose             Enable verbose logging
  --help                Display this help message and exit

Examples:
  # Run in daemon mode
  $(basename "$0") run --interval 15
  
  # Execute a specific proposal
  $(basename "$0") execute path/to/proposal.dsl
  
  # Trace a proposal
  $(basename "$0") trace 123
EOF
}

parse_args() {
  # Parse command if present
  if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
    RUN_MODE="$1"
    shift
    
    # Parse additional command arguments
    case "$RUN_MODE" in
      execute)
        if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
          EXECUTE_FILE="$1"
          shift
        else
          log_error "Missing file argument for 'execute' command"
          print_usage
          exit 1
        fi
        ;;
      trace)
        if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
          TRACE_PROPOSAL="$1"
          shift
        else
          log_error "Missing proposal ID for 'trace' command"
          print_usage
          exit 1
        fi
        ;;
      run|watch)
        # No additional arguments needed
        ;;
      *)
        log_error "Unknown command: $RUN_MODE"
        print_usage
        exit 1
        ;;
    esac
  fi
  
  # Parse options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --data-dir)
        DATA_DIR="$2"
        LOG_FILE="${DATA_DIR}/logs/icn-node.log"
        PID_FILE="${DATA_DIR}/icn-node.pid"
        shift 2
        ;;
      --interval)
        CHECK_INTERVAL="$2"
        shift 2
        ;;
      --force)
        FORCE_EXECUTE=true
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
        log_error "Unknown option: $1"
        print_usage
        exit 1
        ;;
    esac
  done
}

validate_args() {
  # Check if rust binary exists and build if needed
  if [[ ! -x "$RUST_NODE_BIN" ]]; then
    log_info "Rust node binary not found, building..."
    
    if ! command -v cargo &> /dev/null; then
      log_error "Cargo not found. Please install Rust and Cargo."
      exit 1
    fi
    
    (
      cd "${SCRIPT_DIR}/.."
      cargo build --bin icn-node
    )
    
    if [[ ! -x "$RUST_NODE_BIN" ]]; then
      log_error "Failed to build Rust node binary"
      exit 1
    fi
  fi
  
  # Create necessary directories
  mkdir -p "$(dirname "$LOG_FILE")"
  mkdir -p "${DATA_DIR}/queue"
  mkdir -p "${DATA_DIR}/executed"
}

run_node() {
  log_info "Starting ICN node runner in $RUN_MODE mode"
  
  case "$RUN_MODE" in
    run)
      # Run as daemon
      local cmd="$RUST_NODE_BIN run --interval $CHECK_INTERVAL"
      [[ "$VERBOSE" == true ]] && cmd="$cmd --log-level debug"
      
      log_info "Executing: $cmd"
      
      if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
          log_warn "Node already running with PID $pid"
          return 0
        else
          log_info "Removing stale PID file"
          rm -f "$PID_FILE"
        fi
      fi
      
      nohup "$RUST_NODE_BIN" run --interval "$CHECK_INTERVAL" \
        $([[ "$VERBOSE" == true ]] && echo "--log-level debug") \
        > "$LOG_FILE" 2>&1 &
      
      echo $! > "$PID_FILE"
      log_success "Node started with PID $(cat "$PID_FILE")"
      ;;
      
    execute)
      # Execute proposal file
      local cmd="$RUST_NODE_BIN execute --file \"$EXECUTE_FILE\""
      [[ "$FORCE_EXECUTE" == true ]] && cmd="$cmd --force"
      [[ "$VERBOSE" == true ]] && cmd="$cmd --log-level debug"
      
      log_info "Executing: $cmd"
      eval "$cmd"
      ;;
      
    trace)
      # Trace proposal
      local cmd="$RUST_NODE_BIN trace --proposal \"$TRACE_PROPOSAL\""
      [[ "$VERBOSE" == true ]] && cmd="$cmd --log-level debug"
      
      log_info "Executing: $cmd"
      eval "$cmd"
      ;;
      
    watch)
      # Watch DAG and queue
      local cmd="$RUST_NODE_BIN watch"
      [[ "$VERBOSE" == true ]] && cmd="$cmd --log-level debug"
      
      log_info "Executing: $cmd"
      eval "$cmd"
      ;;
  esac
}

stop_node() {
  if [[ -f "$PID_FILE" ]]; then
    local pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      log_info "Stopping ICN node with PID $pid"
      kill "$pid"
      rm -f "$PID_FILE"
      log_success "Node stopped"
    else
      log_info "No running node found"
      rm -f "$PID_FILE"
    fi
  else
    log_info "No PID file found, node not running"
  fi
}

# Main execution
parse_args "$@"
validate_args
run_node 