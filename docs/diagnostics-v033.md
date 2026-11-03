<!-- SPDX-License-Identifier: AGPL-3.0-or-later -->
# Diagnostics added in v0.1.33

## Subtitles from the stream, unplayable tracks

- Subtitles from the stream (Silo Android #770/#776): the caps show `allrend=` (hls_subtitle_renditions_all_v1
  negotiated) and `nativesubs=` (native_embedded_limitations_v1: original_http's native_embedded entry and
  embedded_subtitles_v1); the plan shows `sub_native=mkv/<id>` and `sub_rows=rend:N,native:N,unplayable:N`.
  Each mount with stream tracks prints `subtitle mount: sidecars= renditions= native= unavailable= pick=
  preselect=<mkv/N|webvtt/N|none> hold=`; then `subtitle native mkv/N selected`, `hls subtitle rendition
  subs:<name> selected as webvtt/N (by=name|index|ambiguous)`, `subtitle check settle|switch: roku plays
  mkv/3(<trackId>) (ok)`, `subtitle native mkv/N not listed by roku; using the server's sidecar at the
  position`, `hls subtitle rendition ... not named by roku; using the server's sidecars at the position` with
  `subtitle listing: TrackName|Description|Language;...`, and `subtitle request dropped: <id> has no format
  the server can show`. Mock: `--switch renditions_all=1` (every embedded text row of an HLS plan gets
  hls_rendition; 4K files add a Spanish row; log `SUBTITLE renditions=`), `native_subs=1` (file 42 is an MKV
  original with English mkv/3 and Spanish mkv/4 rows; log `SUBTITLE native_entry=`), `unplayable_sub=1|legacy`
  (an embedded French row with no codec, flagged or not; catalog too; log `SUBTITLE requested unplayable`).

## Card focus look

- None: purely visual, no new console lines, mock switches or deep-link parameters. (Simulator recipe:
  `debugScreen=DetailScreen,debugItem=series:orbital` shows the episode rail; wait 50 s.)

## Movie box sets

- Movie box sets (Silo Android #646, `BoxSets.brs`, `BoxSetScreen`): `open box set library=`, `box set read movies= played= quiet=` / `box set read failed status=
  quiet=` (404/410: "isn't available"), `play movie index= of N resume=`, `search box sets=<n>
  status=` / `search box sets late; showing the titles without them` (1.5 s grace), `open box set
  from search`, `movie box set row shown=true|false` / `movie box set read failed status=`,
  `explore all from a movie page`. Since v0.1.37 (Silo Android #796) library grids never send
  `group=box_set` (the server answers 422; so does the mock). Mock: `--switch box_sets=1` (library 1; log `BOX SETS browse library=
  group=`, `BOX SET <id> library= status=`, `BOX SET SEARCH q= n=`, `BOX SET ITEM <id> library=
  found=`). Simulator: `debugScreen=BoxSetScreen,debugItem=8650,debugLibrary=1` (Night Collection;
  1241 = The Paper Collection), `debugScreen=DetailScreen,debugItem=movie:paper-tigers` (the row),
  `debugScreen=SearchScreen,debugQuery=night`.

## Copy-remux re-anchoring

- `seek reanchor target= ... lead_in=<s>|-` (the position asked of the server: 10 s before the
  target on a copy remux) and `seek reanchored ... lead_in=true|false`; `seek reanchor load
  target= origin= play_start=` when a lead-in plan is handed to the Video node after its 1.5 s hold;
  `seek reanchor hold dropped: the plan changed meanwhile`.
- `start check start= position= lead_in= action=landed|seek|seek_forward|reanchor` (a copy remux's
  every mount, any other mount only when it opened more than 3 s away), then `start seek
  kind=back|forward start= position= landed=true|false`. A `seek reanchor ... reason=start_slip`
  is the one reanchor a late copy-remux start or reload sends.
- Simulator: `debugVoice=seek:900` with `debugFile=56` and the mock's `--hls-copy-ts` is the
  reliable way to trigger a reanchor (wait ~150 s with other slices running).
- Playback-facts paragraph (CLAUDE.md "Copy remuxes have open-ended timelines..."): add "A reanchor
  on a copy remux asks 10 s before its target, starts the load at the target and assigns it 1.5 s
  after the answer (silo-roku W0-2); not verified on a Roku by Siku." See section 4 for the open
  item before stating it as fact.

