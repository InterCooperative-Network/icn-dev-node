# ICN Development Node

A developer-friendly environment for running and testing ICN (InterChain Network) nodes with support for both local development and testnet connectivity.

## 🚀 Quick Start

```bash
# Clone this repository
git clone https://github.com/your-org/icn-dev-node.git
cd icn-dev-node

# Install dependencies and build ICN Node
./scripts/install.sh

# Run a local node
./scripts/run-node.sh

# OR connect to the testnet
./scripts/join-testnet.sh

# Generate identities and simulate a cooperative
./scripts/simulate-coop.sh --coop "my-coop" --identity-count 3 --replay
```

## 🛠️ Prerequisites

- **Rust** (1.60+) and Cargo
- **Git**
- **pkg-config** and **libssl-dev** (Linux) or equivalent on your platform
- **jq** (for JSON processing in the scripts)
- **Docker** (optional, for containerized runs)

## 📂 Repository Structure

```
.
├── .wallet/                # Identity storage
│   └── identities/         # Scoped identities by cooperative
├── config/                 # Configuration templates
│   ├── dev-config.toml     # Local development configuration
│   ├── testnet-config.toml # Testnet connection configuration
│   └── bootstrap-peers.toml # Testnet peer information
├── docker/                 # Docker-related files
│   ├── Dockerfile          # Multi-stage Dockerfile for ICN node
│   ├── docker-compose.yml  # Compose setup with persistent storage
│   └── entrypoint.sh       # Container entrypoint script
├── scripts/                # Helper scripts
│   ├── install.sh          # Dependency installation script
│   ├── run-node.sh         # Local node runner
│   ├── join-testnet.sh     # Testnet connection script
│   ├── demo-proposals.sh   # Script for governance demos
│   ├── generate-identity.sh # Create scoped identities
│   ├── replay-dag.sh       # Trace and replay DAG state
│   └── simulate-coop.sh    # Simulate a cooperative with governance
└── .env.example            # Environment variable template
```

## 📋 Usage Instructions

### Installation

```bash
# Default installation
./scripts/install.sh

# Skip building (useful for CI or if already built)
./scripts/install.sh --skip-build

# Build with release mode
./scripts/install.sh --release

# Install the binary to your PATH
./scripts/install.sh --cargo-install

# Clean build (removes previous artifacts)
./scripts/install.sh --clean

# Install/update only a specific repository
./scripts/install.sh --repo icn-covm
```

### Running a Local Node

```bash
# Start with default settings
./scripts/run-node.sh

# Custom node name
./scripts/run-node.sh --node-name "my-awesome-node"

# Custom data directory
./scripts/run-node.sh --data-dir "/path/to/data"

# Without federation or storage
./scripts/run-node.sh --no-federation --no-storage

# With release build
./scripts/run-node.sh --release
```

### Joining the Testnet

```bash
# Join with default settings
./scripts/join-testnet.sh

# Custom configuration file
./scripts/join-testnet.sh --config "/path/to/my-testnet-config.toml"

# Use specific bootstrap peers file
./scripts/join-testnet.sh --bootstrap-peers "/path/to/peers.toml"

# Skip peer validation
./scripts/join-testnet.sh --no-validate-peers

# Increase connection retry attempts
./scripts/join-testnet.sh --retry 5
```

### Managing Scoped Identities

```bash
# Generate an identity with default settings
./scripts/generate-identity.sh

# Create an admin identity for a specific cooperative
./scripts/generate-identity.sh --name "admin" --coop "my-cooperative" --role "admin"

# Create a member identity
./scripts/generate-identity.sh --name "member1" --coop "my-cooperative" --role "member"

# Create an observer with custom output directory
./scripts/generate-identity.sh --name "observer1" --coop "my-cooperative" --role "observer" --output "/custom/path"

# Show verbose output
./scripts/generate-identity.sh --verbose
```

### Exploring the DAG and Proposals

```bash
# Show general DAG information
./scripts/replay-dag.sh

# Show proposal details
./scripts/replay-dag.sh --proposal <proposal-id>

# Show vertex details with ancestry and descendants
./scripts/replay-dag.sh --vertex <vertex-id>

# Output as JSON for further processing
./scripts/replay-dag.sh --json

# Use with offline DAG path
./scripts/replay-dag.sh --dag-path "/path/to/dag/data"

# Custom node URL (for remote nodes)
./scripts/replay-dag.sh --node-url "http://remote-node:26657"
```

### Simulating a Cooperative

