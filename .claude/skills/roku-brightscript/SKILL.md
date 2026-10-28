---
name: roku-brightscript
description: How to write, verify and debug BrightScript and SceneGraph code for the Siku Roku channel so that it works on a real Roku, not just in lint and the simulator. Use this whenever you add or change anything under components/ or source/, when a Roku prints a compile or runtime error, when a screen looks wrong on device (collapsed widgets, frozen UI, dots instead of text), when deciding how to size text or lay out a screen, or when running the simulator or mock server. Also use it when reviewing someone else's BrightScript diff.
---

# Roku BrightScript for Siku

The lint tool (BrighterScript, `bsc`) and the simulator (brs-engine) are forgiving. Roku OS is
not. Every pitfall below was found by installing a build that passed both and watching it fail on
a real Roku. Treat the list as the acceptance checklist for any BrightScript change.

## Real-device pitfalls (the acceptance checklist)

**1. Never index a function result directly.**
`transportButtons()[i].setFocus(true)` is a *syntax error* on Roku (bsc accepts it).
Assign first: `btns = transportButtons() : btns[i].setFocus(true)`.
Check your diff with `grep -n ')\[' <file>`.

**2. Know which objects the render thread may create.**
SceneGraph component code (anything in `components/` that is not a `Task`) runs on the render
thread, and `CreateObject` silently returns `invalid` or raises "MAIN|TASK-only component" for
many types. Then the next line crashes with "'Dot' Operator attempted with invalid...".
- Safe in components: `roSGNode`, `roDeviceInfo`, `roAppInfo`, `roDateTime`, `roTimespan`,
  `roRegistrySection`, `roByteArray`, `roArray`, `roAssociativeArray`, `roRegex`, `roString`.
- **Task or `main.brs` only:** `roUrlTransfer`, `roFontRegistry`, `roMessagePort` + `Wait()`,
  `roAudioPlayer`, `roVideoPlayer`, `roChannelStore`, `roFileSystem`.
Two crashes came from this: URL-encoding with `roUrlTransfer` (now `Str_urlEncode` is hand-rolled
in `components/common/Utils.brs`) and measuring text with `roFontRegistry` (see pitfall 3).
All network I/O goes through `components/tasks/ApiTask` via the `Api_*` helpers; never fetch from
a component.

