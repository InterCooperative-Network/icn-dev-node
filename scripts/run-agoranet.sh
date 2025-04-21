#!/bin/bash

# AgoraNet Service Runner
# This script starts the AgoraNet deliberation service as a long-running process

set -e

# Default values
PORT=7654
DAG_PATH="$HOME/.icn-node/dag"
COOP_NAME=""
VERBOSE=false
DAEMON=false
LOG_FILE="$HOME/.icn-node/agoranet.log"
API_ENABLED=true

# ANSI color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print header
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}       AgoraNet Service Runner        ${NC}"
echo -e "${BLUE}======================================${NC}"

# Function to show usage
show_usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --coop NAME         Cooperative name to associate with this AgoraNet instance"
  echo "  --port PORT         API port to listen on (default: 7654)"
  echo "  --dag-path PATH     Path to ICN DAG directory (default: ~/.icn-node/dag)"
  echo "  --daemon            Run as a background daemon"
  echo "  --log-file FILE     Log file when running as daemon (default: ~/.icn-node/agoranet.log)"
  echo "  --no-api            Disable API server"
  echo "  --verbose           Enable verbose logging"
  echo "  --help              Show this help message"
  echo ""
  echo "Examples:"
  echo "  $0 --coop mycoop --port 8000"
  echo "  $0 --coop federation-xyz --daemon"
  exit 1
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --coop)
      COOP_NAME="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --dag-path)
      DAG_PATH="$2"
      shift 2
      ;;
    --daemon)
      DAEMON=true
      shift
      ;;
    --log-file)
      LOG_FILE="$2"
      shift 2
      ;;
    --no-api)
      API_ENABLED=false
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

# Ensure a cooperative name is provided
if [[ -z "$COOP_NAME" ]]; then
  echo -e "${YELLOW}No cooperative name specified. Using interactive mode.${NC}"
  echo -e "${YELLOW}Enter cooperative name:${NC}"
  read -r COOP_NAME
  
  if [[ -z "$COOP_NAME" ]]; then
    echo -e "${RED}Error: Cooperative name is required.${NC}"
    exit 1
  fi
fi

# Check if DAG path exists
if [[ ! -d "$DAG_PATH" ]]; then
  echo -e "${YELLOW}DAG directory does not exist at: $DAG_PATH${NC}"
  echo -e "${YELLOW}Creating directory...${NC}"
  mkdir -p "$DAG_PATH"
fi

# Function to start AgoraNet service
start_agoranet() {
  echo -e "${GREEN}Starting AgoraNet service for cooperative: $COOP_NAME${NC}"
  echo -e "${GREEN}DAG Path: $DAG_PATH${NC}"
  
  if [[ "$API_ENABLED" = true ]]; then
    echo -e "${GREEN}API Server: Enabled on port $PORT${NC}"
  else
    echo -e "${GREEN}API Server: Disabled${NC}"
  fi
  
  # Create a PID file to track the process
  PID_FILE="/tmp/agoranet-$COOP_NAME.pid"
  
  # Check if already running
  if [[ -f "$PID_FILE" ]]; then
    PID=$(cat "$PID_FILE")
    if ps -p "$PID" > /dev/null; then
      echo -e "${YELLOW}AgoraNet service for $COOP_NAME is already running with PID: $PID${NC}"
      echo -e "${YELLOW}To restart, kill the existing process or use --restart flag.${NC}"
      exit 0
    else
      echo -e "${YELLOW}Found stale PID file. Cleaning up...${NC}"
      rm "$PID_FILE"
    fi
  fi
  
  # Start the service
  if [[ "$DAEMON" = true ]]; then
    echo -e "${GREEN}Running as daemon, logging to: $LOG_FILE${NC}"
    
    # Use demo-proposals.sh as a base for now, will be replaced with actual AgoraNet daemon
    # In a real implementation, this would start a proper background service
    {
      echo "--- AgoraNet Service Started at $(date) ---"
      echo "Cooperative: $COOP_NAME"
      echo "API Port: $PORT"
      echo "DAG Path: $DAG_PATH"
      
      # Call demo-proposals as a placeholder for the real AgoraNet service
      if [[ "$API_ENABLED" = true ]]; then
        echo "Starting API server on port $PORT..."
        echo "This is a placeholder for the actual AgoraNet API server"
        
        # Simulate an API server with netcat (if available)
        if command -v nc &> /dev/null; then
          echo "HTTP/1.1 200 OK" > /tmp/agoranet-response.http
          echo "Content-Type: application/json" >> /tmp/agoranet-response.http
          echo "" >> /tmp/agoranet-response.http
          echo "{\"status\":\"running\",\"cooperative\":\"$COOP_NAME\",\"uptime\":0}" >> /tmp/agoranet-response.http
          
          # Don't actually start this in production - just a demo
          # while true; do nc -l -p $PORT < /tmp/agoranet-response.http; done
        fi
      fi
      
      # Execute the demo-proposals script in the background
      ./scripts/demo-proposals.sh --no-start --coop "$COOP_NAME" --monitor
      
      echo "--- AgoraNet Service Stopped at $(date) ---"
    } > "$LOG_FILE" 2>&1 &
    
    # Save the PID
    echo $! > "$PID_FILE"
    echo -e "${GREEN}AgoraNet service started with PID: $(cat "$PID_FILE")${NC}"
    echo -e "${GREEN}To check logs: tail -f $LOG_FILE${NC}"
    echo -e "${GREEN}To stop: kill $(cat "$PID_FILE") && rm $PID_FILE${NC}"
  else
    # Interactive mode
    echo -e "${GREEN}Running in interactive mode...${NC}"
    echo -e "${GREEN}Press Ctrl+C to stop${NC}"
    
    # Call demo-proposals.sh as a placeholder for the real AgoraNet service
    ./scripts/demo-proposals.sh --no-start --coop "$COOP_NAME" --verbose
    
    echo -e "${GREEN}AgoraNet service stopped.${NC}"
  fi
}

# Start the service
start_agoranet

echo -e "${BLUE}======================================${NC}"
if [[ "$DAEMON" = true ]]; then
  echo -e "${GREEN}AgoraNet service is running in the background.${NC}"
else
  echo -e "${GREEN}AgoraNet service has completed.${NC}"
fi 