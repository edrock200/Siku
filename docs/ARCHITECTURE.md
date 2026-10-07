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
  Settings.brs  Settings_* server-synced settings (effective cascade read/write, typed getters, Home row layout)
components/tasks/
  ApiTask       one HTTP request (Task); JSON in and out; 401 → refresh → retry
  AuthTask      long-lived single-flight token refresher (rotating refresh tokens)
  Http.brs      roUrlTransfer wrapper and Silo device headers
components/widgets/             reusable UI: MediaCardItem, PillButton, Toast, LoadingSpinner, …
components/screens/             one folder or file pair per screen
components/player/              PlayerScreen and its overlays
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
- `Nav_reset("@start")` re-runs startup routing:
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
| `ShellScreen` | none. Top bar and root tabs: Home, Movies, Series, Music, Audiobooks, For You, Calendar, Requests (only when `GET /api/v2/requests/status` enables it; page `RequestsPage`) |
| `LibraryScreen` | `{ libraryId, libraryName, mode, section: "browse"\|"collections"\|..., title, source?, collectionId? }` |
| `LibraryPage` (shell page) | `{ section, libraryId, libraryName, mode, mediaType?, ... }`. Sections: `browse`, `collections`, `alphabet` (A‑Z), `genres` (Music), `authors` / `series` (audiobook groups via `GET /api/v2/catalog/audiobook-groups`, drill-in through `POST /api/v2/catalog/query` with an `author`/`series` `is` rule), plus the personal lists. Browse and A‑Z show the right-edge `AlphabetRail` (`name_prefix`) |
| `DetailScreen` | `{ itemId, itemType?, libraryId? }`. Movie, series, season and episode |
| `PersonScreen` | `{ personId, name? }` |
| `SearchScreen` | `{ query? }` |
| `RequestDetailScreen` | `{ mediaType: "movie"\|"series", tmdbId, title?, moderationRequestId? }`. A TMDB title to request (or its request's status); `moderationRequestId` pins the page to one request, as from an admin's approval row |
| `SettingsScreen` | none. Android TV `TvSettingsScreen`: rail (account, General / Playback / Subtitles / Server, Sign Out) and a pane of grouped rows. Values are the server's effective settings (`Settings.brs`) with the device prefs as fallback; the Home Sections editor (`SettingsHomeSections.brs`) is a full-screen overlay |
| `NotificationsScreen` | none. Notifications inbox (Android TV `TvInboxScreen`): Mark all read card, newest-first delivery cards, OK marks read and opens the series/episode, pages of 25. Android TV has no route to it, so Siku has no entry point either (deep link `debugScreen=NotificationsScreen`) |
| `PlayerScreen` | `{ itemId, fileId?, startPosition?, title?, audioTrackId?/audioTrackIndex?, subtitleTrackId?/subtitleTrackIndex? (-1 = off), shuffleId?, shuffle? }`. With `shuffleId` the player runs a shuffle session: picks start at 0, Up Next shows the server's random pick with Pick Another / Stop shuffling |
| `AudioDetailScreen` | `{ itemId, itemType }` for `album`, `artist`, `audiobook`, `track`. Use `Nav_openItem(id, type)`, which picks this or `DetailScreen` |
| `AudioPlayerScreen` | Music `{ queue: [{contentId, fileId?, title?, artist?, album?, posterUrl?, durationSeconds?}], index?, startPosition?, shuffle? }`; audiobook `{ itemId, startPosition? }` (whole-book seconds). `Nav_play` routes audio types here |

Music: the Silo v2 contract has no album/artist/track types yet, and Android TV keeps music minimal. `AudioDetailScreen` reads a provisional shape (`tracks[]` on albums, `albums[]` on artists) that only `tools/mock_server.py` serves today. Audiobooks use the real contract.

## Global state (`m.global`)

| Field | Contents |
|---|---|
| `session` | `{serverUrl, serverOrigin, serverId, serverName, accessToken, refreshToken, expiresAt, user, profileId, profileToken, profileName, profileAvatar, deviceId}`. Never mutate it in place: edit a copy, then call `Session_save(copy)`. |
| `prefs` | Device-local settings (`Prefs_load`, `Prefs_save`). |
| `toast` | Set a string to show a toast, e.g. `m.global.toast = "Added to Watchlist"`. |
| `authExpired` | Set by the network layer. MainScene then signs out and routes to the login screen. |
| `homeDirty` | Set to `true` after playback or after watched/favorite/watchlist changes, so Home and the details reload on show. |
| `shuffleCaps` | Cached `GET /api/v2/shuffles/capabilities` keyed by server+profile (`Shuffle_refreshCaps` / `Shuffle_supports`). Shuffle entry points are hidden until it says available. |
| `keyReleaseSeen` | Set once a key release reached a card list; arms the long-OK-press card menu (`LongPress_*` in Utils.brs). |
| `requests` | `{enabled, canModerate, resolved}`: the media-requests gate, set by `ShellScreen` from `/api/v2/requests/status` and `/api/v2/admin/requests/capabilities`. Read it with `Req_gate()` (`components/common/Requests.brs`). |
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
