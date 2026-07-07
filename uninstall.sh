#!/bin/bash
set -euo pipefail

# Removes the awtrix-zoom-watcher launchd agent and installed files.

BIN_DIR="$HOME/.local/bin"
PLIST_LABEL="com.awtrix.zoom-watcher"
PLIST_DEST="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"

echo "Uninstalling awtrix-zoom-watcher..."

if [ -f "$PLIST_DEST" ]; then
  launchctl unload "$PLIST_DEST" 2>/dev/null || true
  rm -f "$PLIST_DEST"
  echo "  removed launchd agent and $PLIST_DEST"
fi

rm -f "$BIN_DIR/awtrix-zoom-watcher.sh"
rm -f "$BIN_DIR/awtrix-zoom-watcher.log"
echo "  removed script and log from $BIN_DIR"

echo "Done."
