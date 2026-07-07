#!/bin/bash

# awtrix-zoom-watcher
# Shows a red "LIVE" indicator on an AWTRIX 3 clock (e.g. Ulanzi TC001)
# whenever you are in a Zoom meeting or webinar, then clears it when you leave.
#
# Configure the two variables below, then run via launchd (see README).

AWTRIX_URL="http://awtrix.lan"   # Base URL of your AWTRIX 3 clock (hostname or IP)
APP_NAME="live"                  # Custom app slot name used on the clock

was_in_meeting=false

wake_clock() {
  curl -s -X POST "$AWTRIX_URL/api/power" \
    -H "Content-Type: application/json" \
    -d '{"power":true}'
}

push_live() {
  wake_clock
  sleep 1

  curl -s -X POST "$AWTRIX_URL/api/custom?name=$APP_NAME" \
    -H "Content-Type: application/json" \
    -d '{"text":"LIVE","color":"#FF0000","icon":"pulse_red","pushIcon":0,"noScroll":true,"lifetime":0}'

  curl -s -X POST "$AWTRIX_URL/api/switch" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$APP_NAME\"}"
}

hold_live() {
  curl -s -X POST "$AWTRIX_URL/api/switch" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$APP_NAME\"}"
}

clear_live() {
  curl -s -X POST "$AWTRIX_URL/api/custom?name=$APP_NAME" \
    -H "Content-Type: application/json" \
    -d '{}'
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
  elif $in_meeting && $was_in_meeting; then
    hold_live
  elif ! $in_meeting && $was_in_meeting; then
    echo "$(date): Meeting ended"
    clear_live
  fi

  was_in_meeting=$in_meeting
  sleep 5
done
