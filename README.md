# awtrix-zoom-watcher

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/X3W822RWA9)

Turn your [AWTRIX NG](https://blueforcer.github.io/awtrix-ng/) pixel clock (like the
[Ulanzi TC001](https://www.ulanzi.com/products/ulanzi-pixel-smart-clock-2882)) into an
on-air light for Zoom.

When you join a Zoom **meeting** or **webinar**, the clock wakes up and shows
an on-air sign: a pulsing red circle next to solid red **LIVE** text. When you
leave, it clears itself and returns to whatever it was showing before. It's a
tiny "do not disturb / I'm on a call" sign for the people around you.

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

- **Meeting starts** -> push a `LIVE` notification, which interrupts whatever app
  is currently showing. It carries `wakeup:true`, so it renders even if the
  matrix is powered off — and, because that only suspends blanking while the
  notification is up, a display you left off goes back to off afterwards.
- **Still in a meeting** -> almost nothing to do. The notification is pushed with
  `hold:true`, so AWTRIX keeps it pinned on screen by itself until it's
  explicitly dismissed. The watcher only re-pushes it every `REASSERT_INTERVAL`
  seconds as a safety net, in case the clock rebooted mid-call and forgot it.
- **Meeting ends** (or the script exits) -> dismiss the notification, and
  AWTRIX falls back to its normal app rotation.

No Zoom API keys, no OAuth, no cloud service. It only reads local window titles
and talks to your clock on your LAN.

## Requirements

- **macOS** (uses `osascript` / AppleScript and `launchd`).
- An **AWTRIX NG** device reachable over HTTP on your network. The default URL is
  `http://awtrix-ng.local` — change it if your clock uses a different hostname or IP.
- The Zoom desktop client.

> Coming from AWTRIX 3? This version targets the [AWTRIX NG](https://blueforcer.github.io/awtrix-ng/)
> HTTP API (`/api/v1/...`) and will not work against an AWTRIX 3 device — see
> [AWTRIX NG's migration guide](https://blueforcer.github.io/awtrix-ng/guides/migrating-from-awtrix3/)
> if you're moving from one to the other. A fresh AWTRIX NG flash also wipes
> uploaded icons, so `install.sh` re-uploads the bundled `pulse_red` icon for
> you - see [Icon](#icon) below if you ever need to redo that by hand.

## Install

```bash
git clone https://github.com/crstamps2/awtrix-zoom-watcher.git
cd awtrix-zoom-watcher
./install.sh
```

`install.sh` copies the watcher to `~/.local/bin`, renders the `launchd` agent
with your home directory, and loads it so it runs now and on every login.

If your clock is not at `http://awtrix-ng.local`, edit `AWTRIX_URL` at the top of
`~/.local/bin/awtrix-zoom-watcher.sh`, then reload:

```bash
launchctl unload ~/Library/LaunchAgents/com.awtrix.zoom-watcher.plist
launchctl load   ~/Library/LaunchAgents/com.awtrix.zoom-watcher.plist
```

### Finding your clock's address

`awtrix-ng.local` is AWTRIX NG's default hostname over mDNS (note the `-ng` — it
differs from AWTRIX 3's, so this is worth re-checking if you just migrated).
Confirm it resolves and that you're talking to an NG device:

```bash
curl -s http://awtrix-ng.local/api/v1/device
# -> {"version":"1.1.0","boardType":"awtrixng","hostname":"awtrix-ng",...}
```

If that fails, find the IP in your router's client list or on the clock's own
settings screen and use e.g. `AWTRIX_URL="http://192.168.1.42"`. If you renamed
the device, use whatever hostname the `hostname` field above reports.

## Permissions

The first time it runs, macOS will ask to let the script control
`System Events` / `zoom.us` (Automation permission) so it can read window
titles. Approve it under **System Settings -> Privacy & Security -> Automation**.
Without this, the watcher can't tell when you're in a call.

## Configuration

All settings live at the top of `awtrix-zoom-watcher.sh`:

| Variable            | Default                    | Meaning                                                                 |
| ------------------- | -------------------------- | ----------------------------------------------------------------------- |
| `AWTRIX_URL`        | `http://awtrix-ng.local`   | Base URL of your AWTRIX NG clock.                                       |
| `APP_NAME`          | `live`                     | Notification name, used to dismiss it by name. `active` is reserved by the API — pick anything else. |
| `POLL_INTERVAL`     | `5`                        | Seconds between Zoom checks.                                            |
| `CURL_TIMEOUT`      | `10`                       | Per-request timeout, so an unreachable clock can't stall the loop.      |
| `REASSERT_INTERVAL` | `60`                       | Seconds between re-pushes during a call, so a clock that reboots mid-meeting gets `LIVE` back. `0` disables. |

Want a different look? Edit the `-d '{...}'` payload in `push_live`. The
`text`, `textColor`, and `icon` fields map directly to the AWTRIX NG
[notification API](https://blueforcer.github.io/awtrix-ng/reference/http/#post-apiv1notifications) —
the full set of fields it accepts (colors, effects, sound, etc.) is in the
[app & notification payload reference](https://blueforcer.github.io/awtrix-ng/reference/payload/).
`icon` is an AWTRIX icon ID that must already exist on the device — see
[Icon](#icon) below.

## Icon

The pulsing circle is `assets/pulse_red.gif`, an 8x8 animated icon bundled in
this repo (its own animation is what pulses - the notification's `text` stays
a solid color, not blinking, so it reads as an on-air sign rather than a
flashing alert). `install.sh` uploads it to your clock automatically. If your
clock was offline during install, was factory-reset, or you just want to
re-push it:

```bash
./upload-icon.sh                        # uses http://awtrix-ng.local
./upload-icon.sh http://192.168.1.42     # or a specific address
```

Want a different icon instead? Drop any GIF or JPEG into AWTRIX's `/ICONS`
folder (via the web UI or `POST /api/v1/files?dir=/ICONS`) and point `icon` in
`push_live` at its filename, minus the extension.

## Logs

Output goes to `~/.local/bin/awtrix-zoom-watcher.log`:

```bash
tail -f ~/.local/bin/awtrix-zoom-watcher.log
```

## Troubleshooting

### `LIVE` stays on the clock after the call ends

Notifications are pushed with `hold:true`, so the clock shows `LIVE` until
something dismisses it — meaning a dismissal that never arrives leaves the sign
up indefinitely. The watcher retries the dismissal three times and logs
`could not clear LIVE ...` if all three fail, so check the log first. Restarting
the agent also clears any stale sign, because it dismisses `LIVE` once on
startup:

```bash
launchctl kickstart -k gui/$(id -u)/com.awtrix.zoom-watcher
```

To clear it by hand:

```bash
curl -4 -X DELETE http://awtrix-ng.local/api/v1/notifications/live
```

### Requests to the hostname time out, but the IP works

Worth knowing if you write your own scripts against the clock: it publishes no
IPv6 address, and resolving a `.local` name for both address families — which
`curl` does by default — blocks on the IPv6 half for about five seconds before
giving up, every time the mDNS cache goes cold. Confusingly `ping` looks fine,
because it only ever asks for IPv4.

```bash
curl    -s -m4 http://awtrix-ng.local/api/v1/device   # times out
curl -4 -s -m4 http://awtrix-ng.local/api/v1/device   # ~2ms
```

Passing `-4` avoids it, which is why every request in these scripts does. A
short `--max-time` without `-4` is the bad combination: it expires during the
stalled lookup, so the request never even goes out.

## Uninstall

```bash
./uninstall.sh
```

Removes the `launchd` agent, the installed script, and the log.

## Notes & tips

- The poll interval is 5 seconds (`sleep 5`). Lower it for a snappier response,
  raise it to be gentler.
- Detection is by window title, so it triggers for both meetings and webinars but
  not for the Zoom app merely being open.
- Not just for "LIVE" — it's a generic Zoom-presence -> AWTRIX hook. Repurpose the
  payload for a mute indicator, a countdown, whatever your clock can render.

## Support

If this saved you from an awkward interruption, you can buy me a beer:

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/X3W822RWA9)

## License

MIT — see [LICENSE](LICENSE).
