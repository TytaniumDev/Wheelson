#!/usr/bin/env bash
set -euo pipefail

# Check if busted is already in PATH
if ! command -v busted &> /dev/null; then
  echo "=== Installing busted ==="
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    sudo apt-get update -qq && sudo apt-get install -y -qq luarocks >/dev/null
    sudo luarocks install busted >/dev/null
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    if ! command -v luarocks &> /dev/null; then
      echo "=== Installing luarocks via brew ==="
      brew install luarocks
    fi
    echo "=== Installing busted via luarocks ==="
    luarocks install --user busted
  else
    echo "ERROR: Unsupported OS for automatic installation. Please install 'busted' manually." >&2
    exit 1
  fi
fi

echo "=== Running busted tests ==="
busted
