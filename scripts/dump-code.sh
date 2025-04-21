#!/bin/bash
set -euo pipefail

# Default file names
OUT_FILE="icn-dev-node_dump.txt"
TMP_FILE=".tmp_icn_dump.txt"
INCLUDE_DEPS=false
EXCLUDE_PATTERNS=(
  "./.git/*"
  "./target/*"
  "./node_modules/*"
  "./deps/*"         # Exclude all content in deps by default
  "./.cursor/*"      # Exclude cursor IDE files
  "./.wallet/*"      # Exclude wallet data
)
INCLUDE_REPOS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      OUT_FILE="$2"
      shift 2
      ;;
    --include-deps)
      INCLUDE_DEPS=true
      shift
      ;;
    --exclude)
      EXCLUDE_PATTERNS+=("$2")
      shift 2
      ;;
    --include-repo)
      INCLUDE_REPOS+=("$2")
      shift 2
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  --out FILE              Output file name (default: icn-dev-node_dump.txt)"
      echo "  --include-deps          Include repositories from deps/ directory"
      echo "  --exclude PATTERN       Exclude files matching pattern (can be used multiple times)"
      echo "  --include-repo DIR      Include specific repository (requires --include-deps)"
      echo "  --help                  Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown flag: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

echo "🧵 Dumping repo to $OUT_FILE..."

# Write header
echo "# Code Dump for icn-dev-node" > "$TMP_FILE"
echo "# Generated on $(date)" >> "$TMP_FILE"
echo "# --------------------------------" >> "$TMP_FILE"

# Build exclude arguments for find
FIND_EXCLUDES=()
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
  FIND_EXCLUDES+=(-not -path "$pattern")
done

# Main repo files
find . -type f \
  "${FIND_EXCLUDES[@]}" \
  ! -name "$TMP_FILE" \
  ! -name "$OUT_FILE" \
  | sort | while read -r file; do
    echo -e "\n--- FILE: $file ---" >> "$TMP_FILE"
    cat "$file" >> "$TMP_FILE"
done

# Optional dependency dump (only if explicitly enabled)
if [ "$INCLUDE_DEPS" = true ]; then
  echo -e "\n\n# --- DEP REPOS ---" >> "$TMP_FILE"
  
  # If specific repos were provided, only include those
  if [ ${#INCLUDE_REPOS[@]} -gt 0 ]; then
    for repo in "${INCLUDE_REPOS[@]}"; do
      if [ -d "$repo" ]; then
        echo -e "\n\n## Repo: $repo" >> "$TMP_FILE"
        find "$repo" -type f -not -path "*/\.*" | sort | while read -r f; do
          echo -e "\n--- FILE: $f ---" >> "$TMP_FILE"
          cat "$f" >> "$TMP_FILE"
        done
      fi
    done
  else
    # Include all repos in deps directory
    for dep in deps/*; do
      if [ -d "$dep" ] && [ ! -d "$dep/.git" ]; then
        # Skip git repositories unless explicitly included
        continue
      fi
      
      if [ -d "$dep" ]; then
        echo -e "\n\n## Repo: $dep" >> "$TMP_FILE"
        find "$dep" -type f -not -path "*/\.*" | sort | while read -r f; do
          echo -e "\n--- FILE: $f ---" >> "$TMP_FILE"
          cat "$f" >> "$TMP_FILE"
        done
      fi
    done
  fi
fi

# Rename temp file to final output
mv "$TMP_FILE" "$OUT_FILE"
echo "✅ Dump completed: $OUT_FILE"
echo "📏 File size: $(du -h "$OUT_FILE" | cut -f1)"
