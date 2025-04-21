#!/bin/bash
set -euo pipefail

# ICN Network Mesh Status Monitor
# Visualize mesh health, DAG consistency, and federation status

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Default values
LOCAL_NODE_URL="http://localhost:26657"
DATA_DIR="${HOME}/.icn"
LOG_FILE="${DATA_DIR}/logs/mesh-status.log"
PEERS_FILE="${SCRIPT_DIR}/../config/bootstrap-peers.toml"
CHECK_INTERVAL=0  # 0 means run once, >0 means monitor every X seconds
OUTPUT_FORMAT="text"  # text, json, or csv
MIN_PEERS=3  # Minimum number of peers needed for a healthy federation
MONITOR_DAG=true
MONITOR_PROPOSALS=true
MONITOR_FEDERATION=true
VERBOSE=false

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Monitor the health of the ICN node mesh network.

Options:
  --node-url URL        Local node RPC URL (default: http://localhost:26657)
  --peers-file FILE     TOML file with peer information (default: config/bootstrap-peers.toml)
  --monitor SEC         Run continuously, checking every SEC seconds (default: 0 = run once)
  --min-peers N         Minimum number of peers for healthy status (default: 3)
  --format FORMAT       Output format: text, json, or csv (default: text)
  --no-dag              Skip DAG consistency checks
  --no-proposals        Skip proposal consistency checks
  --no-federation       Skip federation status checks
  --verbose             Show more detailed information
  --help                Display this help message and exit

Examples:
  # Check mesh status once
  $(basename "$0")
  
  # Monitor continuously every 60 seconds with JSON output
  $(basename "$0") --monitor 60 --format json
  
  # Check only federation status
  $(basename "$0") --no-dag --no-proposals
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --node-url)
        LOCAL_NODE_URL="$2"
        shift 2
        ;;
      --peers-file)
        PEERS_FILE="$2"
        shift 2
        ;;
      --monitor)
        CHECK_INTERVAL="$2"
        shift 2
        ;;
      --min-peers)
        MIN_PEERS="$2"
        shift 2
        ;;
      --format)
        OUTPUT_FORMAT="$2"
        shift 2
        ;;
      --no-dag)
        MONITOR_DAG=false
        shift
        ;;
      --no-proposals)
        MONITOR_PROPOSALS=false
        shift
        ;;
      --no-federation)
        MONITOR_FEDERATION=false
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
  # Create log directory
  mkdir -p "$(dirname "$LOG_FILE")"
  
  # Validate output format
  if [[ ! "$OUTPUT_FORMAT" =~ ^(text|json|csv)$ ]]; then
    log_error "Invalid output format: $OUTPUT_FORMAT. Must be one of: text, json, csv"
    exit 1
  fi
  
  # Check if local node is running
  if ! curl -s "${LOCAL_NODE_URL}/status" >/dev/null 2>&1; then
    log_error "Local node is not running at ${LOCAL_NODE_URL}"
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
      echo '{"status":"error","message":"Local node is not running","timestamp":"'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}'
    elif [[ "$OUTPUT_FORMAT" == "csv" ]]; then
      echo "timestamp,status,message"
      echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"),error,Local node is not running"
    else
      echo "Error: Local node is not running at ${LOCAL_NODE_URL}"
    fi
    exit 1
  fi
  
  # Check if peers file exists when federation monitoring is enabled
  if [[ "$MONITOR_FEDERATION" == true && ! -f "$PEERS_FILE" ]]; then
    log_warn "Peers file not found: $PEERS_FILE"
    log_info "Will use only connected peers for federation status"
  fi
}

