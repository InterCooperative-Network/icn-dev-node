#!/bin/bash

# Federation Status Check and Diagnostics Tool
# This script helps validate federation connections and diagnose issues

set -e

# Default values
NODE_URL="http://localhost:26657"
BOOTSTRAP_PEERS_FILE="config/bootstrap-peers.toml"
VERBOSE=false
OUTPUT_FORMAT="human" # Options: human, json
TIMEOUT=3
CHECK_INTERVAL=0  # 0 means run once, >0 means monitor every N seconds
MIN_PEERS=2

# ANSI color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print header
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}    ICN Federation Status Check       ${NC}"
echo -e "${BLUE}======================================${NC}"

# Function to show usage
show_usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --node-url URL       Node RPC URL to check (default: http://localhost:26657)"
  echo "  --peers FILE         Bootstrap peers file (default: config/bootstrap-peers.toml)"
  echo "  --min-peers N        Minimum required peers for healthy federation (default: 2)"
  echo "  --monitor N          Monitor mode: check every N seconds (default: run once)"
  echo "  --timeout N          Connection timeout in seconds (default: 3)"
  echo "  --json               Output results in JSON format"
  echo "  --verbose            Enable verbose logging"
  echo "  --help               Show this help message"
  echo ""
  echo "Examples:"
  echo "  $0 --node-url http://mynode:26657 --peers my-peers.toml"
  echo "  $0 --monitor 60 --min-peers 3      # Check every minute, require 3+ peers"
  exit 1
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --node-url)
      NODE_URL="$2"
      shift 2
      ;;
    --peers)
      BOOTSTRAP_PEERS_FILE="$2"
      shift 2
      ;;
    --min-peers)
      MIN_PEERS="$2"
      shift 2
      ;;
    --monitor)
      CHECK_INTERVAL="$2"
      shift 2
      ;;
    --timeout)
      TIMEOUT="$2"
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
      show_usage
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      show_usage
      ;;
  esac
done

# Check for required tools
if ! command -v curl &> /dev/null; then
  echo -e "${RED}Error: 'curl' is required but not found${NC}"
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo -e "${RED}Error: 'jq' is required but not found${NC}"
  exit 1
fi

# Function to check if the node is reachable
check_node_status() {
  if [[ "$VERBOSE" = true ]]; then
    echo -e "${BLUE}Checking node status at $NODE_URL...${NC}"
  fi
  
  if ! curl -s --max-time "$TIMEOUT" "$NODE_URL/status" > /dev/null; then
    if [[ "$OUTPUT_FORMAT" = "human" ]]; then
      echo -e "${RED}ERROR: Node is not reachable at $NODE_URL${NC}"
    else
      echo '{"status":"error","error":"Node not reachable","node_url":"'$NODE_URL'"}'
    fi
    return 1
  fi
  
  local status_response
  status_response=$(curl -s --max-time "$TIMEOUT" "$NODE_URL/status")
  
  # Extract node ID and moniker
  local node_id
  node_id=$(echo "$status_response" | jq -r '.result.node_info.id')
  
  local moniker
  moniker=$(echo "$status_response" | jq -r '.result.node_info.moniker')
  
  if [[ "$OUTPUT_FORMAT" = "human" ]]; then
    echo -e "${GREEN}Node is reachable:${NC}"
    echo -e "  ID: $node_id"
    echo -e "  Moniker: $moniker"
  else
    echo '{"status":"ok","node_id":"'$node_id'","moniker":"'$moniker'","node_url":"'$NODE_URL'"}'
  fi
  
  return 0
}

