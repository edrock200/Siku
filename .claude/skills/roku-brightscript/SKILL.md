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
  that the Task also reads once when it starts (`discover`, like `config`, and `castState`:
  RemoteControl's idle state was set before the Task observed it, so phones got no state until
  a player opened).
- A Task loop that sends must never block: LanTask queues frames per connection and drains them
  every pass (25 ms waits while anything is queued), reads only readable sockets, and checks
  datagram byte counts. Device checks still open: `[siku-lan] mdns step` lines on a Roku with
  AirPlay (shared 5353?), Find servers against a real Silo server (`discovery complete: N`,
  `found server identity ... matched=true`), and the `send queue full` / `send stalled` paths.
- A connection the LanTask never registered (refused at the controller limit) cannot use the
  queued senders: `sendRaw` drops frames for an unregistered conn, so that refusal was silent
  for a release. Write such last words straight to the socket (`s.Send`) before `Close`.
- The borrowed phone identity (RemoteControl) is undone by any later `Session_save`: a
  non-temporary save (Change server, a sign-in) or a temporary one with no token (Sign Out on
  the phone's profile) must end it without restoring the snapshot taken at activation, and its
  logout must use the token stored with it, never `m.global.session`'s (by then it may be the
  Roku's own). Verify with `silo_phone.py cast --profile p-sam --hold 150` while the simulator
  presses Sign Out / Change server on ProfileScreen; the mock prints `LOGOUT session=handoff|debug`.
- Bound everything an unauthenticated LAN peer controls: frames before the hello are capped at
  4 KiB (`cn.frames.max`), a silent phone sign-in connection closes after 30 s, mDNS answers are
  de-duplicated within one response. `silo_phone.py cast --check-limits` and `pair --idle` check
  the first two; `lan_vectors.py` the framing cap and the de-duplication.
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
  against the *registry* session so a phone's temporary profile never triggers one, and asked for only
  after `m.global.session` holds the new session (MainScene keeps that owner's file; asking first kept
  the old owner's Home). Size limits count UTF-8 bytes on write and read alike: `FromAsciiString`
  copies a string's UTF-8 bytes, so `Len()` undercounts accented and CJK text. In brs-cli,
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
- A failed "load more" must not re-request on the next focus change: a grid fires `itemFocused` on
  every key, so the Library toasted and re-asked on each move. Library backs off (5 s doubling to
  60 s, `Library_moreRetryDelay`); Notifications waits for its error card's Retry. Any section whose
  first load can fail needs something focusable for the retry (DetailScreen's episodes Retry button);
  an OK handled in the screen's `onKeyEvent` never arrives while a `RowList` has focus (pitfall 7).
- A quiet refresh (back from the player, Mark Watched) must recompute what was derived from the old
  answer: DetailScreen re-resolves the series' next-up episode when the refreshed episodes land, as
  `TvItemDetailViewModel.refreshOnReturn` does, and refetches only after the watched write landed.
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
- Episode parent artwork (Silo #711): the choice lives in `Spoilers.brs` (`Spoilers_heroBackdropUrl`,
  `Spoilers_posterUrl`, `Spoilers_firstBackdropUrl`, the series-backdrop fallback of
  `Spoilers_wideImageUrl`) and reaches every card through `Content_fillCard` (`backdropUrl` is the
  marquee hero). Series/season art is never a still, so it bypasses spoiler protection; older servers
  omit the fields and the helpers fall back to the card's own art. The Home cache keeps a whitelist of
  card keys, so the new signed URLs never reach `cachefs:` (`tests/test_parent_artwork.py` checks it).
- Optimistic card writes (Mark as Watched, Silo #706): patch the card at once, toast only after the
  server answers, and roll back on failure. `CardActions_perform(..., target)` keeps the page's
  reference in the request context; every page that includes `HomeCardActions.brs` must define
  `CardActions_rollback(target, patch)` (bsc reports a missing one as an unknown function; Roku
  would not compile the component). The rollback patch carries `contentId`
  and the feed/grid ignores it when the rows changed meanwhile; only the newest write per card may
  roll back (`m.cardWatchSeq`). `Api_reasonText(resp, fallback)` turns a problem into toast text.
- Row caps and "Explore all" (Silo Android #688, `SectionRows.brs`): a parameter only newer servers
  know (`item_limit`) goes only to a server that advertised it (`section_item_limit_max`), read once
  per server with a 3 s budget; a failed or slow read means "not supported", and a 422
  `validation_failed` naming `query.item_limit` / `unknown_parameter` is retried once without it and
  remembered for the session. Rows cap at 20 on the client whatever the server sends. The "Explore
  all" card is an ordinary last item of the RowList row (`exploreAll` on its ContentNode, drawn by
  MediaCardItem), not a row-title action: Android TV's is a trailing card, it inherits the cell
  headroom (`cardInsetY`), Back restores focus to it for free (the RowList keeps `rowItemFocused` while
  the page is covered), and Roku's screen reader reads its ContentNode title and description ("Explore
  all", the row title) like any card, so no `A11y_say` is needed. Everything that counts or walks a
  row's children (`removeEmptyRows`, the progress-row removal, item patches, the options key, the
  marquee) must skip that node; RowList reuses item components, so MediaCardItem resets every
  explore-only state for ordinary cards. The page itself is LibraryPage section `section`
  (`GET /api/v2/catalog?source=section`, no sort or `type` overlay: a mixed library's Movies / Series
  view filters client-side and reads on past pages the filter empties; 404 = "This row is no longer
  available."). HomePage's mixed-library refill target is capped at 20 too, and the Home cache keeps
  up to 24 raw cards a row (headroom for hide-watched), so a cached row still draws 20.
- Phone handoff address (Silo Android #716/#717): a phone offers its own server address, which may
  be public while the Roku is on the LAN. `HandoffAddress.brs` holds the pure choice (host-tested in
  `tests/test_handoff_address.py`, a port of Android's `RemotePlaybackServerAddressTest`):
  candidates are this Roku's saved addresses recorded under the offer's identity, then unverified
  saved ones (active first, at most 6), the phone's address, then at most 6 probe-able of the first
  24 `serverEndpoints`. All are probed at once (one Api_call each) and judged *in order* as answers
  land, under one 8 s budget Timer, so stale addresses cost one timeout in total (Android phones
  wait 15 s for the challenge). Another identity at the phone's address (or an endpoint) ends the
  handoff; at a saved-only address it is skipped. Siku records no separate plain-HTTP consent: a
  saved http:// server is the approval (ServerConnect asks before saving one). The handoff keeps
  naming the phone's server id; only `base` (capability/start/poll/cancel, borrowed `serverUrl`)
  moves. The own identity is read once per listener start when the session has none and saved with
  `Session_save` (a dotted `serverId` lands in the registry as `serverid`; reads are
  case-insensitive), which also purges the Home cache once (its owner key includes the identity).
  While a phone's profile is borrowed, it is written to `m.ownSession` and the registry instead,
  because any non-temporary `Session_save` ends the borrowed profile. Simulator check: mock
  `--also-port 8182`, `debugServers=reset`, `silo_phone.py cast --server http://127.0.0.1:8182
  --identity mock-server-1` and read `HANDOFF ... port=8181` in the mock log. Never grep for a
  pattern that also appears in your own shell command line before `kill` (it killed the shell).
- Registry writes wear flash: a heartbeat writes only as often as the rule it serves needs
  (Profile Selection's away clock: a twelfth of the away interval, 5-10 minutes).
- Several accounts from one phone session (Silo Android #810, silo-roku #38): a limit that depends on
  the registry budget is checked by running the real save code as a what-if (`PairSession_room` calls
  `Accounts_next(..., quiet = true)` and `Session_serversNext` with the next sign-in at its largest),
  never by a second copy of the shedding rules; pass `quiet` so a what-if logs no "registry budget"
  lines. The binding secret needs `roEVPDigest`, so LanTask makes it per phone connection and hands it
  to the screen in the `connected` event; the render thread only base64-copies strings. Never send
  it over plain HTTP. A screen that must open another screen over the one `@start` routes to passes a
  param (`openAccounts`) and the target pushes it in its first `onScreenShown`: two `navigateTo`
  writes from a screen that the first one removes are not reliable. Simulator: the mock is plain
  HTTP, so `binding sent=yes` needs an HTTPS server on a device.
- A confirmation before a destructive card action on a ShellPage (Remove request, Silo Android #792) is a
  StandardMessageDialog on `getScene().dialog` with the safe button first, as SignOutFlow does; the page's
  `focusContent` must not take focus back while it is up, and closing it hands focus to the feed. The feed's
  `onRows` already keeps the neighbouring card focused when the focused one leaves a row.
- Polling on a page (the season translation job, Silo Android #822) uses a one-shot `Timer` per step, stopped in
  `onScreenHidden` and restarted in `onScreenShown`, and every answer carries the job it belongs to. Changing a
  RowList card means `setFields` on its ContentNode (no rebuild), so focus stays where it is.

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
   `pair ...` against it (see the tool's docstring); `cast --check-limits`, `cast --hold N` and
   `pair --idle` cover the limits and the borrowed-profile endings. Find servers: with nothing else holding UDP
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
9. Host tests: `python3 -m unittest discover -s tests` (pure BrightScript functions run in brs-cli;
   `tests/test_source_pitfalls.py` fails on any `f()[i]`, pitfall 1)
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

## Lessons from v0.1.31 (Silo's official Roku app's device findings and six parallel slices)

Device facts from Silo-Server/silo-roku `docs/hardware-evidence.md` (TCL Roku TV OS 15.3.4, Roku Ultra
OS 16.0.4), adopted in v0.1.31, plus tool quirks found while building it:

- A Video error is not a route failure by code alone: Roku reports dropped connections as -3/-5 with
  the cause only in errorStr/errorInfo.dbgmsg; classify by HTTP status first, then transport text
  (silo-roku HE runs 8, 14, 15). failure_recovery excludes the route, so a few seconds of outage used
  to exhaust every route.
- The Video node reports "finished" right after "error": never treat it as the end without checking
  the plan played and no error/replan is pending.
- Anything that must outlive a screen (a stop DELETE) belongs to MainScene: a removed screen's
  observers and ApiTask callbacks die with it. Reach MainScene with `getScene().callFunc` and wrap the
  return in `PlaybackCaps_truthy` (callFunc can return invalid; pitfall 16).
- Video/Audio `HttpHeaders` go to every origin a playlist or redirect names (silo-roku HE H1): put the
  account token only on server-origin URLs.
- brs-engine's roRegex accepts PCRE lookahead and `\b` (JS regex), so host tests cover the transport
  patterns; Roku's PCRE does too.
- With six simulators at once (load ~38 on 4 cores) the player needs several minutes before its
  first plan; wait 300 s, not 45 s.
- A sidecar's TrackName in `Video.availableSubtitleTracks` is Roku's own (it contains the URL given,
  e.g. `/tmp/plugin/<dir>/…`); select by the listed name, match "contains", never only equality
  (silo-roku hardware runs 17/18). Never write `subtitleTrack` before the content's first frame + ~3 s on
  MKV originals (run 20: content stopped); one corrective write after that fixed run 21.
- `Video.suppressCaptions` is the per-node way to keep captions off UI; Roku draws captions above
  every SceneGraph node.
- Server-side first extraction of an embedded text track takes 65-279 s; a Video-node sidecar URL just
  shows nothing. Probe it from a Task with a long timeout.
- `CanDecodeAudio({"codec":"aac","chcnt":6})` is false on some Rokus (Ultra) and true on others (TCL TV).
- Simulator: `debugSubtitle=<combined index>` starts the player with that subtitle (handy for subtitle work).
- Simulator: under heavy host load (load average 40), brs-cli runs so slowly that `snap:` steps fail and
  the debug screen opens after ~1-2 min; give `wait:` steps 150 s+.
- Simulator: a request a screen starts right before `Nav_reset` replaces it may never be sent (the
  avatar menu's logout never reached the mock); wait for the answer (bounded) before navigating.
- brs-engine keeps unquoted AA-literal keys' case in the registry JSON (`accessToken`), while dot
  assignment lower-cases; read stored data with dot access, never `DoesExist("camelCase")`.
- `simulate.py` snapshots fail ("snapshot failed") when the render thread is busy for >1.5 s (all
  shots then land in `siku.png`); with six simulators running, trust `[siku-…]` lines.
- In brs-engine the StandardMessageDialog's first Down seems to land on the first button only after
  an extra press (two Downs from Cancel chose "Sign Out", three chose "& Remove Server"); on a Roku
  focus starts on the first button — device check.
- Pitfall 16 again: `m.flag = true` on a never-set `m.flag` (and `resp.context.prefetch = true`)
  would throw on a Roku; use a typed helper. ProfileScreen's `m.offerVisible` is now initialised.
- brs-cli honours `#if`/`bs_const` from the zip's manifest, in components and Tasks alike; the manifest
  does not have to be the zip's first entry. So a simulator-only manifest is a cheap way to keep debug
  aids out of release builds.
- Under a load of ~35 on 4 cores (six agents' simulators), a Task's first HTTP answer took > 20 s and
  60 s waits saw nothing at all: wait 150 s+ before judging, and drive interactive tests from console
  lines (scratchpad `setupdrv/drive.py`: a pty driver that presses keys written to `<out>/keys.txt`)
  rather than fixed `wait:` steps.
- `m.exit` would be a reserved-word member (pitfall 4); used `m.leaving`.
- Dot-assigning an AA key lower-cases it (pitfall 15) also bites host tests that compare dicts:
  build returned AAs as literals.
- brs-engine: an AA literal with an empty-string key `{ "": true }` did not match `DoesExist("")`;
  test the empty case explicitly.
- Roku OS 15.3.4 `roDateTime.FromISO8601String("YYYY-MM-DD")` gives the epoch (sroku hardware run
  5); brs-engine parses it, so the simulator hides it. Append `T00:00:00Z` and format in UTC.
- `Num_or` returns a single-precision float: never use it on epoch seconds (1.8e9 rounds to 128 s
  steps). Use integer types (`Time_nowSeconds()`, `Fresh_secs`).
- AA literal keys keep their case, dot assignment lower-cases (pitfall 15 again in a test:
  `{ "matchAll": true }` vs `out.matchAll =`): keep one style per object.
- `continue for` avoided (not sure of older Roku OS / brs-engine support); restructure with if/else.
- simulate.py: under heavy load (load average 35 with six agents) the screenshot can take longer than
  its 1.5 s wait, so snapshots report "failed" and only `siku.png` (the last one) remains; keys also
  get lost. Use long waits and `[siku-a11y]` / mock logs as proof.
- Unicode ▲▼ avoided in UI text (font may lack them → boxes); ↑↓ (Arrows block, like the existing →).
- brs-engine's `roRegex.ReplaceAll` does not support `\1` back-references (Roku's PCRE does): it
  inserts a literal `\1`. Scan words instead (`Diag_scrubKeys`).
- brs-cli: `ReadAsciiFile` on a missing file prints `BRIGHTSCRIPT: ERROR: ReadAsciiFile: file open
  for read failed` (not fatal); check `roFileSystem.Exists` first in a Task.
- brs-cli reports `media_player_state: "stopped"` and an empty/`EXIT_UNKNOWN` exit code from
  GetLastExitInfo; real exit codes only on a device (use `debugExit`).
- Dot-assigning into an AA literal lower-cases the key in brs-cli results too (`appState` →
  `appstate`); host tests compare such AAs case-insensitively (pitfall 15).
- A `while` that cuts a string into pieces with an indent must check the width exceeds the
  indent, or it never ends (brs-cli host test hung).
- Roku OS 15.1 sends a single memory warning at 80 %: without polling `GetMemoryLimitPercent()`
  a "low memory" state never clears. 15.2 sends rising and falling events at 80/85/90/95.
- sroku device lessons worth listing (from sroku docs, not re-verified by Siku): setFocus on a
  parent of a focused child is a no-op on TCL; clippingRect drew nothing on 15.3.4; MaskGroup
  does not clip without OpenGL; a full-screen texture/shader under rows cost ~10 fps on an Ultra;
  observe `focusPercent` in items, never `rowFocusPercent`; the memory check's own allocations do
  not move GetMemoryLimitPercent; cachefs survives a relaunch; LaunchApp/ECP fail store Static
  Analysis; render-thread rules now checked by `tests/test_thread_rules.py`.

## Lessons from v0.1.33

- brs-engine shares one for-each iterator per array: a helper that walks `plan.subtitle.inventory` called
  inside a for-each over the same inventory ended the outer loop after one row (mount showed 2 of 5 rows).
  Use index loops in any loop whose body calls helpers over the same array (now done in applyPlan and the
  PlaybackCaps subtitle helpers).
- Roku track names of the stream (`mkv/3`, `webvtt/1`) must be compared exactly; only sidecar URLs use
  containment (Subs_isTrack / Subs_isFile).
- Roku numbers HLS WebVTT renditions DEFAULT-first (silo-roku TCL run 2026-11-01); a SubtitleConfig naming the
  plain playlist index opened the wrong language there.
- Mock bug pattern: a Python local named like a module-level function (`detail`) anywhere in a function makes
  every call to that function in it fail.
- Focus look idiom changed: cards lift 1.05 by whole px per side about the top-left (CardFocus.brs) with
  a 4 px white 70% outline and a black shadow 9-patch; replace "cards scale 1.10 with a ring" in
  "Porting notes" / "Focus idiom".
- Roku resamples a scaled Label's glyphs (blurred Inter on device, sroku d776b67). Never let a focus
  Group's scale reach a Label: use `FocusText_place` (inverse scale about the same centre, whole-px
  origin, box grown by the scale) with a Font of `Int(size * scale)` — rounded DOWN, since rounding to
  nearest made text outgrow its box and ellipsize on a TCL (sroku 3fd96f1). Changing the Font per
  animation frame is costly: place it when the scale settles.
- Roku has no reduced-motion setting an app can read; Android's "no lift under reduced motion" cannot
  be ported.
- A Label's font size in single precision: `Int(25 * 1.04)` is 25, not 26; add a small epsilon.
- `box` is also rejected by bsc as an AA key / local (pitfall 4 again, hit while porting).
- Mock: never name a local `detail` (or any module helper) inside `route()`: Python makes it local for the
  whole function and every catalog item request fails (second time this class of bug hit; v0.1.23 too).
- A lifted card at a RowList's first visible slot is cut on the left by the list's own bounds; give the row
  `focusXOffset` and move it left by the same amount (simulator shows this one).
- Under host load brs-cli rendezvous timeouts crash the app (`EXIT_BRIGHTSCRIPT_CRASH`, "render thread
  blocked"); not a code bug, rerun when `uptime` load is low.
- Simulator: 8 parallel brs-cli runs on a loaded host made every snapshot fail ("snapshot failed");
  run at most two at a time.
- (mock) A local variable in a Python handler shadows a module helper for the whole function, even
  in a branch that never runs: `code, _, detail = ...` in the info_status branch made every item
  detail read fail. The v0.1.23 lesson again (loop variable shadowing a helper).
- Never `ps | grep <pattern>` + kill in a command whose own text contains the pattern: it matched
  the shell itself twice (exit 144). Print the pids in one command, kill them in the next.
- brs-cli under load (load ~35-56) drops most keys sent by fixed `wait:` scripts; a reactive driver
  that presses keys when a `[siku-…]` console line appears (scratchpad bsdrv/drive.py) worked first
  time.
- `m.top.findNode("titleLabel")` in BoxSetScreen returned ShellActionMenu's own internal
  `titleLabel` (a child component's node; the screen's label sat deeper, inside page/hero groups), so
  the title was set on the hidden menu and the hero showed none. Give screen nodes ids no child
  widget uses (`boxSetTitle`); check new ids against the ids inside ShellActionMenu, PillButton etc.
  Whether a Roku's findNode also descends into child components this way is unverified.
- A one-row RowList whose items all fit should use `rowFocusAnimationStyle="floatingFocus"`: with
  fixedFocus, jumping to (or coming Back to) the second card scrolls the first one off screen.
- MediaCardItem has no Utils.brs in scope, so pill widths there are estimated from the text length
  (~12 px a character at 19-21 px), not measured: check "BOX SET" / "THIS FILM" / "12 films" fit on a
  device.

## Simulator runs (scratchpad, driver bsdrv/drive.py)

- sim33-boxsets-B: shell → Movies → Browse with box sets on: 21 cards, "BOX SET" cards with sleeves
  (night_card.png, paper_card.png), OK opens The Paper Collection (paper_boxset.png).
- sim33-boxsets-OFF / OFFS: `box_sets` switched off: 24 plain titles, no `group`, no box-set search.
- sim33-boxsets-A / F: box set page, card menu Mark as Watched (POST /watched, facts "1 of 3 watched",
  Play → "Continue · Midnight Garden"), title, Back from a film re-reads quietly and lands on its card.
- sim33-boxsets-S: Search "night": Night Collection first, "4 results".
- sim33-boxsets-D2 / T2: movie page row "The Paper Collection" / "Night Collection" with THIS FILM and
  Explore all, first Down landing on the film on screen; library_id sent from a box set's film page.
  Not exercised: OK on Explore all (the key run went past the row), the 1.5 s search grace, a refused
  watched write on the box set page.
### Playback (affect CLAUDE.md "Playback on Roku")
1. ADDS (implemented here): Roku treats a growing copy-remux playlist (`EVENT`, no `ENDLIST`) as
   live. A `PlayStart` near its start (0.2-1.6 s) is ignored: the load opens 4-8 s in, near the end
   of the playlist as first read, and no seek in the first seconds goes below that (sroku runs 8-10;
   W0-2 Streaming Stick 27/28). Roku honours `PlayStart` >= 10 s once the playlist reaches past it;
   lead-in + 1.5 s hold: 14/14 within 1.06 s. Siku's old local "seek back" after a late start on a
   copy remux therefore never landed on device.
2. CONTRADICTS 1 on big streams (open item in sroku spec, Roku Ultra OS 16.0.4, 2026-11-01): on a
   69 Mbps 4K Dolby Vision copy remux through a proxy origin (10-22 MB segments, slowly growing
   playlist) Roku opened EVERY lead-in reanchor at the stream's origin (10.3-10.6 s short) because
   the playlist had not grown past the target at its first read; the forward seek then landed 4.4
   and 6.9 s in ("did not land"). Once the node also jumped back ~9 s by itself after a rebuffer.
   sroku keeps the lead-in for ordinary seeks and resumes pending device runs (options: longer hold,
   retried forward seek, or the server's `#EXT-X-START` / complete playlist). Siku's copy remuxes
   are exactly the 4K HEVC/HDR case, so on big files a reanchor may now land ~4-6 s EARLY instead of
   4-8 s late. FOR THE LEAD: decide whether to ship the lead-in as is (sroku does) and write the
   upstream request for `#EXT-X-START`/complete playlists into docs/upstream/; I did not change
   CLAUDE.md. The `start check` / `start seek ... landed=` lines will show which case a device hits.
3. ADDS: a seek counts as landed only within 3 s of its target; "the position moved" is not landing
   (W0-2: a seek back from 8.0 s to 0.2 s played on from 7.96 s).
4. CONFIRMS: Roku reports position 0 while it rebuffers after a seek (run 10), so judge a seek at
   the first position once it plays again or after 3 s.
5. No finding in the diff touches audio over TS, HEVC/HDR10 from TS, Dolby Vision profiles,
   passthrough, max bitrate, or `client_selected_audio_track_v1`: those CLAUDE.md facts stand.

### Subtitles (for the subtitle-rendition slice; I did not touch SubtitleSelect/SubtitleSuite)
6. ADDS: Roku draws an MKV original's own SubRip tracks natively, listed as `mkv/<Matroska
   TrackNumber>` in `availableSubtitleTracks` 35-90 ms after `buffering`, before the first frame
   (Ultra 16.0.4; TCL 15.3.4 PASS in-app). Content `SubtitleConfig: {TrackName: "mkv/N"}` preselects
   before the first frame, also with `PlayStart`; `subtitleTrack = "mkv/N"` switches with a 150-250 ms
   rebuffer. Not listed: Forced tracks, PGS, any MP4 (`mov_text`) track; SDH flag not reported.
   ASS draws as plain text, `{\an8}` prints literally, `<i>` drawn upright. Contradicts nothing in
   CLAUDE.md ("Roku renders only SRT/WebVTT sidecars" is Siku's choice, not a Roku limit) but would
   change it if Siku adopted `native_embedded` (server feature `native_embedded_limitations_v1`).
7. ADDS (important for any embedded/native work): a Forced track in the playing audio's language,
   or a default-flagged PGS track, makes Roku draw THAT track instead of the selected embedded one,
   while `subtitleTrack`/`currentSubtitleTrack` still report the selection. A side-loaded sidecar is
   never overridden. Siku uses sidecars, so it is safe today.
8. CONFIRMS Siku's Off handling: writing `subtitleTrack = ""` makes Roku fall back to its own pick
   by caption language; caption mode Off draws nothing, Forced included. Siku sets
   `globalCaptionMode = "Off"` with the empty track (PlayerScreen applyPlan / Off) - correct.
9. ADDS: Roku numbers a stream's WebVTT renditions `webvtt/<n>` with the playlist's `DEFAULT` first,
   then the others in playlist order (TCL 15.3.4, 2026-11-01). `Description` = the rendition `NAME`.
   Preselecting `webvtt/<index>` by inventory index FAILED (played another language); `webvtt/1`
   on a new stream whose `DEFAULT` is the plan's rendition PASSED. Before the playlist loads, Roku
   lists the preselected `TrackName` alone (`Language` `eng`, no `Description`). Left alone, Roku
   opened new content on its own rendition in the caption language (English) until the 3 s check
   (Ultra, 2026-10-31), whatever `DEFAULT` said. -> subtitle slice should check Siku's rendition
   selection against this numbering.
10. ADDS: with `hls_subtitle_renditions_all_v1` the server lists every embedded text track as a
    rendition (22 on a remux; switch in place reused the transport, answered in 25 ms, cues within
    2 s; TCL). A copy remux's playlist there was a full VOD playlist (3,482 segments up front) - i.e.
    a remux with renditions was NOT a growing EVENT playlist in that run.
11. ADDS: first sidecar extraction of a 3.1 GB MKV on a CephFS server took 116 s cold, 1 s cached;
    the server keeps extracting after a client timeout, so re-asking the same URL joins it; proxies
    answer 502/504/524 meanwhile (sroku retries for 5 min, 120 s per try, backoff 2-30 s).

### Skill (roku-brightscript) lessons
12. Roku resamples a scaled Label's glyphs (blurs Inter's hinted stems): scale the art but set the
    text at the scaled size rounded down to a whole px, on whole pixels (sroku `theme.placeUnscaled`).
13. A Roku Ultra in its Suspend power mode fails loads with "Failed to create decoder"; ECP
    `keypress/PowerOn` before a test run fixes it (not a stream problem).
14. sroku moved card focus to tvOS's outlined lift (1.05 scale, 4 px white 70% outline inside the
    edge); edges on whole px (a fractional edge drew a white line past the 9-patch frame) - UI, FYI
    only (Siku follows Android TV).
15. Tool note: `debugHoldSeek=1` did not open a hold session in my run; `debugVoice=seek:<s>` did
    the far seek. The mock's route() `detail` shadowing (fixed here) broke every item/watch read.

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
- **v0.1.26** Silo Android #702 (catalog flag rule values must be JSON booleans; strings got a 500) and a four-slice review with fixes. Lessons: a `)[` slipped in at v0.1.23 because nothing enforced pitfall 1, so `tests/test_source_pitfalls.py`, `package_check.py` and `release.yml` now refuse it; every playback answer needs an attempt/session context; only a 400/401 refresh answer signs out; a borrowed phone identity must end on any later own-session change; a `.gitignore` entry `node_modules/` does not ignore a `node_modules` symlink (a worktree link got committed and a fast-forward replaced the real folder with it). Device checks pending: the SeriesChoice compile fix, auth back-off, Up Next/subtitles between episodes, sign-out while borrowed.
- **v0.1.27** Silo Android #688 (item_limit capability + "Explore all" trailing card), #711 (series/season art for episode heroes and posters, never hidden by spoiler protection) and #706 (optimistic card writes roll back with the server's reason). Lessons: focus starts on the top bar, so simulator key scripts need a Down before row moves; the simulator ignores request timeouts and can take over 8 s for an instant answer, so screen-side timeouts must be generous; the simulator mis-measures toast text (it truncated a wrapping message). Device checks pending: Explore all clipping and speech, signed series art, toast wrap, 3 s capability timeout.
- **v0.1.28** Silo Android #716 (handoff at the Roku's own saved address for the phone's server identity, then the phone's, then offered endpoints; parallel identity probes with an 8 s budget) and #717 (record a missing server identity so it is advertised). Lessons: plain-HTTP consent is implied by a saved origin (Siku keeps no separate approval list); the debug session seeds two server addresses, so identity reads in the simulator can run twice with one failing. Device checks pending: probe budget vs the phone's 15 s wait on a real network, public/Tailscale phone handing off to a LAN Roku.
- **v0.1.29** Silo Android #726 (AI subtitle jobs send the playback `session_id` so the server runs them in the foreground from the playhead; a 404 is resent once without it unless the user cancelled meanwhile). Lessons: the simulator reaches the AI dialog with `debugScreen=PlayerScreen,debugItem=movie:paper-moons,debugFile=42,debugA11y=1` and `options, right x3, down x3, ok, down x3, ok` (the a11y lines confirm each focus); a snapshot taken right after a fast mock answer can still show the previous frame ("Submitting..."), so prove state from the mock log. Device check pending: progress moving within seconds on a real server.
- **v0.1.30** Silo Android #737 (More Like This chain: the first rail pick pushes, later picks replace, the start title goes back; a one-move-per-page latch reset in `onScreenShown`). Lessons: in the simulator a detail page's similar-titles answer lands about 30 s after the page opens (the row is missing before), so wait 45-50 s per page; a DetailScreen's first Back closes it only when focus is already at the top; and a snapshot can still show the previous screen right after Back, so trust the `[siku-a11y]` lines and take a second snapshot. Device check pending: a long chain and Back.
- **v0.1.31** Twenty-five items from a comparison with Silo's official Roku app (reconnect, progress, subtitles, AAC ceilings, saved servers, sign-out, first-run sign-in choice, debug gating, deep links, phone idle timeout, dates, calendar, filters, Requests layout, diagnostics, memory). Lessons: date-only ISO strings parse to 1970 on Roku OS 15.3.4 (the simulator hides it); Roku reports dropped connections as -3/-5 with the cause only in the text; select subtitles by Roku's listed TrackName; `Num_or` must never carry epoch seconds; debug deep links belong behind `#if DEBUG`, enforced by package_check; with six simulators running, wait 150 s+ and trust console lines over snapshots. Device checks pending for nearly all of it. The release workflow's `)[` grep also matches inside string literals (a regex in Diag.brs failed the first v0.1.31 release while package_check, which strips strings, passed): run the workflow's own grep `grep -rn ')\[' components source` before pushing a release.
- **v0.1.32** Silo Android #773 (Search's request row drops in-library titles and hides when only those matched). Lessons: nothing new about devices; a new flag read in `layoutRequests` is initialised in `init` (pitfall 16), and `debugQuery` joins the DEBUG-only deep-link parameters.
- **v0.1.33** Silo Android #646 (box sets), #770/#776 and Silo Roku's rendition work (subtitles from the stream, unplayable rows), #781 (focus outline), Silo Roku 01a0f42 (re-anchor lead-in). Lessons: brs-engine shares one for-each position per array, so nested helpers walking the same inventory cut loops short (use index loops); `m.top.findNode(id)` can return a child widget's node with the same id; Roku names an MKV's own text tracks `mkv/<TrackNumber>` and numbers HLS renditions DEFAULT first; a reanchored copy remux is an EVENT playlist Roku treats as live. Device checks pending for all of it.
- **v0.1.34** Silo Android #782 / silo-roku 5b296d7 (Requests moved from the top bar to the profile menu). Lessons: nothing new about devices; the profile panel's rows are filtered per open (the gate can change), and Up from a page opened from the panel needs its own bar target (the avatar).
- **v0.1.35** Silo Android #786 / silo-roku addf483 (Watchlist and Favorites leave the profile menu; For You keeps them). Lessons: nothing new about devices. Reviewed and already covered: silo-roku b5e43ae (root-relative artwork: `Url_resolve`), 0065969 (a refused subtitle replan keeps playing; unplayable rows hidden since v0.1.33); Silo Android #789 (audio sink output) has no Roku equivalent.
- **v0.1.36** Silo Android #790 (temporary password: every call but `account/me`, the password capability, the change and sign-out answers 403 `password_change_required`; the picker says where to change it, Sign out focused, Retry kept; other screens get the same plain text from `Http_problem`). Lessons: nothing new about devices; a problem whose detail is a protocol instruction is rewritten once in `Http_problem` (Task side) so every screen's `Api_errorText`/`Api_reasonText` shows it, and the pure check lives in a file both threads include (`PasswordChange.brs`). Silo's own Roku app already showed a message (sroku `loadErrorKey`). Device check pending: the message wrap at 1080p.
- **v0.1.37** Silo Android #796 (library grids stop sending `group=box_set`; the server drops it from the catalog group enum and answers 422). Lessons: nothing new about devices; a server can withdraw a query value a client already ships, so a browse parameter tied to one server feature is worth a mock that refuses it (the mock now answers 422 to `group=box_set`). Box set page, search box sets and the movie page row are unchanged.
- **v0.1.38** Silo Android #722 (Calendar movies on their first home release carry `digital` / `physical` badges: DIGITAL / PHYSICAL pills) and #798 (an X beside the search field while it holds text; OK clears, focuses the field and opens the KeyboardDialog). Lessons: nothing new about devices; a control that disappears when its job is done (the X once the query is empty) must hand focus back before it hides, as Android moves focus first; `debugScreen=CalendarPage` draws the page but keys go elsewhere in the simulator, so reach the Calendar through the shell (Right x5, OK, then Down twice into the rows, Up/Down between days). Device checks pending: DIGITAL / PHYSICAL pill widths at 1080p and the X's focus look beside the field.
- **v0.1.39** Silo Android #795 (several accounts per server, Change Account; registry layout 2 with an offline migration that reads back before deleting, adapted from Silo-Server/silo-roku 1dd2d6c), #802 (series return as a screen result via `Nav_close(result)`), #803 (progress rows keep focus by series). Lessons: one source of truth for "which account" (`Session_save` → `Accounts_assign`); every sign-in is a new identity matched only on the server user id; write stash → session → clean around a switch; ignore a second `authExpired` from requests already in flight; `t.camelKey = x` stores lower-case keys, so build result AAs with quoted literals; a loopback URL literal fails package_check even inside `#if DEBUG`; simulator timing is too loose for cache/menu races (host-test them). Device checks pending: migration with real JWTs (16 KB registry), the "finished" series return, the stale-menu close.
- **v0.1.40** Silo Android #810 / silo-roku 77e5932 (several accounts from one phone session: TXT acct=1 and lim=6, limit_reached past lim or when the registry could not keep every account the session signed in, a per-session binding sent only to https servers whose capability says session_binding, the first account's picker with Change account over it) and #813 (the Home marquee's text title waits 0.7 s for a loading logo). Lessons: nothing new about devices; check a registry-dependent limit by running the save code as a quiet what-if, keep secrets that need roEVPDigest in LanTask and hand them over in the event, and open a screen over the `@start` target with a param, not a second navigateTo. Device checks pending: the phone's multi-account card against a Roku, binding on a real HTTPS server, the marquee grace with slow logos.
- **v0.1.41** Silo card overlays (adapted from Silo-Server/silo-roku e8244ee; Android TV draws them too) and Silo Android #708 (audiobook session renewal). Lessons: draw badge art once per distinct look in a Task (`OverlayArtTask`, two Posters per card, focus must rest 1.5 s) instead of building nodes per card; in brs-engine a Task field set several times in a burst arrives only partly, so send requests through a numbered queue the Task acknowledges; observe `m.global` only with `observeFieldScoped` added on show and removed on hide; brs-engine ignores alpha when copying bitmaps (translucent fills look black in the simulator only); wide-card badges use scale 1 like silo-roku (Android TV's 1.4 overlapped on 202 px cards); the audio start route in the mock is separate (`audiobook_session=start_fail`), and the paused-expiry path is host-tested only. Device checks pending: scroll frame rate with badges, alpha/corners at 1080p, WebP uploaded images, renewal with sound.
- **v0.1.42** Silo Android #792 (remove a failed request that delivered nothing: `remove_failed_supported`, a confirmation naming the title with Keep first, DELETE `/api/v2/requests/{id}`; 404 drops the row too, 409 `conflict` re-reads and says why, an uncertain answer is settled by the re-read) and #822 (a series page auto-translates the shown season and shows "Translating description…" on its pending episode cards, then "Translated by AI"). Lessons: nothing new about devices; a page-level poll is a one-shot Timer paused while covered, and a list read already in flight must not bring back a row the page just removed (`m.removedIds`). The mock's `detail` shadowing came back a third time (v0.1.41's audiobook branch broke every catalog item read); `tests/test_mock_shadowing.py` now fails on any local named like a module function the same function calls. Device checks pending: the dialog's first focus, the card line at 1080p.
- **v0.1.43** Live AI subtitle lines (the user's request, past Android TV: Silo's web player shows the `subtitle_translation_*` events the server streams to the playback control socket `silo.playback-control.v2`). Lessons: a Task's built-in `state` field cannot be redeclared (`AddReplace … Type mismatch`): name socket status fields otherwise (`socketState`); brs-engine 2.6 has a real `roWebSocket` (Node helper process), so the simulator exercises the control socket end to end against the mock, but its `roRegex.ReplaceAll` has no `\1` backreferences (Roku has them): parse with plain string scans; JSON int64 ids (job_id) are quoted before `ParseJson` (`AiLive_quoteIds`) so ids past 2^53 keep their digits; a Task that hands bursts of events to the render thread resends everything unacknowledged with an `ack` field back (`AiLiveTask`); the WebSocket accept GUID is `258EAFA5-E914-47DA-95CA-C5AB0DC85B11` (the mock had it wrong and node's `ws` said "Invalid Sec-WebSocket-Accept"). Device checks pending: Roku OS 16 live lines (timing, 1080p look, takeover by the saved track), an older OS falling back.
- **v0.1.44** Detail header length like Silo's `selectedMediaRuntimeMinutes`: the shown file's `versions[].duration` (seconds), else `runtime` (minutes); Silo sends 0 for either when unknown, so 0 hides it (`detailLengthSeconds`). Lesson: the mock's `curl` needs `Authorization: Bearer acc-…` and `X-Profile-Id`; mock `--switch no_runtime=1` serves runtime 0 with measured files.
