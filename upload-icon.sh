#!/bin/bash
set -euo pipefail

# Uploads assets/pulse_red.gif - an 8x8 animated pulsing red circle - to an
# AWTRIX NG clock's /ICONS folder, so the "live" notification has an icon to
# show. AWTRIX NG doesn't persist icons across a fresh flash or factory
# reset, so re-run this any time that happens.
#
# Usage: ./upload-icon.sh [AWTRIX_URL]
#   AWTRIX_URL defaults to http://awtrix-ng.local, or $AWTRIX_URL if set.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWTRIX_URL="${1:-${AWTRIX_URL:-http://awtrix-ng.local}}"
ICON="$SCRIPT_DIR/assets/pulse_red.gif"

echo "Uploading $ICON to $AWTRIX_URL/ICONS ..."
curl -sf -X POST "$AWTRIX_URL/api/v1/files?dir=/ICONS" \
  -F "file=@$ICON"
echo
echo "Done."