# Function to check net info and peers
check_federation_status() {
  if [[ "$VERBOSE" = true ]]; then
    echo -e "${BLUE}Checking federation status...${NC}"
  fi
  
  local net_info
  net_info=$(curl -s --max-time "$TIMEOUT" "$NODE_URL/net_info")
  
  # Extract peer count
  local peer_count
  peer_count=$(echo "$net_info" | jq -r '.result.n_peers')
  
  # Extract peer details
  local peers_json
  peers_json=$(echo "$net_info" | jq -r '.result.peers')
  
  # Check if we have minimum required peers
  local federation_health
  if [ "$peer_count" -ge "$MIN_PEERS" ]; then
    federation_health="healthy"
  else
    federation_health="unhealthy"
  fi
  
  if [[ "$OUTPUT_FORMAT" = "human" ]]; then
    if [ "$peer_count" -ge "$MIN_PEERS" ]; then
      echo -e "${GREEN}Federation status: HEALTHY${NC}"
    else
      echo -e "${RED}Federation status: UNHEALTHY${NC}"
      echo -e "${YELLOW}Connected to $peer_count peers, but minimum requirement is $MIN_PEERS${NC}"
    fi
    
    echo -e "Connected peers: $peer_count"
    
    # Show peer details
    if [ "$peer_count" -gt 0 ]; then
      echo -e "\nPeer details:"
      for ((i=0; i<peer_count; i++)); do
        local peer_id
        peer_id=$(echo "$peers_json" | jq -r ".[$i].node_info.id")
        
        local peer_moniker
        peer_moniker=$(echo "$peers_json" | jq -r ".[$i].node_info.moniker")
        
        local peer_addr
        peer_addr=$(echo "$peers_json" | jq -r ".[$i].remote_ip")
        
        echo -e "  $((i+1)). $peer_moniker ($peer_id) @ $peer_addr"
      done
    fi
  else
    # JSON output
    echo "$net_info" | jq '{
      status: "ok",
      federation_status: "'$federation_health'",
      peer_count: '$peer_count',
      min_peers_required: '$MIN_PEERS',
      peers: [.result.peers[] | {
        id: .node_info.id,
        moniker: .node_info.moniker,
        address: .remote_ip
      }]
    }'
  fi
}

# Function to check federation configuration
check_federation_config() {
  if [[ "$VERBOSE" = true ]]; then
    echo -e "${BLUE}Checking federation configuration...${NC}"
  fi
  
  # Check if bootstrap peers file exists
  if [[ ! -f "$BOOTSTRAP_PEERS_FILE" ]]; then
    if [[ "$OUTPUT_FORMAT" = "human" ]]; then
      echo -e "${RED}ERROR: Bootstrap peers file not found: $BOOTSTRAP_PEERS_FILE${NC}"
    else
      echo '{"status":"error","error":"Bootstrap peers file not found","file":"'$BOOTSTRAP_PEERS_FILE'"}'
    fi
    return 1
  fi
  
  # Read bootstrap peers
  local bootstrap_peers
  if grep -q "peers = " "$BOOTSTRAP_PEERS_FILE"; then
    # Handle array format
    bootstrap_peers=$(grep -A 10 "peers = \[" "$BOOTSTRAP_PEERS_FILE" | 
                      sed -n '/\[/,/\]/p' | 
                      grep -oE '"[^"]+"' | 
                      sed 's/"//g')
  else
    # Handle key-value format
    bootstrap_peers=$(grep "peer[0-9]* = " "$BOOTSTRAP_PEERS_FILE" | 
                      cut -d '"' -f 2)
  fi
  
  # Count bootstrap peers
  local bootstrap_peer_count
  bootstrap_peer_count=$(echo "$bootstrap_peers" | wc -l)
  
  if [[ "$OUTPUT_FORMAT" = "human" ]]; then
    echo -e "Bootstrap peers configuration from $BOOTSTRAP_PEERS_FILE:"
    echo -e "  Total configured peers: $bootstrap_peer_count"
    
    if [[ "$VERBOSE" = true ]]; then
      echo -e "\nPeer addresses:"
      echo "$bootstrap_peers" | while read -r peer; do
        echo -e "  - $peer"
      done
    fi
  else
    # Convert bootstrap peers to JSON array
    local peers_json
    peers_json="["
    first=true
    while read -r peer; do
      if [ "$first" = true ]; then
        first=false
      else
        peers_json="$peers_json,"
      fi
      peers_json="$peers_json\"$peer\""
    done <<< "$bootstrap_peers"
    peers_json="$peers_json]"
    
    echo "{\"status\":\"ok\",\"config_file\":\"$BOOTSTRAP_PEERS_FILE\",\"peer_count\":$bootstrap_peer_count,\"peers\":$peers_json}"
  fi
}