```bash
# Run a basic simulation with default settings
./scripts/simulate-coop.sh

# Create a named cooperative with 5 members
./scripts/simulate-coop.sh --coop "village-coop" --identity-count 5

# Use a custom governance macro
./scripts/simulate-coop.sh --governance-macro "budget_allocation"

# Show DAG replay after simulation
./scripts/simulate-coop.sh --replay

# Verbose output for debugging
./scripts/simulate-coop.sh --verbose
```

### Running Demo Proposals

```bash
# Create and vote on a demo governance proposal
./scripts/demo-proposals.sh

# Use with an already running node
./scripts/demo-proposals.sh --no-start

# Create a proposal with a specific identity
./scripts/demo-proposals.sh --scoped-identity "your-identity-address"

# Use a different proposal type
./scripts/demo-proposals.sh --proposal-type "ParameterChange"

# Skip DAG state display
./scripts/demo-proposals.sh --no-dag
```

### Using Docker

```bash
# Build and start the container
cd docker
docker-compose up -d

# View logs
docker-compose logs -f

# Stop the container
docker-compose down
```

## ⚙️ Configuration

You can configure the node using:

1. **Command-line flags** (as shown in the usage examples)
2. **Environment variables** (copy `.env.example` to `.env` and edit)
3. **Configuration files** (in the `config/` directory)

Important configurable options:

- **Node name** - Identifies your node in the network
- **P2P/RPC ports** - Network connectivity settings
- **Bootstrap peers** - For connecting to testnet
- **Data directory** - Where blockchain data is stored
- **Federation settings** - For cooperative network participation
- **Storage settings** - For distributed storage capabilities

## 🔍 ICN Concepts

The InterChain Network (ICN) is built around several key concepts:

- **CoVM (Cooperative Virtual Machine)** - A Byzantine fault-tolerant execution environment for cooperative applications.
- **DAG Ledger** - A directed acyclic graph that stores the chain state and provides an immutable audit trail of all operations.
- **Scoped Identity** - Namespace-based role system that allows identities to have different permissions in different contexts.
- **Federation** - A peer-based messaging and policy synchronization system enabling network coordination.
- **CEC / Tokens** - Non-speculative typed tokens used for reputation, budgeting, and other cooperative functions.

### Understanding Scoped Identities

Identities in ICN are always scoped to a specific cooperative namespace:

- Each cooperative has its own identity namespace (e.g., `coop-xyz`, `town-council`, etc.)
- Identities have roles within their scope (`admin`, `member`, `observer`)
- Actions are authorized based on the scope + role combination
- Identities can be stored locally in the `.wallet/identities/<coop>/<name>.json` directory

### Understanding the DAG Structure

The DAG (Directed Acyclic Graph) provides a distributed, versioned record of all network activity:

- **Vertices**: Individual entries in the DAG, with a unique ID
- **Parents/Children**: Relationships between vertices showing causality
- **Proposals**: Special vertices containing governance actions
- **Votes**: Vertices that reference a proposal vertex and contain a vote decision
- **Scopes**: Vertices are scoped to specific cooperatives or system-wide

## 🧩 Governance Process

Governance in ICN follows a structured lifecycle:

1. **Proposal Creation**: An identity with sufficient permissions creates a proposal
2. **Discussion Period**: Members can discuss the proposal (off-chain or via comments)
3. **Voting Period**: Eligible members cast votes (yes/no/abstain) 
4. **Execution**: If approved, the proposal actions are executed on the CoVM

The `simulate-coop.sh` script demonstrates this entire process with test identities.

## 🧪 Troubleshooting

### Common Issues

**Q: Node fails to start with "address already in use" error**
A: Another process is using one of the required ports. Check with `lsof -i :26657` and stop the conflicting process.

**Q: Cannot connect to testnet peers**
A: Ensure your firewall allows outbound connections to port 26656, and that you've configured the correct bootstrap peers.

**Q: Build errors during installation**
A: Ensure you have all system dependencies installed. On Ubuntu: `apt-get install -y git pkg-config libssl-dev build-essential`

**Q: Federation not working between nodes**
A: Check that both nodes have `--federation` flag enabled and that they can reach each other on their P2P ports.

**Q: Identity generation fails**
A: Make sure the ICN node binary is built and the identity directory is writable by your user.

**Q: DAG replay shows no data**
A: Ensure the node has been running for some time and has processed at least one proposal or transaction.

## 🤝 Contributing

Contributions are welcome! Please ensure:

1. Scripts follow shellcheck guidelines (use pre-commit hooks)
2. All scripts include proper error handling (`set -euo pipefail`)
3. New features are properly documented in README

To set up pre-commit hooks:

```bash
pip install pre-commit
pre-commit install
```

## 📜 License

[Add license information here] 