# Get local node information
get_local_node_info() {
  local status_json
  status_json=$(curl -s "${LOCAL_NODE_URL}/status")
  
  if ! command_exists jq; then
    log_error "jq is required for processing node information"
    return 1
  fi
  
  # Extract basic node information
  local node_id
  local node_network
  local node_moniker
  local block_height
  local catching_up
  
  node_id=$(echo "$status_json" | jq -r '.result.node_info.id')
  node_network=$(echo "$status_json" | jq -r '.result.node_info.network')
  node_moniker=$(echo "$status_json" | jq -r '.result.node_info.moniker')
  block_height=$(echo "$status_json" | jq -r '.result.sync_info.latest_block_height')
  catching_up=$(echo "$status_json" | jq -r '.result.sync_info.catching_up')
  
  # Output node info based on format
  if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    jq -n \
      --arg id "$node_id" \
      --arg network "$node_network" \
      --arg moniker "$node_moniker" \
      --arg height "$block_height" \
      --argjson catching_up "$catching_up" \
      '{
        local_node: {
          id: $id,
          network: $network,
          moniker: $moniker,
          latest_block_height: $height,
          catching_up: $catching_up
        }
      }'
  elif [[ "$OUTPUT_FORMAT" == "csv" ]]; then
    echo "node_id,network,moniker,block_height,catching_up"
    echo "$node_id,$node_network,$node_moniker,$block_height,$catching_up"
  else
    echo "Local Node Information:"
    echo "ID:            $node_id"
    echo "Network:       $node_network"
    echo "Moniker:       $node_moniker"
    echo "Block Height:  $block_height"
    echo "Catching Up:   $catching_up"
  fi
}

# Get connected peers information
get_connected_peers() {
  local net_info
  net_info=$(curl -s "${LOCAL_NODE_URL}/net_info")
  
  if ! command_exists jq; then
    log_error "jq is required for processing peer information"
    return 1
  fi
  
  # Extract peer information
  local peer_count
  peer_count=$(echo "$net_info" | jq -r '.result.n_peers')
  
  local peers
  if [[ "$peer_count" -gt 0 ]]; then
    peers=$(echo "$net_info" | jq -c '.result.peers')
  else
    peers="[]"
  fi
  
  # Output peer info based on format
  if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    jq -n \
      --arg count "$peer_count" \
      --argjson peers "$peers" \
      '{
        peers: {
          count: $count|tonumber,
          connected: $peers
        }
      }'
  elif [[ "$OUTPUT_FORMAT" == "csv" ]]; then
    echo "peer_count"
    echo "$peer_count"
    
    if [[ "$peer_count" -gt 0 ]]; then
      echo ""
      echo "peer_id,moniker,ip,port"
      echo "$net_info" | jq -r '.result.peers[] | [.node_info.id, .node_info.moniker, .remote_ip, (.node_info.listen_addr | split(":") | .[2])] | @csv'
    fi
  else
    echo "Connected Peers: $peer_count"
    
    if [[ "$peer_count" -gt 0 ]]; then
      echo "$net_info" | jq -r '.result.peers[] | "- \(.node_info.id): \(.node_info.moniker) (\(.remote_ip):\(.node_info.listen_addr | split(":") | .[2]))"'
    fi
    
    # Assess federation health
    if [[ "$peer_count" -ge "$MIN_PEERS" ]]; then
      echo "Federation Status: Healthy (≥ $MIN_PEERS peers)"
    else
      echo "Federation Status: Unhealthy (< $MIN_PEERS peers)"
    fi
  fi
}

