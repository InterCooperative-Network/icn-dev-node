#!/bin/bash

# ICN Node Initialization Script
# This script guides developers through initializing an ICN Dev Node

set -e

# ANSI color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}    ICN Node Initialization Tool     ${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# Ask for node type
echo -e "${YELLOW}Which type of node do you want to initialize?${NC}"
PS3="Select a node type: "
options=("Dev-Net" "Cooperative" "Community" "Federation")
select node_type in "${options[@]}"; do
  case $node_type in
    "Dev-Net")
      echo -e "${GREEN}Initializing Dev-Net node...${NC}"
      
      # Join test network
      echo -e "${YELLOW}Running join-testnet.sh...${NC}"
      read -p "Proceed? [Y/n] " -n 1 -r
      echo
      if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        ./scripts/join-testnet.sh
      else
        echo "Skipped joining test network."
      fi
      
      # Create test identities
      echo -e "${YELLOW}Would you like to create test scoped identities?${NC} [Yes/No]"
      read -r create_identities
      if [[ "$create_identities" =~ ^[Yy][Ee][Ss]$ ]] || [[ "$create_identities" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Running simulate-coop.sh...${NC}"
        read -p "Proceed? [Y/n] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
          ./scripts/simulate-coop.sh --coop "dev-net-test-coop" --identity-count 3 --replay
        else
          echo "Skipped creating test identities."
        fi
      fi
      break
      ;;
    
    "Cooperative")
      echo -e "${GREEN}Initializing Cooperative node...${NC}"
      
      # Get cooperative name
      echo -e "${YELLOW}Enter your cooperative name:${NC}"
      read -r COOP_NAME
      
      # Run node
      echo -e "${YELLOW}Running run-node.sh with name '$COOP_NAME'...${NC}"
      read -p "Proceed? [Y/n] " -n 1 -r
      echo
      if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        ./scripts/run-node.sh --node-name "$COOP_NAME"
      else
        echo "Skipped running node."
      fi
      
      # Generate admin identity
      echo -e "${YELLOW}Generating admin identity...${NC}"
      read -p "Proceed? [Y/n] " -n 1 -r
      echo
      if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        ./scripts/generate-identity.sh --name "admin" --coop "$COOP_NAME" --role "admin"
      else
        echo "Skipped generating admin identity."
      fi
      
      # Ask for additional identities
      echo -e "${YELLOW}Would you like to create additional identities?${NC} [Yes/No]"
      read -r create_more
      while [[ "$create_more" =~ ^[Yy][Ee][Ss]$ ]] || [[ "$create_more" =~ ^[Yy]$ ]]; do
        echo -e "${YELLOW}Enter identity name:${NC}"
        read -r ID_NAME
        echo -e "${YELLOW}Enter identity role:${NC}"
        read -r ID_ROLE
        
        echo -e "${YELLOW}Generating identity '$ID_NAME' with role '$ID_ROLE'...${NC}"
        read -p "Proceed? [Y/n] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
          ./scripts/generate-identity.sh --name "$ID_NAME" --coop "$COOP_NAME" --role "$ID_ROLE"
        else
          echo "Skipped generating identity."
        fi
        
        echo -e "${YELLOW}Create another identity?${NC} [Yes/No]"
        read -r create_more
      done
      break
      ;;
    
    "Community")
      echo -e "${GREEN}Initializing Community node...${NC}"
      
      # Get community name
      echo -e "${YELLOW}Enter your community name:${NC}"
      read -r COMMUNITY_NAME
      
      # Run node
      echo -e "${YELLOW}Running run-node.sh with name '$COMMUNITY_NAME' and no federation...${NC}"
      read -p "Proceed? [Y/n] " -n 1 -r
      echo
      if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        ./scripts/run-node.sh --node-name "$COMMUNITY_NAME" --no-federation
      else
        echo "Skipped running node."
      fi
      
      # Generate observer identity
      echo -e "${YELLOW}Generating observer identity...${NC}"
      read -p "Proceed? [Y/n] " -n 1 -r
      echo
      if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        ./scripts/generate-identity.sh --name "observer" --coop "$COMMUNITY_NAME" --role "observer"
      else
        echo "Skipped generating observer identity."
      fi
      
      # Ask for additional identities
      echo -e "${YELLOW}Would you like to create additional identities?${NC} [Yes/No]"
      read -r create_more
      while [[ "$create_more" =~ ^[Yy][Ee][Ss]$ ]] || [[ "$create_more" =~ ^[Yy]$ ]]; do
        echo -e "${YELLOW}Enter identity name:${NC}"
        read -r ID_NAME
        
        echo -e "${YELLOW}Generating identity '$ID_NAME' with observer role...${NC}"
        read -p "Proceed? [Y/n] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
          ./scripts/generate-identity.sh --name "$ID_NAME" --coop "$COMMUNITY_NAME" --role "observer"
        else
          echo "Skipped generating identity."
        fi
        
        echo -e "${YELLOW}Create another identity?${NC} [Yes/No]"
        read -r create_more
      done
      break
      ;;
    
    "Federation")
      echo -e "${GREEN}Initializing Federation node...${NC}"
      
      # Get federation name
      echo -e "${YELLOW}Enter federation group name:${NC}"
      read -r FEDERATION_NAME
      
      # Run node
      echo -e "${YELLOW}Running run-node.sh with federation enabled...${NC}"
      read -p "Proceed? [Y/n] " -n 1 -r
      echo
      if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        ./scripts/run-node.sh --node-name "$FEDERATION_NAME" --enable-federation
      else
        echo "Skipped running node."
      fi
      
      # Get peer multiaddresses
      echo -e "${YELLOW}Enter federation peer multiaddresses (comma-separated):${NC}"
      read -r PEER_ADDRESSES
      
      # Write peer addresses to bootstrap-peers.toml
      PEERS_FILE="config/bootstrap-peers.toml"
      echo -e "${YELLOW}Writing peer addresses to ${PEERS_FILE}...${NC}"
      
      # Create peers file with header
      cat > "$PEERS_FILE" << EOF
