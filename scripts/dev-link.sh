#!/usr/bin/env bash
set -euo pipefail

# Symlinks this repo into WoW's AddOns folder for live development.
# After linking, edit files and /reload in-game to pick up changes.
# Undo with: scripts/dev-unlink.sh

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WOW_ADDONS="${WOW_ADDONS_PATH:-/Applications/World of Warcraft/_retail_/Interface/AddOns}"
ADDON_DIR="$WOW_ADDONS/Wheelson"
BACKUP_DIR="$WOW_ADDONS/Wheelson.wago-backup"

# --- Preflight checks ---

if [ ! -d "$WOW_ADDONS" ]; then
  echo "ERROR: WoW AddOns directory not found at: $WOW_ADDONS" >&2
  echo "Set WOW_ADDONS_PATH to override." >&2
  exit 1
fi

if [ -L "$ADDON_DIR" ]; then
  echo "Already linked: $ADDON_DIR -> $(readlink "$ADDON_DIR")"
  exit 0
fi

if [ ! -d "$ADDON_DIR" ]; then
  echo "ERROR: No existing Wheelson addon found at: $ADDON_DIR" >&2
  echo "Install Wheelson via Wago first so we can copy its libs." >&2
  exit 1
fi

# --- Copy libs from Wago install into repo ---

echo "Copying libs from Wago install into repo..."
if [ -d "$ADDON_DIR/libs" ]; then
  rsync -a --delete "$ADDON_DIR/libs/" "$REPO_ROOT/libs/"
  echo "  Copied $(ls "$REPO_ROOT/libs/" | wc -l | tr -d ' ') libraries."
else
  echo "WARNING: No libs/ in Wago install — addon may fail to load." >&2
fi

# --- Back up Wago install and create symlink ---

echo "Backing up Wago install to Wheelson.wago-backup..."
if [ -d "$BACKUP_DIR" ]; then
  echo "  Backup already exists, removing stale Wago dir."
  rm -rf "$ADDON_DIR"
else
  mv "$ADDON_DIR" "$BACKUP_DIR"
fi

echo "Creating symlink: $ADDON_DIR -> $REPO_ROOT"
ln -s "$REPO_ROOT" "$ADDON_DIR"

echo ""
echo "Done! Dev mode is active."
echo "  Edit files in: $REPO_ROOT"
echo "  Reload in WoW: /reload"
echo "  To restore Wago version: scripts/dev-unlink.sh"
