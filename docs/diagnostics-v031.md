<!-- SPDX-License-Identifier: AGPL-3.0-or-later -->
# Diagnostics added in v0.1.31

Console lines (`telnet <roku-ip> 8085`), mock switches and simulator deep-link parameters added by v0.1.31. CLAUDE.md links here.

## Network, reconnect, progress

- Dropped connections: `[siku-playback] video error … kind=network|server|http|media`, then
  `connection lost code= delivery=; reconnecting for up to 120 s`, `reconnect <n> in <s> s`,
  `reconnect <n> mounted delivery=`, `reconnect <n> answered status=` (a failed reconnect replan),
  `reconnected after <s> s tries=<n>`, or `reconnect gave up after <s> s tries=<n>; asking for
  another route` (then the usual `recovery <n> classification=network_error`). Voice refusal reason
  `reconnecting`. `playlist too large: Roku refuses HLS playlists over 4 MiB delivery= define=`.
  The caps part of the playback line shows `define=` (hls_variable_substitution_v1 negotiated).
- `finished ignored reason=after_error|replanning|reconnecting|reanchoring|never_played`.
- Sessions: `progress answered status=404`, `session not found on the server (<why>); starting a new
  one at <s> s (renewal <n>)`, `session renewed at <s> s`, `session renewal failed status=; playing on
  without a session`, `session lost again …; not renewing after 3 renewals`.
- Stops (MainScene): `stop not delivered status=<n>; try <n> in <s> s`, `stop delivered status= tries=`,
  `stop not delivered after 8 tries …; giving up`, `stop dropped: the account, profile or server changed`.
- `stream on another origin (<host>): no account headers`.
- Simulator: `debugVideoError=net|drop|large|<code>[:N]`. Mock: `--switch progress_404=<n>`,
  `--switch stop_fail=<n>`; mock log `PROGRESS …` / `STOP …`.

## Subtitles, audio, Up Next

