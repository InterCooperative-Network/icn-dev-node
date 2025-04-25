#!/bin/bash

# Test script for linking credentials to AgoraNet threads
# This script demonstrates the end-to-end flow for credential linking

set -e

# Configuration variables
WALLET_DIR="../icn-wallet"
AGORANET_DIR="../icn-agoranet"
RUNTIME_ENDPOINT="http://localhost:8000"
AGORANET_ENDPOINT="http://localhost:8080"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔗 ICN AgoraNet Credential Linking Test${NC}"
echo "-------------------------------------"
echo

# Check if AgoraNet is running
if ! curl -s "$AGORANET_ENDPOINT" > /dev/null; then
  echo -e "${YELLOW}⚠️  AgoraNet not running. Starting AgoraNet...${NC}"
  
  # Start AgoraNet in the background
  cd "$AGORANET_DIR"
  cargo run &
  AGORANET_PID=$!
  
  # Wait for AgoraNet to start
  echo "Waiting for AgoraNet to start..."
  while ! curl -s "$AGORANET_ENDPOINT" > /dev/null; do
    sleep 1
  done
  
  echo -e "${GREEN}✅ AgoraNet started${NC}"
else
  echo -e "${GREEN}✅ AgoraNet is already running${NC}"
fi

echo

# Create a test thread
echo -e "${BLUE}Step 1: Creating a test thread in AgoraNet${NC}"
PROPOSAL_ID="test-proposal-$(date +%s)"
THREAD_PAYLOAD='{
  "title": "Test Thread for Credential Linking",
  "content": "This is a test thread for linking credentials",
  "author_did": "did:icn:test:author",
  "proposal_id": "'$PROPOSAL_ID'",
  "tags": ["test", "credential-linking"]
}'

# Create the thread
THREAD_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "$THREAD_PAYLOAD" \
  "$AGORANET_ENDPOINT/api/threads")

THREAD_ID=$(echo $THREAD_RESPONSE | jq -r .id)

echo -e "${GREEN}✅ Thread created with ID: $THREAD_ID${NC}"
echo -e "${GREEN}✅ Thread proposal ID: $PROPOSAL_ID${NC}"
echo

# Create a test credential in the wallet
echo -e "${BLUE}Step 2: Creating a test credential in the wallet${NC}"
CREDENTIAL_PAYLOAD='{
  "id": "cred-'$(uuidgen)'",
  "title": "Test Governance Credential",
  "type": "vote",
  "issuer": {
    "did": "did:icn:test:issuer",
    "name": "Test Issuer"
  },
  "subjectDid": "did:icn:test:subject",
  "issuanceDate": "'$(date -Iseconds)'",
  "credentialSubject": {
    "proposalId": "'$PROPOSAL_ID'",
    "executionHash": "0x1234567890",
    "jobId": "job-123"
  },
  "proof": {
    "type": "Ed25519Signature2020",
    "created": "'$(date -Iseconds)'",
    "verificationMethod": "did:icn:test:issuer#keys-1",
    "proofPurpose": "assertionMethod",
    "proofValue": "z3TSgXTuaHxY2GhXprJtqZD"
  },
  "trustLevel": "High",
  "tags": ["test", "vote"]
}'

# Save the credential to a temporary file
CREDENTIAL_FILE="/tmp/test-credential.json"
echo $CREDENTIAL_PAYLOAD > $CREDENTIAL_FILE

echo -e "${GREEN}✅ Test credential created${NC}"
echo -e "${YELLOW}   Credential file: $CREDENTIAL_FILE${NC}"
echo

# Link the credential to the thread
echo -e "${BLUE}Step 3: Linking the credential to the thread${NC}"
cd "$WALLET_DIR"

# Install the credential linking utility if needed
if ! npm list | grep -q "credential-utils"; then
  echo -e "${YELLOW}⚠️  Installing credential-utils...${NC}"
  npm install
fi

# Create a test linking script
LINKING_SCRIPT="/tmp/link-credential.js"
cat > $LINKING_SCRIPT << EOF
const fs = require('fs');
const { linkCredentialToAgoraThread } = require('./packages/credential-utils');

async function main() {
  const credential = JSON.parse(fs.readFileSync('$CREDENTIAL_FILE', 'utf8'));
  
  const result = await linkCredentialToAgoraThread(credential, {
    agoraNetEndpoint: '$AGORANET_ENDPOINT',
    threadId: '$THREAD_ID',
    metadata: {
      test: true,
      description: 'Test credential link'
    }
  });
  
  console.log(JSON.stringify(result, null, 2));
}

main().catch(console.error);
EOF

# Run the script
echo -e "${YELLOW}Executing linking script...${NC}"
NODE_RESULT=$(node $LINKING_SCRIPT)

if echo "$NODE_RESULT" | grep -q '"success":true'; then
  echo -e "${GREEN}✅ Credential successfully linked to thread!${NC}"
  echo -e "${YELLOW}$(echo $NODE_RESULT | jq -r .threadUrl)${NC}"
else
  echo -e "${RED}❌ Failed to link credential:${NC}"
  echo "$NODE_RESULT"
  exit 1
fi

echo

# Verify the link
echo -e "${BLUE}Step 4: Verifying the credential link${NC}"
LINKS_RESPONSE=$(curl -s "$AGORANET_ENDPOINT/api/threads/credential-links?thread_id=$THREAD_ID")
LINKS_COUNT=$(echo $LINKS_RESPONSE | jq '.linked_credentials | length')

if [ "$LINKS_COUNT" -gt 0 ]; then
  echo -e "${GREEN}✅ Found $LINKS_COUNT credential link(s) for thread $THREAD_ID${NC}"
  echo -e "${YELLOW}$(echo $LINKS_RESPONSE | jq -r '.linked_credentials[0].credential_id')${NC}"
else
  echo -e "${RED}❌ No links found for thread $THREAD_ID${NC}"
  exit 1
fi

echo
echo -e "${GREEN}🎉 All tests completed successfully!${NC}"

# Clean up
echo -e "${BLUE}Cleaning up...${NC}"
rm -f $CREDENTIAL_FILE $LINKING_SCRIPT

# Kill AgoraNet if we started it
if [ -n "$AGORANET_PID" ]; then
  kill $AGORANET_PID
  echo -e "${YELLOW}AgoraNet stopped${NC}"
fi

echo -e "${GREEN}Done!${NC}" 