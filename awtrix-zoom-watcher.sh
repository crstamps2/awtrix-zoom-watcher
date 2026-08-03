#!/bin/bash

# awtrix-zoom-watcher
# Shows a red "LIVE" indicator on an AWTRIX 3 clock (e.g. Ulanzi TC001)
# whenever you are in a Zoom meeting or webinar, then clears it when you leave.
#
# Configure the variables below, then run via launchd (see README).

AWTRIX_URL="http://awtrix.lan"   # Base URL of your AWTRIX 3 clock (hostname or IP)
APP_NAME="live"                  # Custom app slot name used on the clock
POLL_INTERVAL=5                  # Seconds between Zoom checks
CURL_TIMEOUT=4                   # Per-request timeout, so a dead clock can't stall the loop

LIVE_PAYLOAD='{"text":"LIVE","color":"#FF0000","icon":"pulse_red","pushIcon":0,"noScroll":true,"lifetime":0}'

was_in_meeting=false

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

# POST to the clock. Returns non-zero on a transport error or any non-200 reply,
# so callers can actually notice when the clock rejects a request.
awtrix_post() {
  # Note: do not name this "path" -- under zsh that is tied to $PATH.
  local endpoint="$1" body="$2" response code
  response=$(curl -sS -m "$CURL_TIMEOUT" -w '\n%{http_code}' \
    -X POST "$AWTRIX_URL$endpoint" \
    -H "Content-Type: application/json" \
    -d "$body") || return 1
  code="${response##*$'\n'}"
  [ "$code" = "200" ]
}

awtrix_get() {
  curl -sS -m "$CURL_TIMEOUT" "$AWTRIX_URL$1"
}

wake_clock() {
  awtrix_post "/api/power" '{"power":true}'
}

# True when the clock currently has our custom app in its app loop. /api/switch
# only succeeds for names that appear here.
app_registered() {
  awtrix_get "/api/loop" | grep -q "\"$APP_NAME\":"
}

# Name of the app the clock is showing right now.
current_app() {
  awtrix_get "/api/stats" | sed -n 's/.*"app":"\([^"]*\)".*/\1/p'
}

delete_slot() {
  # An empty body makes the firmware drop the app from BOTH its app loop and its
  # internal custom-app map. This is load-bearing: the firmware only registers a
  # custom app in the loop when the name is absent from that map, so re-pushing a
  # name it still remembers is silently ignored and every /api/switch after it
  # fails with 500 FAILED until the clock reboots. Always delete before pushing.
  awtrix_post "/api/custom?name=$APP_NAME" '{}'
}

push_slot() {
  awtrix_post "/api/custom?name=$APP_NAME" "$LIVE_PAYLOAD"
}

switch_slot() {
  awtrix_post "/api/switch" "{\"name\":\"$APP_NAME\"}"
}

# (Re)build the LIVE app from scratch and bring it to the front.
show_live() {
  wake_clock || log "WARN: power on failed"

  local attempt
  for attempt in 1 2 3; do
    delete_slot || log "WARN: clearing slot '$APP_NAME' failed (attempt $attempt)"
    sleep 0.5
    push_slot || log "WARN: pushing slot '$APP_NAME' failed (attempt $attempt)"
    sleep 0.5

    if ! app_registered; then
      log "WARN: '$APP_NAME' not in app loop after push (attempt $attempt)"
      sleep 1
      continue
    fi

    if switch_slot; then
      return 0
    fi
    log "WARN: switch to '$APP_NAME' failed (attempt $attempt)"
    sleep 1
  done

  log "ERROR: gave up showing LIVE after 3 attempts"
  return 1
}

# Called every poll while in a meeting. Only writes to the clock when something
# is actually wrong, instead of re-POSTing a switch every few seconds.
hold_live() {
  if ! app_registered; then
    log "'$APP_NAME' vanished from the app loop -- rebuilding"
    show_live
  elif [ "$(current_app)" != "$APP_NAME" ]; then
    switch_slot || log "WARN: re-switch to '$APP_NAME' failed"
  fi
}

clear_live() {
  delete_slot || log "WARN: clearing slot '$APP_NAME' failed"
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

trap 'clear_live' EXIT
trap 'clear_live; exit 0' INT TERM

while true; do
  zoom_status=$(check_zoom_meeting)

  if [ "$zoom_status" = "in_meeting" ]; then
    in_meeting=true
  else
    in_meeting=false
  fi

  if $in_meeting && ! $was_in_meeting; then
    log "Meeting started"
    show_live
  elif $in_meeting && $was_in_meeting; then
    hold_live
  elif ! $in_meeting && $was_in_meeting; then
    log "Meeting ended"
    clear_live
  fi

  was_in_meeting=$in_meeting
  sleep "$POLL_INTERVAL"
done