- `[siku-playback] credits ranges=<n> upnext_at=<s>`: the file's credits ranges; Up Next waits for the
  last one (Silo Android #694). Mock `--switch credits_twice=1` (two credits ranges on every version).
- Subtitle selection (`SubtitleSelect.brs`): `subtitle check settle|switch: roku plays <sidecar:<id>|mkv/N|none|url>`
  `(ok)` / `; selected again (listed=…)` / `; reloading at the position` / `after a second selection; left as it is`.
  Captions are suppressed (`Video.suppressCaptions`) while the controls or panel show.
- Slow embedded subtitles: `subtitle loading track=`, `subtitle ready track= after Ns[; reloading at the position]`,
  `subtitle load failed track= status= after Ns`. Mock `--switch subtitle_slow=<seconds>` (log `VTT slow key= waited= range=`);
  play file 52 or 56 and pick the embedded English track.
- Caps line: `aac6=` (box decodes 5.1 AAC) and `aaccap=` (`max_channels_by_codec {aac: 2}` sent, server lists
  `codec_channel_ceilings_v1`). Mock `--switch channel_ceilings=1`; its START CAPS line ends `ceilings=original:…,hls:…`.

## Sign-in and saved servers

- `[siku-servers]` lines (saved servers and sign-out, no URLs or tokens): `manage servers: N saved`,
  `picked the current server`, `that is the current server`, `switched signed_in=true|false
  profile=kept|ask|none`, `saved server answered as another deployment; signing in again`,
  `address refused: <message>`, `connect failed update= server_message=`, `sign out asked`,
  `sign out cancelled`, `sign out remove=true|false borrowed=true|false`, `logout answered status=N;
  signing out on this Roku anyway`, `removed current=true next=signed_in|signed_out|setup`,
  `removed current=false`, `the phone's profile did not end in time; the server is kept`,
  `registry budget: forgot the sign-in of a least recently used server`.
- `[siku-signin] choose how to sign in`, `chose phone`, `chose password`, `a phone asked to sign in;
  showing the code`, `code sign-in unavailable; password only`. `[siku-profiles] open automatically
  answered remember=`.
- Mock: `--server-id ID --server-name NAME` (a second, distinct server: e.g. `--port 8193
  --server-id mock-server-2 --server-name "Den Silo"`); `--switch info_status=<code>[:<detail>]`
  (GET /system/info answers that error, with a problem detail or bare; log `INFO answered`).
- Simulator: `debugServers=two` (with `debugSession=mock`; saves a second server signed in as sam /
  profile Sam at `debugPort2`, default debugPort+1), `debugManage=1` (with
  `debugScreen=ServerConnectScreen`: open it as Manage Servers).

## Phones, deep links, debug gating

- `[siku-deeplink]` lines: `refused reason=missing_content_id|content_id_too_long|unsupported_media_type`,
  `held until server setup|sign-in|profile type=`, `opening the held link`, `launch link skips Who's
  Watching; reopening the last profile`, `resolving type=`, `item type= action=play|next|detail|audio|drop`,
  `play resume=<s>`, `dropped reason=unavailable status=`, `answer dropped: a newer link arrived`.
  Simulator: add `contentId=<id>,mediaType=<type>` to the `--deep-link` (with `debugSession=mock` it is
  handled after the seeding); `debugDeepLink=<s>` on PlayerScreen now replaces the player with a new one.
- Debug deep-link parameters are compiled only with `bs_const=DEBUG=true`: `tools/simulate.py` builds
  that way; `--release-flags` runs as a release build; `npm run package` / releases ignore them, and
  `tools/package_check.py` fails a release zip whose manifest is not `DEBUG=false` or that reads
  `args.debug*` outside `#if DEBUG`. (Update the "Debug screens open with curl …" sentence.)
- `[siku-lan] phone sign-in cN silent for 180 s with no sign-in in progress; closing (idle_timeout)`
  (after the 30 s first-frame rule); `[siku-pair] panel <view>` for every panel state, `[siku-pair] panel took focus back`;
  `silo_phone.py pair --expect-idle-timeout`.
- `[siku-launch] leaving: requests=N lan=true|false`, `[siku-lan] app exit: mdns goodbye for N service(s)
  sent=` / `nothing advertised`, `[siku-launch] exit after <ms> ms (requests pending= lan done=)`.
- mDNS TTLs: PTR/SRV/A 120 s, TXT 4500 s.
- Mock: seasons have `play_content_id`.

## Screens and catalog

- `[siku-calendar] time zone roku=<Roku name> sent=<IANA|none>` once per zone; `[siku-calendar]
  clock format unreadable:`. Mock logs `CALENDAR start= timezone= filter=`; mock events carry
  `air_at` (with Z and with -04:00), `air_time` 20:15 / 00:00 and two badges.
- `[siku-detail] watchlist|favorite write failed status=<n> pending=true|false`; `[siku-detail] mark
  season|episode watched=true|false`. Mock `--switch member_fail=<code>|bare` (watchlist/favorites
  refused with a detail); seasons carry `user_data.played`; a season watched write covers its episodes.
- `[siku-art] reload page=home|library-home|foryou|calendar|library reason=stale|image-failed age=Ns`;
  `[siku-art] reload failed page=calendar status=`. Mock `--switch art_expire=<seconds>`: every
  `/mock-img` URL gets `?exp=` and answers 404 after it (log `ART EXPIRED <kind>/<name>`). NB a mock
  started before a mock_server.py edit keeps the old code — restart it.
- `[siku-requests] discover failed|your requests failed status=…; keeping N`, `[siku-requests]
  follow PUT|DELETE <type>`, `follow failed status=`. Mock `--switch discover_layout=1` (row_order
  with a studios brand row and an empty row; log `REQUESTS DISCOVER layout=`), `mine_fail=1`,
  `follow_fail=1` (log `REQUESTS FOLLOW`). Mock r-4 (The Understudy, tmdb 9102) is another user's
  request: its detail page offers Notify me.
- `[siku-library] filters applied facets=<n> match=true|false`. Mock logs `CATALOG FILTERS library=
  skip_technical=` and `CATALOG QUERY groups= match= -> n`; mock titles get studio, country,
  languages, resolution, HDR facets. Deep link `debugScreen=LibraryScreen,debugLibrary=1`.

## Memory and on-device diagnostics

- `[siku-diag]` lines: `last exit code=<EXIT_*> kind=crash|hang|memory|killed| app_state= media=
  [mem_limit_mb=]` once per launch (Roku's GetLastExitInfo, else the launch reason), `notice shown
  kind=` (Home's one-time "closed unexpectedly" toast), `log cleared`. Settings › Diagnostics shows
  the on-device log (`cachefs:/siku-diag.txt` + `.1.txt`, ~96 KB, scrubbed by `Diag_scrub`).
  Add lines to it with `Diag_log(...)`; after merging, `python3 tools/diag_log_convert.py`
  converts new `print "[siku-<logged category>]` lines (tests/test_diag.py checks). Simulator:
  `debugExit=<EXIT_CODE>` (e.g. `EXIT_CHANNEL_MEM_LIMIT_FG`) stands in for the last exit.
- `[siku-memory]` lines: `device tier=low|standard reasons=ui,graphics,monitor,foregroundLimit
  limit_mb=` at launch; `pressure <pct> level=normal|trim|pressure|critical was=` when the level
  changes (main.brs samples every 2 s after a warning); `library pages dropped=N kept=N budget=N`
  and `library page reread page=N items=N` (bounded library grid); `released` / `restored` as
  before (now also screens deeper than the stack budget). Note: `debugMemory=<pct>` now needs
  >= 70 (trim), >= 85 to release every covered screen, >= 90 for critical grid budgets. The
  simulator reports an HD UI, so it always runs in low-memory mode.
- Mock: `--switch big_library=<n>` pads the library grid to n titles (mock log `CATALOG big
  library= cursor= limit=`).