**3. Don't trust `Label.boundingRect()` for layout.**
On device it can return width/height 0 before the font is ready. (The blank white top-bar
capsules were first blamed on this; the real cause was pitfall 11.) Measure with `Label_width(lbl)` and `Label_height(lbl)` from `Utils.brs`:
they use a cached SceneGraph `Font` node (`getOneLineWidth` / `getOneLineHeight`, guarded with
`try`/`catch` because the simulator's Font node lacks them) and fall back to `boundingRect`.
If you add a layout that depends on text size, use those helpers, never `boundingRect()` alone.

**4. Reserved words are stricter than bsc thinks.**
Roku rejects reserved words as member names and unquoted AA-literal keys. Confirmed on device:
`.next`, `.sub`, `.end`. Also avoid as identifiers: `pos`, `left`, `right`, `mid`, `str`, `len`,
`run`, `step`, `tab`, `stop`, `exit`, `line_num`, `box`, `objfun`.
Use bracket access and quoted keys for data that arrives with such names:
`sh["next"]`, `{ "end": 90 }`, `prof["sub"]`. (`card.type` happens to work on device; still prefer
quoting `type` in literals.)

**5. Field types are not coerced.**
Assigning an array to an `assocarray` interface field, or a float to an `integer` field, is a
silent no-op on device. Declare the right type in the XML `<field>`, and when in doubt use
`type="assocarray"` with a wrapper `{ items: [...] }`.

**6. Real-server data is looser than the mock.**
The real Silo server and TMDB omit fields the mock always sends, and may send numbers as strings.
`it.runtime * 60` with a string crashes with a type mismatch, and so do `>`/`<` comparisons and
`Int()` on a string (`=` merely returns false). Use `Num_or()` (Utils, parses numeric strings),
`Content_num()`, `Req_num()` (or the local `toInt()` in `DetailScreen.brs`) and `Str_orEmpty()`
before arithmetic, comparison or concatenation; wrap arrays with `Arr_or()`;
check `Type(resp.data) = "roAssociativeArray"` in response handlers before dotting into it.

**7. Keys go to the focused node first.**
A parent's `onKeyEvent` only sees keys its focused descendants did not handle. `RowList` and
`MarkupGrid` consume the OK *press* (firing `rowItemSelected`/`itemSelected`) but not the
*release*; the long-press scheme in `Utils.brs` (`LongPress_*`) depends on that. Every screen must
call `setFocus(true)` on something inside it in `onScreenShown`, or the remote goes dead.

**8. `HttpHeaders` on a `ContentNode` are `"Name: value"` strings** (with the space), and a
Video/Audio node cannot change them mid-stream. The access token is refreshed right before
playback starts (`ensureFreshToken`); don't add logic that assumes it can be refreshed during a
stream.

**9. Keep the device compile log free of warnings.** Roku prints `WARNING: unused variable` for
every declared-but-unread variable or parameter; bsc does not. Seventeen of them buried a real
error once. Remove dead assignments; where a signature forces an unused parameter (`onKeyEvent`,
callback hooks, `catch e`), reference it once with a comment saying why.

**10. Things the simulator cannot test.** Video and audio never leave the buffering state; keyboard
dialogs can't be typed into; key *hold* can't be simulated. Anything in those areas needs a real
Roku. Say so in your report instead of claiming it works.

**11. `node.findNode(id)` does not search that node's subtree.** On device it searches from the
*nearest enclosing component* (Roku documents this; brs-engine searches the subtree, so the
simulator hides it). Rows, tabs and chips built at runtime with shared child ids (`"label"`,
`"bg"`, `"ring"`) all resolve to the *first* row's nodes: one label gets every text, the rest stay
blank, their backgrounds are never sized and show as small white circles. Use
`Node_find(parent, id)` from `Utils.brs`, or keep direct references when you create the children.
`m.top.findNode(id)` is fine for ids declared once in the component's XML.
Check with `grep -rn '\.findNode(' components --include=*.brs | grep -v 'm\.top\.findNode'`.

**12. List items are clipped to their cell.** On device, `RowList` (and `MarkupGrid`) items cannot
draw outside their item cell; brs-engine does not clip. The focused card's 1.10 scale, ring and
glow were cut flat at the top of every row. Give the card headroom inside a taller cell: pass the
padding to `Content_rows(rows, insetY)` (or `cardInsetX/Y` on grid nodes), add the same amount
to `itemSize` / `rowItemSize`, and move the list up (or shrink `rowLabelOffset.y`) by it so the
layout does not shift. Anything that scales or overflows inside an item component needs this.

**13. Declare playback capabilities from the right APIs, and never cap what the user did not.**
`GetDisplayMode()` / `GetUIResolution()` describe the UI canvas (720p or 1080p even on a 4K TV);
only `GetVideoMode()` ("2160p60") and `CanDecodeVideo({Codec:"hevc", Profile:"main 10",
Level:"5.1"})` say what the box can play, and `GetDisplayProperties()` (Hdr10 / Hdr10Plus / Hlg /
DolbyVision) what the TV takes. `CanDecodeAudio` answers true for decode *or* HDMI passthrough,
so DD+/DTS go in `codecs_audio` (the Silo server copies audio only from that list at the
"declared" tier). Guard every probe with `try`/`catch`, read result keys loosely, and never
compare a possibly-missing key (`entry.max_height >= 2160` crashed; pitfall 6 applies to your own
AAs too). On the Silo side, `playback.max_bitrate_kbps` is nullable: an uncapped preset must PUT
`{"value": null}` at `profile_device` (FormatJson renders an `invalid` value as `null`), because
deleting the row lets a profile-scope cap through and the server then transcodes to 720p
regardless of "Original". `PlaybackCaps.brs` is the reference; the `[siku-playback]` console
line shows what was declared. Probe with lower-case quoted keys (`{ "codec": c, "passthru": 1 }`;
Roku OS before 14.1 is case-sensitive) and re-probe at every playback start
(`PlaybackCaps_reprobe`): a receiver switching on changes every answer. No Roku API forces HDMI
passthrough; the *Force Dolby Audio Passthrough* setting only changes the declaration, and on a
sink whose EDID lists LPCM only the result is direct play with no sound (confirmed on device).

**14. Roku's HLS player ignores audio muxed into fMP4 (CMAF) segments.** Roku's streaming spec:
"video: TS, CMAF (muxing audio and video not supported for CMAF); audio: aac, ac3, eac3". Silo's
HLS remux (`server_remux_hls`) is fMP4 with the audio muxed in, so it plays silent on device
whatever the codec; H.264 transcodes come as MPEG-TS and play. PlaybackCaps declares the HLS
delivery as H.264/SDR/AAC only, and PlayerScreen replans once (`failure_recovery`,
`unsupported_container`) if a remux_hls plan still arrives. Server-side fix requested in
`docs/upstream/silo-server-roku-hls-audio.md`. Also: query `CanDecodeAudio`/`CanDecodeVideo`
with lower-case quoted keys (`{ "codec": c, "passthru": 1 }`; older OS is case-sensitive) and
re-probe at every playback start, as Roku documents, because a receiver switching on changes the
answers. Device-confirmed 2026-10-07 with `StreamTestScreen`: Apple's HEVC and H.264 fMP4 samples
with a separate audio rendition play with sound on the same Roku, and Silo's progressive remux
(fragmented MP4 over HTTP) fails at once, so copied video reaches a Roku only as MPEG-TS or
demuxed CMAF.
Silo answered with `hls_copy_mpegts_v1` (2026-10-26; listed by the client in
`deliveries.hls.features`, not `client_features`). Siku negotiates it when the server's
capabilities list it and `server_remux_hls`, declares H.264 + HEVC (Main 10 level 5.1 probed with
`"container": "ts"`), AAC/AC3/E-AC3 probed from TS, HDR10/HLG and `dolby_vision_profiles: []` on
HLS, and keeps remux plans with `effective_recipe.segment_container: "mpegts"` and no
`video_sample_entry`; the old declaration and the one-shot recovery remain for servers without it.
**Implemented but not device-verified**: read `seg=` (and `tscopy=`, `tsvideo=`, `tsaudio=`) in
the `[siku-playback]` line and check the sound before calling it working. Copy remuxes have an
open-ended timeline (`can_seek_anywhere: false`): `seekToSource` hands far seeks to
`PlayerSeekReanchor.brs` (`seek_reanchor` replans, gated on `seek_reanchor_v1`).

**15. Dot assignment lower-cases a key; JSON for another app needs literal or bracket keys.**
`msg.requestId = id` stores `requestid`, and `FormatJson` writes it that way (reading is
case-insensitive, so Siku's own code never notices). Silo's phone app decodes camelCase exactly
(`requestId`, `serverURL`, `handoffReady`), so every frame Siku sends is built from AA literals
with quoted keys (`{ "requestId": id }`) or `aa["requestId"] = id`. Found with brs-cli, which
behaves the same (the registry shows `accesstoken`); check any new wire message with a test.

**16. Comparing `invalid` with a boolean throws.** `h.passive = true` when the JSON had no
`passive` is a Type Mismatch on device. Read wire and config flags with `Lan_isTrue` (or
`PlaybackCaps_truthy`), never `= true` / `<> true` on a value that may be missing.

## Porting notes worth keeping
- Showing part of an image (Silo's seek-preview sprite sheets): Roku has no crop API. Draw the
  whole image in a Poster inside a Group with `clippingRect` = the window and offset the Poster;
  put the clip *inside* any MaskGroup used for rounded corners, so the clip never depends on the
  MaskGroup. Bound texture memory with `loadWidth`/`loadHeight` (+ `loadDisplayMode`), keep a
  small pool of Posters, and set `uri = ""` to release them. A Poster cannot send headers, which
  suits signed URLs; a load that fails says nothing about why (`loadStatus = "failed"`), so a
  failure is treated as a possibly expired signature and the URLs are read again once.
  `PlayerTrickplay.brs` is the reference; device unverified as of this note: decoding a 3000 px
  sheet with `loadWidth`, MaskGroup over a moving card, invisible-Poster preloading.
- `box` is a reserved builtin (bsc says so; it is also in pitfall 4): name windows `win`.
- Channel hand-off (YouTube trailers, channel 837): brs-engine's `roAppManager.IsAppInstalled`
  always answers false, so a hand-off can only be tested on a device. Run it in a Task, log every
  step (`[siku-trailer]`), and treat "this channel is still running a few seconds after LaunchApp
  / ECP launch" as failure, then fall back (Siku shows the watch URL and a QR code). Launching
  another channel closes Siku (no instant resume). Never extract YouTube streams: Roku has no
  WebView, and ripping streams breaks YouTube's terms.
- The SceneGraph `Audio` node has no volume field: theme music cannot be faded or played quieter.
- A screen opened by deep link (no ShellScreen) has no settings loaded. A feature gated on a
  setting must call `Settings_load()` itself and react to its `settingsLoaded` field; merge such
  hooks into one `onSettingsLoaded` per screen (two features each adding one is a compile error).
- Problem codes newer than the server contract checkout (`playback_session_ended`,
  `profile_verification_required`) come from the Android repo: the code is the last path segment
  of the problem `type`, which `Http_problem` already parses.
- State machines kept free of SceneGraph can be tested without the simulator by replaying JSON
  vectors through `brs-cli -n -r <root> a.brs b.brs` (see `tools/bq_vectors.py`, which runs the
  server's 66 buffering-quality conformance cases against `BufferingQuality.brs`).
- Roku cannot blur a Poster. Where Android blurs (spoiler protection of an unwatched episode's
  still), Siku does not load the image at all and shows series art the server marks as such
  (`*_is_episode_still = false`) or the default artwork (`Spoilers.brs`).
- LAN features (phone sign-in, SiloCast remote control; `components/lan/`, `docs/ARCHITECTURE.md`
  "Phone features"): sockets, `roMessagePort` and the crypto objects (`roEVPCipher`, `roHMAC`,
  `roEVPDigest`) live only in `LanTask`; the render thread gets events through fields. brs-cli
  supports listening TCP and multicast UDP, so `tools/silo_phone.py` can drive the simulator end
  to end, but a socket assigned straight to `m.<name>` in a Task is disposed by brs-engine at once
  (its listener closed right after `Listen` returned true): keep sockets nested (`m.io.cast`,
  `m.conns[id].sock`). Device checks still open: whether a channel may bind UDP 5353 and join
  224.0.0.251 (`[siku-lan] mdns bind ... bound= joined=`; without it phones need the QR link),
  `roEVPCipher`/`roHMAC` output on a Roku (`[siku-lan] sealed: cN paired` then commands work),
  and Video `mute`.
- Never nest `for each` over the *same* array (an outer `for each ptr in records` calling a helper
  that does `for each rr in records`): brs-engine shares one iterator per array, so the outer loop
  ended after its first item and Find servers listed one server of two. Use index loops
  (`for i = 0 to a.Count() - 1`) whenever a loop body may walk the same array.
- brs-engine's datagram socket differs from a Roku's: `GetReuseAddr` is registered under another
  name ("Member function not found"; call it in `try`), `JoinGroup` only records the group (and
  makes `GetAddress()` return it, so read the bound port *before* joining), `SetSendToAddress`
  returns `invalid` (never test its result), multicast loop/TTL are ignored, and the bind of
  5353 is exclusive: only one simulator on the machine gets mDNS, and parallel agents' simulators
  take it (wait until `grep -i ":14E9 " /proc/net/udp` is empty). LanTask opens 5353 in the order
  ManavA/silo-roku verified on a C208X (reuse set + read, bind 0.0.0.0:5353 + port read, join,
  TTL 255 + read) and logs each `[siku-lan] mdns step`.
- A Task only hears field changes made after its thread runs `observeField(..., port)`: a
  screen that shows as the app starts set LanTask's `command` too early and the scan was lost
  (it worked in some runs, by timing). A request a screen may send at start-up gets its own field
  that the Task also reads once when it starts (`discover`, like `config`).
- A Task loop that sends must never block: LanTask queues frames per connection and drains them
  every pass (25 ms waits while anything is queued), reads only readable sockets, and checks
  datagram byte counts. Device checks still open: `[siku-lan] mdns step` lines on a Roku with
  AirPlay (shared 5353?), Find servers against a real Silo server (`discovery complete: N`,
  `found server identity ... matched=true`), and the `send queue full` / `send stalled` paths.
- `roAudioGuide` lives in a Task (A11yTask), never on the render thread; spoken text is label,
  role and position only, never a value, PIN, address or URL.
- brs-cli `ParseJson` objects are case-sensitive, unlike Roku event objects: read a device event
  field under both spellings. brs-cli also returns false for `invalid = true` instead of throwing,
  so pitfall 16 cannot be caught by host tests.
- Releasing a hidden screen's Posters (memory warnings) fires their `loadStatus` observers; a
  crossfade must ignore its own front layer reloading (Home's backdrop went black).
- Host tests (`tools/brs_test.py`, `tests/`) give `m.global` a `hasField`; anything else a node
  does (observers, `getField` on children) still needs the simulator.
- Silo's phone keys a server by base64url of its URL (`Lan_serverIdFor`) and matches by that or
  by the deployment identity (`/api/v2/system/identity` `server_id`, Siku's `session.serverId`).
- Voice transport commands (`components/common/VoiceTransport.brs`, idea from ManavA/silo-roku):
  `roInput.EnableTransportEvents()` in `main.brs` (in `try`; older firmware lacks it), then each
  `roInputEvent` whose info has `type: "transport"` must be answered with
  `input.EventResponse({ "id": info.id, "status": ... })` from the main thread, never handed to the
  deep-link path. `main.brs` gets the status synchronously with `scene.callFunc("handleTransport",
  info)`; MainScene routes it to the player on top (`voiceTransport` interface functions). Statuses:
  `success`, `success.seek-start`, `success.seek-end`, `error.generic` (refused: loading,
  replanning, re-anchoring, recovering, error screen, a dialog up). Seeks go through the screen's
  own seek path (`seekToSource`, which re-anchors copy remuxes) with the remote's skip sizes;
  `duration` is accepted only as 1-6 ASCII digits. Device checks still open: that the voice remote
  and the mobile app's voice button deliver the events, and Roku's answer to each status.
- The simulator is slow right after a plan mounts: a request sent in the first seconds can miss
  PlayerScreen's 2.5 s stop timeout (a `debugVoice=stop` 3 s in never reached the mock, the same at
  12 s did). Fire simulator-only injections several seconds after the plan, and read the mock log
  before blaming the code.
- Hand-drawn pickers (`DetailMoreMenu`, `SubtitleDialog`) speak for themselves: they call
  `A11y_reset()` when shown or hidden and prefix the first row spoken with their title; the
  player's panel speaks its tab or row from `applyHudRowFocus`. Read optional row flags with
  `A11y_isTrue` (pitfall 16), and combine label and value with `A11y_join`.
- Caching between launches (Home cache, `HomeCache.brs` / `HomeCacheTask`): `cachefs:` is Roku's
  evictable cache volume; `roFileSystem` and `roEVPDigest` stay in a Task, every storage failure is a
  miss, the file name is a SHA-256 of server|account|profile, the write goes to a temp file with a
  unique name (two Home pages once raced on one shared `.part`) and is renamed over the old file. Silo
  artwork URLs are signed (`exp`/`sig` or presigned S3) and expire, so a cache stores no image URLs:
  the cached Home draws default artwork and the server answer brings the pictures. Purges hang off
  `Session_save` (the one place sign-out, server, account and profile changes pass through), compared
  against the *registry* session so a phone's temporary profile never triggers one. In brs-cli,
  `cachefs:` (and `tmp:`) are in-memory volumes that start empty every run, `GetDirectoryListing`
  returns an `roList` (FormatJson refuses it; copy into an array), and two Tasks writing the same
  file at once fail at random. Device checks pending: that cachefs survives a channel restart
  (`[siku-home] cache hit` on the second launch) and the cost of the read on a low-end Roku.
- A refreshed `RowList` keeps the viewer's place only if you restore it: `HomeSkylineFeed.onRows`
  finds the focused row id and card `contentId` in the new content and sets `jumpToRowItem` after the
  row sizes are set.
- A covered player has stopped: `onScreenHidden` closes the server session, so when it is uncovered
  (`onScreenShown` with `m.closing`) it closes itself, and anything that opens a screen while a
  player is on top (a deep link, a phone launch) replaces the player instead of pushing over it.
  Every playback answer (`start`, `replan`, `progress`, the stop `DELETE`) carries a context
  (`attemptId`, `sessionId` / `sid`) and is dropped when it no longer matches: Up Next and retries
  start a new attempt while the old answers are still on their way. Simulator check:
  `debugDeepLink=<seconds>` on PlayerScreen.
- A Roku channel has no background state: it runs or it is closed, and Home closes it without
  notice. "Time away" rules (Profile Selection) measure from a periodically written last-active
  time (`ProfileLaunch.brs`), never from an exit hook alone.
- Token refresh (AuthTask): only a 400/401 answer to `POST /auth/refresh` means the refresh token
  is dead (sign out). A 5xx from a proxy, a 403, a captive portal's 200 HTML page or no answer keeps
  the session: three tries with back-off, then give up quietly so the caller shows its error and a
  later request (Retry) tries again. Save a refresh by merging only the token fields into the
  *current* `m.global.session` (a profile switch may have happened meanwhile), never a copy taken
  before the request. `Auth_refresh` (Http.brs, any Task) waits for AuthTask's `answered` field to
  echo its own request id, longer than `AuthTask_worstCaseSeconds` (host-tested); never time a wait
  shorter than the work it waits for. Any Task that calls the API outside ApiTask (ProbeTask) must
  send the same credentials (`X-Profile-Token` for a PIN profile) and refresh on 401 the same way.
- A request that reads `m.global.session` when its Task runs cannot target a server the screen is
  about to forget: pass `baseUrl` explicitly when the session changes right after the call (Change
  server's device-code cancel).
- Loads that several screens start and whose answers replace one shared snapshot (settings) carry a
  sequence number; the snapshot keeps the number it came from and an older answer is dropped. An
  optimistic local write bumps the snapshot past the loads already in flight.
- Registry writes wear flash: a heartbeat writes only as often as the rule it serves needs
  (Profile Selection's away clock: a twelfth of the away interval, 5-10 minutes).

## Project conventions (short version; `docs/ARCHITECTURE.md` has the full one)
- 1920×1080 canvas, pixel coordinates. Android dp × 2 = px; Android sp × 1.72 = px.
- Every component is an XML file plus a sibling `.brs` referenced by `<script uri>`. No inline
  `<![CDATA[` scripts (bsc can't check them).
- Screens extend `BaseScreen`; shell-hosted pages extend `ShellPage`. Navigate with
  `Nav_push/Nav_replace/Nav_reset/Nav_close`, open items with `Nav_openItem(id, type)` (it routes
  audio types to the audio screens), play with `Nav_play(params)`.
- API calls: `Api_get(path, query, "callback")`, `Api_send(method, path, body, "callback")`;
  read results with `Api_result(event)`. All IDs are opaque strings; escape them in paths with
  `Str_urlEncode`.
- Rounded shapes are white 9-patch Posters tinted with `blendColor` (`images/ui/r{R}.9.png`).
  Icons are white PNGs under `images/icons/`; add new ones via `scripts/make_icons.py`.
- Focus idiom: controls invert to `#EDEDED` with black text; cards scale 1.10 with a ring.
- Shared state lives on `m.global` (`session`, `prefs`, `toast`, `homeDirty`, ...). Edit a copy and
  call `Session_save` / `Prefs_save`; never mutate `m.global.session` in place.
- Playback: `PlaybackCaps.brs` is the only place that describes the device to the server
  (`client_capabilities`, `client_playback_context.deliveries` of kind `original` / `hls` /
  `progressive`, claims). `PlayerScreen.applyPlan` hands a plan to the Video node; every change
  of track, quality or output is a `sendReplan(operation, kind)` and `onReplan` swaps the plan at
  the current position. `Subs_autoChoice` resolves the profile's subtitle preference client-side.
  Settings that only change the declaration (`Force HDR Passthrough`, `Force Dolby Audio
  Passthrough`, `Experimental: Progressive Remux`) are device-local prefs read in PlaybackCaps.

## Verify before you finish

1. Lint: `cd <repo> && npx bsc --project bsconfig.json` → must print no errors.
2. Pitfall scan on your diff: `grep -n ')\[' <files>`; look for `CreateObject("ro` outside
   `components/tasks/` and `source/main.brs`; look for new `.boundingRect()`; look for reserved
   words after `.` or as literal keys.
3. Mock server (fakes the Silo v2 API with a synthetic library):
   `python3 tools/mock_server.py --port 8097 > out/mock.log 2>&1 &`
   Password login: any username, password `silo`. Profiles Laura / Sam / Kids (PIN 1234).
   Requests it receives are logged to `out/mock.log`, which is how you prove an endpoint was hit.
4. Simulator run with screenshots:
   ```
   python3 tools/simulate.py --brs-cli node_modules/.bin/brs-cli --out out/sim-<name> \
     --deep-link "debugSession=mock,debugScreen=<Screen>,debugItem=<id>" \
     --steps "wait:12,snap:a,down,wait:1,ok,wait:6,snap:b,back,wait:2,snap:c"
   ```
   Steps: `wait:N`, `snap:NAME`, `up/down/left/right/ok/back/options/play`. Put `wait:1` between
   keys (the simulator lags). View the PNGs; read `out/sim-<name>/console.log` for runtime errors.
   `debugSession=mock` seeds a signed-in session against the mock (port 8097, or
   `debugPort=<port>` for a mock started with `--port <port>`, so parallel runs don't collide); `debugScreen` opens a screen
   directly; `debugItem` becomes `params.itemId`. Useful ids: `movie:glass-city`,
   `series:orbital`, `audiobook:the-long-orbit`, person `100`.
   The simulator's registry is one file shared by every brs-cli run on the machine
   (`~/.local/share/brs-cli/registry.json`, keyed by the app), so parallel and earlier runs leak
   prefs and sessions into yours (a session pointing at another worktree's mock port, the Profile
   Selection choice from your last test). Seed what a test needs through deep-link parameters
   (`debugSession=mock`, `debugProfileLaunch=<choice|new>`, `debugAwaySeconds=N`) instead of
   trusting stored state. With several simulators running, a page can take 40-70 s to load: keys
   pressed while it loads are lost, so start with a long `wait` and run long scripts in the
   background. `tools/mock_server.py --help` lists switches that emulate older servers.
5. Release announcement: after a release is published, make sure it reached Discord
   (`tools/announce_discord.py <tag>`; automatic when the `DISCORD_WEBHOOK_URL` secret is set).
6. LAN code (`components/lan/`): `python3 tools/lan_vectors.py` must print `0 failure(s)` (the
   phone's sealed vectors, framing, mDNS); then run the simulator with `debugSession=mock` and
   `python3 tools/silo_phone.py cast --key <lanPairingKey from the brs-cli registry> ...` /
   `pair ...` against it (see the tool's docstring). Find servers: with nothing else holding UDP
   5353, start `sudo python3 tools/silo_responder.py --raw-to <this machine's IP> --address <same>
   --port <mock port> --id mock-server-1` and the simulator with
   `debugScreen=ServerConnectScreen,debugLanSelf=1` (the deep link lets the strict reader accept
   this machine's non-private address); `--scenario conflict|wrongport|badtxt|many|second` covers
   the refusals. On a real network run it without `--raw-to` from a machine on the Roku's LAN.
7. Home cache: start the mock with `--home-delay 20` and the simulator with
   `debugSession=mock,debugPort=<port>,debugProfileLaunch=automatic,debugRelaunch=<s>` (the first Home
   must have loaded before the relaunch; with several simulators running that takes 60-110 s); the
   console must show `cache write` then, after `debug relaunch`, `cache hit` and `cache drawn` while the
   mock is still sleeping, and a snapshot then shows titles over default artwork.
8. Auth changes: start the mock with `--switch reject_access=1 --switch refresh_status=502`; Home
   must show its error with Retry (still signed in, `[siku-auth] refresh gave up`), and after
   `curl -X POST -d '{"refresh_status": null}' localhost:<port>/mock/switch` Down + OK on Retry loads
   Home (`refresh ok`). With `refresh_status=401` the Login screen must appear.
9. Host tests: `python3 -m unittest discover -s tests` (pure BrightScript functions run in brs-cli)
   and, after `npm run package`, `python3 tools/package_check.py` (manifest images, no secrets,
   LAN/loopback URLs, v1 paths, webhooks, SPDX headers). CI runs both.
10. Build: `npm run package` → `out/siku.zip`. Side-load on a Roku in developer mode
   (`http://<roku-ip>`, user `rokudev`) and watch `telnet <roku-ip> 8085` for errors. A compile
   error prints `Syntax Error ... in pkg:/...(line)`; a runtime crash prints a full backtrace with
   local variables, which is the single most useful thing to paste into a bug report.
11. Playback changes: on the device, play one direct-play title and one that needs a server route,
   and read the two `[siku-playback]` lines (declared caps | request | decision). Open the debug
   screens with `curl -d '' "http://<roku-ip>:8060/launch/dev?debugScreen=StreamTestScreen"`
   (ECP needs POST; `&debugUrl=<url-encoded>` adds a stream) to test a packaging claim against
   Apple's reference streams and the last Silo stream; results print as `[siku-streamtest]`.

## When a Roku prints an error
- **Compile error at a line:** almost always pitfall 1 or 4. Fix it, then grep the whole tree for
  the same pattern; Roku stops at the first failing component, so there may be more.
- **"'Dot' Operator attempted with invalid":** something returned `invalid`. If the line follows a
  `CreateObject`, it's pitfall 2. Otherwise it's missing data: pitfall 6.
- **"Type Mismatch":** pitfall 6, usually string arithmetic.
- **UI frozen but no error:** focus is on a hidden or removed node (pitfall 7), or a dialog is
  invisible because its labels measured as zero (pitfall 3).
- **Hangs on the splash screen:** a crash during `MainScene.init` or the first screen's `init`.
  The telnet log has the backtrace.
- **Video plays, no sound, Audio menu empty:** the plan is an fMP4 `server_remux_hls` (`seg=-
  vse=hvc1`, pitfall 14); with `seg=mpegts` it is the new TS copy lane, which is the first thing to
  report upstream and to declare off (no `hls_copy_mpegts_v1`) if TS copies are silent too; or a
  forced Dolby declaration on a stereo sink (`forcedolby=true`, `out=Stereo`); never a codec bug
  in Siku. Check `plan: delivery=` and `audio=`/`decodeinfo=` in the `[siku-playback]` line.
- **Direct play refused although codecs match:** read `request:` fields. A non-default
  `audio_req` needs the `client_selected_audio_track_v1` claim, a `sub_req` naming a PGS track
  forces burn-in, a `cap=` forces a ladder rung; the server's `reason=` names the gate.
- **Playback fails within a second on a server route:** `delivery=server_remux_progressive`
  (fragmented MP4 over HTTP) is not playable on Roku; the `[siku-playback] video error` line has
  the Video node's code.
- **A seek on a remux snaps back or stalls:** the timeline is open-ended (`seek_any=false`). With
  `reanchor=true` look for `seek reanchor` / `seek reanchored` / `seek reanchor failed` lines; with
  `reanchor=false` the server does not list `seek_reanchor_v1` and the Video node seeks alone.
- **Everything transcodes to 720p "at 6 Mbps":** a bandwidth cap reached the request; see
  pitfall 13 (nullable `playback.max_bitrate_kbps`).

## Release log

One line per release: what that build taught about running on a real Roku. Add an entry for
every release, even when the lesson is "nothing new". The release workflow warns when the
released version is missing here.

- **v0.1.1** First install on a device. Nothing was known yet; everything below came from it.
- **v0.1.2** Roku's compiler rejects indexing a function result (`f()[i]`); bsc accepts it.
- **v0.1.3** `roUrlTransfer` cannot be created on the render thread; URL encoding is now hand-rolled.
- **v0.1.4** Neither can `roFontRegistry`. Text is measured with a SceneGraph `Font` node instead.
- **v0.1.5** `.next`, `.sub`, `.end` are reserved on device; real-server payloads may send numbers as strings.
- **v0.1.6** Sharing one `Font` node across Labels was *not* the cause of blank capsules (theory disproved on device); the cause is still being isolated with `FontTestScreen`. Lesson: when the simulator agrees with every hypothesis, build a diagnostic screen and let the device decide.
- **v0.1.7** `findNode` on a runtime-built group searches the whole enclosing component (pitfall 11). That, not fonts or `boundingRect`, caused the white top-bar circles, the blank Search chips and the stuck subtitle highlight. Found by logging every tab's resolved label on device.
- **v0.1.8** Settings ported to the server-synced cascade (`Settings.brs`). Two things learned in the simulator while building it: a component cannot rely on `m.global.observeField` firing in brs-engine (the screen declares its own `settingsLoaded` field and the loader sets it instead), and a one-line `' comment` inside a multi-line AA literal is accepted by bsc but the simulator dropped the entry that followed it; keep comments at the end of a line. The device has not run this build yet: the pane scrolling (`clippingRect`), the picker windowing and the Home Sections editor's rotated arrow icons need a real-Roku check.
- **v0.1.9** RowList clips items to their cell on device (pitfall 12): the focused card's zoom was cut at the top of every row. Cards now sit 32 px down inside taller cells.
- **v0.1.10** Not a device rule but a porting one: the Silo server does not pick subtitles from the profile's Off/Auto/Always setting (the plan's `subtitle.mode` is usually `off`); Android TV resolves them client-side (`AutoSubtitleResolver.kt`). `Subs_autoChoice` ports it. When a Silo feature "does nothing" on Roku, check whether the Android client does the work itself before blaming the server.
- **v0.1.11** Full review. Comparisons (`>`, `<`) and `Int()` on a string throw Type Mismatch on device (`=` just returns false), so every server number used in arithmetic or comparison goes through `Num_or` / `Content_num` (pitfall 6). Grids and calendar shelves got the pitfall-12 headroom; float-to-integer field assignments are rounded (pitfall 5).
- **v0.1.12** A nullable setting (`playback.max_bitrate_kbps`) must be PUT as JSON `null` to mean "no limit at this scope"; DELETE lets a broader scope's value show through (it was a 6 Mbps profile cap forcing 720p). Capability probes: `CanDecodeAudio` with `PassThru`/`ChCnt`, `CanDecodeVideo` with profile and level, `GetVideoMode` for output (never the UI resolution); read device flags with `PlaybackCaps_truthy`, because an Integer/Boolean comparison throws on device.
- **v0.1.13** AC3 copied into the server's fMP4 HLS remux played silent on a real Roku while video was fine. The HLS delivery now declares only AAC/MP3 audio; direct play keeps AC3/E-AC3 passthrough. Device display flags are read with `PlaybackCaps_truthy`, and the diagnostic line prints the raw `GetDisplayProperties()` JSON and model.
- **v0.1.14** Silent remux traced to Roku's CMAF rule (pitfall 14): fMP4 HLS with muxed audio plays video only. Lesson: when video plays and audio does not on a server route, check the packaging against Roku's streaming spec before suspecting codecs.
- **v0.1.15** No Roku API forces HDMI audio passthrough; the OS decides from the system HDMI audio mode and the sink's EDID (`GetAudioDecodeInfo`). A viewer override can only change what Siku declares to the server (Force Dolby Audio Passthrough), mirroring Android TV's Force HDR Passthrough.
- **v0.1.16** jellyfin-roku is a good reference for Roku playback: TS-only HLS transcoding profiles, per-container `CanDecodeAudio` probes, and an AC3 assumption under "5.1 surround" output (false negatives on some receivers). A HUD that shows a server-side choice must be rebuilt when the replan answer lands, not only when the picker closes.
- **v0.1.17** Silo refuses original_http when the requested audio track is not the container default unless the client claims `client_selected_audio_track_v1`; the Video node can select tracks in a direct-played MKV, so Siku claims it and applies `selected_tracks.audio.index` on availableAudioTracks. Log the request's track choices next to the decision; a refused direct play is usually a request detail, not a codec.
- **v0.1.18** Device test of the forced-Dolby declaration: direct play with E-AC3 arrived and played silent, confirming a Streaming Stick 4K does not decode Dolby itself and a sink advertising LPCM only will not take the bitstream. An override that bypasses a device report must announce itself on screen.
- **v0.1.19** `StreamTestScreen` (debug deep link `debugScreen=StreamTestScreen`, optional `debugUrl=`) plays reference HLS streams and the last Silo stream and logs `[siku-streamtest]` state and track counts: the way to prove a packaging claim on device instead of arguing from the spec. The `progressive` delivery is declared only behind the experimental setting until a device confirms Roku plays fragmented MP4 over HTTP.
- **v0.1.20** Device result: Roku's Video node does not play a fragmented MP4 served progressively (Silo's `server_remux_progressive` failed at once), so copied video reaches a Roku only as MPEG-TS or demuxed CMAF HLS. Always print the Video node's errorCode/errorMsg to the console; the on-screen message is too short to diagnose.
- **v0.1.21** Catch-up with Silo Android TV (Oct 6–24): built by four agents in parallel worktrees and merged. Lessons: parallel simulator runs need their own mock port (`debugPort=`) and share one brs-cli registry; two features adding the same `onSettingsLoaded`/`settingsLoaded` hook collide at merge; a channel hand-off can only be verified on a device. Device checks pending: YouTube hand-off (`mediaType`), theme music, buffering lowering (`observed=` must be non-zero on HLS), speed test `method=`, HLS subtitle rendition selection. The release from a session branch tagged the default branch's commit (the action's default); `release.yml` now passes `target_commitish: ${{ github.sha }}`.
- **v0.1.22** Trailer button next to Play (a Siku addition; Android TV has only the Trailers & More row). Nothing new about the device; first release tagged on the built commit (`target_commitish`).
- **v0.1.23** Catch-up with Silo Android (Oct 24–26): phone remote control and phone sign-in (LAN sockets, sealed frames, mDNS), seek previews, series audio/subtitle memory. Lessons: `FormatJson` lower-cases dotted keys (quote wire keys); a socket stored directly in `m.` of a Task is disposed in brs-engine; a loop variable can shadow a module helper in `tools/mock_server.py` (it broke "similar titles"). Device checks pending: mDNS bind on 5353, listening sockets, Roku crypto vs vectors, Video `mute`.
- **v0.1.24** Ideas from ManavA/silo-roku adapted in four parallel branches: MPEG-TS copy remux (`hls_copy_mpegts_v1`, delivery-scoped feature) with `seek_reanchor`, failure recovery with `attempted_plan_keys`, numbered errors and route reports, Find servers (strict mDNS reader), non-blocking LAN sends, screen reader, memory release, launch beacons, host tests and a package check. Lessons: a merged branch's tests can encode the pre-merge behaviour (DV 5/7/8), so run the whole suite after each merge; never nest `for each` over one array in brs-engine; a Task misses field changes made before it observes them. Device checks pending: TS copies with sound, mDNS bind beside AirPlay, recovery ladder, roAudioGuide, roAppMemoryMonitor.
- **v0.1.25** Silo Android #700 (card caption choice retired; `ui.card_presentation` still sends `caption: "title_metadata"`), Roku voice transport commands, player-panel speech and a Home cache in `cachefs:` (the latter two ideas from ManavA/silo-roku). Lessons: debug params from a deep link reach only the `debugScreen` itself (open `PlayerScreen` directly to test `debugVoice`); brs-cli's `cachefs:` is in memory only, so a "second launch" needs `debugRelaunch`; signed artwork URLs must never be cached; an edit that replaces a list item's first words must keep them (v0.1.24 dropped half a sentence in this file). Device checks pending: transport events delivered, cachefs across restarts, panel speech.
