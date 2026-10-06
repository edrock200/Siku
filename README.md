# Siku

**Siku is a Roku client for [Silo](https://github.com/Silo-Server/silo-server), the self-hosted media server.**

Siku brings your Silo library to Roku TVs and streaming players. It is a port of the official [Silo Android TV client](https://github.com/Silo-Server/silo-android) to Roku SceneGraph and BrightScript, and aims to look, feel and behave like it on a 10-foot, remote-driven screen.

> **Status:** early development. Sign-in, browsing, detail pages and the player are built and tested in a simulator; they still need testing on a real Roku. Music and audiobooks are in progress. The checklist below tracks progress.
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
| Browse | Library grids with sort and filters, collections | ✅ |
| Detail | Movies, series (seasons and episodes), episodes, cast, person pages | ✅ |
| Discover | Search, For You (Watchlist and Favorites), release Calendar | ✅ |
| Playback | Direct Play, Remux or Transcode chosen by the server from the Roku's capabilities | 🟡 needs device testing |
| Playback | Resume, progress sync, mark watched, audio and subtitle selection, Skip Intro, Up Next | 🟡 needs device testing |
| Settings | Account, playback and subtitle preferences, sign out, switch server | ✅ |

Not planned for v1: Watch Party, Requests, AI subtitle tools, ebooks (also absent from Android TV), and downloads or any offline/local-storage features (Android TV is streaming-only too).

## Install (side-load)

Siku is not in the Roku Channel Store. To run it on your own Roku:

1. **Turn on developer mode.** On the Roku remote press **Home ×3, Up ×2, Right, Left, Right, Left, Right**. Note the IP address shown, accept the license and set a developer password. The Roku restarts.
2. **Build the package** (see [Build](#build)) or download a release zip.
3. **Upload it.** Open `http://<roku-ip>` in a browser, sign in as `rokudev` with your password, choose **Upload** and select the zip, then **Install**.

See Roku's [developer setup guide](https://developer.roku.com/docs/developer-program/getting-started/developer-setup.md) for details.

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
  player/                Video player and its on-screen controls
images/                  Channel icons, splash screen and UI artwork
scripts/                 Packaging and deploy helpers
```

## How it works

Siku talks to a Silo server over the same HTTP API (v2) as the Android TV client. The server owns the library, metadata, transcoding decisions and accounts; Siku displays them and drives playback with Roku's native `Video` node. When playback starts, Siku describes what this Roku can decode (H.264, HEVC, AAC, AC3/EAC3, HLS…) so the server can pick Direct Play, Remux or Transcode.

## References

- Silo server: <https://github.com/Silo-Server/silo-server>
- Silo Android TV client (the design reference; the `androidTvApp` module of <https://github.com/Silo-Server/silo-android>)
- Roku developer documentation: <https://developer.roku.com/docs/developer-program/getting-started/roku-dev-prog.md>

## License

Siku is free software, released under the **GNU Affero General Public License v3.0 or later** (`AGPL-3.0-or-later`). See [LICENSE](LICENSE). It ports logic and UI from the AGPL-3.0 [Silo Android TV client](https://github.com/Silo-Server/silo-android).

The Silo name and logo are trademarks of Silo Media L.L.C. and are not covered by this license. Siku uses its own logo.
