# Siku — project rules for Claude Code

Siku is a Roku SceneGraph/BrightScript channel that ports the Silo **Android TV** client
(`androidTvApp` module of https://github.com/Silo-Server/silo-android) to Roku. It should look
and behave like that app. Start with `docs/ARCHITECTURE.md`; it links the design spec and the
API spec. `docs/upstream/` holds requests we have written for the Silo server team.

## Scope (non-negotiable)
- Port only the Android TV app, not the phone app. No phone-only features.
- No downloads, offline playback, or any local-media-storage features. Android TV has none either.
- Silo **v2 API only** (`/api/v2/...`). `ApiTask` refuses other paths. Never call `/api/v1` or `/health`.
- Watch Party is out of scope (experimental and off in Android TV release builds).
- The app is named **Siku** everywhere a user can see it. The Silo name and logo are Silo Media's
  trademarks; use our own logo (`images/logo_*.png`) and refer to Silo only as what we connect to.
- License: AGPL-3.0-or-later. Every new source file starts with an
  `' SPDX-License-Identifier: AGPL-3.0-or-later` comment (or the XML equivalent).

## Build, lint, test
- `npm install` once, then `npm run lint` (BrighterScript, must report 0 errors) and
  `npm run package` (writes `out/siku.zip`, the side-loadable channel).
- Before finishing any change: lint clean, then run the affected screen in the simulator against
  the mock server. See the `roku-brightscript` skill for the exact commands. The simulator cannot
  play video, does not clip list items, searches `findNode` differently and reports a 720p stereo
  box, so playback, layout-clipping and capability changes need a real Roku; say so in your report.
- Pushes to the default branch publish a GitHub Release automatically when `build_version` in
  `manifest` changes. To ship a build: bump `build_version` AND add a `## vX.Y.Z` section to
  `CHANGELOG.md` written for users in plain language (what they will notice, not how it was
  done). The release page shows that section as its notes; the workflow warns if it is missing.
  Documentation-only changes are pushed without a bump and make no release.
- Every release also updates `.claude/skills/roku-brightscript/SKILL.md`: add what the build
  taught (a new device pitfall, a verification step, a tool quirk) and append a line to its
  "Release log" section naming the version and the lesson. The workflow warns when a released
  version is absent from the skill. A release that taught nothing new still gets a one-line entry.
- Never use `pkill`/`killall` to stop the mock server from a shell that also runs the tooling
  (it matched the shell and killed it). Find the pid (`ps -eo pid,args | grep "[m]ock_server"`)
  and `kill` it; start it with `setsid nohup python3 tools/mock_server.py --port 8097 ... &`.

## Playback on Roku: the facts we have established on a real device
These decide what `components/player/PlaybackCaps.brs` declares to the server. Do not undo them
without a device test (see the skill, pitfalls 13 and 14, and `docs/upstream/silo-server-roku-hls-audio.md`).
- Roku plays HEVC, 4K and Dolby Vision over HLS in fMP4 **only when the audio is its own
  rendition**. Silo's HLS remux muxes the audio into the video segments, so every
  `server_remux_hls` plan is silent on Roku, whatever the codec. Fragmented MP4 over plain HTTP
  (Silo's `server_remux_progressive`) does not play at all. MPEG-TS plays, but Silo produces it
  only for H.264 transcodes. Hence the HLS delivery is declared H.264/SDR/AAC-only and the player
  asks for another route once if a remux plan still arrives.
- A Roku app cannot switch HDMI audio passthrough on. The OS decides from *Settings › Audio*
  and the TV/receiver's EDID; Siku only reports what `CanDecodeAudio` says (re-probed at every
  start, lower-case quoted keys). The *Force Dolby Audio Passthrough* setting overrides the
  report for AC3/E-AC3 and announces itself on screen; on a stereo-only sink it yields direct play
  with no sound, which is the TV's doing.
- `playback.max_bitrate_kbps` is nullable: uncapped presets PUT `null` at `profile_device`;
  deleting the row let a profile-scope 6 Mbps cap force 720p transcodes. "Original" never sends a cap.
- Direct play of a non-default audio track needs the `client_selected_audio_track_v1` claim;
  Dolby Vision profile 8 on a non-DV output needs `client_dv8_base_layer_fallback_v1`. Both are
  declared on `original_http`.
- Subtitles: the server picks none on its own; Siku resolves the profile's Off/Auto/Always choice
  client-side (`Subs_autoChoice`, a port of Android's `AutoSubtitleResolver`). Roku renders only
  SRT/WebVTT sidecars; PGS/VobSub/ASS are listed as unavailable.

## Diagnostics
- `telnet <roku-ip> 8085` is the device console. Every playback start and replan prints one
  `[siku-playback]` line: declared capabilities, the request (`quality`, `cap`, `audio_req`,
  `sub_req`, `op`), and the server's decision (`delivery`, `reason`, `sel_audio`, `sub_mode`,
  recipe, source, warnings). Player errors print `[siku-playback] video error …`.
- Debug screens open with `curl -d '' "http://<roku-ip>:8060/launch/dev?debugScreen=<Name>"`
  (ECP needs POST): `StreamTestScreen` (plays reference HLS streams, the last Silo stream or
  `&debugUrl=`, logs `[siku-streamtest]` state and track counts), `FontTestScreen` (label and
  9-patch rendering). Simulator deep links: `debugSession=mock`, `debugScreen`, `debugItem`,
  `debugFile` (mock 4K files 52 and 56; 56 always remuxes), `debugUrl`.
- When a user report says "video but no sound", "direct play refused" or "fails at once", read
  the `[siku-playback]` line before touching code; the skill's error table maps each to a cause.

## Code conventions that exist because of device failures
- Never `x.findNode(id)` on a runtime-built node; use `Node_find(x, id)` or keep references.
- Every server number used in arithmetic or comparison goes through `Num_or` / `Content_num`.
- Cards inside `RowList`/`MarkupGrid` need cell headroom (`Content_rows(rows, insetY)`,
  `cardInsetX/Y`) because items are clipped to their cell on device.
- Measure text with `Label_width` / `Label_height`, never `boundingRect()` alone.
- Read device flags with `PlaybackCaps_truthy`; declare integer fields with `Int()`.
- A HUD row that shows a server-side choice is rebuilt when the replan answer lands.

## The one rule that matters most
Code that passes lint and runs in the simulator can still crash a real Roku. Several did.
Before considering BrightScript done, read `.claude/skills/roku-brightscript/SKILL.md`,
which lists the known real-device pitfalls, and check your diff against them.
