# ICN Cooperative Node Runner

The Cooperative Node Runner is a Rust implementation of the core node functionality for the Intercooperative Network (ICN). It connects proposal ingestion, CoVM execution, DAG recording, and federation sync into a persistent loop.

## Features

- Monitors proposal queue for `.dsl` files
- Fetches proposals from AgoraNet (optional)
- Validates proposals using CoVM
- Executes valid proposals using the CoVM
- Records execution in DAG
- Publishes DAG state to federation
- Provides CLI interface for node management

## Usage

### Building

```
cd crates/icn-node
cargo build
```

### Running

#### Daemon Mode

Start the node in daemon mode that checks for proposals every 30 seconds:

```
./target/debug/icn-node run --interval 30
```

#### Execute a Specific Proposal

Execute a specific proposal file:

```
./target/debug/icn-node execute --file path/to/proposal.dsl
```

#### Trace a Proposal

Look up execution history and results for a specific proposal:

```
./target/debug/icn-node trace --proposal 123
```

#### Watch Mode

Watch both the DAG and proposal queue in real-time:

```
./target/debug/icn-node watch
```

### Integration with Scripts

The node runner can be used directly from the `daemon.sh` script with the `--rust-node` flag (enabled by default). 

You can also use the provided wrapper script:

```
./scripts/icn-node-runner.sh run --interval 15
```

## Architecture

The node is structured into several modules:

- `executor.rs`: Handles proposal execution using CoVM
- `queue.rs`: Manages the proposal queue
- `dag.rs`: Handles DAG operations
- `federation.rs`: Manages federation communication
- `state.rs`: Manages node state persistence

## State Management

The node state is stored in `~/.icn/state.json` and includes:

- Node identity
- Execution history
- DAG vertices
- Federation information

## Logs

Logs are stored in `~/.icn/logs/`:
- `icn-node.log`: General node logs
- `dag.log`: DAG vertex logs 
- `rejected.log`: Rejected proposals 