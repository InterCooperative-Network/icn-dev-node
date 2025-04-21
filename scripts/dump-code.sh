#!/bin/bash
set -euo pipefail

# Default file names
OUT_FILE="icn-dev-node_dump.txt"
TMP_FILE=".tmp_icn_dump.txt"
INCLUDE_DEPS=false

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
    *)
      echo "Unknown flag: $1"
      exit 1
      ;;
  esac
done

echo "🧵 Dumping repo to $OUT_FILE..."

# Write header
echo "# Code Dump for icn-dev-node" > "$TMP_FILE"
echo "# Generated on $(date)" >> "$TMP_FILE"
echo "# --------------------------------" >> "$TMP_FILE"

# Main repo files (excluding .git, target, and the temp dump file itself)
find . -type f \
  ! -path "./.git/*" \
  ! -path "./target/*" \
  ! -name "$TMP_FILE" \
  ! -name "$OUT_FILE" \
  | sort | while read -r file; do
    echo -e "\n--- FILE: $file ---" >> "$TMP_FILE"
    cat "$file" >> "$TMP_FILE"
done

# Optional dependency dump
if [ "$INCLUDE_DEPS" = true ]; then
  echo -e "\n\n# --- DEP REPOS ---" >> "$TMP_FILE"
  for dep in deps/*; do
    if [ -d "$dep" ]; then
      echo -e "\n\n## Repo: $dep" >> "$TMP_FILE"
      find "$dep" -type f -name "*.rs" | sort | while read -r f; do
        echo -e "\n--- FILE: $f ---" >> "$TMP_FILE"
        cat "$f" >> "$TMP_FILE"
      done
    fi
  done
fi

# Rename temp file to final output
mv "$TMP_FILE" "$OUT_FILE"
echo "✅ Dump completed: $OUT_FILE"