# Function to test connectivity to bootstrap peers
test_bootstrap_connectivity() {
  if [[ "$VERBOSE" = true ]]; then
    echo -e "${BLUE}Testing connectivity to bootstrap peers...${NC}"
  fi
  
  # Read bootstrap peers
  local bootstrap_peers
  if grep -q "peers = " "$BOOTSTRAP_PEERS_FILE"; then
    # Handle array format
    bootstrap_peers=$(grep -A 10 "peers = \[" "$BOOTSTRAP_PEERS_FILE" | 
                      sed -n '/\[/,/\]/p' | 
                      grep -oE '"[^"]+"' | 
                      sed 's/"//g')
  else
    # Handle key-value format
    bootstrap_peers=$(grep "peer[0-9]* = " "$BOOTSTRAP_PEERS_FILE" | 
                      cut -d '"' -f 2)
  fi
  
  local reachable_count=0
  local unreachable_count=0
  local reachable_peers=()
  local unreachable_peers=()
  
  if [[ "$OUTPUT_FORMAT" = "human" ]]; then
    echo -e "\nTesting connectivity to bootstrap peers:"
  fi
  
  # Test each peer
  while read -r peer; do
    # Extract node ID and address
    local node_id=${peer%%@*}
    local node_addr=${peer##*@}
    
    if [[ "$VERBOSE" = true && "$OUTPUT_FORMAT" = "human" ]]; then
      echo -e "  Testing $node_id @ $node_addr..."
    fi
    
    # Try to connect
    if curl -s --max-time "$TIMEOUT" "http://$node_addr/status" > /dev/null; then
      reachable_count=$((reachable_count + 1))
      reachable_peers+=("$peer")
      
      if [[ "$OUTPUT_FORMAT" = "human" ]]; then
        echo -e "  ${GREEN}✓ $peer is reachable${NC}"
      fi
    else
      unreachable_count=$((unreachable_count + 1))
      unreachable_peers+=("$peer")
      
      if [[ "$OUTPUT_FORMAT" = "human" ]]; then
        echo -e "  ${RED}✗ $peer is not reachable${NC}"
      fi
    fi
  done <<< "$bootstrap_peers"
  
  local total_peers=$((reachable_count + unreachable_count))
  
  if [[ "$OUTPUT_FORMAT" = "human" ]]; then
    echo -e "\nConnectivity summary:"
    echo -e "  Total peers: $total_peers"
    echo -e "  Reachable: $reachable_count"
    echo -e "  Unreachable: $unreachable_count"
    
    if [ "$reachable_count" -lt "$MIN_PEERS" ]; then
      echo -e "\n${RED}WARNING: Not enough reachable bootstrap peers!${NC}"
      echo -e "${YELLOW}Federation requires at least $MIN_PEERS connected peers.${NC}"
    elif [ "$reachable_count" -eq 0 ]; then
      echo -e "\n${RED}CRITICAL: No bootstrap peers are reachable!${NC}"
      echo -e "${YELLOW}Check your network connection and peer configurations.${NC}"
    fi
  else
    # Build JSON arrays for reachable and unreachable peers
    local reachable_json="["
    local unreachable_json="["
    
    local first=true
    for peer in "${reachable_peers[@]}"; do
      if [ "$first" = true ]; then
        first=false
      else
        reachable_json="$reachable_json,"
      fi
      reachable_json="$reachable_json\"$peer\""
    done
    reachable_json="$reachable_json]"
    
    first=true
    for peer in "${unreachable_peers[@]}"; do
      if [ "$first" = true ]; then
        first=false
      else
        unreachable_json="$unreachable_json,"
      fi
      unreachable_json="$unreachable_json\"$peer\""
    done
    unreachable_json="$unreachable_json]"
    
    echo "{\"status\":\"ok\",\"total_peers\":$total_peers,\"reachable_count\":$reachable_count,\"unreachable_count\":$unreachable_count,\"reachable\":$reachable_json,\"unreachable\":$unreachable_json}"
  fi
}

# Function to run all checks
run_federation_checks() {
  if [[ "$OUTPUT_FORMAT" = "human" ]]; then
    echo -e "\n${BLUE}Running federation status check at $(date)${NC}"
    echo -e "${BLUE}--------------------------------------${NC}\n"
  fi
  
  # Check if the node is running
  if ! check_node_status; then
    return 1
  fi
  
  echo ""
  
  # Check federation configuration
  check_federation_config
  
  echo ""
  
  # Test connectivity to bootstrap peers
  test_bootstrap_connectivity
  
  echo ""
  
  # Check federation status
  check_federation_status
  
  if [[ "$OUTPUT_FORMAT" = "human" ]]; then
    echo -e "\n${BLUE}--------------------------------------${NC}"
  fi
}

# Main execution
if [ "$CHECK_INTERVAL" -eq 0 ]; then
  # Run once
  run_federation_checks
else
  # Monitor mode
  if [[ "$OUTPUT_FORMAT" = "human" ]]; then
    echo -e "${BLUE}Federation monitoring mode enabled.${NC}"
    echo -e "${BLUE}Checking every $CHECK_INTERVAL seconds. Press Ctrl+C to stop.${NC}\n"
  fi
  
  while true; do
    run_federation_checks
    
    if [[ "$OUTPUT_FORMAT" = "human" ]]; then
      echo -e "${YELLOW}Next check in $CHECK_INTERVAL seconds...${NC}"
    fi
    
    sleep "$CHECK_INTERVAL"
  done
fi 