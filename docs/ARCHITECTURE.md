# Siku architecture

Siku is a Roku SceneGraph channel written in BrightScript. It ports the Silo **Android TV** client (the `androidTvApp` module, not the phone app), so it should look and behave the same. Phone-only features are out of scope, and so are downloads and any offline/local-storage features. Read these first:

- [`design-spec.md`](design-spec.md): colors, type, spacing, focus, and every screen's layout. Pixel values are for the 1920×1080 canvas.
- [`api-spec.md`](api-spec.md): the Silo `/api/v2` endpoints, with example JSON.

## Conventions

- **Canvas:** 1920×1080 (`ui_resolutions=fhd`). All coordinates are in pixels.
- **License header:** every new file starts with an `SPDX-License-Identifier: AGPL-3.0-or-later` comment.
- **No inline scripts:** each component's XML points at a sibling `.brs` file through `<script uri=...>`. BrighterScript can't validate inline `CDATA` scripts.
- **Reserved names:** don't use `run`, `pos`, `left`, `right`, `mid`, `str`, `len` or `type` as identifiers.
- **Lint before you finish:** `npx bsc --project bsconfig.json` must report 0 errors.
- **Fonts:** Inter, at `pkg:/fonts/Inter-{regular,medium,semibold,bold,black}.otf`. To convert Android sp to pixels, multiply by 1.72; to convert dp, multiply by 2.
- **Colors:** use `0xRRGGBBAA` strings. Use the tokens in `Theme().colors` (`components/common/Theme.brs`).
- **Rounded shapes:** draw them as a `Poster` with a white 9-patch tinted by `blendColor`.
  - Fills: `pkg:/images/ui/r{R}.9.png`.
  - Rings: `r{R}_ring2.9.png` and `r{R}_ring4.9.png`.
  - Available radii R: 6, 8, 12, 14, 16, 20, 22, 26, 28, 30, 32, 38, 40, 42.
  - For a capsule, use R = height/2, choosing the closest available radius at or below it.
  - Circles: `circle.png` and `circle_ring.png`.
- **Icons:** white 96 px PNGs at `pkg:/images/icons/<name>.png`. Tint them with `blendColor`. The available names are listed in `scripts/make_icons.py`. To add an icon, add it to that script's `ICONS` map and re-render. The font is in the scratchpad; otherwise ask the lead.
- **Masks:** `images/ui/mask_poster.png`, `mask_landscape.png`, `mask_circle.png` and `mask_square.png`, for `MaskGroup`.
- **Scrims:** `images/ui/scrim_bottom.png`, `scrim_top.png`, `scrim_left.png`, `scrim_bottom_player.png` and `mask_backdrop.png`.
- **Focus idiom:**
  - Buttons, tabs, menu rows and pills invert to a solid `#EDEDED` fill with black text and icons.
  - Media cards scale to 1.10 and show a 4 px `#EDEDED` ring and glow. `MediaCardItem` does this for you.

## Files

