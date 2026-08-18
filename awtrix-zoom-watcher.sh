#!/bin/bash

# awtrix-zoom-watcher
# Shows a red pulsing "LIVE" notification on an AWTRIX NG clock (e.g. Ulanzi TC001)
# whenever you are in a Zoom meeting or webinar, then clears it when you leave.
#
# Configure the two variables below, then run via launchd (see README).

AWTRIX_URL="http://awtrix.lan"   # Base URL of your AWTRIX NG clock (hostname or IP)
APP_NAME="live"                  # Notification name used on the clock (for targeted dismissal)

was_in_meeting=false

push_live() {
  # POST /api/v1/notifications interrupts the rotation immediately.
  # hold keeps it on screen until we DELETE it (no need to re-send while the
  # meeting continues), wakeup turns the display on if it was off, and
  # stack:false replaces anything currently showing instead of queueing.
  # The pulsing comes from the icon's own GIF animation (see README/icons),
  # not from blinking the text - an on-air sign, not a flashing one.
  curl -s -X POST "$AWTRIX_URL/api/v1/notifications" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$APP_NAME\",\"text\":\"LIVE\",\"textColor\":\"#FF0000\",\"icon\":\"pulse_red\",\"scroll\":\"static\",\"hold\":true,\"wakeup\":true,\"stack\":false}"
}

clear_live() {
  curl -s -X DELETE "$AWTRIX_URL/api/v1/notifications/$APP_NAME"
}

check_zoom_meeting() {
  osascript -e '
    tell application "System Events"
      if (name of every process) contains "zoom.us" then
        tell process "zoom.us"
          set windowNames to name of every window
          repeat with w in windowNames
            if w contains "Zoom Meeting" or w contains "Zoom Webinar" then
              return "in_meeting"
            end if
          end repeat
        end tell
      end if
    end tell
    return "not_in_meeting"
  ' 2>/dev/null
}

trap clear_live EXIT

while true; do
  zoom_status=$(check_zoom_meeting)

  if [ "$zoom_status" = "in_meeting" ]; then
    in_meeting=true
  else
    in_meeting=false
  fi

  if $in_meeting && ! $was_in_meeting; then
    echo "$(date): Meeting started"
    push_live
  elif ! $in_meeting && $was_in_meeting; then
    echo "$(date): Meeting ended"
    clear_live
  fi

  was_in_meeting=$in_meeting
  sleep 5
done
