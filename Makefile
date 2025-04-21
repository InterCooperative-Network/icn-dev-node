.PHONY: link-covm check-covm-version clean build test 

# Link CoVM for development
link-covm:
	@echo "Linking CoVM for development..."
	@chmod +x scripts/setup-covm.sh
	@./scripts/setup-covm.sh
	@echo "✅ CoVM linked. You can now run 'cargo build -p icn-node'"

# Force link CoVM (ignore warnings)
link-covm-force:
	@echo "Forcing CoVM link (ignoring warnings)..."
	@chmod +x scripts/setup-covm.sh
	@./scripts/setup-covm.sh --force
	@echo "✅ CoVM force-linked. You can now run 'cargo build -p icn-node'"

# Check if CoVM version matches .covm-version
check-covm-version:
	@echo "Checking CoVM version..."
	@chmod +x scripts/check-covm-version.sh
	@./scripts/check-covm-version.sh

# Clean build artifacts
clean:
	cargo clean

# Build the node
build:
	cargo build -p icn-node

# Run tests
test:
	cargo test -p icn-node

# Initialize development environment
init-dev: link-covm build

# Help message
help:
	@echo "ICN Development Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  link-covm          - Link CoVM for development (from ../icn-covm)"
	@echo "  link-covm-force    - Force link CoVM (ignore warnings)"
	@echo "  check-covm-version - Check if CoVM version matches .covm-version"
	@echo "  clean              - Clean build artifacts"
	@echo "  build              - Build the node"
	@echo "  test               - Run tests"
	@echo "  init-dev           - Initialize development environment"
	@echo ""
	@echo "See docs/DEVELOPER_SETUP.md for detailed instructions."

# Default target
default: help 