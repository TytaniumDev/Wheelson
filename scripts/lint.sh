#!/usr/bin/env bash
set -euo pipefail

echo "=== Installing luacheck ==="
sudo apt-get update -qq && sudo apt-get install -y -qq luarocks >/dev/null
sudo luarocks install luacheck >/dev/null

echo "=== Running luacheck ==="
luacheck src/ tests/
