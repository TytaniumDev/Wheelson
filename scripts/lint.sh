#!/usr/bin/env bash
set -euo pipefail

# Check if luacheck is already in PATH
if ! command -v luacheck &> /dev/null; then
  echo "=== Installing luacheck ==="
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    sudo apt-get update -qq && sudo apt-get install -y -qq luarocks >/dev/null
    sudo luarocks install luacheck >/dev/null
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    if ! command -v luarocks &> /dev/null; then
      echo "=== Installing luarocks via brew ==="
      brew install luarocks
    fi
    echo "=== Installing luacheck via luarocks ==="
    luarocks install luacheck
  else
    echo "ERROR: Unsupported OS for automatic installation. Please install 'luacheck' manually." >&2
    exit 1
  fi
fi

echo "=== Running luacheck ==="
luacheck src/ tests/
