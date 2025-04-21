#!/usr/bin/env bash
set -euo pipefail

# Default settings
COOP_NAME="sim-coop-$(date +%s)"
IDENTITY_COUNT=3
GOVERNANCE_MACRO="proposal_lifecycle"
REPLAY=false
RELEASE_MODE=false
VERBOSE=false
NODE_RUNNING=false
DATA_DIR="$HOME/.icn-node"
NODE_URL="http://localhost:26657"
NODE_BINARY=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --coop)
      COOP_NAME="$2"
      shift 2
      ;;
    --identity-count)
      IDENTITY_COUNT="$2"
      if ! [[ "$IDENTITY_COUNT" =~ ^[0-9]+$ ]] || [ "$IDENTITY_COUNT" -lt 2 ]; then
        echo "❌ Identity count must be a number >= 2"
        exit 1
      fi
      shift 2
      ;;
    --governance-macro)
      GOVERNANCE_MACRO="$2"
      shift 2
      ;;
    --replay)
      REPLAY=true
      shift
      ;;
    --data-dir)
      DATA_DIR="$2"
      shift 2
      ;;
    --node-url)
      NODE_URL="$2"
      shift 2
      ;;
    --release)
      RELEASE_MODE=true
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo "Simulate a cooperative with multiple identities and governance flows"
      echo ""
      echo "Options:"
      echo "  --coop <name>             Cooperative name (default: sim-coop-timestamp)"
      echo "  --identity-count <number> Number of identities to create (default: 3, min: 2)"
      echo "  --governance-macro <name> Governance macro to run (default: proposal_lifecycle)"
      echo "  --replay                  Replay and display DAG after simulation"
      echo "  --data-dir <dir>          Node data directory (default: $HOME/.icn-node)"
      echo "  --node-url <url>          Node RPC URL (default: http://localhost:26657)"
      echo "  --release                 Use release build of icn-node"
      echo "  --verbose                 Show detailed output"
      echo "  --help                    Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Run '$0 --help' for usage information"
      exit 1
      ;;
  esac
done

# Load environment variables if .env exists
if [[ -f ../.env ]]; then
  # shellcheck disable=SC1091
  source ../.env
fi

# Check for required tools
check_dependencies() {
  local missing=false

  if ! command -v curl &> /dev/null; then
    echo "❌ 'curl' is required but not found"
    missing=true
  fi
  
  if ! command -v jq &> /dev/null; then
    echo "❌ 'jq' is required but not found"
    missing=true
  fi
  
  if [[ "$missing" = true ]]; then
    echo "Please install missing dependencies"
    exit 1
  fi
}

# Function to check if the node binary exists
check_node_binary() {
  local binary_path
  if [[ "$RELEASE_MODE" = true ]]; then
    binary_path="../deps/icn-covm/target/release/icn-node"
  else
    binary_path="../deps/icn-covm/target/debug/icn-node"
  fi

  if [[ ! -f "$binary_path" ]]; then
    echo "❌ Node binary not found at $binary_path"
    echo "Please run install.sh first or check that the build completed successfully."
    exit 1
  fi

  NODE_BINARY="$binary_path"
  
  if [[ "$VERBOSE" = true ]]; then
    echo "✅ Using node binary: $NODE_BINARY"
  fi
}

# Check if node is running
check_node_running() {
  if curl -s "$NODE_URL/health" > /dev/null; then
    NODE_RUNNING=true
    echo "✅ Node is running at $NODE_URL"
  else
    echo "⚠️ Node is not running at $NODE_URL"
    echo "Starting a local node..."
    ./run-node.sh --data-dir "$DATA_DIR" &
    NODE_PID=$!
    
    # Wait for node to start
    echo "Waiting for node to start..."
    local max_attempts=30
    local attempts=0
    while ! curl -s "$NODE_URL/health" > /dev/null && [[ $attempts -lt $max_attempts ]]; do
      sleep 1
      ((attempts++))
      echo -n "."
    done
    
    if [[ $attempts -lt $max_attempts ]]; then
      echo -e "\n✅ Node started successfully"
      NODE_RUNNING=true
    else
      echo -e "\n❌ Failed to start node"
      exit 1
    fi
  fi
}

# Create identities for the cooperative
create_identities() {
  echo "Creating $IDENTITY_COUNT identities for cooperative '$COOP_NAME'..."
  
  # Create admin identity
  echo "Creating admin identity..."
  ./generate-identity.sh --name "admin" --coop "$COOP_NAME" --role "admin" --output "../.wallet/identities"
  
  # Create member identities
  for ((i=1; i<IDENTITY_COUNT; i++)); do
    echo "Creating member$i identity..."
    ./generate-identity.sh --name "member$i" --coop "$COOP_NAME" --role "member" --output "../.wallet/identities"
  done
  
  echo "✅ Created $IDENTITY_COUNT identities for cooperative '$COOP_NAME'"
}