# Federation Bootstrap Peers
# Generated by init-node.sh on $(date)
# Federation: $FEDERATION_NAME

[peers]
EOF
      
      # Parse comma-separated addresses and add them to the file
      IFS=',' read -ra ADDR_ARRAY <<< "$PEER_ADDRESSES"
      for i in "${!ADDR_ARRAY[@]}"; do
        ADDR=$(echo "${ADDR_ARRAY[$i]}" | xargs)  # Trim whitespace
        echo "peer$((i+1)) = \"$ADDR\"" >> "$PEERS_FILE"
      done
      
      echo -e "${GREEN}Peer configuration written to ${PEERS_FILE}${NC}"
      echo -e "${YELLOW}Connecting to federation peers...${NC}"
      read -p "Proceed? [Y/n] " -n 1 -r
      echo
      if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        ./scripts/run-node.sh --node-name "$FEDERATION_NAME" --enable-federation --bootstrap-peers "$PEERS_FILE" --restart
      else
        echo "Skipped connecting to federation peers."
      fi
      
      # Generate federation admin identity
      echo -e "${YELLOW}Generating federation admin identity...${NC}"
      read -p "Proceed? [Y/n] " -n 1 -r
      echo
      if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        ./scripts/generate-identity.sh --name "federation-admin" --coop "$FEDERATION_NAME" --role "admin"
      else
        echo "Skipped generating federation admin identity."
      fi

      # Check federation status
      echo -e "${YELLOW}Would you like to check federation connectivity?${NC} [Yes/No]"
      read -r check_federation
      if [[ "$check_federation" =~ ^[Yy][Ee][Ss]$ ]] || [[ "$check_federation" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Running federation status check...${NC}"
        read -p "Proceed? [Y/n] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
          ./scripts/federation-check.sh --peers "$PEERS_FILE" --verbose
        else
          echo "Skipped federation status check."
        fi
      fi

      break
      ;;
    
    *)
      echo "Invalid option. Please select 1, 2, 3, or 4."
      ;;
  esac
done

# AgoraNet Integration
echo -e "${YELLOW}Would you like to enable AgoraNet deliberation tools?${NC} [Yes/No]"
read -r enable_agora
if [[ "$enable_agora" =~ ^[Yy][Ee][Ss]$ ]] || [[ "$enable_agora" =~ ^[Yy]$ ]]; then
  echo -e "${YELLOW}Running AgoraNet service...${NC}"
  
  # Get cooperative name based on node type
  case $node_type in
    "Dev-Net")
      COOP_NAME="dev-net-test-coop"
      ;;
    "Cooperative")
      COOP_NAME="$COOP_NAME"
      ;;
    "Community")
      COOP_NAME="$COMMUNITY_NAME"
      ;;
    "Federation")
      COOP_NAME="$FEDERATION_NAME"
      ;;
  esac
  
  # Ask if it should run as a daemon
  echo -e "${YELLOW}Run AgoraNet as a background daemon?${NC} [Yes/No]"
  read -r run_daemon
  DAEMON_FLAG=""
  if [[ "$run_daemon" =~ ^[Yy][Ee][Ss]$ ]] || [[ "$run_daemon" =~ ^[Yy]$ ]]; then
    DAEMON_FLAG="--daemon"
  fi
  
  # Run the AgoraNet service
  read -p "Proceed? [Y/n] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    ./scripts/run-agoranet.sh --coop "$COOP_NAME" $DAEMON_FLAG
  else
    echo "Skipped running AgoraNet service."
  fi