# Get remote peer status by connecting to their endpoints
get_remote_peer_status() {
  local peers_json
  peers_json=$(curl -s "${LOCAL_NODE_URL}/net_info" | jq -c '.result.peers')
  
  if ! command_exists jq; then
    log_error "jq is required for processing peer status"
    return 1
  fi
  
  # Prepare array to hold remote peer data
  local remote_data=()
  local remote_data_json="[]"
  
  # Get our local node latest block height for comparison
  local local_height
  local_height=$(curl -s "${LOCAL_NODE_URL}/status" | jq -r '.result.sync_info.latest_block_height')
  
  # For each connected peer, try to get their status
  local peer_count
  peer_count=$(echo "$peers_json" | jq -r '. | length')
  
  for ((i=0; i<peer_count; i++)); do
    local peer_ip
    local peer_p2p_port
    local peer_rpc_port
    local peer_id
    local peer_moniker
    
    peer_ip=$(echo "$peers_json" | jq -r ".[$i].remote_ip")
    # Get P2P port from the listen_addr (assuming format is "tcp://0.0.0.0:PORT")
    peer_p2p_port=$(echo "$peers_json" | jq -r ".[$i].node_info.listen_addr" | cut -d':' -f3)
    # Assume RPC port is P2P port + 1 (common convention)
    peer_rpc_port=$((peer_p2p_port + 1))
    peer_id=$(echo "$peers_json" | jq -r ".[$i].node_info.id")
    peer_moniker=$(echo "$peers_json" | jq -r ".[$i].node_info.moniker")
    
    # Try to get remote node status
    local remote_status
    local remote_height
    local remote_catching_up
    local height_diff
    local status_ok
    
    if curl -s --connect-timeout 2 "http://${peer_ip}:${peer_rpc_port}/status" > /dev/null 2>&1; then
      remote_status=$(curl -s "http://${peer_ip}:${peer_rpc_port}/status")
      remote_height=$(echo "$remote_status" | jq -r '.result.sync_info.latest_block_height')
      remote_catching_up=$(echo "$remote_status" | jq -r '.result.sync_info.catching_up')
      
      # Calculate block height difference
      if [[ "$remote_height" =~ ^[0-9]+$ && "$local_height" =~ ^[0-9]+$ ]]; then
        height_diff=$((remote_height - local_height))
      else
        height_diff="unknown"
      fi
      
      status_ok=true
    else
      remote_height="unreachable"
      remote_catching_up="unknown"
      height_diff="unknown"
      status_ok=false
    fi
    
    # Add to remote_data array for later formatting
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
      local peer_json
      peer_json=$(jq -n \
        --arg id "$peer_id" \
        --arg moniker "$peer_moniker" \
        --arg ip "$peer_ip" \
        --arg port "$peer_rpc_port" \
        --arg height "$remote_height" \
        --arg height_diff "$height_diff" \
        --arg catching_up "$remote_catching_up" \
        --arg reachable "$status_ok" \
        '{
          id: $id,
          moniker: $moniker,
          ip: $ip,
          rpc_port: $port,
          latest_block_height: $height,
          height_diff: $height_diff,
          catching_up: $catching_up,
          reachable: $reachable
        }')
      
      remote_data_json=$(echo "$remote_data_json" | jq ". += [$peer_json]")
    elif [[ "$OUTPUT_FORMAT" == "csv" ]]; then
      remote_data+=("$peer_id,$peer_moniker,$peer_ip,$peer_rpc_port,$remote_height,$height_diff,$remote_catching_up,$status_ok")
    else
      if [[ "$status_ok" == true ]]; then
        remote_data+=("$peer_moniker ($peer_id): Block: $remote_height (diff: $height_diff), Catching up: $remote_catching_up")
      else
        remote_data+=("$peer_moniker ($peer_id): Unreachable at $peer_ip:$peer_rpc_port")
      fi
    fi
  done
  
  # Output remote peer status based on format
  if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    echo "$remote_data_json" | jq '{remote_peers: .}'
  elif [[ "$OUTPUT_FORMAT" == "csv" ]]; then
    echo "peer_id,moniker,ip,rpc_port,block_height,height_diff,catching_up,reachable"
    printf "%s\n" "${remote_data[@]}"
  else
    echo "Remote Peer Status:"
    for data in "${remote_data[@]}"; do
      echo "- $data"
    done
  fi
}

