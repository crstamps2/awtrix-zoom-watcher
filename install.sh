#!/bin/bash
set -euo pipefail

# Installs awtrix-zoom-watcher as a launchd user agent on macOS.
# - copies the watcher script to ~/.local/bin
# - renders the launchd plist with your home directory
# - loads the agent so it starts now and on every login

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_LABEL="com.awtrix.zoom-watcher"
PLIST_DEST="$LAUNCH_AGENTS_DIR/$PLIST_LABEL.plist"

echo "Installing awtrix-zoom-watcher..."

mkdir -p "$BIN_DIR" "$LAUNCH_AGENTS_DIR"

install -m 0755 "$SCRIPT_DIR/awtrix-zoom-watcher.sh" "$BIN_DIR/awtrix-zoom-watcher.sh"
echo "  copied watcher -> $BIN_DIR/awtrix-zoom-watcher.sh"

sed "s|HOMEDIR|$HOME|g" "$SCRIPT_DIR/com.awtrix.zoom-watcher.plist" > "$PLIST_DEST"
echo "  wrote launchd plist -> $PLIST_DEST"

# Reload if already loaded, then load.
launchctl unload "$PLIST_DEST" 2>/dev/null || true
launchctl load "$PLIST_DEST"
echo "  loaded launchd agent $PLIST_LABEL"

echo
echo "Done. Edit AWTRIX_URL in $BIN_DIR/awtrix-zoom-watcher.sh if your clock"
echo "is not reachable at http://awtrix.lan, then re-run: launchctl unload/load."
echo "Logs: $BIN_DIR/awtrix-zoom-watcher.log"
