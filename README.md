# YT Music by Gerygerger

The song that's playing, right on the bar.

Click to pause. Scroll to skip. When YouTube Music is quiet, the chip is gone — it does not sit there saying nothing. Ads show up as Advertisement, not as whatever junk metadata the player emits.

Plugin id: `gerygerger.ytmusic`

A YouTube Music take on [SwadowMaster's omarchy-spotify](https://github.com/SwadowMaster/omarchy-spotify).

## How it works

Omarchy Quattro has no Waybar and no `playerctl` requirement. The widget has two backends and gives
the chip to whichever one actually has a track:

- **MPRIS** — the D-Bus interface the desktop already uses for media keys, exposed by Quickshell as
  `Quickshell.Services.Mpris`. This is what Spotify, `th-ch/youtube-music` and YTMDesktop 1.x use. On
  each update it looks at every player and keeps the first whose identity, desktop entry, or D-Bus
  name contains a YouTube Music marker (`youtube music`, `youtube-music`, `youtubemusic`, `ytmusic`,
  `ytmdesktop`, or `youtube`). Other players (VLC, Omarchy's own media module) are ignored.
- **YTMDesktop 2.x** — that release dropped MPRIS entirely, so the widget also talks to the app's
  Companion Server over local HTTP. See below.

If the active player has a title or artist, the bar shows a YouTube mark followed by the label:

```
[YouTube mark]  Artist - Title
```

Only 20 characters of the label are visible at a time; anything longer scrolls through the window
using the same marquee as Omarchy's own media widget. Add `maxChars` to this widget's `shell.json`
entry to change the width.

When nothing is playing, the widget sets its width to zero and disappears, then comes back by itself
when playback starts.


Controls (only while a track is visible):

| Input | Action |
|---|---|
| Left click | Play / pause |
| Scroll up or middle click | Previous track |
| Scroll down or right click | Next track |
| Hover | Playing/paused plus the same title |

## Requirements

- Omarchy 4 (Quattro)
- A YouTube Music desktop client that exposes MPRIS:
  - [th-ch/youtube-music](https://github.com/th-ch/youtube-music) — MPRIS is built in.
  - [YTMDesktop](https://ytmdesktop.com/) **1.8.x and earlier** — MPRIS is built in, no plugin to
    enable. It registers as `org.mpris.MediaPlayer2.ytmdesktop2`.
  - [ytmdesktop-mpris](https://github.com/kiselvserg/ytmdesktop-mpris) — external bridge.

Note: playback through a **browser** is not matched. Chromium/Firefox report their own identity (`Chromium`, `Mozilla Firefox`) and no track URL, so YouTube Music cannot be told apart from any other tab. A dedicated client is required.

## YTMDesktop 2.x: the Companion Server

2.x has no MPRIS at all, so it is driven over its **Companion Server** (`http://0.0.0.0:9863/api/v1/`,
endpoints `state`, `metadata`, `playlists`, `command`). It ships disabled, and it refuses to start
without `safeStorage` — on a minimal Hyprland setup Electron cannot auto-detect a keyring, so it needs
to be told which password store to use:

```bash
youtube-music-desktop-app --password-store=gnome-libsecret
```

Without that flag the app logs `Refusing to enable Companion Server Integration with reason:
safeStorage unavailable` and never opens the port. Put the flag in a user-level desktop entry so it
applies to every launch from the menu.

Then, once:

1. Settings → Integrations → enable **Companion server**.
2. Switch on **Enable companion authorization**. It turns itself off after one successful
   authorization or 5 minutes, so do this immediately before step 3.
3. Ask for a code, approve the window that opens in the app, and keep the token:

```bash
API=http://127.0.0.1:9863/api/v1
CODE=$(curl -fsS -X POST $API/auth/requestcode -H 'Content-Type: application/json' \
  -d '{"appId":"gerygerger_ytmusic","appName":"YT Music by Gerygerger","appVersion":"1.0.0"}' \
  | sed -n 's/.*"code":"\([0-9]\{4\}\)".*/\1/p')
curl -fsS -X POST $API/auth/request -H 'Content-Type: application/json' \
  -d "{\"appId\":\"gerygerger_ytmusic\",\"code\":\"$CODE\"}" \
  | sed -n 's/.*"token":"\([0-9a-f]*\)".*/\1/p' \
  > ~/.config/omarchy/plugins/gerygerger.ytmusic/ytmdesktop-token
chmod 600 ~/.config/omarchy/plugins/gerygerger.ytmusic/ytmdesktop-token
```

The token goes in the `Authorization` header bare, with no `Bearer` prefix — the server hashes the
header value and compares. The widget reads that file once at startup, so deleting it simply turns the
2.x backend off. `/state` allows one request per 5 seconds, so the widget polls every 6.

Two things to be aware of: the server binds `0.0.0.0`, not loopback, though every `state`, `command`
and `playlists` call still needs the token; and its `command` endpoint is fire-and-forget, so the chip
flips its icon optimistically and re-syncs from the next poll rather than waiting for an ack.

## Install

```bash
omarchy plugin enable gerygerger.ytmusic
omarchy bar move gerygerger.ytmusic --section center
```

## Remove

```bash
omarchy plugin disable gerygerger.ytmusic
```

## License

MIT. See [LICENSE](LICENSE).
