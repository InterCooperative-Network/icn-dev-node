# ICN Identity Storage Directory

This directory contains scoped identities for the InterChain Network (ICN).

## Directory Structure

```
.wallet/identities/
  ├── <coop-name>/           # Namespace for a specific cooperative
  │   ├── admin.json         # Admin identity for this cooperative
  │   ├── member1.json       # Member identity
  │   └── observer1.json     # Observer identity
  └── <another-coop>/        # Another cooperative namespace
      └── ...                # More identities
```

## Usage

Identities in this directory can be used with the ICN node by referencing their path:

```bash
# Create a proposal using a specific identity
icn-node tx gov submit-proposal \
  --from-macro proposal.dsl \
  --identity .wallet/identities/my-coop/admin.json

# Vote on a proposal
icn-node tx gov vote <proposal-id> yes \
  --identity .wallet/identities/my-coop/member1.json
```

## Security Note

All identity files (*.json) are excluded in .gitignore to prevent committing private keys or sensitive information.