```
source/main.brs                 creates the screen, forwards deep links (roInput)
components/MainScene.*          screen stack, Back, startup routing, global state, toasts
components/BaseScreen.*         base component every screen extends
components/common/
  Theme.brs     design tokens, ThemeFont(weight, px), Sp(sp)
  Utils.brs     Registry_*, Str_*, Num_or, Time_*, Arr_or, AA_get, AA_copy, Device_info, App_version, Node_find
  Session.brs   Session_* (tokens, profile, servers), Url_normalize/origin/host/resolve, Prefs_*
  Api.brs       Api_get / Api_send / Api_call / Api_result / Api_fire / Api_cancelAll / Api_errorText
  Content.brs   Content_cardNode / Content_rows / Content_grid / Content_metaLine / Library_mode
  Nav.brs       Nav_push / Nav_replace / Nav_reset / Nav_close / Nav_play
  Shuffle.brs   Shuffle_* (capability cache, start, scope label) for /api/v2/shuffles
  Tracks.brs    Tracks_* labels and ids for file versions, audio and subtitle tracks
  SeriesChoice.brs SeriesChoice_* audio/subtitle picks remembered for a whole series (or movie): the
                /api/v2/subtitle-prefs and audio-prefs write queue and the unsent-pick overlay
  Settings.brs  Settings_* server-synced settings (effective cascade read/write, typed getters, Home row layout)
  Trailers.brs  Trailer_* "Trailers & More" entries (local extras, then YouTube videos; TrailerRail.kt)
  ThemeMusic.brs ThemeMusic_* opt-in detail-page theme music (capability, playback grant, Audio node)
  Spoilers.brs  Spoilers_* spoiler protection for unwatched episodes (hidden stills and overviews; any component may include it)
  Artwork.brs   Artwork_* per-slot artwork widths when GET /api/v2/images/capabilities lists slot_width_params
  ProfileLaunch.brs  ProfileLaunch_* the Profile Selection setting (who's watching at launch, the new-Roku remember offer)
components/tasks/
  ApiTask       one HTTP request (Task); JSON in and out; 401 → refresh → retry
  ProbeTask     the connection speed test (bandwidth probe download, timed; results POSTed)
  AuthTask      long-lived single-flight token refresher (rotating refresh tokens)
  YouTubeLaunchTask  hands a YouTube trailer to the YouTube channel (837): roAppManager.LaunchApp, then ECP
  Http.brs      roUrlTransfer wrapper and Silo device headers
components/lan/                 the LAN side of Silo's phone app (see "Phone features" below)
  LanTask       one long-lived Task: TCP listeners, frames, sealed level, heartbeats, mDNS responder
  LanBytes.brs  byte helpers (hex slices, base32/base64url, frames, server ids, Lan_isTrue)
  SiloSealed.brs level `sealed` (HKDF, AES-128-CBC, HMAC-SHA256); Task-only (crypto objects)
  Mdns.brs      DNS message parsing/building for the responder (pure)
components/remote/
  RemoteControl the SiloCast receiver's decisions on the render thread (MainScene child)
  RemotePrefs.brs Remote Control settings and helpers (RemoteControl_*, RemoteState_*)
  PhonePairing.brs phone sign-in for the server and sign-in screens (Pair_*)
components/widgets/             reusable UI: MediaCardItem, PillButton, Toast, LoadingSpinner, PairingPanel, …
components/screens/             one folder or file pair per screen
components/screens/debug/       developer diagnostics opened by deep link: StreamTestScreen, FontTestScreen
components/player/
  PlayerScreen.*   the video player: start/replan pipeline, HUD, pickers, recovery, progress
  PlaybackCaps.brs what this Roku can play, as the v3 capability payload; the [siku-playback] line
  SubtitleSuite.brs sidecar tracks, auto choice (Subs_autoChoice), search/AI/sync tools
  BufferingQuality.brs the buffering-quality controller (pure BrightScript, explicit clock);
                   tools/bq_vectors.py replays the server's conformance vectors against it
  PlayerBuffering.brs the player's side of it: Video events in, quality_change replans and the
                   "Playback keeps buffering" / "Quality lowered" pill out, request fields
  Trickplay.brs    seek-preview manifest validation and the time-to-tile mapping (pure BrightScript;
                   tools/trickplay_test.py runs its cases in brs-cli)
  PlayerTrickplay.brs the player's seek previews: manifest reads and renewal, the clipped sheet
                   Posters (bounded pool), the card over the scrubber and the hold-seek frame
  PlayerHoldSeek.brs hold Left/Right with the controls hidden: rate ladder, indicator, OK seeks
  PlayerScrubber.* seek bar with the buffered-ahead segment (reports the puck's x as `puckX`)
  PlayerRemote.brs the player's side of remote control (state every second, remoteCommand)
  PlaybackRecovery.brs Recovery_* the native-error ladder (failure_recovery on a Video error or
                   no progress, Auto 1080p/720p/480p descent), attempted_plan_keys/attempt_count,
                   the empty-inventory re-read
  PlaybackErrors.brs PlaybackError_* numbered errors (docs/playback-errors.md) and the optional
                   route-event report
docs/upstream/                  requests written for the Silo server team (Roku HLS audio packaging)
```

`BaseScreen.xml` already includes `Theme.brs`, `Utils.brs`, `Api.brs`, `Nav.brs`, `Content.brs` and `Session.brs`, so screens that extend it get all of those helpers. A widget that needs a helper adds the `<script uri>` itself.

## Screens

A screen is `<component name="XScreen" extends="BaseScreen">` (`components/BaseScreen.xml`).

**Inputs:**
- `m.top.params`: an associative array set by whoever opened the screen.
- `onScreenShown()`: called each time the screen becomes the top screen. Define it to take focus, e.g. `m.someButton.setFocus(true)`, and to refresh data if needed.
- `onScreenHidden()`: called when the screen is covered or closed.
- `onChildResult(result)`: called when a screen above closes after setting `m.top.result`.

