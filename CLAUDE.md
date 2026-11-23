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
- Pushes to the default branch publish a GitHub Release automatically when the manifest's version
  (`major_version.minor_version.build_version`) has no release yet. **Versioning (the user's decision,
  2026-11-12): every release adds 0.1**: raise `minor_version` by one and set `build_version=00000`
  (v0.1.47 was followed by v0.2.0, then v0.3.0, …). To ship a build: bump the version that way AND add a `## vX.Y.Z` section to
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
  release when the manifest version (raised by 0.1 each release, see above) changes. The notes are that version's `CHANGELOG.md` section, the
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
  an unknown row). "Recently Added in Movies" carries 24 cards without `item_limit`. A Continue Watching / In Progress / Next Up row whose
  `total_count` (≥ 1) is no more than the cards sent and which sent fewer than its limit (`item_limit`, at most 20) shows
  its whole list and ends without Explore all (Silo Android bb53e20d, silo-roku cfda7be; `SectionRows_showsWholeList`):
  `[siku-home] explore all left out row=<id>: the row shows its whole list`. The mock's Continue Watching and Next Up are such rows.
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
  GET `/api/v2/settings/overlay-config`. Layout follows Silo Android #882 (the web's, silo-server #2765): three corners and two
  rails (a stored top-right is the right rail; corners 3, rails 4), the poster's top-right is watch status whether or not badges
  are on (emerald check node in MediaCardItem, 22 at the 185 px reference and 8 in; episodes left drawn in the overlay image;
  landscape cards show neither), bottom corners share rows and wrap (`Ovl_bottomLayout`) and lift clear of the progress bar
  (`Ovl_bottomInset`: at least 28 px, the keyline bar's clearance, Silo Android #902 `WatchProgress.brs`; the bar is 8 px tall,
  20 px in, 16 px up, 8 px under a box set's film count; tests `tests/test_watch_progress.py`), text keeps the presets' letter spacing; host tests `tests/test_overlay_layout.py`. Scale (Silo Android #912, `CardOverlay_scale*` in
  `CardOverlayKeys.brs`): card scale × text factor; a poster's width / 185, a wide card's (landscape, episode still) Poster Size
  multiplier 0.86 / 1 / 1.2 (`m.global.cardPosterScale`, set by ShellScreen; in the image key and the request's `k`), text factor 1
  (Roku gives a channel no system text size); the episode rail's watched check (44 px 12 in) uses the wide scale, and so do the rail's cards themselves (`EpisodeRail_geometry`, Android TV `tvEpisodeCardWidth().cardScaled()`: 310 / 360 / 432 px wide, 16:9 stills, caption text, gaps and 40 px spacing unscaled; cell = headroom + still + 218, the sections below move; DetailScreen `layoutEpisodeRail` on page shown, settings loaded and `cardOverlaysRevision`, `[siku-detail] episode rail size`); a wide card's
  bottom inset never drops below its scale-1 size. Mock:
  `--switch card_overlays=1|<preset>[+rails|+corners|+combined]|off|404|500` (default off; on, it marks some titles watched and Orbital started),
  `overlay_profile=<preset>`, `overlay_profile_enabled=0|1`, `overlay_images=1|missing`; log `OVERLAY CONFIG`, `OVERLAY IMAGE`.
  The simulator draws translucent fills opaque (brs-engine ignores bitmap alpha); `scratchpad/pngfix.py` opens its PNGs.
- Audiobook session expiry (Silo Android #708, `AudioSessionRecovery.brs`): `[siku-audio] session expired on the server
  (progress 404|play|voice play); starting a fresh one at <s> s (renewal N)`, `… while paused; a fresh one starts on Play at
  <s> s`, `session expired again; not renewing after 3 renewals`, `the server ended this playback session
  (session_ended|paused_timeout); not starting another` (410 `playback_session_ended`: Close only), `retry at <s> s`, `retry refused: …`, `play ignored: …`. Mock
  `--switch audiobook_session=expire|expire_v1|ended|other_404|start_fail` (audiobook sessions only; log `AUDIOBOOK SESSION
  <kind> sid=`, `AUDIO START file= start_position= persistence=`).
- WAV audiobooks (Silo Android #707, `AudioCaps_wireNames`): a passing `pcm` probe is declared as `pcm_s16le`, `pcm_s24le`
  (the server matches ffprobe names; a bare `pcm` never matched). `[siku-audio] declared audio codecs=<list>` when the list
  changes. Mock `--switch audiobook_wav=1` (parts are WAV; log `AUDIO WAV file= codec= declared=yes|no`, "no" refuses the
  start). brs-cli answers no PCM, so the simulator shows the refusal; playback with sound needs a Roku.
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
  Transcription streams per ASR chunk: the server's default chunk is 600 s unless its `subtitle_ai.live_asr_chunk_seconds` is
  set (min 15), so first lines can take minutes. Progress names the job (`Subs_aiProgressTitle`); untagged audio sends `transcribe`
  (v0.1.47). Never the ticket. Mock: `--switch ai_live=1|off|fail` (log `AI LIVE ticket|socket|started|cues|done|failed`); brs-cli has
  a real roWebSocket, so the simulator runs the whole path.
  Lines on screen together stack bottom-up, earliest at the bottom, each keeping its line while it shows (Silo Android
  #862; `AiLive_stackOrder` / `AiLive_blockText`).
- Paused too long (Silo Android #1043, silo-roku #107; `PlaybackServerEnd.brs`, host tests `tests/test_paused_timeout.py`):
  every video start and replan sends the `paused_timeout_v1` client feature (`PlaybackCaps_clientFeatures`; audiobook and
  music starts take it out again in `AudioCaps_startBody`: the server times out only video). A session left paused past the
  administrator's limit then answers progress posts and replans with 410 `playback_session_paused_timeout`, handled like an
  administrator's 410 `playback_session_ended` on every path (progress, failure-recovery / quality / audio / output /
  subtitle / buffering / reconnect replans, seek reanchor, subtitle adoption): no stop DELETE, no renewal or new attempt,
  the player leaves and the screen it returns to toasts "Playback stopped because it was paused for too long."
  (`player.notice.pausedTimeout`; the admin end keeps "An administrator ended this playback session."). Console:
  `[siku-playback] the server ended this playback session reason=paused_timeout|session_ended via=progress|replan_<kind>|seek_reanchor|subtitle_adopt
  at <s> s paused=<bool>; leaving playback without a stop`. A media 404/410 goes through the failure-recovery replan, whose
  410 answer decides (silo-roku's separate end probe is not needed). Mock: `--switch paused_timeout=1|progress|replan`
  (log `PAUSED_TIMEOUT 410 <progress|replan> sid= advertised=yes|no`; a start without the feature gets `playback_session_ended`).
- Late stops (Silo Android #954/#955): a stop the server takes (2xx, `PlaybackJobs_isLanded`) sets `homeDirty` and bumps
  `m.global.playbackStopsLanded`; a DetailScreen on top that read before it (the player's 2.5 s `stopTimeout` ran out, or
  a retry delivered it) reads again: `[siku-detail] playback stop landed after the page read; reading again`. Mock:
  `--switch stop_fail=1` (the first DELETE answers 503, the retry 2 s later lands).
- Home watch state (Silo Android #1009, Silo's Roku app c1841ae / #102; `HomeWatch.brs` pure helpers, host tests
  `tests/test_home_watch.py`; `HomeLive.brs`, `HomeEventsTask`): HomePage (Home and library Recommended pages) reads again
  quietly every time it is shown again (back from a detail page, the player, another tab) and when a playback stop lands while
  it shows: `[siku-home] watch state refresh reason=return|stop_landed|changed|reconnect|poll|access_changed|queued page=home|library-home`,
  `watch state refresh queued reason= (a read is running)` (runs after it). A refresh that fails for a transient reason (no
  answer, 408, 429, 5xx) keeps the drawn rows and retries after 1, 2, 4 s while the page shows: `refresh incomplete: a row's
  read failed status=N; keeping the drawn rows`, `refresh retry <n>/3 in <d> s (list|row status=N)`, `refresh retries used up
  (…); keeping the drawn rows` (then the "Couldn't refresh Home" toast for a failed list). Home only, after its first server
  answer, own session only (no borrowed profile): POST `/api/v2/events/ws-ticket` (`silo.events.v2`, `expires_in` ≤ 30,
  `max_connection_seconds` ≤ 300), then `/api/v2/events/ws?channels=user_state` offering `silo.events.v2, silo.ticket.<t>`;
  a `user_state.changed` for this profile re-reads Home after 2 s (a progress-only burst at most every 30 s), nothing is patched
  from the frame (it names the change, not the value). `watch events connecting lifetime=<s> s`, `watch events subscribed
  channel=user_state catch_up=yes|no` (yes after a drop: one re-read), `watch state changed elsewhere change=<c> events=<n>;
  reading Home in <d> s`, `watch events closed reason=<r>; reconnecting now|in <d> s` (back-off 1-30 s; `max_age` and
  `access_changed` reconnect at once), `watch events ticket failed status=N; trying again in <d> s`, `watch events unavailable:
  <reason|ticket status=N>; reading Home every 120 s while it shows` (no roWebSocket before Roku OS 16, 403/404/405, rejected
  channel), `watch events stopped: Home is hidden`. Never the ticket or URL. Mock: `--switch home_events=on|off|404|fail|reject|nosub`,
  `events_lifetime=<s>`, `lazy_rows=1` (Hidden Gems read on its own), `section_items_fail=<n>`, `home_sections_fail=<n>`;
  `curl -X POST -d '{"content_id":"movie:paper-moons"}' localhost:<port>/mock/watch-elsewhere` (another device marks it
  watched: it leaves Continue Watching; `"watched": false`, `"change"`, `"profile_id"`, `"to_all": true`), `POST
  /mock/events/drop`; log `EVENTS ticket|socket open|subscribed|sent|dropped|closed`, `SECTION ITEMS <id> status=`.
- Detail pages from a card (Silo Android #971, `Nav_detailSeed` in `Nav.brs`): a movie or series card picked on Home, For
  You, Library, Search, a person page or More Like This passes `params.seed`; DetailScreen draws its title, facts, overview and
  artwork at once (Play reads "Loading…", disabled; other actions hidden; `m.item` stays invalid until the detail lands) and
  keeps the card's backdrop under the full-size one until it loads (`backdropHold`). `[siku-detail] drawn from the card type=
  backdrop= logo=`, `detail read failed; the card's copy is cleared`. Mock `--switch detail_delay=<s>`, `detail_fail=1`
  (log `DETAIL <id> delay=`). Audiobook pages are not seeded.
- Detail running time (v0.1.44, `detailLengthSeconds` in DetailScreen): the shown file's measured `duration`, else
  `runtime` minutes; 0 means unknown and hides it. Mock `--switch no_runtime=1` (runtime 0, files keep their duration).
- Interface languages (v0.1.45, `Tx`/`TxF`/`TxP`/`TxKey` and `I18n_*` in `Utils.brs`): text is keyed by its English;
  `locale/<lang>/strings.json` are built by `python3 tools/i18n_build.py` from Silo's catalogs in
  `third_party/silo-translations/` plus Siku's own `i18n/siku/<lang>.json` (`--check` fails on stale files or untranslated
  text; `i18n/missing.json` lists gaps). Server text: `TxKey("@home.section.*"|"error.*")`. MainScene prints
  `[siku-i18n]` lines when it loads a language. Language: profile `ui.app_language` (mock: `--settings-revision 28`), else the
  device locale; DEBUG builds take `debugLang=<tag>` (e.g. `de`). After adding user-visible text, rerun the build tool.
  Thirty languages: silo-roku 1cc1149 / 67f082b's seventeen (en es de fr pt_BR nl it pl tr sv da nb fi cs hr ru uk) plus
  the Latin/Cyrillic ones Silo Android added in catalog 2026.11.20-9403fbd (silo-android 63c898084: hu ro sk sl bg ca lt lv
  et vi pt_PT id ms; Android catalog only, silo-roku has none of them, `LANGS` maps them with a `None` Roku folder).
  `I18n_match`: "no" → nb, pt-PT → pt_PT (other Portuguese → pt_BR), legacy "in" → id and "iw" → he. When Silo's apps add
  catalog languages, Siku follows (the user's rule): copy the catalogs into `third_party/silo-translations`, add the folder
  to `LANGS` and `I18n_folders`/`I18n_nativeName` (and `I18n_tagOf`, `I18n_groupedCount`, `I18n_pluralCategory` when the
  language needs it), and translate `i18n/siku/<lang>.json`. Only scripts the fonts draw: `tools/subset_fonts.py` (Inter
  4.1, Latin + Latin Extended Additional for Vietnamese + Cyrillic; `tests/test_i18n.py` `Glyphs` fails on a character the
  fonts lack); Japanese, Korean, Chinese, Arabic, Greek, Hebrew, Hindi and Thai stay out. Plurals: `TxP` reads CLDR
  zero/two/few/many (and a `{0}` "one" for hr/ru/uk/sl/lt/lv, which covers 21, 31 or 101, …) as `"<English other>#few"` etc.
  (`PLURAL_FORMS` in the build tool, `I18n_pluralCategory`; id/ms/vi are "other" for every count, 1 too), so every count needs
  a literal `TxP("1 x", "{0} xs", n)` pair; Turkish capitals go through `I18n_upper` (server text keeps `UCase`).
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
- Still Watching (Silo Android #876, v0.2.0): `viewerInteracted()` in PlayerScreen resets `m.autoAdvances` on any viewer
  pause/play, skip, scrub/hold-seek commit, chapter, skip pill, voice or phone-remote pause/seek (`[siku-playback] still watching
  count reset (viewer)` when it was above 0); intro auto-skip and re-anchors do not.
- v0.3.0 (two reviews + profile management): `[siku-playback] replan queued|dequeued|answer dropped …` (`PlayerReplanFence.brs`; mock `--switch replan_delay=<s>`, `start_delay=<s>`), `unused session stopped reason=`, `ai live reconnect …` (mock `ai_live=drop`), `try again at N s file=`, `media refused status=N …` (`debugVideoError=auth[:N]`, mock `server_resume=<s>`), HUD panes scroll (mock `chapters=<n>`); `[siku-auth] logout outcome=` (`Api_revoke`, mock `stale_logout=1`), `refresh answer kept for …`; `[siku-accounts] forgot N account(s) on servers no longer saved`; `[siku-audio] stream error N; starting again once`, `part finished early`; `[siku-search] titles page …`, `people search media_scope supported=` (mock `search_hidden=1`, `people_scope=0|fail`); `[siku-profiles] manage mode …`, `edit: save|delete outcome=` (ProfileManage.brs, EditProfileScreen; `debugManage=1`, `debugProfileName=`; mock `policy_revision=1`, `profile_write=fail`, `profiles=<n>`); `[siku-diag] registry write failed key=`.
- Editions (Silo Android #899, silo-roku 7bb02a9; `Edition.brs`, host tests `tests/test_edition.py`): Edition picks the cut,
  Version Auto the best first-part file of that cut for `playback.preferred_quality`; the page opens on `last_edition_key`,
  then the edition of `last_file_id`, else by name first (Silo Android #996, silo-roku 3e7ee3a, silo-server #4511;
  `Edition_preference`, Android's exact match: trimmed, lower-cased key and raw name; unnamed, `standard`, `default`, `standard …`
  or `… standard`, then anything containing `theatrical`, then any other cut) and only the cuts of the best class present compare
  their Auto files (fit, resolution, HDR, then server order); Play sends the shown file unless it is the
  last-played Auto file. `[siku-detail] edition source=last_edition|last_file|best|pinned [class=standard|theatrical|other compared=<n>]
  editions= versions= quality= shown=` (once per decision; `class`/`compared` only with `best`), `edition picked versions= shown= (Version on Auto)`, `play file=sent|player reason=pinned|tracks|auto|last_played
  shown=`, `shown file changed; audio and subtitle picks back to Auto`. Mock: `--switch editions=1|lastfile|none|standard` (Iron Orchard,
  `movie:iron-orchard`: Theatrical 70/71, Director's Cut 72/73; `standard`: Extended Cut 74 2160p HDR / 75 listed first, Standard 76
  1080p, opens on Standard; log `EDITIONS detail`).
- Library sorts (Silo Android #843, silo-roku d4303e5; `CatalogSort.brs`, host tests `tests/test_catalog_sort.py`): the web
  client's list, names, order and default directions; a library lists the fields for its media (series add Latest Episode
  Added / Air Date), Favorites, Watchlist and collections leave out Progress / Date Viewed / Plays, the RT sorts only while
  GET `/api/v2/capabilities/ratings` lists `rt_critic` / `rt_audience` (`[siku-library] rating sources shown=` / `read failed
  status=`; cached per server and profile on `m.global.ratingSources`), and a restored sort stays listed. The panel shows 9
  rows and scrolls. Mock `--switch rating_sources=<a,b>|rt|off|fail` (log `RATINGS CAPS`, `CATALOG SORT <sort>`); DEBUG
  deep link `debugLibraryMode=<movies|series|mixed|audiobooks>` with `debugScreen=LibraryScreen,debugLibrary=<id>`.
- Rows of collections (silo-server #4410 / #4415; aligned with Silo Android TV db87f835f / #979, first adapted from silo-roku
  8183af8 / d240f47; `CollectionRows.brs`, host tests `tests/test_collection_rows.py`): a Home or library section of
  `section_type` `collection_posters` carries its cards in `collections` (`items` is `[]`); HomePage builds them with the
  Collections grid's card (`Content_collectionCard`: title, poster or collage, the collections mark when it has none), never reads
  the section's items, skips hide-watched and the mixed library filter, shows every card (at most 40, no 20-card cut), adds no
  Explore all, and keeps the row when the server flags it `featured` (never a hero). Each card is read on its own
  (`CollRows_cards`): a wrongly typed field (object/list for text, non-numeric or fractional `item_count`, a non-boolean
  `poster_is_collage`), an unknown `source`, or a server collection without `library_id` leaves that card out, never the row;
  content ids are `collection:<library|user>:<id>`. Caption (one line, `CollRows_caption`): "by {Name}" (read by catalog key,
  `TxKey("android.collections_posterCard_byOwner", {"0": name}, ...)`: "by {0}" is also the audiobook author line, worded
  differently in hr/cs/pl; `tools/i18n_build.py` writes such keys as `@android.<name>`) for a personal collection whose `creator_profile_id` is another profile than the active one
  and whose name the account's last profile list gave (`m.global.profileNames`, set by ProfileScreen and ShellScreen's
  per-profile refresh; no request of its own; unknown name = no byline), else the count, none on a Movies / Series scoped
  library page. Home shows a server collection only when `m.global.collectionLibraries` (ShellScreen: the tabs' libraries minus
  hidden ones and reading types ebook/book/comic/manga) is known and holds its library: none until the first library read of the
  profile succeeds, so an ebook library's never appears; personal ones always; a row left empty is dropped. HomePage watches both
  globals while shown (`observeFieldScoped`) and redraws the rows. OK opens LibraryScreen section `collection`
  (`CollRows_openParams`): from Home a server collection in its own library (name and mode from the map), a personal one without
  a library; on a scoped (Movies / Series of a mixed library) page that library and scope for both kinds; on an unscoped library
  page a server collection in that library, a personal one without one; a personal one reads `source=user_collection`. Every
  card drives the hero: title and its backdrop, else its poster (`tvMarqueeItem`), no meta line, badges or synopsis; a refresh
  redraws the hero from the focused card (new title / poster) and keeps focus by content id. Siku's hero has no thumbhash
  placeholder or neighbour warming for titles, so `backdrop_thumbhash` is only carried. No card menu (* or a long OK). The Home
  cache keeps the row without cards (drawn once the server answers). An empty collection's page says "This collection is empty"
  with Back (from a row; closes the page) or Back to collections (the grid's drill). `[siku-home] collection row=<id> cards=
  backdrops= empty= shared= held= explore_all=no` (held: server cards Home kept back), `collection hero first|focus
  art=backdrop|poster|none`, `rows of collections redrawn: libraries or profile names changed`, `collection card: no card menu`,
  `collection opened scope=home|library kind=library|user library= type=`; `[siku-library] empty collection back=page|collections`.
  Mock: `--switch collection_rows=1|first[+featured]` (third on Home or first; library 1, and 5 with `mixed_library`, first: Space
  Sagas with a backdrop, Night Noir, Coming Soon empty, Sam's Shelf shared by p-sam ("by Sam" for Laura), Broken Count / No
  Library / Unknown Source left out; on Home also Laura's Picks (hers: its count) and Book Club of the ebook library 6 "Books",
  never shown; log `COLLECTION ROW scope= cards= featured=`, `COLLECTION ITEMS source= id= library= type= n=`).
- Grouped counts (Silo Android #916, silo-roku ed824d3): `TxP(one, other, n, true)` puts the language's thousands separator
  in the count (`I18n_groupedCount`: "1,284", "1.284" de/pt_BR, narrow no-break space fr, Spanish from five digits, es_MX /
  fr_CA follow the device). Used for library and collection grid counts, collection cards and person title counts; years,
  episode numbers and other counts stay ungrouped. Host tests `tests/test_grouped_count.py`; mock `--switch big_library=<n>`
  / `person_works=<n>` with `debugLang=<tag>`.
- Early end (adapted from silo-roku f5078a0; Android TV retries a premature end of stream, MediaLoadRetryPolicy): a
  Video "finished" more than 8 s and 1.5% short of the plan's `source.duration_seconds` (`Recovery_endedEarly`) reconnects
  at the stop point through the dropped-connection path: `[siku-playback] ended early at <s> s of <d> s; resuming there`
  (then `connection lost code=early_end`, `reconnect 1 …`). A second early end within 10 s of that point
  (`Recovery_earlyEndAction`) is the end, but not finished: `ended early again at …; treating it as the end (not finished,
  no auto-play)`; Up Next opens without a countdown and the series page does not move on. Simulator cannot play: device only.
- Reconnect window renewal (Silo Android #993, `MediaLoadRetryPolicy`; `Recovery_openOutage` / `Recovery_holdOutage` /
  `Recovery_addProgress` / `Recovery_progressGain` in `PlaybackRecovery.brs`, host tests `RetryWindow` in
  `tests/test_playback_network.py`): a plan that plays again after a dropped connection holds the outage (its start and tries)
  instead of ending it; 20 s of steady playback (`Recovery_renewSeconds`, Android's `RECOVERY_INTERVAL_MS`; forward steps of at
  most 3 s per watchdog tick, so seeks and stalls count nothing) renew it, and a later drop gets a fresh 120 s. A drop before
  that continues the outage, so a connection that cuts out every few seconds still reaches the ladder after 2 minutes (until
  v0.13.0 any "playing" renewed it). A ladder step drops the held outage (another route). Console: `reconnected after <n> s
  tries=<k>; the reconnect window renews after 20 s of playback`, `reconnect window renewed after 20 s of playback; a later
  drop starts a fresh 120 s`, `connection lost again after <n> s of playback (under 20 s); continuing the outage from <s> s ago
  tries=<k> code=`. Android's byte counts (512 KiB) have no Roku equivalent; position progress stands in. Simulator cannot
  play: device only.
- Subtitle search gate (Silo Android #608, `Subs_probeProviders` / `Subs_providerSearchAfter` in `SubtitleSuite.brs`, host tests
  `tests/test_subtitle_providers.py`): each time the player panel's Subtitles tab shows, GET `/api/v2/subtitles/providers/status`
  (5 s: `timeout` and the `subsProviderTimer` budget); "Search subtitles" is listed only after an answer with `allowed` and
  `enabled` true and `state` `available` (hidden until the first answer, like Android TV). A failed, undecodable or timed-out probe
  keeps the last answer, else offers search; only the newest probe applies. `[siku-playback] subtitle providers search=yes|no
  source=answer state= allowed= enabled= providers=N|failed status=N|timeout [(kept the last answer)|(no earlier answer: offered)]`,
  `subtitle providers answer dropped: probe N, newest M [(after its 5 s budget)]`. Mock `--switch
  subtitle_providers=some|none|denied|fail|404|slow` (slow = "none" after 8 s; log `SUBTITLE PROVIDERS mode=`).
- Top bar menus (Silo Android #970): Siku opens a menu only on Down or OK (no dwell preview, so Android's 120 ms / at-once
  delays have nothing to tune), and Down on a tab whose menu Back just closed opens it again: `[siku-home] top bar menu opened
  kind=libs|sections|foryou|profile tab=<n> after_back=yes|no`.
- Scrubber marker bands (Silo Android #933/#934, adapted from silo-roku 42249ca; `Markers_bands` in `MarkerTimeline.brs`,
  host tests `tests/test_marker_timeline.py`): one band per intro / recap / credits / preview range, over the played fill and
  under the puck, in TheIntroDB's palette (intro #51A2FF, recap #FF8904, credits #C27AFF, preview #00D3F2) at 34% / 45%
  focused. `[siku-playback] marker bands intro= recap= credits= preview=`. Mock `--switch every_marker=1` (two intros, two
  credits, a recap and a preview against the plans' 3000 s; log `MARKERS file= every_marker`).
- Skip pill seeking (Silo Android #928): with the controls up and a Skip pill focused, Left/Right tap-skip (pill keeps focus)
  or hold-seek (`HoldSeek_pressOnPill`; the controls hide for the hold): `[siku-playback] skip pill seek dir=<-1|1>
  kind=tap|hold`. A focused pill that hides with the controls up hands focus to the scrubber. Hold needs a real Roku.
- Specials (Silo Android #929/#931, adapted from silo-roku a41d106; `Seasons.brs`, host tests `tests/test_seasons.py`):
  season 0 or a flagged `is_specials` season is listed first and labelled "Specials" (episode page More: "Go to Specials");
  a series opens on `play_season_number`, else a numbered season (in progress, partly watched, unwatched) before Specials:
  `[siku-detail] seasons listed= specials_first= opens=`. The player's next season never moves into a flagged Specials
  season. Mock `--switch specials=1|flagged` (Orbital: season 0 listed first, or season 99 flagged and listed last; log
  `SEASONS <id> specials=`). Show Series Info (#932/#936-#938) does not apply: Siku's hero never follows rail focus.
- Audiobook pages and player (Silo Android #975, tvOS layouts; `AudiobookFormat.brs`, `CoverPalette.brs`, host tests
  `tests/test_audiobook_format.py`, `tests/test_cover_palette.py`): the detail is an 860 px hero (cover, AUDIOBOOK · GENRE,
  the title without the series locator the server bakes in, gold series line, "by … · read by …", a progress ring with the
  chapter and time left) with Play / Resume / Play Again, Chapters (only with chapters; AudioPanel), Start Over (only while
  resuming), Favorite and Finished (the saved played flag; POST / DELETE `/api/v2/watched/{id}`, rolled back with the reason on
  refusal; a position near the end only makes Play read Play Again), then About (OK expands to 16 lines), Parts, More by Author.
  `[siku-detail] audiobook hero state=not_started|listening|finished played= resume= chapters= title_cleaned= series_line=`
  (when it changes), `audiobook finished write played=` / `… landed played= current=` / `… failed status= current=`,
  `audiobook chapters opened count= current=`, `audiobook about expanded=`, `audiobook action row scroll= focused= row=` (the
  row outgrew the hero; controls pushed past an edge are hidden). Player: `[siku-audio] cover palette mode=audiobook|music
  source=thumbhash|none accent=` (corner tints and accent from `poster_thumbhash`; music queues use the neutral palette); the
  cover backdrop drifts only while the Audio node plays (`driftAnim`, never in the simulator). Mock: books carry
  `poster_thumbhash`, `release_date` and `audiobook.series` (Orbit Cycle, Harbor Chronicles with `series_index`); A Wider Orbit's
  raw title is "Orbit Cycle 2 - A Wider Orbit (2 of 2)"; `played` follows `/api/v2/watched`; refuse it with `--switch watched_fail=409`.
- Collections a title is in (Silo Android #1007, silo-server #4528; `ItemCollections.brs`, host tests
  `tests/test_item_collections.py`): a movie or series page reads GET `/api/v2/catalog/search/capabilities` on every load
  and return, and only with `item_collections: true` GET `/api/v2/catalog/items/{id}/collections` (`library_id` when the page
  has one; body `{items, preview_items}`, both required). One collection with other titles: up to 6 of them under its name
  (reading titles left out) and an Explore all card; otherwise an "Also in" row of collection cards (the rows-of-collections
  card and caption, `CollRows_withCaptions`). Below Cast & Crew on a series page, below the box set row on a movie page.
  Server collections only from libraries this Roku shows (`m.global.collectionLibraries`, else the page reads
  `/user/libraries` itself); a preview left with no titles shows its collection's card under "Also in". A title opens without
  the page's library; a card or Explore all opens LibraryScreen section `collection` as a Home card does. Nothing while
  loading, when empty or after a failed first read; a failed refresh keeps the row. `[siku-detail] collections capability
  item_collections=true|false`, `collections row=preview titles=<n> explore_all=yes held=<n>` / `row=also_in cards=<n>
  held=<n>` / `row=none`, `collections read failed status=N; keeping the row` (also `capability read failed`, `library list
  read failed`), `collections wait for the library list`, `collections title opened`, `collections opened from=collection|explore
  kind=library|user library=`. Mock: `--switch item_collections=several|one|only|books|empty|fail|bad|caps_fail` (default off:
  an older server; log `ITEM COLLECTIONS <id> mode= library=`).
- Up Next timing (Silo Android #994, `NextUp_crossesPromptPoint` / `Markers_finalCreditsStart` in `MarkerTimeline.brs`, host
  tests `tests/test_marker_timeline.py`): the card opens when playback crosses the profile's Show Next Up point
  (`playback.next_up_prompt_seconds` before the end of the file, default 30; 0 = "At end": only when the stream ends); resuming
  or seeking past the point does not open it, the end still does. Credits markers drive only Skip Credits now. A card opened by
  hand gets no countdown at the point (the end arms it). Crossing the closing credits (the last credits range) still marks the
  episode finished for the series page. `[siku-playback] up next point crossed at <s> s (<n> s before the end)`, `up next point
  crossed with the card open by hand; no countdown until the end`, `closing credits reached at <s> s; the series page moves
  on`; the marker line now reads `credits ranges=<n> closing_at=<s>`. Simulator cannot play: device only.
- Slow-link claim on a buffering step-down (Silo Android #1011, `BQ_loweringFor` / `BQ_claimForRequest` in
  `BufferingQuality.brs`, host tests `tests/test_buffering_claim.py`): an Auto lowering still goes out on any counted stall,
  but `bandwidth_estimate_source: observed_rebuffer` (+ `observed_throughput_kbps`) only when the plan's measured throughput
  is below its delivered bitrate, only with the reading it rests on, and never on `server_transcode_hls` (Roku's
  `downloadedSegment` time includes the wait for the encoder, so a slow encoder or burn-in would read as a slow link);
  otherwise the estimate goes unsourced and the server does not learn it. `[siku-playback] buffering replan quality= est=
  source=observed_rebuffer|none [(no slow-link claim: no_evidence|no_reading|server_encodes|not_slow)] learned_limit= observed=`.
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
