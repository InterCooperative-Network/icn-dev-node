#!/usr/bin/env bash
set -euo pipefail

# Default settings
OUTPUT_FORMAT="tree"  # Options: raw, json, tree
NODE_URL="http://localhost:26657"
PROPOSAL_ID=""
VERTEX_ID=""
DAG_PATH=""
RELEASE_MODE=false
VERBOSE=false
NODE_BINARY=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --raw)
      OUTPUT_FORMAT="raw"
      shift
      ;;
    --json)
      OUTPUT_FORMAT="json"
      shift
      ;;
    --tree)
      OUTPUT_FORMAT="tree"
      shift
      ;;
    --proposal)
      PROPOSAL_ID="$2"
      shift 2
      ;;
    --vertex)
      VERTEX_ID="$2"
      shift 2
      ;;
    --node-url)
      NODE_URL="$2"
      shift 2
      ;;
    --dag-path)
      DAG_PATH="$2"
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
      echo "Replay and trace DAG state and proposals"
      echo ""
      echo "Options:"
      echo "  --raw                Output raw data (minimal formatting)"
      echo "  --json               Output JSON formatted data"
      echo "  --tree               Output tree-structured data (default)"
      echo "  --proposal <id>      Trace a specific proposal by ID"
      echo "  --vertex <id>        Trace a specific vertex and its relationships"
      echo "  --node-url <url>     Node RPC URL (default: http://localhost:26657)"
      echo "  --dag-path <path>    Custom path to DAG data (for offline analysis)"
      echo "  --release            Use release build of icn-node"
      echo "  --verbose            Show detailed output"
      echo "  --help               Show this help message"
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
  # Skip if we're using a local DAG path
  if [[ -n "$DAG_PATH" ]]; then
    if [[ ! -d "$DAG_PATH" ]]; then
      echo "❌ DAG path not found: $DAG_PATH"
      exit 1
    fi
    return 0
  fi

  if ! curl -s "$NODE_URL/health" > /dev/null; then
    echo "❌ Node is not running at $NODE_URL"
    echo "Please start a node first with './run-node.sh'"
    exit 1
  fi
  
  if [[ "$VERBOSE" = true ]]; then
    echo "✅ Node is running at $NODE_URL"
  fi
}

# Get general DAG info
get_dag_info() {
  echo "Fetching DAG information..."
  
  local dag_info
  
  if [[ -n "$DAG_PATH" ]]; then
    # Use offline mode with local DAG path
    dag_info=$("$NODE_BINARY" dag info --path "$DAG_PATH" --format json)
  else
    # Use online mode with RPC
    dag_info=$(curl -s "$NODE_URL/dag_info")
  fi
  
  case "$OUTPUT_FORMAT" in
    raw)
      echo "$dag_info"
      ;;
    json)
      echo "$dag_info" | jq .
      ;;
    tree)
      echo "DAG Summary:"
      echo "$dag_info" | jq '.result.dag_info | {
        vertex_count: .vertex_count,
        root_count: .root_count,
        tip_count: .tip_count,
        genesis_time: .genesis_time,
        latest_update: .latest_update
      }'
      echo -e "\nLatest Tips:"
      echo "$dag_info" | jq -r '.result.dag_info.tips[] | " - \(.id): \(.summary // "No summary")"' 2>/dev/null || echo "No tips found"
      ;;
  esac
}