else
  echo "Skipped enabling AgoraNet tools."
fi

# DNS and DID Registration
echo -e "${YELLOW}Would you like to register a DNS name and DID for your node?${NC} [Yes/No]"
read -r register_dns
if [[ "$register_dns" =~ ^[Yy][Ee][Ss]$ ]] || [[ "$register_dns" =~ ^[Yy]$ ]]; then
  echo -e "${YELLOW}Running DNS and DID registration...${NC}"
  
  # Get cooperative name based on node type
  case $node_type in
    "Dev-Net")
      COOP_NAME="dev-net-test-coop"
      ;;
    "Cooperative")
      COOP_NAME="$COOP_NAME"
      ;;
    "Community")
      COOP_NAME="$COMMUNITY_NAME"
      ;;
    "Federation")
      COOP_NAME="$FEDERATION_NAME"
      ;;
  esac
  
  # Run the DNS registration
  read -p "Proceed? [Y/n] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    ./scripts/register-dns.sh --coop "$COOP_NAME"
  else
    echo "Skipped DNS and DID registration."
  fi
else
  echo "Skipped DNS and DID registration."
fi

# Final verification
echo -e "${YELLOW}Verifying initialization by checking DAG state...${NC}"
read -p "Proceed? [Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
  ./scripts/replay-dag.sh --json
else
  echo "Skipped final verification."
fi

# Print summary
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}    ICN Node Initialization Summary   ${NC}"
echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}Node Type:${NC} $node_type"
case $node_type in
  "Dev-Net")
    echo -e "${GREEN}Environment:${NC} Test Network"
    ;;
  "Cooperative")
    echo -e "${GREEN}Cooperative Name:${NC} $COOP_NAME"
    ;;
  "Community")
    echo -e "${GREEN}Community Name:${NC} $COMMUNITY_NAME"
    ;;
  "Federation")
    echo -e "${GREEN}Federation Name:${NC} $FEDERATION_NAME"
    echo -e "${GREEN}Federation Peers:${NC} $PEER_ADDRESSES"
    ;;
esac

if [[ "$enable_agora" =~ ^[Yy][Ee][Ss]$ ]] || [[ "$enable_agora" =~ ^[Yy]$ ]]; then
  echo -e "${GREEN}AgoraNet Tools:${NC} Enabled"
  if [[ "$run_daemon" =~ ^[Yy][Ee][Ss]$ ]] || [[ "$run_daemon" =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}AgoraNet Mode:${NC} Background Daemon"
  else
    echo -e "${GREEN}AgoraNet Mode:${NC} Interactive"
  fi
else
  echo -e "${GREEN}AgoraNet Tools:${NC} Disabled"
fi

if [[ "$register_dns" =~ ^[Yy][Ee][Ss]$ ]] || [[ "$register_dns" =~ ^[Yy]$ ]]; then
  # Determine the cooperative name based on node type for display
  case $node_type in
    "Dev-Net")
      DNS_COOP="dev-net-test-coop"
      ;;
    "Cooperative")
      DNS_COOP="$COOP_NAME"
      ;;
    "Community")
      DNS_COOP="$COMMUNITY_NAME"
      ;;
    "Federation")
      DNS_COOP="$FEDERATION_NAME"
      ;;
  esac
  
  echo -e "${GREEN}DNS Registration:${NC} Enabled"
  echo -e "${GREEN}DNS Name:${NC} ${DNS_COOP}.icn"
  echo -e "${GREEN}DID:${NC} did:icn:${DNS_COOP}"
else
  echo -e "${GREEN}DNS Registration:${NC} Disabled"
fi

echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}Initialization complete!${NC}"
echo -e "${YELLOW}For additional configuration options, check the documentation.${NC}" 