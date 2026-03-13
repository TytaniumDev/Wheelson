#!/usr/bin/env bash
set -euo pipefail

echo "=== Validating .toc file exists ==="
if [ ! -f MythicPlusWheel.toc ]; then
  echo "ERROR: MythicPlusWheel.toc not found" >&2
  exit 1
fi

echo "=== Checking all .toc source files exist ==="
grep -E '^[^#].*\\.(lua|xml)$' MythicPlusWheel.toc | tr '\\' '/' | while IFS= read -r file; do
  if [ ! -f "$file" ]; then
    echo "ERROR: $file listed in .toc but not found on disk" >&2
    exit 1
  fi
done

echo "Build validation passed."
