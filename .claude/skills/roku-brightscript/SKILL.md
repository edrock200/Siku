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
`it.runtime * 60` with a string crashes with a type mismatch. Use `Content_num()`, `Req_num()`
(or the local `toInt()` in `DetailScreen.brs`) and `Str_orEmpty()` before arithmetic or concatenation; wrap arrays with `Arr_or()`;
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
   `debugSession=mock` seeds a signed-in session against the mock; `debugScreen` opens a screen
   directly; `debugItem` becomes `params.itemId`. Useful ids: `movie:glass-city`,
   `series:orbital`, `audiobook:the-long-orbit`, person `100`.
5. Build: `npm run package` → `out/siku.zip`. Side-load on a Roku in developer mode
   (`http://<roku-ip>`, user `rokudev`) and watch `telnet <roku-ip> 8085` for errors. A compile
   error prints `Syntax Error ... in pkg:/...(line)`; a runtime crash prints a full backtrace with
   local variables, which is the single most useful thing to paste into a bug report.

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
