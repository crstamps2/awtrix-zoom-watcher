# awtrix-zoom-watcher

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/X3W822RWA9)

Turn your [AWTRIX 3](https://blueforcer.github.io/awtrix3/) pixel clock (like the
[Ulanzi TC001](https://www.ulanzi.com/products/ulanzi-pixel-smart-clock-2882)) into an
on-air light for Zoom.

When you join a Zoom **meeting** or **webinar**, the clock wakes up and shows a
red pulsing **LIVE** indicator. When you leave, it clears itself and returns to
whatever it was showing before. It's a tiny "do not disturb / I'm on a call"
sign for the people around you.

```
+-----------------+
|  🔴  L I V E     |   <- shown while you're in a Zoom call
+-----------------+
```

## How it works

A small bash loop polls Zoom every few seconds using AppleScript. It looks for a
window titled `Zoom Meeting` or `Zoom Webinar` in the `zoom.us` process, which is
only present during an active call. On a state change it hits the AWTRIX HTTP
API:

- **Meeting starts** -> power the display on, rebuild the custom `LIVE` app, switch
  to it, and confirm it actually landed (retrying if not).
- **Still in a meeting** -> check the clock is still showing `LIVE`, and only
  intervene if it isn't.
- **Meeting ends** (or the script exits) -> clear the custom app.

No Zoom API keys, no OAuth, no cloud service. It only reads local window titles
and talks to your clock on your LAN.

## Requirements

- **macOS** (uses `osascript` / AppleScript and `launchd`).
- An **AWTRIX 3** device reachable over HTTP on your network. The default URL is
  `http://awtrix.lan` — change it if your clock uses a different hostname or IP.
- The Zoom desktop client.

## Install

```bash
git clone https://github.com/crstamps2/awtrix-zoom-watcher.git
cd awtrix-zoom-watcher
./install.sh
```

`install.sh` copies the watcher to `~/.local/bin`, renders the `launchd` agent
with your home directory, and loads it so it runs now and on every login.

If your clock is not at `http://awtrix.lan`, edit `AWTRIX_URL` at the top of
`~/.local/bin/awtrix-zoom-watcher.sh`, then reload:

```bash
launchctl unload ~/Library/LaunchAgents/com.awtrix.zoom-watcher.plist
launchctl load   ~/Library/LaunchAgents/com.awtrix.zoom-watcher.plist
```

### Finding your clock's address

`awtrix.lan` works if your router resolves the device's mDNS/hostname. Otherwise
find its IP in your router's client list or on the clock's own settings screen,
and use e.g. `AWTRIX_URL="http://192.168.1.42"`.

## Permissions

The first time it runs, macOS will ask to let the script control
`System Events` / `zoom.us` (Automation permission) so it can read window
titles. Approve it under **System Settings -> Privacy & Security -> Automation**.
Without this, the watcher can't tell when you're in a call.

## Configuration

Both settings live at the top of `awtrix-zoom-watcher.sh`:

| Variable     | Default              | Meaning                                        |
| ------------ | -------------------- | ---------------------------------------------- |
| `AWTRIX_URL` | `http://awtrix.lan`  | Base URL of your AWTRIX 3 clock.               |
| `APP_NAME`   | `live`               | Custom app slot name used for the indicator.   |
| `POLL_INTERVAL` | `5`               | Seconds between Zoom checks.                   |
| `CURL_TIMEOUT`  | `4`               | Per-request timeout, so an unreachable clock can't stall the loop. |

Want a different look? Edit the `LIVE_PAYLOAD` variable. The
`text`, `color`, and `icon` fields map directly to the AWTRIX
[custom app API](https://blueforcer.github.io/awtrix3/#/api?id=custom-apps-and-notifications).
`icon` is an AWTRIX icon ID that must already exist on the device (the default
`pulse_red` is a common one — swap it for any icon you have installed, or drop
the field).

## Logs

Output goes to `~/.local/bin/awtrix-zoom-watcher.log`:

```bash
tail -f ~/.local/bin/awtrix-zoom-watcher.log
```

## Troubleshooting

### The clock never switches to LIVE, and the log is full of `FAILED`

`FAILED` comes from exactly one place in the AWTRIX firmware: `POST /api/switch`,
when the app name isn't in the clock's app loop. The giveaway is that the custom
app push right before it returns `OK` — the clock accepts the app but never adds
it to the loop, so every switch after that fails until the clock reboots.

The cause is a firmware quirk. AWTRIX only registers a custom app in the loop if
it doesn't already remember the name, but it keeps remembering the name in a
separate internal map. Anything that drops the app from the loop while leaving
that map intact — hiding the app from the web UI or the apps API, for instance —
wedges the slot permanently. Re-pushing the app **cannot** fix it, because the
push is silently ignored.

Sending an empty body (`{}`) clears both, so the watcher now deletes the slot
before every push and rebuilds it if it goes missing mid-call. If you hit this on
an older version, the manual recovery is:

```bash
curl -X POST "http://awtrix.lan/api/custom?name=live" -H "Content-Type: application/json" -d '{}'
```

### Checking what the clock thinks is going on

```bash
curl -s http://awtrix.lan/api/loop    # apps in the rotation -- "live" must appear here
curl -s http://awtrix.lan/api/stats   # includes "app" (what's on screen) and "uptime"
```

### Nothing reaches the clock at all

`curl` errors are no longer swallowed, so the log will show them. Check that
`AWTRIX_URL` resolves (`ping awtrix.lan`) and fall back to the raw IP if your
router doesn't do mDNS.

## Uninstall

```bash
./uninstall.sh
```

Removes the `launchd` agent, the installed script, and the log.

## Notes & tips

- The poll interval is 5 seconds (`POLL_INTERVAL`). Lower it for a snappier
  response, raise it to be gentler.
- While you're in a call the watcher only writes to the clock when something is
  actually wrong (the app went missing, or something else took over the screen).
  It doesn't re-POST a switch on every tick.
- Detection is by window title, so it triggers for both meetings and webinars but
  not for the Zoom app merely being open.
- Not just for "LIVE" — it's a generic Zoom-presence -> AWTRIX hook. Repurpose the
  payload for a mute indicator, a countdown, whatever your clock can render.

## Support

If this saved you from an awkward interruption, you can buy me a beer:

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/X3W822RWA9)

## License

MIT — see [LICENSE](LICENSE).
