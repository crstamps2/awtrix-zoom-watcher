#!/bin/bash

# awtrix-zoom-watcher
# Shows a red pulsing "LIVE" notification on an AWTRIX NG clock (e.g. Ulanzi TC001)
# whenever you are in a Zoom meeting or webinar, then clears it when you leave.
#
# Configure the variables below, then run via launchd (see README).

AWTRIX_URL="http://awtrix-ng.local"  # Base URL of your AWTRIX NG clock (hostname or IP)

# Every curl below passes -4. The clock publishes no AAAA record, so resolving
# a .local name for both address families - which curl does by default - blocks
# on the IPv6 half for ~5s before giving up, on every single request once the
# mDNS cache goes cold. -4 skips that entirely and takes DNS from ~5s to ~2ms.
# Set AWTRIX_URL to a literal IP if your network somehow needs IPv6.
APP_NAME="live"          # Notification name on the clock (for targeted dismissal)
POLL_INTERVAL=5          # Seconds between Zoom checks
CURL_TIMEOUT=10          # Per-request timeout, so an unreachable clock can't stall the loop
REASSERT_INTERVAL=60     # Seconds between re-pushes while still in a meeting (0 disables)

was_in_meeting=false
last_assert=0
applescript_failing=false

push_live() {
  # POST /api/v1/notifications interrupts the rotation immediately.
  # hold pins it on screen until we DELETE it, so there is no need to re-send
  # it every poll the way the AWTRIX 3 version had to. wakeup renders it even
  # if the matrix is powered off, and stack:false replaces whatever
  # notification is showing instead of queueing behind it.
  # The pulsing comes from the icon's own GIF animation (see README/icons),
  # not from blinking the text - an on-air sign, not a flashing one.
  if ! curl -4 -sf -m "$CURL_TIMEOUT" -o /dev/null -X POST "$AWTRIX_URL/api/v1/notifications" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$APP_NAME\",\"text\":\"LIVE\",\"textColor\":\"#FF0000\",\"icon\":\"pulse_red\",\"scroll\":\"static\",\"hold\":true,\"wakeup\":true,\"stack\":false}"; then
    echo "$(date): could not push LIVE to $AWTRIX_URL (clock unreachable, or the icon is missing - see upload-icon.sh)"
    return 1
  fi
}

clear_live() {
  # This is the one call that must not fail quietly. hold:true means the clock
  # keeps LIVE up until something dismisses it, so a dropped DELETE here leaves
  # a permanent on-air sign - the failure that is least acceptable and hardest
  # for anyone to diagnose from the clock itself. So: retry, then complain.
  local attempt code
  for attempt in 1 2 3; do
    code=$(curl -4 -s -m "$CURL_TIMEOUT" -o /dev/null -w '%{http_code}' \
      -X DELETE "$AWTRIX_URL/api/v1/notifications/$APP_NAME")
    # 200 = dismissed. 404 = nothing was held (the clock rebooted, say), which
    # is the state we wanted anyway. Anything else, including curl failing
    # outright and reporting 000, is worth another try.
    case "$code" in
      200|404) return 0 ;;
    esac
    sleep 1
  done
  echo "$(date): could not clear LIVE from $AWTRIX_URL after 3 tries (last HTTP status ${code:-none}) - the clock may still be showing it"
  return 1
}

# Sets $zoom_status to "in_meeting" or "not_in_meeting".
#
# This assigns a global rather than echoing a result, because the caller would
# otherwise have to run it as $(check_zoom_meeting) - a subshell, which would
# both swallow the diagnostics below into the captured value and lose the
# applescript_failing flag that keeps them from repeating every poll.
check_zoom_meeting() {
  # A failure here is almost always the macOS Automation permission being
  # missing or revoked. That looks identical to "not in a meeting", so say so
  # out loud - once per outage - instead of going quietly dead for the rest of
  # the login session.
  local out
  if ! out=$(osascript -e '
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
  ' 2>&1); then
    if ! $applescript_failing; then
      applescript_failing=true
      echo "$(date): cannot read Zoom's window titles, so meetings will not be detected: $out"
      echo "$(date): approve this under System Settings > Privacy & Security > Automation, then restart the agent:"
      echo "$(date):   launchctl kickstart -k gui/$(id -u)/com.awtrix.zoom-watcher"
    fi
    zoom_status="not_in_meeting"
    return
  fi

  if $applescript_failing; then
    applescript_failing=false
    echo "$(date): reading Zoom's window titles again"
  fi
  zoom_status="$out"
}

trap clear_live EXIT

# A previous run may have exited without dismissing LIVE - killed with SIGKILL,
# lost power, or simply unable to reach the clock at the time. Because hold:true
# never expires, that sign would otherwise stay up until the next meeting ends.
# Clearing once at startup means a restart of this agent is always enough to
# recover, which is what KeepAlive and login relaunch give us for free.
clear_live

while true; do
  check_zoom_meeting

  if [ "$zoom_status" = "in_meeting" ]; then
    in_meeting=true
  else
    in_meeting=false
  fi

  if $in_meeting && ! $was_in_meeting; then
    echo "$(date): Meeting started"
    push_live
    last_assert=$SECONDS
  elif $in_meeting && $was_in_meeting; then
    # hold:true means the clock keeps LIVE up on its own, so this is only a
    # safety net: if the clock rebooted or dropped off the network mid-call it
    # has forgotten the notification, and nothing else would ever put it back.
    if [ "$REASSERT_INTERVAL" -gt 0 ] && [ $((SECONDS - last_assert)) -ge "$REASSERT_INTERVAL" ]; then
      push_live
      last_assert=$SECONDS
    fi
  elif ! $in_meeting && $was_in_meeting; then
    echo "$(date): Meeting ended"
    clear_live
  fi

  was_in_meeting=$in_meeting
  sleep "$POLL_INTERVAL"
done
