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
- Host tests: `python3 -m unittest discover -s tests`, and `python3 tools/package_check.py` after
  packaging (both run in CI with `trickplay_test.py`, `lan_vectors.py`, `bq_vectors.py`).
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
  rendition**. Silo's fMP4 HLS remux muxes the audio into the video segments, so every such
  `server_remux_hls` plan is silent on Roku, whatever the codec. Fragmented MP4 over plain HTTP
  (Silo's `server_remux_progressive`) does not play at all. MPEG-TS plays (H.264 transcodes,
  device-confirmed). On a server without `hls_copy_mpegts_v1` the HLS delivery is declared
  H.264/SDR/AAC-only and the player asks for another route once if a remux plan still arrives.
- Silo added `hls_copy_mpegts_v1` (2026-10-26): with it Siku declares H.264 + HEVC (Main 10 level
  5.1 from TS), AAC/AC3/E-AC3 probed with `"container": "ts"`, HDR10/HLG and no Dolby Vision on
  HLS, and keeps remux plans whose `segment_container` is `mpegts`. **Implemented, not verified on
  a Roku** by Siku: whether TS copies play with sound (and HEVC/HDR10 from TS) is still to be heard.
  Silo's official Roku app (Silo-Server/silo-roku, `docs/hardware-evidence.md`) reports a real
  `audioFormat` (aac_adts, ac3, eac3, also with HEVC and E-AC-3 JOC) for every TS copy on a TCL Roku
  TV and an Ultra, `none` for every fMP4 one, and an HDR10 TS copy PASS on the Ultra; its testers
  could not listen either. Its DV 8.1 TS remux showed a green picture, and it now claims DV profile 5
  only (Siku's direct-play profile 8 is untested on a DV TV; keep it until a device says otherwise).
  Copy remuxes have open-ended timelines, so far seeks are `seek_reanchor` replans
  (`PlayerSeekReanchor.brs`) when the server lists `seek_reanchor_v1`.
- Dolby Vision is declared as profiles 5 and 8 only (never 7, whatever the Profile 7 fallback
  setting says) and without `dolby_vision_profile_levels` (any bound makes the server refuse DV
  on files scanned without a level and with unknown bitrate).
- A Roku app cannot switch HDMI audio passthrough on. The OS decides from *Settings › Audio*
  and the TV/receiver's EDID; Siku only reports what `CanDecodeAudio` says (re-probed at every
  start, lower-case quoted keys). The *Force Dolby Audio Passthrough* setting overrides the
  report for AC3/E-AC3 and announces itself on screen; on a stereo-only sink it yields direct play
  with no sound, which is the TV's doing.
