#!/bin/bash
set -euo pipefail

# Install the ICN Node systemd service

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/../common.sh"

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Install the ICN Node as a systemd service.

Options:
  --user USER           User to run the service as (default: current user)
  --node-type TYPE      Node type: 'dev', 'testnet', or 'livenet' (default: dev)
  --data-dir DIR        Data directory (default: ~/.icn)
  --auto-register       Automatically register DNS and DID
  --no-federation       Disable federation
  --no-storage          Disable storage
  --help                Display this help message and exit

Example:
  $(basename "$0") --user alice --node-type testnet --auto-register
EOF
}

# Default values
SERVICE_USER="$(whoami)"
NODE_TYPE="dev"
DATA_DIR="${HOME}/.icn"
AUTO_REGISTER=false
FEDERATION=true
STORAGE=true

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user)
        SERVICE_USER="$2"
        shift 2
        ;;
      --node-type)
        NODE_TYPE="$2"
        shift 2
        ;;
      --data-dir)
        DATA_DIR="$2"
        shift 2
        ;;
      --auto-register)
        AUTO_REGISTER=true
        shift
        ;;
      --no-federation)
        FEDERATION=false
        shift
        ;;
      --no-storage)
        STORAGE=false
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
  if [[ ! "$NODE_TYPE" =~ ^(dev|testnet|livenet)$ ]]; then
    log_error "Node type must be 'dev', 'testnet', or 'livenet'"
    exit 1
  fi
  
  if ! id "$SERVICE_USER" &>/dev/null; then
    log_error "User '$SERVICE_USER' does not exist"
    exit 1
  fi
}

install_service() {
  if ! is_root; then
    log_error "This script must be run as root to install the systemd service"
    exit 1
  }
  
  log_info "Installing ICN Node systemd service for user '$SERVICE_USER'..."
  
  # Copy service file to systemd directory
  local service_name="icn-node@${SERVICE_USER}.service"
  local service_path="/etc/systemd/system/${service_name}"
  
  cp "${SCRIPT_DIR}/icn-node.service" "$service_path"
  
  # Create the daemon config file
  local user_home
  user_home=$(eval echo "~${SERVICE_USER}")
  local config_dir="${user_home}/.icn/config"
  mkdir -p "$config_dir"
  
  local daemon_config="${config_dir}/daemon.conf"
  cat > "$daemon_config" <<EOF
# ICN Node Daemon Configuration
# Created on $(date)

# Node type: dev, testnet, or livenet
NODE_TYPE="${NODE_TYPE}"

# Data directory
DATA_DIR="${DATA_DIR}"

# Auto-register DNS and DID
AUTO_REGISTER=${AUTO_REGISTER}

# Enable federation
FEDERATION=${FEDERATION}

# Enable storage
STORAGE=${STORAGE}
EOF

  # Set proper permissions
  chown -R "${SERVICE_USER}:${SERVICE_USER}" "$(dirname "$daemon_config")"
  
  # Reload systemd and enable service
  systemctl daemon-reload
  systemctl enable "$service_name"
  
  log_info "Service installed successfully as $service_name"
  log_info "You can now start it with: sudo systemctl start $service_name"
}

main() {
  parse_args "$@"
  validate_args
  install_service
}

main "$@" 