# Get DAG consistency across nodes
check_dag_consistency() {
  if [[ "$MONITOR_DAG" == false ]]; then
    return 0
  fi
  
  if ! command_exists jq; then
    log_error "jq is required for checking DAG consistency"
    return 1
  fi
  
  # Get local DAG info
  local local_dag_info
  if [[ -x "${SCRIPT_DIR}/replay-dag.sh" ]]; then
    local_dag_info=$("${SCRIPT_DIR}/replay-dag.sh" --json 2>/dev/null || echo '{"vertices": 0, "proposals": 0, "votes": 0, "dag_hash": "unknown"}')
  else
    log_warn "replay-dag.sh script not found, skipping DAG consistency check"
    return 1
  fi
  
  local local_vertices
  local local_proposals
  local local_votes
  local local_dag_hash
  
  local_vertices=$(echo "$local_dag_info" | jq -r '.vertices // 0')
  local_proposals=$(echo "$local_dag_info" | jq -r '.proposals // 0')
  local_votes=$(echo "$local_dag_info" | jq -r '.votes // 0')
  local_dag_hash=$(echo "$local_dag_info" | jq -r '.dag_hash // "unknown"')
  
  # Get remote peer information
  local peers_json
  peers_json=$(curl -s "${LOCAL_NODE_URL}/net_info" | jq -c '.result.peers')
  
  local peer_count
  peer_count=$(echo "$peers_json" | jq -r '. | length')
  
  # Prepare arrays for storing remote DAG info
  local remote_dag_data=()
  local remote_dag_json="[]"
  local consistent_peers=0
  local inconsistent_peers=0
  local unreachable_peers=0
  
  # Check DAG state on each peer
  for ((i=0; i<peer_count; i++)); do
    local peer_ip
    local peer_p2p_port
    local peer_rpc_port
    local peer_id
    local peer_moniker
    
    peer_ip=$(echo "$peers_json" | jq -r ".[$i].remote_ip")
    peer_p2p_port=$(echo "$peers_json" | jq -r ".[$i].node_info.listen_addr" | cut -d':' -f3)
    peer_rpc_port=$((peer_p2p_port + 1))
    peer_id=$(echo "$peers_json" | jq -r ".[$i].node_info.id")
    peer_moniker=$(echo "$peers_json" | jq -r ".[$i].node_info.moniker")
    
    # Try to get remote DAG info
    local remote_dag_url="http://${peer_ip}:${peer_rpc_port}/abci_query?path=\"/dag/info\""
    local remote_dag_info
    local remote_vertices
    local remote_proposals
    local remote_votes
    local remote_dag_hash
    local is_consistent
    local status_ok
    
    if curl -s --connect-timeout 2 "$remote_dag_url" > /dev/null 2>&1; then
      remote_dag_info=$(curl -s "$remote_dag_url")
      
      # Try to extract DAG info from response
      if echo "$remote_dag_info" | jq -e '.result.response.value' > /dev/null 2>&1; then
        # Decode base64 value if present
        local dag_data
        dag_data=$(echo "$remote_dag_info" | jq -r '.result.response.value' | base64 -d 2>/dev/null || echo '{}')
        
        remote_vertices=$(echo "$dag_data" | jq -r '.vertices // 0')
        remote_proposals=$(echo "$dag_data" | jq -r '.proposals // 0')
        remote_votes=$(echo "$dag_data" | jq -r '.votes // 0')
        remote_dag_hash=$(echo "$dag_data" | jq -r '.dag_hash // "unknown"')
        
        # Check consistency based on DAG hash
        if [[ "$remote_dag_hash" == "$local_dag_hash" && "$local_dag_hash" != "unknown" ]]; then
          is_consistent=true
          consistent_peers=$((consistent_peers + 1))
        else
          is_consistent=false
          inconsistent_peers=$((inconsistent_peers + 1))
        fi
        
        status_ok=true
      else
        remote_vertices="unknown"
        remote_proposals="unknown"
        remote_votes="unknown"
        remote_dag_hash="unknown"
        is_consistent=false
        inconsistent_peers=$((inconsistent_peers + 1))
        status_ok=true
      fi
    else
      remote_vertices="unreachable"
      remote_proposals="unreachable"
      remote_votes="unreachable"
      remote_dag_hash="unreachable"
      is_consistent=false
      unreachable_peers=$((unreachable_peers + 1))
      status_ok=false
    fi
    
    # Add to remote_dag_data array for later formatting
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
      local dag_json
      dag_json=$(jq -n \
        --arg id "$peer_id" \
        --arg moniker "$peer_moniker" \
        --arg ip "$peer_ip" \
        --arg vertices "$remote_vertices" \
        --arg proposals "$remote_proposals" \
        --arg votes "$remote_votes" \
        --arg dag_hash "$remote_dag_hash" \
        --arg consistent "$is_consistent" \
        --arg reachable "$status_ok" \
        '{
          id: $id,
          moniker: $moniker,
          ip: $ip,
          vertices: $vertices,
          proposals: $proposals,
          votes: $votes,
          dag_hash: $dag_hash,
          consistent: $consistent,
          reachable: $reachable
        }')
      
      remote_dag_json=$(echo "$remote_dag_json" | jq ". += [$dag_json]")
    elif [[ "$OUTPUT_FORMAT" == "csv" ]]; then
      remote_dag_data+=("$peer_id,$peer_moniker,$peer_ip,$remote_vertices,$remote_proposals,$remote_votes,$remote_dag_hash,$is_consistent,$status_ok")
    else
      if [[ "$status_ok" == true ]]; then
        local consistency_status
        if [[ "$is_consistent" == true ]]; then
          consistency_status="Consistent"
        else
          consistency_status="Inconsistent"
        fi
        remote_dag_data+=("$peer_moniker ($peer_id): Vertices: $remote_vertices, Proposals: $remote_proposals, Votes: $remote_votes, Status: $consistency_status")
      else
        remote_dag_data+=("$peer_moniker ($peer_id): DAG info unreachable")
      fi
    fi
  done
  
  # Calculate overall DAG consistency
  local total_reachable=$((consistent_peers + inconsistent_peers))
  local consistency_percentage
  
  if [[ $total_reachable -gt 0 ]]; then
    consistency_percentage=$((consistent_peers * 100 / total_reachable))
  else
    consistency_percentage=0
  fi
  
  # Output DAG consistency info based on format
  if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    jq -n \
      --arg vertices "$local_vertices" \
      --arg proposals "$local_proposals" \
      --arg votes "$local_votes" \
      --arg dag_hash "$local_dag_hash" \
      --arg consistent_peers "$consistent_peers" \
      --arg inconsistent_peers "$inconsistent_peers" \
      --arg unreachable_peers "$unreachable_peers" \
      --arg consistency_percentage "$consistency_percentage" \
      --argjson remote_data "$remote_dag_json" \
      '{
        dag_consistency: {
          local_node: {
            vertices: $vertices,
            proposals: $proposals,
            votes: $votes,
            dag_hash: $dag_hash
          },
          stats: {
            consistent_peers: $consistent_peers|tonumber,
            inconsistent_peers: $inconsistent_peers|tonumber,
            unreachable_peers: $unreachable_peers|tonumber,
            consistency_percentage: $consistency_percentage|tonumber
          },
          remote_nodes: $remote_data
        }
      }'
  elif [[ "$OUTPUT_FORMAT" == "csv" ]]; then
    echo "local_vertices,local_proposals,local_votes,local_dag_hash,consistent_peers,inconsistent_peers,unreachable_peers,consistency_percentage"
    echo "$local_vertices,$local_proposals,$local_votes,$local_dag_hash,$consistent_peers,$inconsistent_peers,$unreachable_peers,$consistency_percentage%"
    
    echo ""
    echo "peer_id,moniker,ip,vertices,proposals,votes,dag_hash,consistent,reachable"
    printf "%s\n" "${remote_dag_data[@]}"
  else
    echo "DAG Consistency:"
    echo "Local DAG: Vertices: $local_vertices, Proposals: $local_proposals, Votes: $local_votes"
    echo "DAG Hash: $local_dag_hash"
    echo "Consistency: $consistency_percentage% ($consistent_peers consistent, $inconsistent_peers inconsistent, $unreachable_peers unreachable)"
    
    echo "Remote DAG Status:"
    for data in "${remote_dag_data[@]}"; do
      echo "- $data"
    done
  fi
}

