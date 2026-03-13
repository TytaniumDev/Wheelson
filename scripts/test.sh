#!/usr/bin/env bash
set -euo pipefail

echo "=== Installing busted ==="
sudo apt-get update -qq && sudo apt-get install -y -qq luarocks >/dev/null
sudo luarocks install busted >/dev/null

echo "=== Running busted tests ==="
busted
