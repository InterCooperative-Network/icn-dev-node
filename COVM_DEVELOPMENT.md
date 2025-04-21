# CoVM Development Workflow

This document explains how to set up a development environment for working on the Intercooperative Network (ICN) Node with a local copy of the Cooperative Virtual Machine (CoVM).

## Repository Setup

For CoVM development, you need both repositories cloned side by side:

```
~/dev/
├── icn-dev-node/  (this repository)
└── icn-covm/      (the CoVM repository)
```

## Initial Setup

1. Clone both repositories:

```bash
mkdir -p ~/dev
cd ~/dev
git clone <icn-dev-node-repo-url> icn-dev-node
git clone <icn-covm-repo-url> icn-covm
```

2. Link CoVM as a development dependency:

```bash
cd ~/dev/icn-dev-node
./scripts/setup-covm.sh
```

This script copies the CoVM repository into the `deps/icn-covm` directory, allowing the node to build against your local CoVM code.

## Development Workflow

When developing CoVM features and testing them in the node:

1. Make changes to the CoVM repository in `~/dev/icn-covm/`
2. Run the setup script to update the copy in the node:
   ```bash
   cd ~/dev/icn-dev-node
   ./scripts/setup-covm.sh
   ```
3. Build and test your changes:
   ```bash
   cargo build -p icn-node
   ```
   or
   ```bash
   cargo test -p icn-node
   ```

## Version Locking

The node can be locked to a specific version of CoVM using the `.covm-version` file:

- To lock to your current CoVM version:
  ```bash
  cd ~/dev/icn-dev-node
  echo $(cd ../icn-covm && git rev-parse HEAD) > .covm-version
  ```

- To check out a specific version of CoVM:
  ```bash
  cd ~/dev/icn-covm
  git checkout $(cat ../icn-dev-node/.covm-version)
  cd ../icn-dev-node
  ./scripts/setup-covm.sh
  ```

The setup script will warn you if your local CoVM version doesn't match the version in `.covm-version`.

## Troubleshooting

If you encounter build errors after updating CoVM:

1. Run `cargo clean` in the node repository
2. Re-run the setup script
3. Try building again

This ensures a clean build with the latest CoVM code. 