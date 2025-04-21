# ICN Developer Setup Guide

This guide explains how to set up a development environment for the Intercooperative Network (ICN), which consists of two main repositories:

- **icn-covm**: The Cooperative Virtual Machine — a programmable governance and economic execution engine
- **icn-dev-node**: The appliance that runs CoVM as a service, forming a mesh-federated network

## Directory Layout

For ICN development, both repositories should be cloned side by side:

```
~/dev/
├── icn-dev-node/  (this repository)
└── icn-covm/      (the CoVM repository)
```

This layout allows for a streamlined development workflow with path-based dependencies.

## Initial Setup

### 1. Clone Both Repositories

```bash
mkdir -p ~/dev
cd ~/dev
git clone <icn-dev-node-repo-url> icn-dev-node
git clone <icn-covm-repo-url> icn-covm
```

### 2. Link CoVM for Development

```bash
cd ~/dev/icn-dev-node
make link-covm
```

This will:
- Check if the CoVM repository exists in the expected location
- Copy it into `deps/icn-covm` (this directory is git-ignored)
- Configure the path-based dependency for the node to use your local CoVM code

### 3. Build the Node

```bash
make build
```

Or, if you prefer to use Cargo directly:

```bash
cargo build -p icn-node
```

## Development Workflow

### Making Changes to CoVM

1. Make changes to CoVM in `~/dev/icn-covm/`
2. Run `make link-covm` from the icn-dev-node directory to update the local copy
3. Build and test the node with your changes: `make build` and `make test`

### Version Locking with .covm-version

The `.covm-version` file contains a git commit hash that locks the node to a specific version of CoVM.

#### Check Version Status

To check if your linked CoVM matches the version in `.covm-version`:

```bash
make check-covm-version
```

#### Update .covm-version

To update `.covm-version` with the currently linked CoVM commit:

```bash
./scripts/check-covm-version.sh --update
```

Or manually:

```bash
echo $(cd ../icn-covm && git rev-parse HEAD) > .covm-version
```

#### Check Out a Specific Version

To check out a specific version of CoVM (e.g., from `.covm-version`):

```bash
cd ~/dev/icn-covm
git checkout $(cat ../icn-dev-node/.covm-version)
cd ../icn-dev-node
make link-covm
```

## Advanced Setup

### Force Linking (Ignore Warnings)

If you want to link CoVM despite warnings (e.g., uncommitted changes):

```bash
make link-covm-force
```

### Makefile Targets

| Target | Description |
|--------|-------------|
| `make link-covm` | Link CoVM for development |
| `make link-covm-force` | Force link CoVM (ignore warnings) |
| `make check-covm-version` | Check if CoVM version matches `.covm-version` |
| `make build` | Build the node |
| `make test` | Run tests |
| `make clean` | Clean build artifacts |
| `make init-dev` | Initialize development environment (link + build) |
| `make help` | Show available targets |

## Scripts

### setup-covm.sh

This script creates a copy of the CoVM repository in the `deps/` directory for local development.

```bash
./scripts/setup-covm.sh [--force] [-p /path/to/covm]
```

Options:
- `--force`: Ignore warnings about uncommitted changes
- `-p, --path PATH`: Specify a custom path to the CoVM repository

### check-covm-version.sh

This script checks if the currently linked CoVM version matches `.covm-version`.

```bash
./scripts/check-covm-version.sh [--quiet] [--update]
```

Options:
- `--quiet`: Only output on error (useful for CI)
- `--update`: Update `.covm-version` with the current CoVM commit

## Continuous Integration

For CI workflows, you can use:

```bash
./scripts/check-covm-version.sh --quiet
```

This will return a non-zero exit code if the versions don't match, which can be used to fail CI builds.

## Troubleshooting

### Build Errors

If you encounter build errors after updating CoVM:

1. Clean the build artifacts: `make clean`
2. Re-link CoVM: `make link-covm`
3. Try building again: `make build`

### Missing CoVM Repository

If the CoVM repository is not found:

1. Ensure it's cloned at `~/dev/icn-covm`
2. If it's in a different location, specify the path:
   ```bash
   ./scripts/setup-covm.sh -p /path/to/icn-covm
   ```

### Version Mismatch

If you get a version mismatch warning:

1. If intentional (testing new changes): Proceed as normal
2. If unintentional:
   - Switch CoVM to the expected version, or
   - Update `.covm-version` to match your current version

## Federation and Production Deployment

For production deployments, always:

1. Ensure CoVM is at a tagged release
2. Update `.covm-version` to match that release
3. Verify the match with `make check-covm-version`
4. Commit the updated `.covm-version` file

This ensures that all nodes in the federation are running the same version of CoVM. 