**Navigation:**
- `Nav_push("DetailScreen", { itemId: "movie:heat-1995" })` opens a screen on top.
- `Nav_replace(...)` swaps the current screen.
- `Nav_reset(...)` clears the stack.
- `Nav_reset("@start")` re-runs startup routing (at app launch, the Profile Selection rule in
  `ProfileLaunch.brs` may first clear the saved profile so Who's watching shows):
  - no server → `ServerConnectScreen`
  - no token → `LoginScreen`
  - no profile → `ProfileScreen`
  - otherwise → `ShellScreen`
- `Nav_close(result)` closes this screen.
- `Nav_play({ itemId, ... })` opens the player.

**Back:** return `false` from `onKeyEvent` for `"back"` and MainScene pops the screen; at the root, it exits the app. Return `true` if you handled Back yourself, for example by closing a panel.

**Screen names** (MainScene creates them by name):

| Screen | Params |
|---|---|
| `ServerConnectScreen` | none |
| `LoginScreen` | none |
| `ProfileScreen` | `{ switching: bool }` |
| `ShellScreen` | none. Top bar and root tabs: Home, Movies, Series, Music, Audiobooks, For You, Calendar, Requests (only when `GET /api/v2/requests/status` enables it; page `RequestsPage`). Libraries listed in the profile's `ui.disabled_library_ids` setting are left out of the tabs and panels (`Settings_withoutHiddenLibraries`), re-filtered whenever the settings snapshot lands. A mixed library appears under both Movies and Series; its pages get `mediaType` (`movie`/`series`): Recommended (`HomePage`) filters each shelf to that type and refills short shelves from `GET /api/v2/catalog?source=section`, Browse and collections send `type`, and Shuffle is not offered there (a shuffle request carries no media type) |
| `LibraryScreen` | `{ libraryId, libraryName, mode, section: "browse"\|"collections"\|..., title, source?, collectionId? }` |
| `LibraryPage` (shell page) | `{ section, libraryId, libraryName, mode, mediaType?, ... }`. Sections: `browse`, `collections`, `alphabet` (A‑Z), `genres` (Music), `authors` / `series` (audiobook groups via `GET /api/v2/catalog/audiobook-groups`, drill-in through `POST /api/v2/catalog/query` with an `author`/`series` `is` rule), plus the personal lists. Browse and A‑Z show the right-edge `AlphabetRail` (`name_prefix`) |
| `DetailScreen` | `{ itemId, itemType?, libraryId? }`. Movie, series, season and episode. Zones: actions, season chips, episodes, Cast & Crew, Trailers & More, Related, Details. A local extra plays with `Nav_play({itemId, fileId, itemType: "extra", startPosition: 0})`; a YouTube video goes to `YouTubeLaunchTask`, and when YouTube can't be opened a `YouTubeHandoffDialog` shows the watch URL and a QR code. Theme music plays while the page is on top (`ui.theme_music_enabled`) |
| `PersonScreen` | `{ personId, name? }` |
| `SearchScreen` | `{ query? }` |
| `RequestDetailScreen` | `{ mediaType: "movie"\|"series", tmdbId, title? }`. A TMDB title to request (or its request's status), with Cancel Request for the user's own pending request. Request administration (approve, decline, retry) stays in web admin, as on Android TV |
| `SettingsScreen` | none. Android TV `TvSettingsScreen`: rail (account, General / Playback / Subtitles / Server, Sign Out) and a pane of grouped rows. Values are the server's effective settings (`Settings.brs`) with the device prefs as fallback; the Home Sections editor (`SettingsHomeSections.brs`) is a full-screen overlay |
| `ConnectPhoneScreen` | none. Profile menu › Connect a Phone (a Siku addition; Silo's phone app sends Roku users there): the pairing link's QR code, the pairing code, Remote Control on/off, Require pairing on/off, New pairing code, Disconnect phones |
| `NotificationsScreen` | none. Notifications inbox (Android TV `TvInboxScreen`): Mark all read card, newest-first delivery cards, OK marks read and opens the series/episode, pages of 25. Android TV has no route to it, so Siku has no entry point either (deep link `debugScreen=NotificationsScreen`) |
| `PlayerScreen` | `{ itemId, fileId?, startPosition?, title?, audioTrackId?/audioTrackIndex?, subtitleTrackId?/subtitleTrackIndex? (-1 = off), shuffleId?, shuffle?, itemType?/source? ("extra"), durationSeconds? }`. With `shuffleId` the player runs a shuffle session: picks start at 0, Up Next shows the server's random pick with Pick Another / Stop shuffling. An extra plays alone (no next episode, Up Next or On Deck) and starts by its file id when it has no watch detail. Up Next shows the next episode's still under a scrim and an On Deck row (home continue-watching items) |
| `AudioDetailScreen` | `{ itemId, itemType }` for `album`, `artist`, `audiobook`, `track`. Use `Nav_openItem(id, type)`, which picks this or `DetailScreen` |
| `AudioPlayerScreen` | Music `{ queue: [{contentId, fileId?, title?, artist?, album?, posterUrl?, durationSeconds?}], index?, startPosition?, shuffle? }`; audiobook `{ itemId, startPosition? }` (whole-book seconds). `Nav_play` routes audio types here |

Music: the Silo v2 contract has no album/artist/track types yet, and Android TV keeps music minimal. `AudioDetailScreen` reads a provisional shape (`tracks[]` on albums, `albums[]` on artists) that only `tools/mock_server.py` serves today. Audiobooks use the real contract.

## Global state (`m.global`)

| Field | Contents |
|---|---|
| `session` | `{serverUrl, serverOrigin, serverId, serverName, accessToken, refreshToken, expiresAt, user, profileId, profileToken, profileName, profileAvatar, deviceId}`. Never mutate it in place: edit a copy, then call `Session_save(copy)`. |
| `prefs` | Device-local settings (`Prefs_load`, `Prefs_save`), including `profileLaunch` / `profileLaunchOffer` (Profile Selection). Library Browse sort and filters are saved separately in the registry under `browsePrefs.<server>.<profile>.<library>[.type-<mediaType>]`. |
| `lanTask` / `remoteControl` | The LanTask and RemoteControl nodes (phone features). Screens reach them through `RemotePrefs.brs` helpers. |
| `castPlayer` | The PlayerScreen that remote control drives (it registers itself), or invalid. |
| `imageCaps` | `{serverUrl, slots}`: the image capability probe for the active server (`Artwork_storeCaps`); `slots` maps an artwork slot to its width parameter. |
| `toast` | Set a string to show a toast, e.g. `m.global.toast = "Added to Watchlist"`. |
| `authExpired` | Set by the network layer. MainScene then signs out and routes to the login screen. |
| `staleProfile` | Set by `ApiTask` on 403 `profile_verification_required` with the profile id/token the request sent (household-management calls excepted). If that is still the active profile, MainScene clears the profile selection (keeping the sign-in) and opens `ProfileScreen`; it waits while the player or the sign-in/server screens are on top. |
| `homeDirty` | Set to `true` after playback or after watched/favorite/watchlist changes, so Home and the details reload on show. |
| `shuffleCaps` | Cached `GET /api/v2/shuffles/capabilities` keyed by server+profile (`Shuffle_refreshCaps` / `Shuffle_supports`). Shuffle entry points are hidden until it says available. |
| `keyReleaseSeen` | Set once a key release reached a card list; arms the long-OK-press card menu (`LongPress_*` in Utils.brs). |
| `requests` | `{enabled, resolved}`: the media-requests gate, set by `ShellScreen` from `/api/v2/requests/status`. Read it with `Req_gate()` (`components/common/Requests.brs`). Siku never calls `/api/v2/admin/requests*`. |
| `lastStream` | `{url, format, headers, label}` of the stream the player mounted last; `StreamTestScreen` replays it with its auth headers. |
| `playbackCaps` | Cached `GET /api/v2/playback/capabilities` for the server (installation id, protocol versions, deliveries). |
| `settings` | `{ready, available, identity, revision, manifestRevision, items: {key: {value, source, scope, ...}}, error}`: the server's effective settings for the active server + profile (`Settings_load`, called by `ShellScreen` per profile and by `SettingsScreen` on open and after every write). Read values through `Settings_*` getters (`Settings_quality`, `Settings_introSkipMode`, `Settings_autoPlayNext`, ...) or `Theme_cardPresentation` / `Theme_showTitleArt`; they fall back to `prefs` until the server answers. `Session_save` resets it when the server or profile changes. A component that calls `Settings_load` declares a boolean `settingsLoaded` field (alwaysNotify) to be told when the snapshot landed. |

## Calling the API

Siku uses the Silo **v2 API only** (`/api/v2/...`). `ApiTask` refuses any `path` outside `/api/v2/`. Never call `/api/v1` or the root `/health` route.


```brightscript
Api_get("/api/v2/home/sections", { image_size: "medium" }, "onHome")

sub onHome(event as object)
    resp = Api_result(event)   ' {ok, status, data, error:{code,title,detail}, context}
    if not resp.ok then
        showError(Api_errorText(resp))
        return
    end if
    sections = resp.data.sections
end sub
```

- `Api_send("POST", path, body, "cb")` sends a request with a JSON body.
- `Api_call({method, path, query, body, auth:false, profile:false, baseUrl, timeout, context}, "cb")` is the full form.
- `Api_fire("PUT", "/api/v2/watchlist/" + id)` sends a request and ignores the result.
- All IDs are opaque strings. Escape them in paths with `Str_urlEncode(id)`; content IDs contain `:`.
- Image URLs come ready-made from the API. Pass them through `Url_resolve(url)` and don't add auth.
- Call `Api_cancelAll()` in `onScreenHidden` only when the screen is being destroyed. Screens covered by another screen stay alive.

## Lists and cards

- Rows of media use a `RowList` with:
  - `itemComponentName="MediaCardItem"`
  - `drawFocusFeedback="false"`
  - `rowFocusAnimationStyle="fixedFocus"`, which pins focus at the row start like Android TV
- Build the content with `Content_rows([{ id, title, style: "poster"|"landscape", items: [card...] }])`.
- Grids use a `MarkupGrid` with `itemComponentName="MediaCardItem"`. MarkupGrid clips to its bounds, so grid cells carry an inset (`Content_grid(cards, style, insetX, insetY)` → `cardInsetX/Y` on the node) and the grid starts that much left of / above the first card.
- Card styles: `poster` (2:3), `landscape` (16:9), `circle` (people) and `square` (1:1: audiobooks, albums, audiobook groups; `initials` on the node draws a lettered placeholder when there is no image).
- Row titles in `HomeSkylineFeed` are drawn by the feed itself (RowList's own label is transparent): RowList sizes its label to the row's content width, so a one-card row would truncate its title.
- Item sizes:

  | Card | Image | Item height (with captions) |
  |---|---|---|
  | poster | 176×264 | about 264+90 |
  | landscape | 360×203 | about 203+90 |
  | grid poster | 236×354 | about 354+90 |

- `node.raw` holds the original API object for the card, so read `contentId`, `itemType` and `raw` when the user selects it.

## Playback

The pipeline (`components/player/PlayerScreen.brs`, `startPipeline`):

1. `GET /api/v2/watch/{id}` (versions, user_data, markers, effective subtitle prefs) and
   `GET /api/v2/playback/capabilities` (cached on `m.global.playbackCaps`).
2. `POST /api/v2/playback/start` with `PlaybackCaps_startBody`: `client_capabilities` (codec
   lists, detailed `video_decode[]` with profiles, levels, bit depths and frame sizes from
   `CanDecodeVideo`, `hdr_details` from `GetDisplayProperties`, audio lists from `CanDecodeAudio`
   decode/passthrough/channel probes) and `client_playback_context` (device, output, and the
   `deliveries` the Roku can execute). The deliveries are declared per kind in
   `PlaybackCaps_delivery`: `original_http` (the file itself; claims
   `client_dv8_base_layer_fallback_v1` and `client_selected_audio_track_v1`), `hls` and, behind an
   experimental setting, `progressive` (fails on device; kept for other models). `hls` has two
   lanes. When the server's capabilities list `hls_copy_mpegts_v1` and `server_remux_hls`, Siku
   puts `hls_copy_mpegts_v1` in `deliveries.hls.features` and declares H.264, HEVC (only if
   Main 10 level 5.1 decodes from `"container": "ts"`), AAC/AC3/E-AC3 probed from TS, HDR10/HLG
   and no Dolby Vision profiles: remuxes then come as MPEG-TS (`effective_recipe.segment_container:
   "mpegts"`, no `video_sample_entry`), which Roku reads audio from (implemented, not yet
   device-verified). Otherwise `hls` is declared H.264 / SDR / AAC+MP3 only, because Silo's
   fMP4 HLS remux muxes the audio into the video segments, which Roku plays silent.
   `quality_preference` and `bandwidth_cap_kbps` come from the Resolution and Maximum Bitrate
   settings (a saved "original" is Auto; "original" is never sent for video; No limit sends no
   cap). The player's Quality menu is Auto plus the plan's `available_qualities` without the
   source entry, with the row the server reports in `active_quality` checked.
3. The plan is handed to the Video node by `applyPlan`: stream URL and format, auth headers,
   `PlayStart` from the timeline, sidecar subtitle tracks (`Subs_buildTrack`, SRT/WebVTT only), and
   the default subtitle (`Subs_autoChoice`: the profile's language and Off/Auto/Always as Android TV
   resolves them, after an explicit pick from the details page). On `original_http` the server's
   `selected_tracks.audio.index` is applied to `availableAudioTracks` when playback starts.
4. An fMP4 `server_remux_hls` plan is started and then `maybeRecoverSilentRemux` asks for another
   route once (`failure_recovery`, classification `unsupported_container`); the server answers with
   an H.264 MPEG-TS transcode, which has sound. An MPEG-TS remux is kept. A copy remux's timeline
   is open-ended (`can_seek_anywhere: false`, no `seek_window_end_seconds`): when the server lists
   `seek_reanchor_v1`, a seek outside what the mounted stream provably holds (origin to the furthest
   downloaded segment) is a `seek_reanchor` replan and the returned plan is mounted at the target
   (`PlayerSeekReanchor.brs`, used by `seekToSource`, so skips, the scrubber, hold-seek, markers,
   chapters and phone remote seeks all go through it). A remux can carry the selected embedded
   text subtitle as an HLS rendition (`hls_remux_subtitle_renditions_v1`), like a transcode.
5. A viewer's audio or subtitle pick (player menus, detail-page selectors) is saved for the whole
   series or movie (`SeriesChoice.brs`); the next start follows the server's effective fields
   (`Subs_autoChoice` selects the track `effective_subtitle_track_signature` names). A replan that
   lands on another version is adopted as the playing file; its subtitle is carried by identity,
   and a version without it plays with subtitles Off, which is not saved or carried as a choice.
6. Replans (`sendReplan(operation, kind)`): `quality_change` from the Quality picker,
   `track_change` from the Audio picker (server-side track list when the stream exposes one or
   none), `output_change` from the HDR / Dolby Vision HUD toggles, `failure_recovery` as above.
   `onReplan` swaps the plan at the current position and rebuilds the HUD.
7. Progress (`/progress`, sequenced), markers (Skip Intro / credits), Up Next and the final
   `DELETE /playback/{session}` follow the Android TV player's behaviour. Markers are the playing
   file's own (`/watch/{id}?file_id=`), read again after every start and when a replan lands on
   another file. A 410 `playback_session_ended` answer to progress or a replan means an
   administrator ended the session: the player says so in a toast and closes without a DELETE.
8. Buffering quality (`BufferingQuality.brs` + `PlayerBuffering.brs`, Silo Android #636): two
   counted stalls in two minutes, or one of 6 s, after a 10 s start-up grace, lower Auto with a
   `quality_change` replan carrying `bandwidth_estimate_kbps` = delivered × 7 / 10 (and, when the
   server lists `buffering_quality_v1`, `bandwidth_estimate_source: observed_rebuffer`,
   `observed_throughput_kbps`), then offer "Restore quality" (`learned_limit: clear`) for 15 s;
   Ask first and picked qualities prompt instead. Settings → Playback shows the mode, the server's
   learned limit (Reset) and the Connection speed test.
9. A transcode may carry the selected embedded text subtitle as a WebVTT rendition of its own HLS
   stream (`hls_subtitle_renditions_v1`); the player selects it on the Video node or asks for the
   sidecar plan (`failure_recovery`, `subtitle_hls_rendition_failed`).

9. Seek previews (`PlayerTrickplay.brs`, Silo Android #695): after every start and replan the
   player binds to the streamed file; if its version says `trickplay_available`, it reads
   `GET /api/v2/watch/{id}/trickplay?file_id=` and validates it (`Trickplay_fromManifest`). While
   the focused scrubber scrubs, a 340 px card over the puck shows the thumbnail (320x180) and the
   time; during a hidden-controls hold seek (`PlayerHoldSeek.brs`) a 480x270 frame sits above the
   rate chip. Roku cannot crop an image, so the whole sheet is drawn in a Poster inside a Group
   with `clippingRect` (the window) and offset to the tile; a MaskGroup rounds the corners. Up to
   three sheets are held (decoded at most 2048 px on a side), the next sheet is prefetched, and the
   Posters are emptied when the file changes or the player closes. URLs are renewed a minute
   before `expires_at`, and once per sheet after a failed load; a refused or invalid manifest
   keeps the time-only preview. Roku's own trick-play thumbnails (BIF on the content node, or HLS
   image playlists) do not apply: the Video node's trick-play UI is off (`enableUI=false`, our own
   HUD) and Silo publishes JPEG sprite sheets, not BIF.

10. Native failures (`PlaybackRecovery.brs`): a Video node error, or no position movement for
   60 s (120 s before the plan first played), sends `failure_recovery` (`decoder_failure`,
   `network_error`, `drm_failure` or `buffering_timeout`) with the same request, then, under
   Auto only, with an advertised 1080p, 720p, 480p rung below what failed; then a numbered error.
   Every replan carries the attempt's `attempted_plan_keys` (≤ 16) and `attempt_count` (failure
   recoveries so far, 1..8). Every failure the player shows has a number (`#3001 … (Roku -5)`,
   `docs/playback-errors.md`); a server listing `playback_route_diagnostics` gets one route event
   per terminal failure (3 s, no retry, allowlisted diagnostics only).

Every start and replan prints one `[siku-playback]` line to the device console; see `CLAUDE.md`
"Diagnostics" for the fields. The device facts behind these choices are in the skill's pitfalls
13 and 14 and in `docs/upstream/silo-server-roku-hls-audio.md`.

## Phone features: sign-in from the phone and remote control (SiloCast)

Silo's Android phone app (silo-android 115263c / aea6120 / 7c4db67) treats a Roku as its own kind
of TV: plain TCP instead of TLS (a Roku listening socket has no TLS), its own DNS-SD types, and a
pairing link in a QR code for networks where discovery fails. Siku implements the Roku's side.
The wire is the phone's: 4-byte big-endian length + UTF-8 JSON per frame, at most 1 MiB.

**Threads.** `LanTask` (a Task, so `roStreamSocket`, `roDatagramSocket`, `roMessagePort`/`Wait`,
`roEVPCipher`, `roHMAC`, `roEVPDigest` stay off the render thread) owns every socket and all
crypto. It talks to the render thread through fields: `config` and `command` in, `castEvent`,
`pairEvent`, `status`, `pairingInfo` out, `castState` in (the player's state, fanned out).
`RemoteControl` (a MainScene child) makes the decisions that need the app: handoff, launch,
control, the borrowed identity. Screens use `PhonePairing.brs`.

**Phone sign-in (`_silopair-roku._tcp`, port 52819, protocol v1).** Advertised only while
`ServerConnectScreen` (TXT `st=setup`) or `LoginScreen` (TXT `st=login`, `srv=<server identity>`)
is up; TXT also carries `v=1`, `name`, `id`, `sid`. One phone at a time. Siku sends
`hello {tvName, tvDeviceId, state, supportedVersions:[1]}`; the phone sends `pushServer
{serverURL, serverName, serverIdentity?, endpoints?}` (one server: a Roku keeps one), Siku asks
"Allow this setup?" (also for every plain-HTTP address), then
- setup: `GET {pushed}/api/v2/system/identity` must answer the pushed identity (another identity
  is `identity_mismatch`; unreachable offers a verified alternate endpoint, never takes it),
  `POST /api/v2/auth/device/start` there, `deviceStarted {serverURL, userCode, matchCode}`,
  poll, save server + tokens, `serverResult {status: signedIn}`, then the phone's `done` routes on;
- login: the pushed identity must equal `srv`; Siku sends the code the sign-in screen already
  shows and relays that screen's outcome.
Failures answer `serverResult {status: failed, error: denied|expired|unreachable|identity_mismatch|update_required|auth_failed}`.
Tokens never cross the LAN; the server gives them to the Roku over HTTPS after the phone approves.

**Remote control (`_silocast-roku._tcp`, port 52817..52821, protocol v2).** TXT: `v=2`, `id`,
`deviceId`, `name`, `server` (base64url of the server URL, the phone's registry key), `serverName`,
`serverIdentity`, `playing=0|1`, `sec=plain|sealed`, `kid` (sealed). Up to six controllers.
- Level `sealed` (Remote Control › Require pairing, default on): the phone's first frame is a
  plain `sealed_hello {keyId, nonce}`; a wrong key gets a plain `close {reason: unauthorized}`.
  Siku answers its own `sealed_hello`, both derive enc/mac/iv keys (HKDF-SHA256 over phone nonce
  || TV nonce), and every later frame is `seq(8) || iv(16) || AES-128-CBC || HMAC-SHA256 tag`.
  Siku's IV is AES-ECB(ivKey, direction || seq || 0…), so no RNG is needed per frame. A frame that
  does not open closes the connection. The 16-byte pairing key is generated in the Task (hashed
  GetRandomUUID output; Roku documents no CSPRNG for channels), kept in the registry
  (`lanPairingKey`), shown on Connect a Phone in base32 groups of four and in the QR link
  `silo://cast?v=2&host&port&id&name&server&security=sealed&key=<base32>`.
- Siku's `hello` lists features `multi_controller, close_reason, resume_token, presence,
  volume_mute_only, no_playback_speed`. A controller is authorized when its hello's server
  matches (same URL-derived id, or same deployment identity) and Siku is signed in; ping every
  3 s, more than three misses drops it; 5 s to say hello.
- `handoff_offer`: the profile Siku plays as gets `handoff_ready {reused: true}` at once; another
  profile (or server) takes the remote-playback handoff: `device/start {client_purpose:
  remote_playback, temporary: true}` at the phone's server, `handoff_challenge`, the phone
  approves, poll, `handoff_ready` (+ `resumeToken`). The approved session is published on
  `m.global.session` with `temporary: true`, which `Session_save` never writes to the registry;
  it is handed back (logout, own session restored) 5 s after the phone leaves with nothing
  playing, or after 10 minutes idle, or when its refresh fails.
- `launch`: needs a ready handoff on that connection; opens PlayerScreen with the file id, the
  audio ordinal and the **combined subtitle ordinal** (a Roku launch carries the server's
  combined index, externals first; -1 is Off), start from the beginning or `resumePosition`.
- `control`: play, pause, play_pause, seek, stop, select_audio_track / select_subtitle_track
  (track ids are the ordinals in Siku's state), set_muted (Video `mute`), set_volume (0 mutes),
  set_quality, play_next. Speed, picture size, subtitle position and sync answer `command_failed`.
- `state` once a second and on change, to every authorized controller: title, episode line,
  times, tracks, quality options, `isMuted`, next episode, and `posterUrl` (the series poster for
  an episode) and `overview` from the item detail.

**What a Roku may or may not allow** (researched; to be confirmed on a device):
- Listening TCP sockets: `roStreamSocket` `SetAddress`/`Listen`/`Accept` are public API in a
  Task. Expected to work on a sideloaded channel.
- mDNS: a channel can only be found by phones if it may bind UDP 5353 and join 224.0.0.251.
  Roku OS runs its own responder on models with AirPlay, so the bind may be refused or shared.
  Siku sets SO_REUSEADDR, tries, and logs `[siku-lan] mdns bind 5353 reuse= bound= joined=`.
  If it fails, `status.mdns` is `unavailable`, Connect a Phone says to scan the code, and the
  pairing link (host, port, key) still works because the phone dials it directly. Phone sign-in
  has no link fallback (the phone finds it only by discovery).
- Crypto: `roEVPCipher` (aes-128-cbc), `roHMAC` (sha256), `roEVPDigest` exist on every current
  Roku OS; their output is checked against the phone's vectors only in brs-engine.

**Testing.** `tools/lan_vectors.py` runs the BrightScript crypto, framing and mDNS code in brs-cli
against the phone's `SiloCastSealedTest` vectors and a Python reference (`tools/silo_lan.py`).
`tools/silo_phone.py` plays the phone: `browse` (mDNS), `pair` (sign-in; `--approve` with the
mock's `device_manual=1`), `cast` (plain or sealed via `--link`/`--key`; `--check-refusals`,
`--stop`). brs-cli supports listening and multicast sockets, so the whole flow runs against the
simulator, with one simulator bug: a socket assigned straight to `m.<name>` is disposed at once
(the listener closes), so LanTask keeps sockets one level down (`m.io.*`, `m.conns[id].sock`).
Console tags: `[siku-lan]` (listeners, connections, sealed handshake, hello, mDNS),
`[siku-cast]` (handoff, launch, commands, borrowed profile), `[siku-pair]` (phone sign-in).

