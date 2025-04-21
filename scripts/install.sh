#!/usr/bin/env bash
set -euo pipefail

# Default settings
SKIP_BUILD=false
RELEASE_BUILD=false
LOG_LEVEL="info"
DEPS_DIR="../deps"
CARGO_INSTALL=false
CLEAN_BUILD=false
SPECIFIC_REPO=""
UPDATE_VERSION_FILE=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    --release)
      RELEASE_BUILD=true
      shift
      ;;
    --log-level)
      LOG_LEVEL="$2"
      shift 2
      ;;
    --cargo-install)
      CARGO_INSTALL=true
      shift
      ;;
    --clean)
      CLEAN_BUILD=true
      shift
      ;;
    --repo)
      SPECIFIC_REPO="$2"
      shift 2
      ;;
    --no-update-version)
      UPDATE_VERSION_FILE=false
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--skip-build] [--release] [--log-level <level>] [--cargo-install] [--clean] [--repo <icn-covm|icn-agoranet|icn-wallet>] [--no-update-version]"
      exit 1
      ;;
  esac
done

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
  local missing_deps=false

  echo "Checking prerequisites..."
  
  if ! command_exists git; then
    echo "❌ git is not installed"
    missing_deps=true
  fi

  if ! command_exists rustc; then
    echo "❌ Rust is not installed"
    missing_deps=true
  fi

  if ! command_exists cargo; then
    echo "❌ Cargo is not installed"
    missing_deps=true
  fi

  # Check for pkg-config and libssl-dev on Linux
  if [[ "$(uname)" == "Linux" ]]; then
    if ! command_exists pkg-config; then
      echo "⚠️ pkg-config is not installed (required for building)"
      echo "  Ubuntu/Debian: sudo apt-get install pkg-config"
      echo "  Fedora/RHEL: sudo dnf install pkgconf-pkg-config"
      missing_deps=true
    fi
    
    if ! ldconfig -p 2>/dev/null | grep -q libssl; then
      echo "⚠️ libssl development files not found (required for building)"
      echo "  Ubuntu/Debian: sudo apt-get install libssl-dev"
      echo "  Fedora/RHEL: sudo dnf install openssl-devel"
      missing_deps=true
    fi
  fi

  if [[ "$missing_deps" = true ]]; then
    echo "Please install missing dependencies and try again."
    echo "To install Rust: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    exit 1
  fi

  echo "✅ All prerequisites met"
  
  # Check Rust version
  local rust_version
  rust_version=$(rustc --version | cut -d ' ' -f 2)
  echo "Rust version: $rust_version"
  
  # Check if Rust version is at least 1.60.0 (using basic string comparison)
  if [[ "$rust_version" < "1.60.0" ]]; then
    echo "⚠️ Recommended Rust version is 1.60.0 or higher"
    echo "Consider upgrading with: rustup update stable"
  fi
}

# Clone or update a repository
clone_or_update_repo() {
  local repo_url="$1"
  local target_dir="$2"
  local branch="${3:-main}"
  
  if [[ -d "$target_dir" ]]; then
    echo "Updating $target_dir..."
    (cd "$target_dir" && git fetch && git checkout "$branch" && git pull)
  else
    echo "Cloning $repo_url to $target_dir (branch: $branch)..."
    git clone --branch "$branch" "$repo_url" "$target_dir"
  fi
  
  # Record commit hash for icn-covm
  if [[ "$target_dir" == "icn-covm" && "$UPDATE_VERSION_FILE" == "true" ]]; then
    local commit_hash
    commit_hash=$(cd "$target_dir" && git rev-parse HEAD)
    echo "Recording CoVM commit hash: $commit_hash"
    cd "$(dirname "$DEPS_DIR")"
    echo "$commit_hash" > .covm-version
    cd - > /dev/null
  fi
}

# Build a repository
build_repo() {
  local repo_dir="$1"
  local repo_name="$2"
  
  echo "Building $repo_name..."
  cd "$repo_dir"
  
  # Clean if requested
  if [[ "$CLEAN_BUILD" = true ]]; then
    echo "Cleaning previous build..."
    cargo clean
  fi
  
  # Build with appropriate flags
  if [[ "$RELEASE_BUILD" = true ]]; then
    if [[ "$CARGO_INSTALL" = true ]]; then
      echo "Running cargo install --path . --force in release mode..."
      cargo install --path . --force
    else
      echo "Running cargo build --release..."
      cargo build --release
    fi
  else
    if [[ "$CARGO_INSTALL" = true ]]; then
      echo "Running cargo install --path . --force in debug mode..."
      cargo install --path . --force --debug
    else
      echo "Running cargo build..."
      cargo build
    fi
  fi
  
  echo "✅ $repo_name build completed!"
}