- `playback.max_bitrate_kbps` is nullable: Maximum Bitrate "No limit" PUTs `null` at
  `profile_device`; deleting the row let a profile-scope 6 Mbps cap force 720p transcodes. There
  is no Original quality any more (Silo Android #613): a saved `original` reads as Auto and a
  video request never sends `"original"` (older servers take it as "never convert").
- Direct play of a non-default audio track needs the `client_selected_audio_track_v1` claim;
  Dolby Vision profile 8 on a non-DV output needs `client_dv8_base_layer_fallback_v1`. Both are
  declared on `original_http`.
- Subtitles: the server picks none on its own; Siku resolves the profile's Off/Auto/Always choice
  client-side (`Subs_autoChoice`, a port of Android's `AutoSubtitleResolver`). Roku renders only
  SRT/WebVTT sidecars; PGS/VobSub/ASS are listed as unavailable.

## Working in parallel
- Several agents can work at once in separate `git worktree`s. Give each its own mock port
  (`python3 tools/mock_server.py --port 81xx` and `debugPort=81xx` in the deep link); the
  simulator registry is shared, so seed state with deep-link parameters. Merge one branch at a
  time and re-run lint after each; shared files (`Settings.brs` key list, `tools/mock_server.py`
  options/OPTS, screen `onSettingsLoaded` hooks) are where merges collide.
- Kill a mock by anchored pid (`ps -eo pid,args | grep "^ *[0-9]* python3 tools/mock_server.py --port 81xx"`),
  never in the same shell command that started it.

## Releases
- **Every release is announced on Discord** with its plain-language notes and download links
  (the user's standing request). `release.yml` runs `tools/announce_discord.py` with the
  repository secret `DISCORD_WEBHOOK` (set by the user on 2026-11-09; `DISCORD_WEBHOOK_URL` is the
  old name, still read as a fallback). Do not also post by hand: check the release run's
  announce step instead, and run the script by hand only when that step failed or was skipped.
  Never commit, print or log the webhook URL: it is a secret, and Discord revokes webhooks found on GitHub.
- Pushes to `main` or a session branch listed in `.github/workflows/release.yml` publish a
  release when `build_version` changes. The notes are that version's `CHANGELOG.md` section, the
  full `CHANGELOG.md` is attached, and the README's feature table must say what is new and what
  still needs a device test.

## Diagnostics
- `telnet <roku-ip> 8085` is the device console. Every playback start and replan prints one
  `[siku-playback]` line: declared capabilities, the request (`quality`, `cap`, `audio_req`,
  `sub_req`, `op`), and the server's decision (`delivery`, `reason`, `sel_audio`, `sub_mode`,
  recipe, `seg` / `vse` (segment container, fMP4 sample entry), `tl_offset`, `seek_any`,
  `reanchor`, source, warnings, `active_q`, `learned_limit`, `sub_hls`; the caps show `tscopy`,
  `tsvideo`, `tsaudio`; the request also shows `est` and `ll` for buffering quality).
  `seek reanchor target= reason=` / `seek reanchored target= origin= same_route=` /
  `seek reanchor failed` trace a seek the server re-anchored. Player errors print
  `[siku-playback] video error …`, each recovery `recovery <n> …`, and the shown error
  `error #<n> …` (numbers: `docs/playback-errors.md`). Other lines: `subtitle auto:` (the track chosen automatically), `ai subtitle session not found (404); sending again without it` (Silo Android #726: AI jobs carry `session_id`; mock `--switch ai_session=missing`), `markers file=` (the playing file's
  markers), `hls subtitle rendition …` (selected or not found), `buffering replan …` / `buffering
  plan=…` (a lowering and each plan's stall summary), `speed test outcome=…`. `[siku-trickplay]`
  lines: the seek-preview manifest (geometry, sheet count, `expires_in`, renewals), a refused or
  unusable manifest, and sheets that failed to load (never the signed URLs).
- **Debug deep-link parameters (`debug*`) exist only in builds with `bs_const=DEBUG=true`**
  (v0.1.31): `tools/simulate.py` builds that way (`--release-flags` runs as a release build);
  `npm run package` and releases ignore them, and `tools/package_check.py` fails a release zip whose
  manifest is not `DEBUG=false` or that reads `args.debug*` outside `#if DEBUG`. Everything below
  that names a `debug…` parameter or a debug screen needs a DEBUG build sideloaded.
- v0.1.31's new console lines, mock switches and deep-link parameters (reconnect, sessions, stops,
  subtitle selection and loading, saved servers and sign-out, `[siku-deeplink]`, phone idle timeout,
  app exit, `[siku-calendar]`, `[siku-art]`, `[siku-requests]`, library filters, `[siku-diag]`, memory
  levels) are listed in `docs/diagnostics-v031.md`. Settings › Diagnostics shows the on-device log
  (`Diag_log`); after merging branches run `python3 tools/diag_log_convert.py` (tests/test_diag.py
  checks that new `print "[siku-…]` lines were converted).
- Require pairing (remote control) is **off by default** (the user's decision, v0.1.31); a saved
  value counts only when the person pressed the toggle (`sealedChosen`).
- Debug screens open with `curl -d '' "http://<roku-ip>:8060/launch/dev?debugScreen=<Name>"`
  (ECP needs POST): `StreamTestScreen` (plays reference HLS streams, the last Silo stream or
  `&debugUrl=`, logs `[siku-streamtest]` state and track counts), `FontTestScreen` (label and
  9-patch rendering). Simulator deep links: `debugSession=mock`, `debugScreen`, `debugItem`,
  `debugFile` (mock 4K files 52 and 56; 56 always remuxes), `debugUrl`, `debugHoldSeek=1`
  (PlayerScreen starts hold-to-seek as a held Right would; the simulator cannot hold keys),
  `debugVideoError=<code>` (fakes a Roku Video error on every plan), `debugStallSeconds=<n|off>`
  (the no-progress watchdog; `off` for long player runs in the simulator) and
  `debugDeepLink=<seconds>` (PlayerScreen: a content deep link for the playing item arrives after
  that long; MainScene prints `deep link replaces the player on top`). Stale answers print
  `[siku-playback] start answer dropped` / `replan answer dropped`; a replan that could not be sent
  `replan not sent kind=`; a player uncovered after it was closed `player shown again after it was
  closed; leaving`. The
  mock serves seek previews for file 42 (`--trickplay ok|off|refused|invalid|expiring`).
- `[siku-trailer]` lines trace a "Trailers & More" pick: a local extra's start, or the YouTube
  hand-off (installed check, `LaunchApp`, ECP status, outcome). `[siku-theme]` lines show the
  theme-music capability, grant (delivery, type, loop) and Audio errors; grant URLs are never printed.
- Phone features (`components/lan/`, `components/remote/`): `[siku-lan]` (sockets, sealed frames,
  mDNS bind steps/answers, send queues, Find servers: `discovery complete: N server(s)`,
  `found server identity ... matched=`), `[siku-cast]` (remote control: handoff, launch, commands, borrowed profile),
  `[siku-pair]` (phone sign-in). Keys, nonces and tokens are never printed. Also:
  `[siku-lan] signed out; closing remote control connections`, `address changed to <ip>` (the
  heartbeat re-reads the IP and re-announces), `phone sign-in cN sent nothing in 30 s; closing`;
  `[siku-cast] signed out on the phone's profile; ending it and signing the TV out` and `the TV's
  own session changed; ending the borrowed profile`. The mock prints `LOGOUT session=handoff|debug|login`. `tools/silo_phone.py`
  acts as Silo's phone app against the simulator; `tools/lan_vectors.py` checks the crypto and
  framing against the phone's own test vectors.
- Handoff address (Silo Android #716, `components/remote/HandoffAddress.brs`): with the phone's
  deployment identity the Roku probes its own saved addresses for that server, the phone's address
  and up to 6 offered `serverEndpoints` at once (GET `/api/v2/system/identity`, 6 s each, 8 s in all)
  and runs the handoff at the first, in that order, reporting the same identity:
  `[siku-cast] full handoff: checking N address(es)`, then `handoff address own|phone|endpoint (tried N)`,
  `handoff address none (tried N)` (nothing answered: "This TV can't reach …") or `handoff address
  refused: another server answered at the phone's address`. An offer without an identity prints
  `handoff address phone (tried 0)`. Plain-HTTP addresses other than the phone's are probed only at
  an origin this Roku saved. Own identity (#717): `reading the server identity (none recorded)`, then
  `recorded server identity` or `server identity not recorded (<state> status=N); trying again at
  the next start`. Mock: `--also-port 8182` serves the same deployment at a second address;
  `--switch port_<N>=down|slow|other|none` makes one address unreachable, slow, another deployment
  or identity-less, `no_identity=1` every port (log: `IDENTITY port= answer=`, `HANDOFF <method>
  <path> port=`). Simulator: `debugNoServerId=1` seeds the mock session without an identity,
  `debugServers=reset` forgets other worktrees' remembered servers. Phone tool: `cast --endpoint URL`
  (repeatable), `--expect-refused`, `--expect-identity ID`.
- `[siku-launch]` lines show the launch beacons (`beacon AppLaunchComplete`, `ready: home`);
  `[siku-memory]` lines show a memory warning (`pressure`) and screens that `released` /
  `restored` pictures; `[siku-a11y] say:` appears with `debugA11y=1` (forces speech in the
  simulator). `debugMemory=<pct>` replays a memory warning once a second screen opens.
- `[siku-voice]` lines trace Roku voice transport commands ("pause", "fast forward", "seek back 30
  seconds"): `transport events enabled=true|false|unsupported` once at start, then one
  `command=<cmd> [direction= duration=] screen=<top screen> result=<status> [target=<s>] [reason=]`
  per command (`reason`: `loading`, `replanning`, `reanchoring`, `recovering`, `error_shown`,
  `closing`, `state_<video state>`, `unsupported`, `no_duration`; `screen=<name>+dialog` when a
  dialog covers it). The simulator receives no voice events: `debugVoice=<command>[:<seconds>]`
  (`seek:-30` seeks back) injects one through MainScene 8 s after the player's first plan.
  The player panel (Info / Video / Audio / Subtitles tabs and rows) and its pickers speak with
  `debugA11y=1` like the rest of the app (`[siku-a11y] say: Video, tab, 2 of 4`).
- `[siku-home]` lines trace the Home cache (instant start): `cache hit age=Ns sections= bytes=`,
  `cache miss reason=none|corrupt|owner|schema|size|unreadable|unsupported|empty`, `cache stale
  reason=stale|future`, `cache drawn rows=`, `cache dropped reason=session|server-first`, `cache write
  sections= bytes=` / `cache write failed|skipped reason=`, `cache purge reason=sign-out|server|account|profile
  files=` and `refresh failed status=…, keeping the drawn rows`. No URLs, ids or tokens. Simulator:
  brs-cli keeps `cachefs:` in memory only, so `debugRelaunch=<seconds>` rebuilds the start screen once
  in the same run (a "second launch"); pair it with `tools/mock_server.py --home-delay <seconds>` to see
  Home drawn from the cache before the server answers.
- Home and library rows (Silo Android #688, `SectionRows.brs`): `[siku-home] section item limit
  max=<n|none|failed status=N> sending=<n|none>` once per server (GET `/api/v2/home/capabilities`,
  3 s; `read timed out; sending none` when the 20 s render-thread backstop fires, then `answer
  arrived late; ignored`), `item_limit rejected by the server; reading the rows again without it` (a 422
  `unknown_parameter` retry) and `explore all scope=home|library row=<n>` (an "Explore all" card
  opened the row's page, LibraryScreen section `section`). Mock: `--switch item_limit=present|off|reject|slow|fail`
  (default present; off = an older server that refuses the parameter, reject = advertised but refused,
  slow = 30 s capability read, fail = 500) and `item_limit_max=<n>`; the mock log prints `HOME CAPS
  item_limit=`, `SECTIONS <path> item_limit=<n|->` and `SECTION CATALOG scope= library= <id>` (404 for
  an unknown row). "Recently Added in Movies" carries 24 cards without `item_limit`.
- `[siku-auth]` lines trace token refreshes (AuthTask): `refresh ok`, `refresh failed status= code=
  attempt=` (kept session, retried with back-off), `refresh gave up, keeping the session`, `refresh
  skipped` (the same token failed moments ago), `refresh rejected status= code=` (400/401: the only
  answer that signs the user out) and `refresh answer dropped` (the session changed meanwhile). No
  tokens. Mock: `--switch refresh_status=502|401|html` with `--switch reject_access=1` (every
  authenticated request answers 401 until a refresh succeeds); the speed-test endpoints refuse the
  Kids profile without its `X-Profile-Token` (mock log `PROBE ... token=yes|no`).
- Mock failure switches for browsing (`--switch` or `POST /mock/switch`): `seasons_fail=1` /
  `episodes_fail=1` (a series page's seasons or episodes answer 500: the Retry button), `more_fail=1`
  (a catalog or notifications page after the first answers 500: Library backs off, Notifications
  waits for Retry). The mock's series `play_content_id` is the first episode not marked watched.
- Card menu Mark as Watched / Unwatched (Home, For You, Library) waits for the server: a refused
  write rolls the card back, toasts "Couldn't mark as watched. <reason>" and prints
  `[siku-cards] watched write failed status=<n> current=true|false` (`false`: a newer write for that
  card decides, no rollback). Mock: `--switch watched_fail=<code>` (a problem with a detail, default
  409) or `watched_fail=bare` (a 500 with no body: "Try again.").
- Episode parent artwork (Silo #711): mock `--switch parent_artwork=1` adds `series_backdrop_url`,
  `series_poster_url`, `season_poster_url` (+ thumbhashes) to episodes; `--switch episode_stills=1`
  makes an episode's own backdrop/poster its still (flagged, as many real servers send);
  `--switch hide_episode_images=1` turns spoiler protection on by default. With all three an unwatched
  episode's Home hero and detail hero show the series backdrop; without `parent_artwork` they go dark.
- More Like This chain (Silo Android #737, `Nav_chainAction` in `Nav.brs`): a rail pick prints
  `[siku-detail] more like this pick action=push|replace|back|ignore`. A rail-opened DetailScreen carries
  `chainStartId`; the first pick pushes, later picks replace, the start title closes back to it, the title on
  screen (or a second OK while the page is leaving) does nothing.
- Calendar movie badges (Silo Android #722): `CalFmt_badgeLabels` names `digital` / `physical` DIGITAL and
  PHYSICAL; the mock's `/api/v2/calendar` adds a movie with each (start day +1 and +3). Search's clear
  button (Silo Android #798, `clearBtn`, focus area `clear`): Right from the field while it holds text, OK
  prints `[siku-search] cleared; keyboard opened`; with `debugA11y=1` it says `Clear search, button` and the
  field `Search, text field`.
- Search's "Available to request" row leaves out titles the server marks `availability: "available"`
  (Silo Android #773, `Req_withoutLibraryTitles`) and hides itself when every match is in the library.
  Simulator: `debugScreen=SearchScreen,debugQuery=<text>` (mock: "Northern" is in the library,
  "Starfall" is requestable).
- v0.1.33 (subtitles from the stream: `hls_subtitle_renditions_all_v1`, `native_embedded_limitations_v1`
  `mkv/<container_track_id>`, unplayable rows; the card focus look in `CardFocus.brs`/`FocusText.brs`;
  movie box sets `[siku-boxsets]` and mock `--switch box_sets=1`; copy-remux re-anchor lead-in and the
  `start check` / `start seek` lines) is listed in `docs/diagnostics-v033.md`. On very large copy
  remuxes behind a proxy Silo's Roku app saw lead-in reanchors open at the stream's start (lands a few
  seconds early); Siku ships the lead-in like it does.
- Requests is a profile-menu row after History while `/requests/status` enables it, not a top-bar tab
  (Silo Android #782, silo-roku 5b296d7); Up from the Requests page focuses the avatar; a page left open
  when requests turn off prints `[siku-requests] requests turned off; closing the page` and shows Home.
- Temporary passwords (Silo Android #790, `PasswordChange.brs`): a 403 `password_change_required` on the
  profile list prints `[siku-auth] password change required: profiles refused (403); showing where to change it`
  (the picker shows "Your password needs to be reset. Use the Silo mobile app or website …" with Retry,
  Change server and Sign out, Sign out focused); `[siku-auth] account says password_change_required=true` when
  the picker read `account/me`. Every other screen's error text for that problem comes from `Http_problem`.
  Mock: `--switch password_change_required=1` (everything but `account/me`, the password capability, the
  change and sign-out answers 403; log `PASSWORD_CHANGE_REQUIRED 403 <method> <path>`); clear it with
  `curl -X POST -d '{"password_change_required": null}' localhost:<port>/mock/switch`, then Retry shows the profiles.
- Accounts (Silo Android #795, `Accounts.brs`, `ChangeAccountScreen`; registry layout 2: `session` + `accountId`,
  `servers` [{url,name,id}], `accounts` [{id,url,userid,username,profiles,maxprofiles?,added,used,expired,session?}], at most 12 / 9000
  bytes, LRU accounts lose their stored sign-in first): `[siku-accounts] migration layout=1->2 accounts= active= servers=`
  (or `migration failed: … did not read back; layout 1 kept`), `added an account on this server (accounts=N)`, `switched
  account=signed_in|sign_in_again|none profile=kept|ask|none accounts_on_server=N`, `signed out of an account; accounts left
  on this server=N`, `session expired; the account stays, needing to sign in again`, `signed in again as a saved account;
  ending the session it replaces`, `change account shown servers= accounts= root=`, `registry budget: …`. Simulator:
  `debugAccounts=reset|two|legacy`. Mock: `--switch multi_user=1` (each username its own user id) and
  `--switch device_user=<name>` (code sign-ins approved as that user); log `SIGNIN password|device user= id=`.
- Series return (Silo Android #802, `SeriesReturn.brs`): `[siku-playback] series return recorded episode=<s>x<e>
  reason=finished|on_screen|shuffle` / `not recorded (no series or another identity)`; the series page `[siku-detail] series
  return episode= reason=`, `loads season <n>`, `selected episode=`, `… not in season <n>; using next-up`; elsewhere
  `series return ignored`. Home focus by show (#803, `RowFocus.brs`): `[siku-home] refresh kept focus on the show's next
  episode row= item=`, `[siku-cards] card menu closed: its card changed in a refresh`; mock `--switch cw_advance=1`.
- Several accounts from one phone session (Silo Android #810, silo-roku #38, `PairSession.brs`):
  `[siku-pair] accepting a phone (state setup); advertising acct=1 lim=6`, `push N accepted (accounts so
  far K)` / `push N limit_reached (lim=6 accounts=6)` / `push N limit_reached (registry room)` (one more
  would cost an account this session signed in its stored sign-in) / `push N auth_failed` (the session is
  ending), `binding sent=yes` / `binding sent=no reason=http|capability_unread|no_session_binding`,
  `the server refused the session binding` (403 `device_binding_mismatch`), `signed in (accounts this
  session N)`, `session ended with N account(s)`, `N accounts signed in: the first one's profiles with
  Change Account over them`, `receiver stopped; Change Account no longer due`. Console only (the
  diagnostics converter leaves `[siku-pair]` out); never the binding, codes or tokens. Mock: `--switch
  device_manual=1` + `tools/silo_phone.py pair --approve --account laura --account sam` (each approved
  as its user; log `DEVICE APPROVE user=`), `--expect-limit`, `--switch session_binding=1` (`DEVICE START
  binding=yes|no`, `DEVICE POLL binding=ok|mismatch|none`; the mock is plain HTTP, so no binding is sent
  to it), `binding_mismatch=1`. Home marquee (Silo Android #813): the text title waits up to 0.7 s for
  a loading logo (`logoGraceTimer` in HomeSkylineFeed).
- Card overlays (Silo's profile badges; adapted from silo-roku e8244ee; `Overlays.brs`, `CardOverlay*.brs`,
  `OverlayArtTask`/`OverlayDraw.brs`): `[siku-overlays] config source=server|builtin enabled= preset= badges= images=
  profile_doc=yes|no profile_enabled=on|off|unset` (or `config read failed status=N; keeping what applies`), `art drawn= hits=
  files= shared= sprites=<hits>/<misses> dropped= failed= queued=` per batch, `image kept|download failed status=|could not
  be kept|unreadable`, `drawing failed:`. Settings `ui.card_overlays` / `ui.card_overlays_enabled` (source `profile` only) +
  GET `/api/v2/settings/overlay-config`. Mock: `--switch card_overlays=1|<preset>|rails|combined|off|404|500` (default off),
  `overlay_profile=<preset>`, `overlay_profile_enabled=0|1`, `overlay_images=1|missing`; log `OVERLAY CONFIG`, `OVERLAY IMAGE`.
  The simulator draws translucent fills opaque (brs-engine ignores bitmap alpha); `scratchpad/pngfix.py` opens its PNGs.
- Audiobook session expiry (Silo Android #708, `AudioSessionRecovery.brs`): `[siku-audio] session expired on the server
  (progress 404|play|voice play); starting a fresh one at <s> s (renewal N)`, `… while paused; a fresh one starts on Play at
  <s> s`, `session expired again; not renewing after 3 renewals`, `the server ended this playback session; not starting
  another` (410 `playback_session_ended`: Close only), `retry at <s> s`, `retry refused: …`, `play ignored: …`. Mock
  `--switch audiobook_session=expire|expire_v1|ended|other_404|start_fail` (audiobook sessions only; log `AUDIOBOOK SESSION
  <kind> sid=`, `AUDIO START file= start_position= persistence=`).
- Remove a failed request (Silo Android #792, `Req_isRemovableFailure` / `Req_removeOutcome` in `Requests.brs`):
  RequestsPage's * menu offers "Remove request" on a failed request with no completed target while
  `/requests/status` says `remove_failed_supported`; a StandardMessageDialog (Keep request first) confirms, then
  `DELETE /api/v2/requests/{id}`. Console: `[siku-requests] remove asked id=`, `remove kept`, `removed id=<id>
  outcome=removed|gone|conflict|uncertain|failed status=N`, and after an uncertain answer's re-read `removed id=<id>
  confirmed by the re-read` / `unconfirmed (still listed|the re-read failed)`. Mock: Laura's r-7 (removable) and r-8
  (1080p delivered, no Remove); `--switch request_remove=off|conflict|gone|fail` (log `REQUESTS REMOVE id= mode= answer=`).
- Season description translation (Silo Android #822, `EpisodeTranslation.brs`): a series page in the profile's
  `auto` on-view mode (GET `/api/v2/capabilities/metadata-ai`) starts the shown season's job once per (season,
  language) when its episodes report `pending_translation_language` (POST `/catalog/items/<season>/translate-description`),
  re-reads the episodes on a 1-5 s backoff (about 45 s) and shows "Translating description…" on each card still
  pending, then "Translated by AI". `[siku-detail] translation capability on_view=`, `translation started season=
  lang=`, `translation poll <n> season= pending=`, `translation done season= after <n> re-reads`, `translation gave up`,
  `translation failed season= status= job=`, `translation deferred season=`. Mock: `--switch season_translation=run|stuck|fail`
  (+ `translation_seconds=<n>`, default 12; Orbital S1's odd episodes; log `METADATA TRANSLATE`, `EPISODES translation=`).
- Live AI subtitle lines (v0.1.43, past Android TV; `AiLiveCues.brs`, `AiLive.brs`, `AiLiveTask`): on Translate with AI the
  player reads GET `/api/v2/playback/sessions/control/capabilities`, mints POST `…/sessions/{sid}/control/ws-ticket`, opens
  `…/control/ws` (`silo.playback-control.v2`, ticket as the second subprotocol; hello advertises no commands) and only then
  sends the job (6 s bound), draws `subtitle_translation_cues` in `aiLiveGroup` and hands over to the stored track the poll
  adopts. `[siku-playback] ai live socket open|failed reason=<unsupported|ticket|open_timeout|error|protocol|timeout>|closed
  reason=`, `ai live started cues=N`, `ai live cues +N done/total` (first batch, then every 10 s), `ai live completed|failed`.
  Never the ticket. Mock: `--switch ai_live=1|off|fail` (log `AI LIVE ticket|socket|started|cues|done|failed`); brs-cli has
  a real roWebSocket, so the simulator runs the whole path.
- Detail running time (v0.1.44, `detailLengthSeconds` in DetailScreen): the shown file's measured `duration`, else
  `runtime` minutes; 0 means unknown and hides it. Mock `--switch no_runtime=1` (runtime 0, files keep their duration).
- Interface languages (v0.1.45, `Tx`/`TxF`/`TxP`/`TxKey` and `I18n_*` in `Utils.brs`): text is keyed by its English;
  `locale/<es|de|fr|pt_BR>/strings.json` are built by `python3 tools/i18n_build.py` from Silo's catalogs in
  `third_party/silo-translations/` plus Siku's own `i18n/siku/<lang>.json` (`--check` fails on stale files or untranslated
  text; `i18n/missing.json` lists gaps). Server text: `TxKey("@home.section.*"|"error.*")`. MainScene prints
  `[siku-i18n]` lines when it loads a language. Language: profile `ui.app_language` (mock: settings revision 28), else the
  device locale; DEBUG builds take `debugLang=<tag>` (e.g. `de`). After adding user-visible text, rerun the build tool.
- Change Account at launch and the profile menu's profile row (Silo Android #880/#881/#883; adapted from silo-roku
  4a22785 / 431c1f1): a launch that asks (Every Time, a lapsed timer) with two or more saved accounts shows Change
  Account in the picker's place (`ProfileLaunch_startScreen`; params `root` + `chooseAccount`; the CURRENT account then
  opens like any other): `[siku-accounts] launch asks: change_account|picker (accounts=N link_waiting=)`, `launch choice:
  the open account`. A held content link keeps the picker route. The menu's row follows the open account's cached
  `profiles` / `maxprofiles` (`Accounts_profileMenuRow`; refreshed by ShellScreen each time a profile opens):
  `[siku-profiles] menu row=switch_profile|add_profile|none profiles=<n|unknown> max=<n|unknown> handoff=`. Add Profile
  opens `NewProfileScreen` (primary profile's PIN first): `[siku-profiles] add profile: asking the primary profile's PIN`,
  `form shown`, `PIN cancelled`, `no primary profile; showing the picker`, `create sent child= pin=`, `create outcome=
  created|unconfirmed|verify|refused|failed status=` (never the name or PIN). Mock: `--switch max_profiles=<n>|none`
  (default 6), `profiles=1`, `primary_pin=1` (log `PROFILE CREATE as= token= child= pin= answer=`). Roku has no
  background, so "return from the background" is not ported; the simulator cannot type in the form's keyboard.
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
