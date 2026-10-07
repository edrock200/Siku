# Siku

**Siku is a Roku client for [Silo](https://github.com/Silo-Server/silo-server), the self-hosted media server.**

Siku brings your Silo library to Roku TVs and streaming players. It is a port of the official [Silo Android TV client](https://github.com/Silo-Server/silo-android) to Roku SceneGraph and BrightScript, and aims to look, feel and behave like it on a 10-foot, remote-driven screen.

> **Status:** alpha. Siku installs and runs on a real Roku against a real Silo server: sign-in, Home, browsing, detail pages, Settings, video playback, resume, progress sync, Up Next, Skip Intro and automatic subtitles work on device. Subtitle tools, audiobooks and music have been exercised only in a simulator so far. The checklist below tracks progress.
>
> **Want to try it?** Jump to [Install on your Roku](#install-on-your-roku-side-load).
>
> Siku is an independent community project. It is not made or endorsed by Silo Media L.L.C. "Silo" is a trademark of Silo Media L.L.C. and is used here only to say what Siku connects to.

---

## Planned features (v1)

| Area | Feature | Status |
|---|---|:---:|
| Connect | Enter a server address, verify it, remember several servers | ✅ |
| Sign in | Username and password | ✅ |
| Sign in | Sign in with a code or QR from your phone (device sign-in) | ✅ |
| Profiles | Profile picker, PIN-protected profiles, switch profile | ✅ |
| Navigation | Top bar like Android TV: Home, media tabs (Movies, Shows, Music, Audiobooks), For You, Calendar, Search, Profile | ✅ |
| Home | Hero banner plus server-defined rows: Continue Watching, Next Up, Recently Added | ✅ |
| Browse | Library grids with sort and filters, collections, A‑Z rail; audiobook Authors / Series groups; music Genres | ✅ |
| Detail | Movies, series (seasons and episodes), episodes, cast, person pages | ✅ |
| Discover | Search, For You (Watchlist and Favorites), release Calendar | ✅ |
| Playback | Direct Play or Transcode chosen by the server from the Roku's real capabilities (4K, Dolby Vision, HDR10/HDR10+/HLG, surround passthrough) | ✅ (Silo's lighter remux route awaits a server-side packaging change, [details](docs/upstream/silo-server-roku-hls-audio.md)) |
| Playback | Resume, progress sync, mark watched, Skip Intro, Up Next, audio and version selection, automatic subtitles from your Off / Auto / Always setting | ✅ |
| Settings | Android TV's General, Playback, Subtitles and Server pages (quality and bandwidth, Dolby Vision, skip intro/credits, auto-play, home sections, cards), synced with your Silo profile | ✅ |
| Audio | Audiobooks (chapters, parts, resume, sleep timer) and music albums/artists with a now-playing screen | 🟡 needs device testing; music waits on server support |
| Requests | Request movies and series, track their status, approve or decline as a moderator (when the server enables it) | ✅ |
| Subtitles | Display and selection of SRT/WebVTT tracks, automatic choice from the profile's preference | ✅ |
| Subtitles | Search and download from providers, AI translate/transcribe, sync to audio, subtitle delay (server-gated) | 🟡 needs device testing |
| Notifications | Inbox from the profile menu, mark read, mark all read | ✅ |

Not planned for v1: Watch Party (experimental and off in Android TV release builds), ebooks (also absent from Android TV), and downloads or any offline/local-storage features (Android TV is streaming-only too).

## Install on your Roku (side-load)

**Requirements:** a Silo server that provides the v2 API (`/api/v2/system/info` reports `api_major: 2`). Siku checks this when you connect and says so if the server is too old.

Siku is not in the Roku Channel Store yet. Any Roku can run it as a *developer channel*
("side-loading"). It takes about five minutes and needs a computer, phone or tablet on the same
network as the Roku.

### 1. Turn on developer mode (once per Roku)

1. On the Roku remote press, in order: **Home Home Home, Up Up, Right, Left, Right, Left, Right**.
2. The *Developer Settings* screen opens. Write down the **IP address** it shows
   (for example `192.168.1.50`).
3. Choose **Enable installer and restart**, accept the developer agreement, and set a
   **web server password**. Remember it; you need it every time you install or update.
4. The Roku restarts.

### 2. Download Siku

Open the [latest release](https://github.com/edrock200/Siku/releases/latest) and download the
file named `siku-vX.Y.Z.zip` under **Assets**. Do not unzip it.

### 3. Install it

1. In a browser on the same network, go to `http://<roku-ip>` (the address from step 1, for
   example `http://192.168.1.50`).
2. Sign in with user name **`rokudev`** and the password you set.
3. Click **Upload**, pick the `siku-vX.Y.Z.zip` file, then click **Install** (or
   **Replace** if an older Siku is already installed).
4. Siku launches on the TV. Enter your Silo server's address and sign in.

Siku then appears on the Roku home screen like any other channel.

### Updating

Download the newer zip from [Releases](https://github.com/edrock200/Siku/releases) and repeat
step 3. Your server, sign-in and settings are kept. Each release lists what changed in plain
language.

### Removing

Open `http://<roku-ip>`, sign in, and click **Delete**. Turning developer mode off (enter the
same remote sequence and choose *Disable installer*) also removes it.

### Good to know

- A Roku holds **one** developer channel at a time. Installing another side-loaded app replaces
  Siku.
- The browser page is plain `http`. If your browser warns or redirects to `https`, type the
  `http://` explicitly.
- **"Install failed" or a compile error:** the installer page shows the reason. Please
  [open an issue](https://github.com/edrock200/Siku/issues) with that text and your Roku model.
- **Debug log** (useful for bug reports): run `telnet <roku-ip> 8085` from a computer while
  using Siku and copy what it prints.

Roku's [developer setup guide](https://developer.roku.com/docs/developer-program/getting-started/developer-setup.md)
has screenshots of each step.

## Build

Requirements: Node.js 18+ and `zip`.

```sh
npm install          # installs the BrighterScript compiler used for linting
npm run lint         # validates BrightScript and SceneGraph XML
npm run package      # writes out/siku.zip, ready to side-load
```

To deploy straight to a Roku in developer mode:

```sh
ROKU_IP=192.168.1.50 ROKU_PASSWORD=yourpassword npm run deploy
```

## Project layout

```
manifest                 Channel metadata (title, version, icons, splash)
source/main.brs          Entry point: creates the SceneGraph screen
components/
  MainScene.*            Root scene: navigation stack and app state
  screens/               One component per screen (connect, sign in, home, detail, player…)
  widgets/               Reusable UI: top bar, cards, rows, buttons, dialogs
  tasks/                 Background Task nodes for HTTP calls to the Silo API
  player/                Video player, its on-screen controls, and the capability report sent to the server
  screens/debug/         Diagnostics opened by deep link (stream test, font test)
images/                  Channel icons, splash screen and UI artwork
scripts/                 Packaging and deploy helpers
docs/                    Architecture, API notes, design spec, and requests for the Silo server team
```

## How it works

Siku talks to a Silo server over the **Silo v2 API only** (`/api/v2/...`), the same API the Android TV client uses. It never calls the legacy v1 API, and its network layer rejects any request outside `/api/v2/`. The server owns the library, metadata, transcoding decisions and accounts; Siku displays them and drives playback with Roku's native `Video` node. When playback starts, Siku describes what this Roku and your TV can play (resolution, HEVC/AV1/VP9 with profiles and levels, HDR10/HDR10+/HLG/Dolby Vision, and the audio formats the Roku accepts or passes through) so the server can pick Direct Play, Remux or Transcode.

What that means on a Roku today:

- A file whose video and audio your Roku accepts **direct-plays** untouched, Dolby Vision included.
- A file whose audio your Roku cannot take (for example E-AC3 when the TV only advertises stereo PCM, or TrueHD/DTS) is **transcoded to H.264** with AAC sound. Silo's lighter "keep the video, convert the audio" remux is packaged as fragmented MP4 with the audio muxed in, which Roku plays without sound, so Siku avoids it until the server can package it for Roku. The request to the Silo team is in [`docs/upstream/silo-server-roku-hls-audio.md`](docs/upstream/silo-server-roku-hls-audio.md).
- Subtitles: SRT and WebVTT tracks are shown, and the profile's language and Off/Auto/Always choice turns them on automatically (both confirmed on a real Roku); image subtitles (PGS, VobSub) and styled ASS are listed but cannot be displayed by Roku.

## Troubleshooting playback

- Roku passes Dolby audio through to your TV or receiver; it does not decode it. If the Roku reports
  "stereo" (Settings › Audio › HDMI set to PCM, or a TV that advertises PCM only), Dolby tracks are
  converted. *Settings › Playback › Force Dolby Audio Passthrough* overrides the report; use it only
  if your TV decodes Dolby but does not say so, and turn it off if there is no sound.
- The debug console shows exactly what happened: run `telnet <roku-ip> 8085`, start a video, and
  copy the line beginning `[siku-playback]`. It lists what Siku told the server and what the
  server decided (`plan: delivery=… reason=…`). Please include it in bug reports.
- To test what your Roku's player accepts, open the stream test screen with
  `curl -d '' "http://<roku-ip>:8060/launch/dev?debugScreen=StreamTestScreen"` and play the
  reference streams; results appear on screen and as `[siku-streamtest]` lines.

## Contributing

Issues and pull requests are welcome. If you use Claude Code, the repo ships a `CLAUDE.md` with the
project rules and a `roku-brightscript` skill (`.claude/skills/`) that lists the real-device
pitfalls we have hit and the exact lint, mock-server and simulator commands to verify a change. Read
`docs/ARCHITECTURE.md` first either way.

## References

- Silo server: <https://github.com/Silo-Server/silo-server>
- Silo Android TV client (the design reference; the `androidTvApp` module of <https://github.com/Silo-Server/silo-android>)
- Roku developer documentation: <https://developer.roku.com/docs/developer-program/getting-started/roku-dev-prog.md>

## License

Siku is free software, released under the **GNU Affero General Public License v3.0 or later** (`AGPL-3.0-or-later`). See [LICENSE](LICENSE). It ports logic and UI from the AGPL-3.0 [Silo Android TV client](https://github.com/Silo-Server/silo-android).

The Silo name and logo are trademarks of Silo Media L.L.C. and are not covered by this license. Siku uses its own logo.