# Check and setup project dependencies
check_dependencies() {
  local repo_dir="$1"
  
  if [[ -f "$repo_dir/Cargo.toml" ]]; then
    echo "Checking dependencies for $(basename "$repo_dir")..."
    
    # Look for external dependencies that need to be installed
    if grep -q 'protoc' "$repo_dir/Cargo.toml"; then
      if ! command_exists protoc; then
        echo "⚠️ Protocol Buffers compiler (protoc) is required but not found"
        echo "  Ubuntu/Debian: sudo apt-get install protobuf-compiler"
        echo "  macOS: brew install protobuf"
        echo "  Or download from https://github.com/protocolbuffers/protobuf/releases"
        echo "Installation will continue, but build may fail"
      else
        echo "✅ Protocol Buffers compiler (protoc) found"
      fi
    fi
  fi
}

# Main installation function
install() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$script_dir"
  
  # Create deps directory if it doesn't exist
  mkdir -p "$DEPS_DIR"
  cd "$DEPS_DIR"
  
  # Define repositories to handle
  declare -A repos=(
    ["icn-covm"]="https://github.com/interchainio/icn-covm.git"
    ["icn-agoranet"]="https://github.com/interchainio/icn-agoranet.git"
    ["icn-wallet"]="https://github.com/interchainio/icn-wallet.git"
  )
  
  # Process only specific repo if requested
  if [[ -n "$SPECIFIC_REPO" ]]; then
    if [[ -v "repos[$SPECIFIC_REPO]" ]]; then
      echo "Processing only the $SPECIFIC_REPO repository..."
      local filtered_repos=("$SPECIFIC_REPO")
    else
      echo "❌ Unknown repository: $SPECIFIC_REPO"
      echo "Valid repositories: ${!repos[*]}"
      exit 1
    fi
  else
    local filtered_repos=("${!repos[@]}")
  fi
  
  # Clone or update repos
  for repo in "${filtered_repos[@]}"; do
    clone_or_update_repo "${repos[$repo]}" "$repo"
  done
  
  # Build if not skipped
  if [[ "$SKIP_BUILD" = false ]]; then
    # Always build icn-covm if it's in the list
    if [[ -z "$SPECIFIC_REPO" ]] || [[ "$SPECIFIC_REPO" == "icn-covm" ]]; then
      check_dependencies "icn-covm"
      build_repo "icn-covm" "icn-covm"
    fi
    
    # Build other repos if specified
    if [[ "$SPECIFIC_REPO" == "icn-agoranet" ]]; then
      check_dependencies "icn-agoranet"
      build_repo "icn-agoranet" "icn-agoranet"
    elif [[ "$SPECIFIC_REPO" == "icn-wallet" ]]; then
      check_dependencies "icn-wallet"
      build_repo "icn-wallet" "icn-wallet"
    fi
  else
    echo "Skipping build as requested."
  fi
  
  echo "Installation completed successfully!"
  
  # Print information about the installed packages
  local build_type="debug"
  if [[ "$RELEASE_BUILD" = true ]]; then
    build_type="release"
  fi
  
  echo "===== Installation Summary ====="
  echo "ICN repositories installed in: $(cd "$DEPS_DIR" && pwd)"
  
  # Display CoVM version info
  cd "$(dirname "$DEPS_DIR")"
  if [[ -f ".covm-version" ]]; then
    echo "🔢 CoVM commit in use: $(cat .covm-version)"
  else
    echo "⚠️ No CoVM version tracked. Run './scripts/check-covm-status.sh' for details."
  fi
  
  if [[ "$SKIP_BUILD" = false ]]; then
    if [[ -z "$SPECIFIC_REPO" ]] || [[ "$SPECIFIC_REPO" == "icn-covm" ]]; then
      echo "ICN-COVM binary: $(cd "$DEPS_DIR" && pwd)/icn-covm/target/$build_type/icn-node"
    fi
  fi
  
  echo "To run the node: ./run-node.sh"
}

# Main script execution
check_prerequisites
install 