# Create governance proposal
create_proposal() {
  echo "Creating governance proposal using '$GOVERNANCE_MACRO' macro..."
  
  # Path to macro template
  local macro_path="../deps/icn-covm/templates/macros/$GOVERNANCE_MACRO.dsl"
  
  # Check if the macro template exists, if not create a simple one
  if [[ ! -f "$macro_path" ]]; then
    echo "⚠️ Macro template not found: $macro_path"
    echo "Creating a simple proposal template..."
    
    # Create the templates directory if it doesn't exist
    mkdir -p "../deps/icn-covm/templates/macros"
    
    # Create a simple proposal template
    cat > "$macro_path" << EOF
proposal {
  title: "Test Proposal for $COOP_NAME",
  description: "This is an automatically generated test proposal for the $COOP_NAME cooperative.",
  scope: "$COOP_NAME",
  voting_period: "30s",
  
  action: {
    type: "text",
    data: "This is a test proposal with no executable actions."
  }
}
EOF
    echo "✅ Created simple proposal template at $macro_path"
  fi
  
  # Get admin identity path
  local admin_identity="../.wallet/identities/$COOP_NAME/admin.json"
  
  # Submit the proposal
  echo "Submitting proposal as admin..."
  
  if [[ "$VERBOSE" = true ]]; then
    echo "Executing: $NODE_BINARY tx gov submit-proposal --from-macro $macro_path --identity $admin_identity --chain-id icn-local --home $DATA_DIR"
  fi
  
  local proposal_output
  proposal_output=$("$NODE_BINARY" tx gov submit-proposal \
                    --from-macro "$macro_path" \
                    --identity "$admin_identity" \
                    --chain-id "icn-local" \
                    --home "$DATA_DIR" \
                    --yes 2>&1)
  
  # Extract proposal ID
  local proposal_id
  proposal_id=$(echo "$proposal_output" | grep -o 'proposal_id: "[^"]*"' | cut -d'"' -f2)
  
  if [[ -z "$proposal_id" ]]; then
    echo "❌ Failed to extract proposal ID"
    if [[ "$VERBOSE" = true ]]; then
      echo "Proposal output: $proposal_output"
    fi
    exit 1
  fi
  
  echo "✅ Proposal created with ID: $proposal_id"
  echo "$proposal_id" > "/tmp/icn_last_proposal_id.txt"
  
  # Wait for the proposal to be visible in the DAG
  echo "Waiting for proposal to be indexed..."
  sleep 3
  
  return 0
}

# Vote on proposal
vote_on_proposal() {
  # Get last proposal ID
  local proposal_id
  proposal_id=$(cat "/tmp/icn_last_proposal_id.txt")
  
  if [[ -z "$proposal_id" ]]; then
    echo "❌ No proposal ID found"
    exit 1
  fi
  
  echo "Voting on proposal $proposal_id..."
  
  # Start from index 1 to skip admin (who created the proposal)
  for ((i=1; i<IDENTITY_COUNT; i++)); do
    local member_identity="../.wallet/identities/$COOP_NAME/member$i.json"
    
    # Determine vote (make it interesting by having some yes/no votes)
    local vote="yes"
    if (( i % 3 == 0 )); then
      vote="no"
    fi
    
    echo "Member$i voting $vote..."
    
    if [[ "$VERBOSE" = true ]]; then
      echo "Executing: $NODE_BINARY tx gov vote $proposal_id $vote --identity $member_identity --chain-id icn-local --home $DATA_DIR"
    fi
    
    "$NODE_BINARY" tx gov vote \
      "$proposal_id" "$vote" \
      --identity "$member_identity" \
      --chain-id "icn-local" \
      --home "$DATA_DIR" \
      --yes
  done
  
  echo "✅ All members have voted on the proposal"
  
  # Wait for votes to be processed
  echo "Waiting for votes to be processed..."
  sleep 5
}

# Replay and show results
replay_results() {
  # Get last proposal ID
  local proposal_id
  proposal_id=$(cat "/tmp/icn_last_proposal_id.txt")
  
  if [[ -z "$proposal_id" ]]; then
    echo "❌ No proposal ID found"
    exit 1
  fi
  
  echo "Replaying DAG state for proposal $proposal_id..."
  
  # Use the replay-dag.sh script to show detailed proposal information
  ./replay-dag.sh --proposal "$proposal_id" --tree
  
  echo "Simulation completed successfully!"
}

# Main function to run the simulation
run_simulation() {
  echo "Starting cooperative simulation..."
  echo "  - Cooperative: $COOP_NAME"
  echo "  - Identities: $IDENTITY_COUNT"
  echo "  - Governance Macro: $GOVERNANCE_MACRO"
  
  create_identities
  create_proposal
  vote_on_proposal
  
  if [[ "$REPLAY" = true ]]; then
    replay_results
  fi
  
  echo "Simulation completed!"
}

# Main script execution
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

check_dependencies
check_node_binary
check_node_running
run_simulation 