# Check proposal consistency across nodes
check_proposal_consistency() {
  if [[ "$MONITOR_PROPOSALS" == false ]]; then
    return 0
  fi
  
  if ! command_exists jq; then
    log_error "jq is required for checking proposal consistency"
    return 1
  fi
  
  # Get local proposals
  local local_proposals
  if [[ -x "${SCRIPT_DIR}/replay-dag.sh" ]]; then
    local_proposals=$("${SCRIPT_DIR}/replay-dag.sh" --proposals --json 2>/dev/null || echo '[]')
  else
    log_warn "replay-dag.sh script not found, skipping proposal consistency check"
    return 1
  fi
  
  # Count local proposals
  local local_proposal_count
  local_proposal_count=$(echo "$local_proposals" | jq -r '. | length')
  
  # Extract local proposal IDs for comparison
  local local_proposal_ids
  local_proposal_ids=$(echo "$local_proposals" | jq -r '.[].id')
  
  # Get remote peer information
  local peers_json
  peers_json=$(curl -s "${LOCAL_NODE_URL}/net_info" | jq -c '.result.peers')
  
  local peer_count
  peer_count=$(echo "$peers_json" | jq -r '. | length')
  
  # Prepare arrays for storing remote proposal info
  local remote_proposal_data=()
  local remote_proposal_json="[]"
  local fully_consistent_peers=0
  local partially_consistent_peers=0
  local inconsistent_peers=0
  local unreachable_peers=0
  
  # Check proposals on each peer
  for ((i=0; i<peer_count; i++)); do
    local peer_ip
    local peer_p2p_port
    local peer_rpc_port
    local peer_id
    local peer_moniker
    
    peer_ip=$(echo "$peers_json" | jq -r ".[$i].remote_ip")
    peer_p2p_port=$(echo "$peers_json" | jq -r ".[$i].node_info.listen_addr" | cut -d':' -f3)
    peer_rpc_port=$((peer_p2p_port + 1))
    peer_id=$(echo "$peers_json" | jq -r ".[$i].node_info.id")
    peer_moniker=$(echo "$peers_json" | jq -r ".[$i].node_info.moniker")
    
    # Try to get remote proposals
    local remote_proposals_url="http://${peer_ip}:${peer_rpc_port}/abci_query?path=\"/proposals/list\""
    local remote_proposals
    local remote_proposal_count
    local remote_proposal_ids
    local matching_proposals
    local consistency_status
    local status_ok
    
    if curl -s --connect-timeout 2 "$remote_proposals_url" > /dev/null 2>&1; then
      remote_proposals=$(curl -s "$remote_proposals_url")
      
      # Try to extract proposal info from response
      if echo "$remote_proposals" | jq -e '.result.response.value' > /dev/null 2>&1; then
        # Decode base64 value if present
        local proposals_data
        proposals_data=$(echo "$remote_proposals" | jq -r '.result.response.value' | base64 -d 2>/dev/null || echo '[]')
        
        remote_proposal_count=$(echo "$proposals_data" | jq -r '. | length')
        remote_proposal_ids=$(echo "$proposals_data" | jq -r '.[].id')
        
        # Count matching proposals
        local matching_count=0
        local total_proposals
        
        for id in $remote_proposal_ids; do
          if echo "$local_proposal_ids" | grep -q "$id"; then
            matching_count=$((matching_count + 1))
          fi
        done
        
        # Get total number of unique proposals
        total_proposals=$(echo -e "$remote_proposal_ids\n$local_proposal_ids" | sort -u | wc -l | tr -d ' ')
        
        matching_proposals=$matching_count
        
        # Determine consistency status
        if [[ $matching_count -eq $total_proposals ]]; then
          consistency_status="Fully Consistent"
          fully_consistent_peers=$((fully_consistent_peers + 1))
        elif [[ $matching_count -gt 0 ]]; then
          consistency_status="Partially Consistent"
          partially_consistent_peers=$((partially_consistent_peers + 1))
        else
          consistency_status="Inconsistent"
          inconsistent_peers=$((inconsistent_peers + 1))
        fi
        
        status_ok=true
      else
        remote_proposal_count="unknown"
        remote_proposal_ids=""
        matching_proposals=0
        consistency_status="Unknown"
        inconsistent_peers=$((inconsistent_peers + 1))
        status_ok=true
      fi
    else
      remote_proposal_count="unreachable"
      remote_proposal_ids=""
      matching_proposals=0
      consistency_status="Unreachable"
      unreachable_peers=$((unreachable_peers + 1))
      status_ok=false
    fi
    
    # Add to remote_proposal_data array for later formatting
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
      local proposal_json
      proposal_json=$(jq -n \
        --arg id "$peer_id" \
        --arg moniker "$peer_moniker" \
        --arg ip "$peer_ip" \
        --arg count "$remote_proposal_count" \
        --arg matching "$matching_proposals" \
        --arg status "$consistency_status" \
        --arg reachable "$status_ok" \
        '{
          id: $id,
          moniker: $moniker,
          ip: $ip,
          proposal_count: $count,
          matching_proposals: $matching,
          consistency_status: $status,
          reachable: $reachable
        }')
      
      remote_proposal_json=$(echo "$remote_proposal_json" | jq ". += [$proposal_json]")
    elif [[ "$OUTPUT_FORMAT" == "csv" ]]; then
      remote_proposal_data+=("$peer_id,$peer_moniker,$peer_ip,$remote_proposal_count,$matching_proposals,$consistency_status,$status_ok")
    else
      if [[ "$status_ok" == true ]]; then
        remote_proposal_data+=("$peer_moniker ($peer_id): Proposals: $remote_proposal_count, Matching: $matching_proposals, Status: $consistency_status")
      else
        remote_proposal_data+=("$peer_moniker ($peer_id): Proposal info unreachable")
      fi
    fi
  done
  
  # Calculate overall proposal consistency
  local total_reachable=$((fully_consistent_peers + partially_consistent_peers + inconsistent_peers))
  local consistency_percentage
  
  if [[ $total_reachable -gt 0 ]]; then
    # Full consistency is weighted more than partial
    consistency_percentage=$(( (fully_consistent_peers * 100 + partially_consistent_peers * 50) / (total_reachable * 100) * 100 ))
  else
    consistency_percentage=0
  fi
  
  # Output proposal consistency info based on format
  if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    jq -n \
      --arg count "$local_proposal_count" \
      --arg fully_consistent "$fully_consistent_peers" \
      --arg partially_consistent "$partially_consistent_peers" \
      --arg inconsistent "$inconsistent_peers" \
      --arg unreachable "$unreachable_peers" \
      --arg consistency_percentage "$consistency_percentage" \
      --argjson remote_data "$remote_proposal_json" \
      '{
        proposal_consistency: {
          local_node: {
            proposal_count: $count|tonumber
          },
          stats: {
            fully_consistent_peers: $fully_consistent|tonumber,
            partially_consistent_peers: $partially_consistent|tonumber,
            inconsistent_peers: $inconsistent|tonumber,
            unreachable_peers: $unreachable|tonumber,
            consistency_percentage: $consistency_percentage|tonumber
          },
          remote_nodes: $remote_data
        }
      }'
  elif [[ "$OUTPUT_FORMAT" == "csv" ]]; then
    echo "local_proposal_count,fully_consistent_peers,partially_consistent_peers,inconsistent_peers,unreachable_peers,consistency_percentage"
    echo "$local_proposal_count,$fully_consistent_peers,$partially_consistent_peers,$inconsistent_peers,$unreachable_peers,$consistency_percentage%"
    
    echo ""
    echo "peer_id,moniker,ip,proposal_count,matching_proposals,consistency_status,reachable"
    printf "%s\n" "${remote_proposal_data[@]}"
  else
    echo "Proposal Consistency:"
    echo "Local Proposals: $local_proposal_count"
    echo "Consistency: $consistency_percentage% ($fully_consistent_peers fully consistent, $partially_consistent_peers partially consistent, $inconsistent_peers inconsistent, $unreachable_peers unreachable)"
    
    echo "Remote Proposal Status:"
    for data in "${remote_proposal_data[@]}"; do
      echo "- $data"
    done
  fi
}