# Trace a specific proposal
trace_proposal() {
  echo "Tracing proposal: $PROPOSAL_ID"
  
  local proposal_data
  
  if [[ -n "$DAG_PATH" ]]; then
    # Use offline mode with local DAG path
    proposal_data=$("$NODE_BINARY" proposal show "$PROPOSAL_ID" --path "$DAG_PATH" --format json)
  else
    # Use online mode with RPC
    proposal_data=$(curl -s "$NODE_URL/abci_query?path=\"/custom/gov/proposal/$PROPOSAL_ID\"")
  fi
  
  case "$OUTPUT_FORMAT" in
    raw)
      echo "$proposal_data"
      ;;
    json)
      echo "$proposal_data" | jq .
      ;;
    tree)
      echo "Proposal Details:"
      # Extract proposal details from response
      if [[ -n "$DAG_PATH" ]]; then
        # Parse directly when using CLI (which gives cleaner output)
        echo "$proposal_data" | jq '{
          id: .id,
          title: .title,
          description: .description,
          status: .status,
          proposer: .proposer,
          submitted_at: .submitted_at,
          voting_end_time: .voting_end_time, 
          final_tally: .final_tally
        }'
      else
        # Parse from RPC response (more complex extraction)
        echo "$proposal_data" | jq -r '.result.response.value | @base64d | fromjson | {
          id: .id,
          title: .title,
          description: .description,
          status: .status,
          proposer: .proposer,
          submitted_at: .submitted_at,
          voting_end_time: .voting_end_time,
          final_tally: .final_tally
        }' 2>/dev/null || echo "Could not parse proposal data"
      fi
      
      # Fetch votes for this proposal
      echo -e "\nVotes:"
      local votes_data
      
      if [[ -n "$DAG_PATH" ]]; then
        # Use offline mode with local DAG path
        votes_data=$("$NODE_BINARY" proposal votes "$PROPOSAL_ID" --path "$DAG_PATH" --format json)
      else
        # Use online mode with RPC
        votes_data=$(curl -s "$NODE_URL/abci_query?path=\"/custom/gov/votes/$PROPOSAL_ID\"")
      fi
      
      # Process votes data
      if [[ -n "$DAG_PATH" ]]; then
        echo "$votes_data" | jq 'map({voter: .voter, vote: .option, time: .time})' 2>/dev/null || 
          echo "No votes found"
      else
        echo "$votes_data" | jq -r '.result.response.value | @base64d | fromjson | map({
          voter: .voter, 
          vote: .option, 
          time: .time
        })' 2>/dev/null || echo "No votes found"
      fi
      
      # Show proposal lifecycle events
      echo -e "\nProposal Lifecycle:"
      echo "  Submission → Discussion → Voting → Execution"
      ;;
  esac
}

# Trace a specific vertex and its relationships
trace_vertex() {
  echo "Tracing vertex: $VERTEX_ID"
  
  local vertex_data
  
  if [[ -n "$DAG_PATH" ]]; then
    # Use offline mode with local DAG path
    vertex_data=$("$NODE_BINARY" dag vertex "$VERTEX_ID" --path "$DAG_PATH" --format json)
  else
    # Use online mode with RPC
    vertex_data=$(curl -s "$NODE_URL/dag_vertex?id=$VERTEX_ID")
  fi
  
  case "$OUTPUT_FORMAT" in
    raw)
      echo "$vertex_data"
      ;;
    json)
      echo "$vertex_data" | jq .
      ;;
    tree)
      echo "Vertex Details:"
      
      if [[ -n "$DAG_PATH" ]]; then
        # Parse directly when using CLI
        echo "$vertex_data" | jq '{
          id: .id,
          timestamp: .timestamp,
          parents: .parents,
          children: .children,
          height: .height,
          proposer: .proposer,
          data_type: .data_type,
          scope: .scope
        }'
      else
        # Parse from RPC response
        echo "$vertex_data" | jq '.result.vertex | {
          id: .id,
          timestamp: .timestamp,
          parents: .parents,
          children: .children,
          height: .height,
          proposer: .proposer,
          data_type: .data_type,
          scope: .scope
        }' 2>/dev/null || echo "Could not parse vertex data"
      fi
      
      # Get ancestry
      echo -e "\nAncestry:"
      
      if [[ -n "$DAG_PATH" ]]; then
        # Use offline mode with local DAG path
        "$NODE_BINARY" dag ancestors "$VERTEX_ID" --path "$DAG_PATH" --format json | 
          jq 'map({id: .id, height: .height, data_type: .data_type})' 2>/dev/null || echo "No ancestry data"
      else
        # Use online mode with RPC
        curl -s "$NODE_URL/dag_ancestors?id=$VERTEX_ID" | 
          jq '.result.ancestors | map({id: .id, height: .height, data_type: .data_type})' 2>/dev/null || echo "No ancestry data"
      fi
      
      # Get descendants
      echo -e "\nDescendants:"
      
      if [[ -n "$DAG_PATH" ]]; then
        # Use offline mode with local DAG path
        "$NODE_BINARY" dag descendants "$VERTEX_ID" --path "$DAG_PATH" --format json | 
          jq 'map({id: .id, height: .height, data_type: .data_type})' 2>/dev/null || echo "No descendant data"
      else
        # Use online mode with RPC
        curl -s "$NODE_URL/dag_descendants?id=$VERTEX_ID" | 
          jq '.result.descendants | map({id: .id, height: .height, data_type: .data_type})' 2>/dev/null || echo "No descendant data"
      fi
      ;;
  esac
}

# Main script execution
main() {
  echo "ICN DAG Trace & Replay Tool"
  
  # Specific vertex tracing
  if [[ -n "$VERTEX_ID" ]]; then
    trace_vertex
    exit 0
  fi
  
  # Specific proposal tracing
  if [[ -n "$PROPOSAL_ID" ]]; then
    trace_proposal
    exit 0
  fi
  
  # Default action: general DAG info
  get_dag_info
}

# Execute script
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

check_dependencies
check_node_binary
check_node_running
main 