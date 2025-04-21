#!/usr/bin/env bash
set -euo pipefail

# Default settings
NO_START=false
DATA_DIR="$HOME/.icn-node"
AMOUNT="100token"
VOTING_PERIOD="30s"  # Short voting period for demo
SCOPED_IDENTITY=""
PROPOSAL_TYPE="Text"
SHOW_DAG_STATE=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --no-start)
      NO_START=true
      shift
      ;;
    --data-dir)
      DATA_DIR="$2"
      shift 2
      ;;
    --amount)
      AMOUNT="$2"
      shift 2
      ;;
    --voting-period)
      VOTING_PERIOD="$2"
      shift 2
      ;;
    --scoped-identity)
      SCOPED_IDENTITY="$2"
      shift 2
      ;;
    --proposal-type)
      PROPOSAL_TYPE="$2"
      shift 2
      ;;
    --no-dag)
      SHOW_DAG_STATE=false
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--no-start] [--data-dir <dir>] [--amount <amount>] [--voting-period <period>] [--scoped-identity <identity>] [--proposal-type <type>] [--no-dag]"
      exit 1
      ;;
  esac
done

# Load environment variables if .env exists
if [[ -f ../.env ]]; then
  # shellcheck disable=SC1091
  source ../.env
fi

# Function to check if there's a running node
check_node_running() {
  if ! curl -s http://localhost:26657/status > /dev/null; then
    if [[ "$NO_START" = true ]]; then
      echo "❌ No node is running and --no-start was specified. Exiting."
      exit 1
    else
      echo "No node is running. Starting a local node..."
      ./run-node.sh --data-dir "$DATA_DIR" &
      NODE_PID=$!
      echo "Node started with PID $NODE_PID"
      echo "Waiting for node to start..."
      
      # Wait for node to start with timeout
      local max_attempts=30
      local attempts=0
      while ! curl -s http://localhost:26657/status > /dev/null && [[ $attempts -lt $max_attempts ]]; do
        sleep 1
        ((attempts++))
        echo -n "."
      done
      
      if [[ $attempts -ge $max_attempts ]]; then
        echo -e "\n❌ Timed out waiting for node to start"
        exit 1
      fi
      
      echo -e "\n✅ Node is running"
    fi
  else
    echo "✅ Node is running"
  fi
}

# Get validator address from node
get_validator_address() {
  local address
  if [[ -n "$SCOPED_IDENTITY" ]]; then
    echo "Using provided scoped identity: $SCOPED_IDENTITY"
    address="$SCOPED_IDENTITY"
  else
    echo "Getting validator address from the node..."
    address=$(curl -s http://localhost:26657/status | grep -o '"address":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [[ -z "$address" ]]; then
      echo "❌ Could not get validator address from node"
      exit 1
    fi
    echo "Found validator address: $address"
  fi
  echo "$address"
}

# Create a governance proposal
create_proposal() {
  local title="Demo Proposal $(date +%s)"
  local description="This is a demonstration proposal created by the ICN dev node."
  local validator_address="$1"
  
  echo "Creating $PROPOSAL_TYPE proposal..."
  echo "  - Title: $title"
  echo "  - Description: $description"
  echo "  - Deposit: $AMOUNT"
  echo "  - Proposer: $validator_address"
  
  # Find the node binary
  local node_binary
  node_binary=$(find ../deps/icn-covm/target -name "icn-node" -type f -executable | head -1)
  
  if [[ -z "$node_binary" ]]; then
    echo "❌ Could not find node binary"
    exit 1
  fi
  
  # Submit the proposal using the CLI
  echo "Submitting proposal to the chain..."
  "$node_binary" tx gov submit-proposal \
    --title "$title" \
    --description "$description" \
    --type "$PROPOSAL_TYPE" \
    --deposit "$AMOUNT" \
    --from "$validator_address" \
    --home "$DATA_DIR" \
    --chain-id "icn-local" \
    --yes
  
  # Get the proposal ID
  echo "Fetching proposal ID..."
  local proposal_id=""
  local max_attempts=10
  local attempts=0
  
  while [[ -z "$proposal_id" ]] && [[ $attempts -lt $max_attempts ]]; do
    sleep 1
    proposal_id=$(curl -s http://localhost:26657/abci_query?path="\"/custom/gov/proposal_id\"" | 
                 grep -o '"value":"[^"]*"' | head -1 | cut -d'"' -f4 | 
                 base64 --decode 2>/dev/null || echo "")
    ((attempts++))
  done
  
  if [[ -z "$proposal_id" ]]; then
    echo "❌ Could not retrieve proposal ID after multiple attempts"
    exit 1
  fi
  
  echo "Proposal created with ID: $proposal_id"
  echo "Voting period: $VOTING_PERIOD"
  
  # Vote yes on the proposal
  echo "Voting yes on proposal..."
  "$node_binary" tx gov vote \
    "$proposal_id" "yes" \
    --from "$validator_address" \
    --home "$DATA_DIR" \
    --chain-id "icn-local" \
    --yes
  
  echo "✅ Demo proposal created and voted on successfully!"
  
  # Display DAG state if requested
  if [[ "$SHOW_DAG_STATE" = true ]]; then
    echo "🔍 Fetching DAG state for the proposal..."
    sleep 2  # Give some time for the vote to be processed
    
    echo "Latest DAG updates:"
    curl -s http://localhost:26657/dag_info | jq . || echo "⚠️ Could not fetch DAG info (jq not installed?)"
    
    echo "Proposal Details:"
    curl -s "http://localhost:26657/abci_query?path=\"/custom/gov/proposal/$proposal_id\"" | 
      jq '.result.response.value | @base64d | fromjson' 2>/dev/null || 
      echo "⚠️ Could not parse proposal details (jq not installed or proposal not found)"
  fi
  
  echo "You can check the proposal status with:"
  echo "curl http://localhost:26657/abci_query?path=\"/custom/gov/proposal/$proposal_id\""
}

# Main script execution
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

check_node_running
validator_address=$(get_validator_address)
create_proposal "$validator_address" 