#!/bin/bash
# Common utility functions for ICN node scripts

# Log levels
LOG_LEVEL_ERROR=0
LOG_LEVEL_WARN=1
LOG_LEVEL_INFO=2
LOG_LEVEL_DEBUG=3

# Default log level
CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO

# Set log level
set_log_level() {
  local level="${1:-info}"
  case "$level" in
    error) CURRENT_LOG_LEVEL=$LOG_LEVEL_ERROR ;;
    warn)  CURRENT_LOG_LEVEL=$LOG_LEVEL_WARN ;;
    info)  CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO ;;
    debug) CURRENT_LOG_LEVEL=$LOG_LEVEL_DEBUG ;;
    *)
      echo "Unknown log level: $level. Using 'info'"
      CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO
      ;;
  esac
}

# Logging functions
log_error() {
  if [[ $CURRENT_LOG_LEVEL -ge $LOG_LEVEL_ERROR ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*" >&2
  fi
}

log_warn() {
  if [[ $CURRENT_LOG_LEVEL -ge $LOG_LEVEL_WARN ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] $*" >&2
  fi
}

log_info() {
  if [[ $CURRENT_LOG_LEVEL -ge $LOG_LEVEL_INFO ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*"
  fi
}

log_debug() {
  if [[ $CURRENT_LOG_LEVEL -ge $LOG_LEVEL_DEBUG ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') [DEBUG] $*"
  fi
}

# Check if a command is available
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check if running as root
is_root() {
  [[ $EUID -eq 0 ]]
}

# Get absolute path
get_abs_path() {
  local path="$1"
  if [[ -d "$path" ]]; then
    (cd "$path" && pwd)
  elif [[ -f "$path" ]]; then
    local dir
    dir=$(dirname "$path")
    local base
    base=$(basename "$path")
    echo "$(cd "$dir" && pwd)/$base"
  else
    echo "$path"
  fi
}

# Check if a port is in use
is_port_in_use() {
  local port="$1"
  if command_exists nc; then
    nc -z localhost "$port" >/dev/null 2>&1
    return $?
  elif command_exists lsof; then
    lsof -i:"$port" >/dev/null 2>&1
    return $?
  else
    # Fallback to /dev/tcp on bash
    (</dev/tcp/localhost/"$port") >/dev/null 2>&1
    return $?
  fi
}

# Find an available port starting from a base port
find_available_port() {
  local base_port="$1"
  local port="$base_port"
  
  while is_port_in_use "$port"; do
    port=$((port + 1))
  done
  
  echo "$port"
}

# Check if a node is running
is_node_running() {
  local port="${1:-26657}"  # Default RPC port
  
  if command_exists curl; then
    curl -s "http://localhost:$port/status" >/dev/null 2>&1
    return $?
  elif command_exists wget; then
    wget -q -O - "http://localhost:$port/status" >/dev/null 2>&1
    return $?
  else
    # Fallback to just checking if the port is in use
    is_port_in_use "$port"
    return $?
  fi
}

# Get node status information
get_node_status() {
  local port="${1:-26657}"  # Default RPC port
  local format="${2:-text}" # Output format: text, json
  
  if ! is_node_running "$port"; then
    log_error "Node is not running on port $port"
    return 1
  fi
  
  local status_url="http://localhost:$port/status"
  local status
  
  if command_exists curl; then
    status=$(curl -s "$status_url")
  elif command_exists wget; then
    status=$(wget -q -O - "$status_url")
  else
    log_error "Neither curl nor wget is available"
    return 1
  fi
  
  if [[ "$format" == "json" ]]; then
    echo "$status"
  else
    # Extract useful fields for text output
    if command_exists jq; then
      local node_info
      node_info=$(echo "$status" | jq -r '.result.node_info // empty')
      local latest_block_height
      latest_block_height=$(echo "$status" | jq -r '.result.sync_info.latest_block_height // "unknown"')
      
      if [[ -n "$node_info" ]]; then
        local id
        id=$(echo "$node_info" | jq -r '.id // "unknown"')
        local moniker
        moniker=$(echo "$node_info" | jq -r '.moniker // "unknown"')
        local network
        network=$(echo "$node_info" | jq -r '.network // "unknown"')
        
        echo "Node ID: $id"
        echo "Moniker: $moniker"
        echo "Network: $network"
        echo "Latest Block: $latest_block_height"
      else
        # Fallback to raw JSON if jq parsing fails
        echo "$status"
      fi
    else
      # Without jq, just return the raw JSON
      echo "$status"
    fi
  fi
}

# Check dependencies for the ICN node
check_dependencies() {
  local missing=0
  
  log_info "Checking dependencies..."
  
  # Required dependencies
  local deps=("git" "rustc" "cargo" "jq")
  
  for dep in "${deps[@]}"; do
    if ! command_exists "$dep"; then
      log_error "Missing dependency: $dep"
      missing=$((missing + 1))
    else
      log_debug "Found dependency: $dep"
    fi
  done
  
  # Platform-specific dependencies
  case "$(uname -s)" in
    Linux)
      if ! command_exists pkg-config; then
        log_error "Missing dependency: pkg-config"
        missing=$((missing + 1))
      fi
      
      # Check for libssl-dev by checking for openssl/ssl.h
      if ! pkg-config --exists openssl 2>/dev/null; then
        log_error "Missing dependency: libssl-dev"
        missing=$((missing + 1))
      fi
      ;;
    Darwin)
      if ! command_exists pkg-config; then
        log_error "Missing dependency: pkg-config"
        missing=$((missing + 1))
      fi
      
      if ! pkg-config --exists openssl 2>/dev/null; then
        log_error "Missing dependency: openssl"
        missing=$((missing + 1))
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      # Windows-specific checks
      log_warn "Running on Windows. Some features may not work as expected."
      ;;
  esac
  
  # Optional dependencies
  local opt_deps=("docker" "docker-compose")
  
  for dep in "${opt_deps[@]}"; do
    if ! command_exists "$dep"; then
      log_warn "Optional dependency not found: $dep"
    else
      log_debug "Found optional dependency: $dep"
    fi
  done
  
  if [[ $missing -gt 0 ]]; then
    log_warn "Missing $missing required dependencies"
    return 1
  else
    log_info "All required dependencies are installed"
    return 0
  fi
}

# Check if a specific binary is built
is_binary_built() {
  local binary_name="$1"
  local binary_path="${2:-${HOME}/.cargo/bin/$binary_name}"
  
  [[ -x "$binary_path" ]]
}

# Get a configuration value from TOML file
get_config_value() {
  local config_file="$1"
  local key="$2"
  local default="${3:-}"
  
  if [[ ! -f "$config_file" ]]; then
    echo "$default"
    return 1
  fi
  
  if command_exists jq && command_exists yq; then
    # Use yq to convert TOML to JSON, then jq to extract the value
    local value
    value=$(yq -p=toml -o=json eval "$config_file" | jq -r ".$key // empty")
    if [[ -n "$value" ]]; then
      echo "$value"
    else
      echo "$default"
    fi
  else
    # Fallback to grep/sed for simple keys
    local value
    value=$(grep -E "^$key\s*=\s*" "$config_file" | sed -E "s/^$key\s*=\s*//;s/\"//g")
    if [[ -n "$value" ]]; then
      echo "$value"
    else
      echo "$default"
    fi
  fi
}

# Export functions
export -f set_log_level
export -f log_error
export -f log_warn
export -f log_info
export -f log_debug
export -f command_exists
export -f is_root
export -f get_abs_path
export -f is_port_in_use
export -f find_available_port
export -f is_node_running
export -f get_node_status
export -f check_dependencies
export -f is_binary_built
export -f get_config_value 