# Generate the full mesh status report
generate_mesh_status_report() {
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    # For JSON output, we combine all the individual reports
    local node_info
    local peers_info
    local dag_consistency
    local proposal_consistency
    
    node_info=$(get_local_node_info)
    peers_info=$(get_connected_peers)
    
    if [[ "$MONITOR_DAG" == true ]]; then
      dag_consistency=$(check_dag_consistency)
    else
      dag_consistency="{}"
    fi
    
    if [[ "$MONITOR_PROPOSALS" == true ]]; then
      proposal_consistency=$(check_proposal_consistency)
    else
      proposal_consistency="{}"
    fi
    
    # Combine all data
    jq -n \
      --arg timestamp "$timestamp" \
      --argjson node_info "$node_info" \
      --argjson peers_info "$peers_info" \
      --argjson dag_consistency "$dag_consistency" \
      --argjson proposal_consistency "$proposal_consistency" \
      '{
        timestamp: $timestamp,
        node_info: $node_info.local_node,
        peers_info: $peers_info.peers,
        dag_consistency: $dag_consistency.dag_consistency,
        proposal_consistency: $proposal_consistency.proposal_consistency
      }'
  elif [[ "$OUTPUT_FORMAT" == "csv" ]]; then
    # For CSV output, we keep each section separate
    echo "ICN Mesh Status Report - $timestamp"
    echo ""
    
    get_local_node_info
    echo ""
    
    get_connected_peers
    echo ""
    
    if [[ "$MONITOR_DAG" == true ]]; then
      check_dag_consistency
      echo ""
    fi
    
    if [[ "$MONITOR_PROPOSALS" == true ]]; then
      check_proposal_consistency
    fi
  else
    # For text output, we format a readable report
    echo "==================================================="
    echo "ICN MESH STATUS REPORT - $timestamp"
    echo "==================================================="
    echo ""
    
    get_local_node_info
    echo ""
    
    get_connected_peers
    echo ""
    
    if [[ "$MONITOR_DAG" == true ]]; then
      check_dag_consistency
      echo ""
    fi
    
    if [[ "$MONITOR_PROPOSALS" == true ]]; then
      check_proposal_consistency
    fi
    
    echo "==================================================="
  fi
}

# Monitor the mesh continuously
monitor_mesh() {
  log_info "Starting mesh monitoring with interval of $CHECK_INTERVAL seconds"
  
  while true; do
    generate_mesh_status_report
    
    if [[ "$CHECK_INTERVAL" -le 0 ]]; then
      # Run once and exit
      break
    else
      # Sleep until next check
      sleep "$CHECK_INTERVAL"
    fi
  done
}

# Main function
main() {
  parse_args "$@"
  validate_args
  
  monitor_mesh
}

main "$@" 