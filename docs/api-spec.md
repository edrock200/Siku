# Silo HTTP API as used by the Android TV client (spec for a Roku/BrightScript port)

Roots used below:
- Android: `<upstream>/silo-android/` (called `A/`). Shared code is in `A/shared/src/commonMain/kotlin/org/siloserver/silo/` (called `S/`).
- Server: `<upstream>/silo-server/` (called `SV/`).
- The authoritative machine-readable contract is `SV/contracts/api/v2/openapi.json` (6 MB OpenAPI). Example bodies are in `SV/contracts/api/v2/fixtures/*.json`. Every JSON example below comes from those fixtures or was checked against that schema.

---

## 0. Answer to #10 first: v1 or v2?

**The TV client uses `/api/v2` only.** `A/docs/api-v2/android-migration-status.md` says: "Every HTTP call the Android clients make goes to `/api/v2/` except the two exceptions."
- The only exception that matters is `GET /health`, the root liveness route.
- Server settings v1 routes were deleted with no v2 replacement.

v1 is the "frozen alpha" surface. The client never falls back to v1, playback included (`A/docs/playback/sequenced-api-v2.md`).

To tell a v1-only server apart, the client calls `GET /api/v2/system/info` once per connection (`S/network/apiv2/ApiV2Probe.kt`):
- If the server answers 404 with the exact body `404 page not found` (Go's default), the client shows an "update your server" state.

**Port v2 only.** The server also hosts a Jellyfin-compatible API (`SV/internal/jellycompat`), but the client does not use it.

### General v2 conventions (`SV/docs/architecture/api-contract.md` §Success/Problem)
- **Bodies:** JSON. Request field names are snake_case.
- **IDs:** all IDs are **strings** (`"id":"1"`, `content_id:"movie:heat-1995"`, `file_id:"42"`). Treat them as opaque.
- **Collections:** returned as `{"items":[...], "page":{"has_more":bool,"next_cursor":"..."}}`.
  - Paging uses opaque cursors only. Pass `cursor=<next_cursor>`. Offsets are rejected (fixtures `*_offset_rejected.json`).
- **Status codes:** create = 201, delete or a command with no body = 204, read = 200.
- **Errors:** RFC 7807 `application/problem+json`:
  ```json
  {"type":"https://siloserver.org/docs/api/v2/problems/profile_verification_required","title":"Profile verification required","status":403,"detail":"...","instance":"urn:silo:request:..."}
  ```
  - Validation errors (422) add `errors:[{"location":"header.x-profile-id","code":"required","detail":"..."}]`.
  - The last path segment of `type` is the machine code: `invalid_token`, `session_expired`, `token_refresh_required` (401: refresh then retry), `profile_verification_required` (403), `installation_changed` (409), and so on.
  - 429 and 503 may carry `Retry-After`.
- **Profile header:** most content endpoints require the `X-Profile-Id` header. Without it you get 422 `header.x-profile-id required` (fixture `get_for_you_main_profile_header_required.json`).

---

## 1. Server discovery and connection

### Entering the URL
The user types a URL (`A/androidTvApp/.../tv/ui/screens/auth/TvServerSetupViewModel.kt`, ~lines 315–335):
- Input is trimmed and trailing `/` is removed.
- If it has no scheme, the client tries **`https://<input>` first, then `http://<input>`**, and uses the first that answers.
- Normalization (`AndroidServerRegistry.normalizeUrl`, `A/shared/src/androidMain/.../network/AndroidServerRegistry.kt:535`): lowercase the scheme and host, keep the port, path and query as typed, and strip the trailing `/`.
- A path prefix (reverse proxy) is allowed. All API paths are appended to the saved base.

### Probe sequence for each candidate
1. `GET {base}/api/v2/system/info` (public, no auth).
   - A 404 with exact body `404 page not found` means "update server".
   - Anything else is not a verdict.
2. `GET {base}/api/v2/system/setup` (public). Response: `{"needs_setup":false,"wizard_completed":true}`.
   - If `needs_setup` is true, the server needs first-admin setup (`POST /api/v2/auth/setup`, body `{username,email,password}` → 201 token pair).
3. `GET {base}/api/v2/auth/signup` (public). Response: `{"enabled":false}`. Optional; it only controls whether a signup button is shown.

### Public discovery endpoints (no auth)
| Endpoint | Response |
|---|---|
| `GET /api/v2/system/info` | `{"api_major":2,"server_version":"abc123","contract_digest":"<sha256>","links":{"openapi":"...","identity":"/api/v2/system/identity","capabilities":"..."}}`. The client requires `api_major == 2`. |
| `GET /api/v2/system/identity` | `{"server_id":"3f2a9d5e-..."}`. A stable deployment ID; use it to recognise the same server at different URLs (`S/network/api/ServerIdentityApi.kt`). 8 s timeout on TV. |
| `GET /health` (root) | `{"status":"ok","server_name":"Silo","server_id":"..."}` (`S/network/api/HealthApi.kt`, 6 s timeout). Used for a friendly name. **Caveat:** in this server checkout the handler is only registered at `/api/v1/health` (`SV/internal/api/router.go:2910`). Treat `/health` as best-effort. |
| `GET /api/v2/theme/branding` | Branding and server name. The client prefers this name over `/health`. |
| `GET /api/v2/system/connections` (auth) | `{state, allowed, server_id, endpoints:[{kind:"public"\|"provider", url, provider, display_name, state}]}`. Lists alternate addresses. Optional. |

### Cleartext HTTP
Android asks the user to consent before sending credentials over `http://` (`CleartextOriginConsent`). This is client policy only; the server does not require it.

---

## 2. Authentication

Files: `S/network/api/AuthApi.kt`, `S/network/api/AuthWireV2.kt`, `S/model/auth/AuthModels.kt`, `S/network/AuthInterceptorImpl.kt`, `S/network/api/DeviceLoginApi.kt`, `S/repository/DeviceSignInMachine.kt`, `A/docs/auth-api-v2.md`, `SV/docs/architecture/device-login.md`.

### 2.1 Password login
`POST /api/v2/auth/login`. No `Authorization` header; the device headers are still sent.
```json
{"username":"laura","password":"secret","provider":"<optional; omit>"}
```
→ **200**:
```json
{"access_token":"acc","refresh_token":"ref","expires_in":3600,
 "user":{"id":"1","username":"laura","email":"laura@example.test","role":"user",
         "permissions":["marker_edit"],"download_allowed":true,"password_change_required":false,
         "impersonation":{"active":true,"impersonator_user_id":"2","impersonator_username":"admin"} }}
```
- `impersonation` is optional.
- `expires_in` is in seconds.
- Errors: 401 `invalid_token` ("Invalid username or password"), 403 `local_login_disabled` / `not_permitted` / `password_expired`, 409, 422, 429, 503 `provider_unavailable`.
- On TV, OAuth/OIDC providers are never run. TVs use the device code flow instead.
- Optional: `GET /api/v2/auth/providers` returns `password_login` and the provider list, so you can decide whether to show the password form.

### 2.2 Token usage (every authenticated request)
- `Authorization: Bearer <access_token>`
- `X-Profile-Id: <profile id>` once a profile is selected.
- `X-Profile-Token: <profile_token>` only when the selected profile is PIN-locked (see §3).
- The client also sends `Content-Type: application/json`. The server returns 406 if `Accept` does not allow JSON, so send `Accept: application/json`.

### 2.3 Device and client identification headers
Sent on every same-origin request, including unauthenticated ones (`AuthInterceptorImpl.kt:899–910`; values from `A/android-shared/.../common/network/AndroidDeviceMetadataProvider.kt`):

| Header | Android TV value | Roku suggestion |
|---|---|---|
| `X-Silo-Device-Id` | random UUID persisted per install | `roDeviceInfo.GetChannelClientId()` or a persisted UUID |
| `X-Silo-Device-Name` | `"<Manufacturer> <Model>"` | `"Roku " + model display name` |
| `X-Silo-Device-Platform` | `android-tv` | `roku` |
| `X-Silo-Client` | `Silo Android TV` | e.g. `Silo Roku` |
| `X-Silo-Client-Version` | app versionName | channel version |
| `X-Silo-Client-Build` | CI build number (optional) | optional |
| `X-Silo-Client-Channel` | `release`/`beta`/`sideload`/`dev` | optional |
| `X-Silo-Client-Family` | `tv` (closed set: tv, mobile, tablet, desktop, web) | `tv` |

None of these is strictly required for auth. Device-scoped settings, however, reject requests without a device id (fixtures `*_device_header_required.json`).

### 2.4 Refresh
`POST /api/v2/auth/refresh` with no `Authorization` header.
```json
{"refresh_token":"ref"}
```
→ 200:
```json
{"access_token":"...","refresh_token":"...","expires_in":3600}
```
- **The refresh token rotates.** Always store the new one.
- When to refresh:
  - **Reactively:** on any 401, under a single-flight lock so N parallel 401s cause one refresh, then retry once.
  - **Proactively:** when remaining lifetime ≤ min(margin, lifetime/2) (`S/network/ProactiveRefreshPolicy.kt`).
- 401 `token_refresh_required` means the role changed: refresh and retry.
- 401 `session_expired` on refresh means signed out.
- 503 `provider_unavailable` on refresh means keep the session and retry later.

### 2.5 Logout
`POST /api/v2/auth/logout` with the bearer token → **204**. This revokes the login session.

### 2.6 Current account
`GET /api/v2/account/me` (bearer, no profile needed) → the same object as `user` above.

### 2.7 TV device-code sign-in (the TV's main path)
Server state machine: `SV/internal/auth/device_login.go`. The poll interval is 3 s on the server (`deviceLoginPollInterval`).

**Capability (optional, public).** `GET {base}/api/v2/auth/device/capability`:
```json
{"revision":"...","state":"available","remote_playback_handoff":true,"protocol_versions":[2],"cancel":true,"opened_signal":true}
```
- Any `state` other than `available`, or a start that returns 404/501, means device login is unavailable; show the password form.

**1) Start.** `POST {base}/api/v2/auth/device/start` with no auth. All body fields are optional:
```json
{"device_name":"Living Room Roku","device_platform":"roku"}
```
Android sends `device_platform:"android-tv"` and `device_name: Build.MODEL`. Response **201**:
```json
{"device_code":"dev-1","user_code":"4821-7730","match_code":"warm pony",
 "verification_uri":"https://silo.example.test/activate",
 "verification_uri_complete":"https://silo.example.test/activate?code=48217730",
 "expires_at":"2026-01-02T03:19:05.678Z","expires_in":900,"interval":5,
 "device_name":"Living room TV","device_platform":"tvos","client_purpose":"device_login","temporary":false}
```
- Display `user_code` as two groups of 4 digits (`4821 7730`).
- Display `<host>/activate`.
- Show a QR code of `verification_uri_complete`.
- Do **not** display `match_code`.
- The request lives 15 minutes.

**2) Poll.** `POST {base}/api/v2/auth/device/poll` with no auth:
```json
{"device_code":"dev-1"}
```
Poll once immediately, then every `interval` / `poll_after` seconds. Response 200 while pending:
```json
{"status":"pending","poll_after":5,"opened":true,"expires_at":"2026-01-02T03:14:05.678Z","profile_id":"","profile_token":"","temporary":false}
```
Response 200 when approved:
```json
{"status":"approved","poll_after":5,"opened":false,
 "tokens":{"access_token":"acc","refresh_token":"ref","expires_in":3600,
           "user":{"id":"1","username":"laura","email":"...","role":"user","permissions":[],"download_allowed":true,"password_change_required":false}},
 "profile_id":"","profile_token":"","temporary":false}
```
- `status` is one of `pending | approved | denied | consumed | canceled | expired`.
- **Tokens are delivered only once.** If the approved reply is lost, the code is consumed and you must start again.
- `opened:true` means someone opened the code on a phone or web. Show "Continue on your phone" and stop rotating the code.
- A pending reply's `expires_at` can move later because approver lookups extend it (up to 30 minutes total). Move your local deadline to it.
- Non-empty `profile_id` / `profile_token` (temporary or handoff sessions) mean the session is already bound to that profile. Use them as `X-Profile-Id` / `X-Profile-Token`.
- 404 or another 4xx on poll means the request is gone; start a new code.
- Backoff rules (`A/docs/auth-api-v2.md`):
  - Network errors, 5xx and 429: back off from the interval up to 30 s.
  - Show "can't reach" after 10 s of failed starts or 30 s of failed polls.
  - Show "too many requests" after 1 minute of 429s.
  - Pause after 1 hour of user inactivity.

**3) Cancel.** Call this when leaving the screen, retrying, switching to password login, or when the deadline passes while still pending. `POST {base}/api/v2/auth/device/cancel`:
```json
{"device_code":"dev-1"}
```
→ 200 `{"status":"canceled"|"denied"|"consumed"|"expired"}`. A 404 is harmless.

**4) After approval.** Store the tokens, then go to profile selection (§3).

The approver side (`GET /api/v2/auth/device?code=`, `POST /api/v2/auth/device/approve|deny|approve-handoff` with `{"code":"48217730"}`) is phone/web-only and not needed on Roku.

---

## 3. Profiles

Files: `S/network/api/ProfileApi.kt`, `S/repository/ProfileRepository.kt`, `A/androidTvApp/.../screens/profiles/TvProfileSelectionViewModel.kt`.

**List.** `GET /api/v2/profiles` with the bearer token. `X-Profile-Id` is optional here because the picker runs before selection.
```json
{"items":[{"id":"p-owner","name":"Laura","avatar":"preset:fox","avatar_url":"/avatars/presets/fox.png","avatar_source":"preset",
  "has_pin":false,"is_child":false,"is_primary":true,"max_content_rating":"","max_advisory_age":null,"require_advisory_age":false,
  "quality_preference":"auto","language":"en","preferred_metadata_language":"","subtitle_language":"","subtitle_mode":"auto",
  "auto_skip_intro":true,"auto_skip_credits":false,"auto_skip_recap":false,"auto_play_next_preview":false,"show_forced_subtitles":false,
  "library_restrictions_enabled":false,"allowed_library_ids":["3"],"max_playback_quality":"1080p",
  "created_at":"2026-01-02T03:04:05.000Z","updated_at":"..."}],
 "avatar_upload_enabled":false,"max_advisory_age_supported":true,"require_advisory_age_supported":true}
```
- `avatar_url` may be root-relative. Resolve it against the server base (§7).
- **TV behaviour:** if there is exactly one profile and it has no PIN, it is auto-selected and the picker is skipped (`TvProfileSelectionViewModel.kt:140`).

**Selecting a profile.** There is no server call. The client starts sending `X-Profile-Id: <id>` on every request (`ProfileRepository.selectProfile` → `tokenManager.setProfileIdentity`).

**PIN.** `POST /api/v2/profiles/{id}/verify-pin`:
```json
{"pin":"1234"}
```
→ 200:
```json
{"valid":true,"profile_token":"...","expires_at":"2026-...Z|null"}
```
- `profile_token` is absent when the PIN is wrong.
- Send it as `X-Profile-Token` together with `X-Profile-Id`. It is bound to this login session.
- Requests for a locked profile without the token get 403 `profile_verification_required`.

**Other operations.** Create `POST /api/v2/profiles` (201), update `PATCH /api/v2/profiles/{id}`, delete `DELETE /api/v2/profiles/{id}` (204). The TV has create/edit screens, but these are optional for a port.

**Current user.** `GET /api/v2/account/me` (§2.6). There is no separate "current profile" endpoint; the client keeps it locally.

---

## 4. Libraries and browsing

Files: `S/network/apiv2/UserLibrariesV2.kt`, `S/network/apiv2/CatalogV2Api.kt`, `S/network/apiv2/CatalogV2Models.kt`, `S/network/api/CatalogApi.kt`, `S/network/apiv2/LibrarySectionItemsV2Api.kt`, `S/model/navigation/MediaMode.kt`, `A/docs/catalog-api-v2.md`.

### 4.1 List libraries
`GET /api/v2/user/libraries` (with `X-Profile-Id`):
```json
{"items":[{"id":"3","name":"Movies","type":"movies","sort_order":0,"poster_url":"..."}]}
```
Media type comes from the free-text `type` field, matched case-insensitively (`MediaMode.kt`):
- Video: `movie, movies, series, show, shows, tv, video, mixed`. `mixed` means movies and shows in one library; it must not be dropped.
- Audio: `music, album(s), artist(s), audio`, plus audiobooks: `audiobook, audiobooks`.
- Reading (hidden on TV): `ebook(s), book(s), comic(s), manga, reading`.

The server's equivalent lives in `SV/internal/librarykind/librarykind.go`. It adds `tvshows`, `podcast(s)` and `manga`.

### 4.2 List items: `GET /api/v2/catalog`
Requires `X-Profile-Id`. Query parameters (from openapi):

| Param | Meaning |
|---|---|
| `source` | `query` (default), `section`, `library_collection`, `user_collection`, `favorites`, `watchlist`, `history`, `person` |
| `library_id` | Restrict to one library |
| `type` | `movie`, `series`, `episode`, `audiobook`, `ebook`, `podcast`, `video`, … |
| `q` | Search text |
| `name_prefix` | A–Z jump |
| `genre`, `year_min`, `year_max`, `content_rating` (repeatable), `status` | Simple filters |
| `sort` | One term: `field` or `-field` for descending. Fields: `title`, `year`, `release_date`, `added_at`, `rating`, `runtime`, `random`, … An unknown field returns 422 (fixture `list_catalog_items_unknown_sort_field.json`). |
| `match` | `all` or `any` |
| `group=work` | Collapse book editions |
| `skip_total=true` | `total` becomes an estimate |
| `image_size` | `small`, `medium`, `large`, `original` |
| `limit` | 1–200, default 50. The client uses ≤100. |
| `cursor` | Next page |
| `collection_id`, `person_id`, `section_id`, `scope` | Used with the matching `source` |
| `seek` | Window jump |

For structured rule groups the client uses `POST /api/v2/catalog/query` instead, with the same fields as a JSON body plus:
```json
"groups":[{"match":"all","rules":[{"field":"genre","op":"contains","value":"Crime"},{"field":"year","op":"between","value":[1990,1999]}]}]
```
and `cursor` in the body. `image_size` stays a query parameter.

Response:
```json
{"items":[{ ...card... }],"page":{"has_more":true,"next_cursor":"opaque"},
 "total":1234,"total_exact":true,"window_cursor":"opaque",
 "effective_sort":{"field":"title","order":"asc"},
 "search_diagnostics":{"provider":"postgres","mode":"keyword","semantic_used":false}}
```
- `effective_sort` and `search_diagnostics` are optional.
- Keep the exact same query for every page. Only the `cursor` changes. An expired cursor returns `invalid_cursor`; reload from page 1.

**Card ("BrowseItem") fields.** The same shape is used for home, similar, for-you and watchlist. Fields include:
- Identity and text: `content_id`*, `type`*, `title`*, `status`*, `genres`*, `keywords`*, `year`, `overview`, `runtime` (minutes), `duration_seconds`, `release_date`, `content_rating`, `original_language`, `studios`, `networks`, `show_status`, `last_air_date`.
- Ratings: `rating_imdb`, `rating_tmdb`, `rating_rt_critic`, `rating_rt_audience`.
- Artwork: `poster_url`, `poster_thumbhash`, `backdrop_url`, `backdrop_thumbhash`, `logo_url`.
- Episode context: `series_id`, `series_title`, `season_number`, `episode_number`.
- `play_content_id`: what to play when the card is a series or season.
- Continue-watching fields: `position_seconds`, `progress_updated_at`, `item_source` (`in_progress` | `next_up`).
- `user_state: {played, is_favorite, in_watchlist}`.
- `overlay_summary: {resolution, hdr, audio, audio_channels, video_codec, container, edition, release_type, aspect_ratio, multi_audio, multi_sub}`.
- Also `badges`, `upcoming_event`, `advisory_age`, `work_*`, `manga_*`.

Example card (fixture `list_home_sections_ok.json`):
```json
{"content_id":"movie:heat-1995","type":"movie","title":"Heat","year":1995,"runtime":170,"genres":["Crime"],"keywords":[],
 "content_rating":"R","status":"matched","rating_imdb":8.3,"position_seconds":1200.5,"duration_seconds":10200,
 "progress_updated_at":"2026-01-02T03:04:05.000Z","poster_url":"https://s3.example.test/poster.jpg",
 "overlay_summary":{"resolution":"4K","hdr":"Dolby Vision"},"item_source":"in_progress",
 "user_state":{"played":false,"is_favorite":false,"in_watchlist":true}}
```

**Filter vocabularies.** `GET /api/v2/catalog/filters?library_id=&source=&collection_id=&skip_technical=true` returns:
```json
{"genres":[],"studios":[],"networks":[],"countries":[],"original_languages":[],"content_ratings":[],
 "authors":[],"narrators":[],"series":[],
 "technical":{"resolutions":[],"audio_languages":[],"subtitle_languages":[]}}
```
- Facet prefix search: `GET /api/v2/catalog/filters/search?facet=&q=&limit=100` → `{"matches":[],"has_more":false}`.
- Audiobook groups: `GET /api/v2/catalog/audiobook-groups?library_id=&group_by=author|narrator|series&sort=name&limit=&cursor=`.

### 4.3 Library landing rows
- `GET /api/v2/library/{id}/sections` → `{"sections":[ResolvedSection...]}`, the same shape as home (§5).
- `GET /api/v2/library/{id}/sections/{section_id}/items` returns one section.
- Server default rows per library type are in `SV/internal/sections/defaults.go:180–245`:
  - Continue Watching / Listening / Reading
  - Recently Added
  - Recently Released
  - Top Rated (custom_filter)
  - Recommended for You
  - Random Picks

### 4.4 Item detail
`GET /api/v2/catalog/items/{content_id}?library_id=&image_size=&file_id=` (with `X-Profile-Id`).
- Works for movie, series, season, episode, audiobook and other types.
- Large response. Key fields:
  - Identity and text: `content_id`, `type`, `title`, `original_title`, `sort_title`, `tagline`, `overview`, `year`, `runtime`, `release_date`, `first_air_date`, `last_air_date`, `content_rating`, `genres`, `studios`, `networks`, `countries`.
  - Ratings: `ratings:[{source,name,score,display}]` and `rating_sources`.
  - Artwork: `poster_url`, `backdrop_url`, `logo_url` and thumbhashes.
  - Series and seasons: `season_count`, `episode_count`, `series_id`, `series_title`, `season_number`, `episode_number`, `is_specials`.
  - Playback pointers: `play_content_id` and `play_season_number` (the episode to play for a series).
  - `cast:[{person_id,name,character,order,photo_url,photo_thumbhash,tmdb_id,imdb_id}]`.
  - `crew:[{person_id,name,job,photo_url}]`.
  - `videos` (trailers): `[{kind,site,site_key,name,is_official}]`.
  - `extras`.
  - `user_state:{played,is_favorite,in_watchlist}`.
  - `user_data:{position_seconds,duration_seconds,is_in_progress,played,watched_count,unplayed_count,in_progress_count,last_file_id,...}`.
  - `user_rating` (1–5).
  - Markers in **`{start,end}`** form (seconds): `intro`, `credits`, `recap`, `preview`.
  - `subtitles:[{language,codec,forced,hearing_impaired,source,title}]`.
  - `versions:[...]` and `playback_variants:[...]` (see below).
  - `effective_subtitle_language`, `effective_subtitle_mode`.
  - Book-specific `audiobook` and `ebook` objects.
- Fixture: `get_catalog_item_ok.json`.

**Version entry** (the file to play):
- File facts: `file_id`*, `resolution`*, `codec_video`*, `codec_audio`*, `container`*, `hdr`*, `duration`* (seconds), `bitrate`*, `file_size`*, `added_at`*, `edition_key`, `edition_raw`.
- Tracks: `video_tracks[]`, `audio_tracks[{index?,language,codec,channels,layout,default,title}]`, `subtitle_tracks[{index,language,codec,forced,default,external,hearing_impaired,title}]`.
- `chapters[{index,title,start_seconds,end_seconds,source,thumbnail_url}]`.
- Markers `intro`/`credits`/`recap`/`preview` in `{start,end}` form.
- `effective_audio_track_index`.

### 4.5 Watch detail (pre-playback)
`GET /api/v2/watch/{content_id}?library_id=` (`S/network/apiv2/WatchDetailV2Api.kt`).
- Returns `content_id`, `type`, `title`, `year`, `series_id`, `season_number`, `episode_number`, `versions[]`, `playback_variants[]`, `subtitles[]`, `user_data` (resume position, `last_file_id`), `effective_*` preferences.
- Markers here use **`{start_seconds,end_seconds}`**.
- Each version adds `marker_segments:[{kind:"intro"|"credits"|"recap"|"preview", start_seconds, end_seconds}]` (ordered; a kind may repeat) and `trickplay_available`.
- Fixture: `get_watch_state_ok.json`.

### 4.6 Seasons and episodes
- `GET /api/v2/catalog/series/{series_id}/seasons?library_id=&image_size=&include_artwork=true`:
  ```json
  {"items":[{"content_id":"...","season_number":1,"title":"Season 1","episode_count":10,"is_specials":false,"air_date":"...","overview":"...","poster_url":"...","play_content_id":"<next ep>","user_data":{...}}]}
  ```
- `GET /api/v2/catalog/series/{series_id}/seasons/{num}/episodes?library_id=&image_size=` (num 0 = specials):
  ```json
  {"items":[{"content_id":"...","season_number":1,"episode_number":1,"title":"...","overview":"...","runtime":52,"air_date":"...",
             "still_url":"...","still_thumbhash":"...","files":[{"file_id":"42","resolution":"1080p","codec_video":"h264","container":"mkv","hdr":false,"audio_channels":6,"file_size":123,"unreadable":false}],
             "overlay_summary":{...},"user_data":{...}}]}
  ```
- Alternatively `GET /api/v2/catalog/items/{season_content_id}/episodes` returns the same shape.
- Versions only: `GET /api/v2/catalog/items/{id}/versions` → `{"items":[version...]}`.
- These lists are not paginated. The client rejects a response with `has_more:true`.

### 4.7 People
- Search: `GET /api/v2/catalog/people?q=&limit=20&media_scope=video|movie|series|episode|audiobook|ebook|manga` → `{"items":[{"id","name","photo_url","bio","birth_date","death_date","birthplace","homepage","tmdb_id","imdb_id"}]}`.
- One person: `GET /api/v2/catalog/people/{id}[?prefetch=true]`. This queues a provider refresh unless `prefetch=true`.
- Filmography: `GET /api/v2/catalog?source=person&person_id={id}&sort=-year&limit=50[&type=movie]`.

### 4.8 Similar items
`GET /api/v2/recommendations/similar/{content_id}?limit=12` (max 50) → `{"items":[card...]}`.

### 4.9 Collections
- Library collections tab: `GET /api/v2/library/{id}/collections` → `{"library_id","collections":[{id,title,poster_url,item_count,collection_type,sort_order,group_id,featured,...}],"groups":[{id,name,kind,sort_mode,sort_order,collections:[...]}],"ungrouped":{sort_order,collections:[]}}`.
- Items of a library collection: `GET /api/v2/catalog?source=library_collection&collection_id={cid}&library_id={id}&limit=50`. `GET /api/v2/library/{id}/collections/{cid}/items` also exists.
- Personal collections: `GET /api/v2/collections`. Items via `/api/v2/catalog?source=user_collection&collection_id=`.

---

## 5. Home screen

Files: `S/network/apiv2/HomeSectionsV2Api.kt`, `S/viewmodel/HomeViewModel.kt`, `A/androidTvApp/.../screens/home/TvHomeScreen.kt`, `TvHomeSections.kt`, `S/model/section/SectionModels.kt`, `FeaturedSplit.kt`.

**The whole home page is one call:** `GET /api/v2/home/sections[?image_size=]` (with `X-Profile-Id`):
```json
{"sections":[{"id":"continue_watching","section_type":"continue_watching","title":"Continue Watching","featured":false,
  "item_limit":20,"total_count":1,"is_custom":false,"customized":false,"items":[card...]}]}
```
- Items come inline. Only when a section has `total_count > 0` but no items does the client fetch `GET /api/v2/home/sections/{id}/items`; the response is a single section object of the same shape.
- **Hero/featured:** the first section with `featured:true` and non-empty items becomes the hero (`FeaturedSplit.kt`). Use its cards' `backdrop_url` and `logo_url`.
- **Server default home layout** (`SV/internal/sections/defaults.go:12–80`):
  1. Continue Watching (`continue_watching`; cards carry `item_source` = `in_progress` or `next_up` and `position_seconds`).
  2. Continue Listening, when an audiobook library exists.
  3. For each library: "Recently Added in X" (`recently_added`), plus either "Recently Released in X" (`recently_released`) or, for series libraries, "Recently Released Episodes in X" (`custom_filter`).
  4. Hidden Gems.
  5. Trending on Server.
  6. Seasonal Picks.
- **All `section_type` values:** `continue_watching, recently_added, recently_released, watchlist, favorites, genre, custom_filter, random, collection, recommended_for_you, because_you_watched, similar_users_liked, taste_match, next_up, next_in_series, hidden_gems, critically_acclaimed, award_winners, forgotten_favorites, format_showcase, editorial_spotlight, seasonal_themed, mood_collection, trending_on_server, profile_activity_feed, new_to_library, most_watched, trending_discover, admin_curated_list, returning_shows, genre_roulette, anniversaries, short_watches` (`SV/internal/sections/types.go:14–51`). Render any type generically as a row of cards.
- **TV-specific behaviour:**
  - Local hide/reorder of rows (`TvHomeSectionPreferences`).
  - Audiobook cards are split out of the continue row into "Continue Listening" (`TvHomeSections.kt`).
  - A "For You" row (`for_you` / `recommendations`) can open the For You screen.
  - The page is refreshed on resume, for example after playback.
- **"See all"** for a section: `GET /api/v2/catalog?source=section&section_id={id}&scope=home` (or `scope=library&library_id=`).
- **Dismiss from Continue Watching / Next Up:** `PUT /api/v2/home/dismissals/{continue_watching|next_up}/{content_id}` → 204.
  - Body for `continue_watching`: `{"progress_updated_at":"<card's value>"}`.
  - Body for `next_up`: `{"series_id":"..."}`.
  - Undo: `DELETE` on the same path.

---

## 6. For You, Watchlist, Favorites, Calendar, Search

**Discover / For You** (`S/network/apiv2/DiscoverV2Api.kt`, used by TV `TvRecommendationsScreen`):
- `GET /api/v2/recommendations/discover` → `{"items":[{"type":"cluster|similar_users_liked|popular|recently_added|top_rated|genre_sampler","key":"...","kind":"...","title":"...","items":[card...]}]}`.
- Also on the server: `GET /api/v2/recommendations/for-you/main?limit=20` returns `{key,kind,title,type,items}`; `/for-you/rows` returns `{items:[row]}`; `/taste-profile`.

**Favorites / Watchlist lists.** The TV reads them through the catalog: `GET /api/v2/catalog?source=favorites` and `GET /api/v2/catalog?source=watchlist` (with `limit`, `cursor`, `sort`). `GET /api/v2/watchlist` and `/api/v2/favorites` also exist.

**Toggles** (`S/network/apiv2/MembershipV2Api.kt`):
| Action | Request | Response |
|---|---|---|
| Add favorite | `PUT /api/v2/favorites/{content_id}` | 204 |
| Remove favorite | `DELETE /api/v2/favorites/{content_id}` | 204 |
| Add to watchlist | `PUT /api/v2/watchlist/{content_id}` | 204 |
| Remove from watchlist | `DELETE /api/v2/watchlist/{content_id}` | 204 |
| Check membership | `GET /api/v2/favorites/{id}` or `GET /api/v2/watchlist/{id}` | 200 `{"item_id","added_at"}`, or 404 if not a member |

All have no body. Do not auto-retry them.

**History.** `GET /api/v2/history?limit=40&cursor=&image_size=`.

**Calendar** (`S/network/api/CalendarApi.kt`). `GET /api/v2/calendar?start=YYYY-MM-DD&end=YYYY-MM-DD&filter=all|everything|following|favorites|watchlist|popular|trending&timezone=America/New_York&library_id=`.
- The window is at most 30 days.
```json
{"events":[{"date":"2026-01-09","items":[{"content_id":"episode:severance-s02e01","type":"episode","title":"Severance","episode_title":"Premiere",
  "series_id":"series:severance","season_number":2,"episode_number":1,"air_date":"2026-01-09","air_time":"21:00",
  "air_at":"2026-01-10T02:00:00.000Z","air_timezone":"America/New_York","local_air_date":"2026-01-09",
  "poster_url":"...","watched":false,"badges":["season_premiere"]}]}]}
```

**Search** (`A/androidTvApp/.../screens/search/TvSearchViewModel.kt`, `S/repository/SearchPeople.kt`):
- Titles: `GET /api/v2/catalog?source=query&q=<text>&type=<movie|series|audiobook…optional>&limit=N&cursor=`.
- People, in parallel: `GET /api/v2/catalog/people?q=<text>&limit=20&media_scope=<scope>`, one call per scope.
- Optional: `GET /api/v2/catalog/search/capabilities` → `{revision,state,provider,people_media_scope,result_window_limit,session_ttl_seconds}`.
- Show `total` as an estimate unless `total_exact`.

---

## 7. Images

Files: `S/network/ArtworkUrls.kt`, `S/network/api/ImageCapabilitiesApi.kt`, `SV/docs/images-api.md`, `SV/internal/artworkurl/artworkurl.go`.

- **The client never builds image URLs.** Every response carries ready-made URLs: `poster_url`, `backdrop_url`, `logo_url`, `still_url`, `photo_url` (people), `avatar_url` (profiles), `thumbnail_url` (chapters), and `poster_urls[]`.
- **Resolving a URL:**
  - Absolute (S3 presigned or CDN): use it as is.
  - Root-relative (`/api/v2/artwork/{key}?exp=<unix>&sig=<hmac>`): prepend `scheme://host[:port]` of the server **origin**. Note this is the origin, not a base that includes a path prefix (`resolveArtworkUrl`).
  - Never re-encode the query.
- **Auth:** artwork URLs are self-authorizing (signed `exp`/`sig`, or a presigned S3 URL). **Do not send `Authorization`.** An expired signature returns 404, so refetch the data. URLs change at least daily, or every 15 minutes for non-revisioned ones. You can cache by path.
- **Sizing:** add `image_size=small|medium|large|original` to the data request. It applies to every image in that response. It is accepted on:
  - catalog browse and query
  - item and watch detail
  - seasons and episodes
  - home and library sections
  - favorites, watchlist and history

  It is not accepted on people endpoints, which always return 500 px photos. Width ladder from `GET /api/v2/images/capabilities` (fixture `get_image_capabilities_ok.json`):
  ```json
  {"state":"available","param":"image_size","sizes":["small","medium","large","original"],
   "widths":{"poster":{"small":300,"medium":500,"large":780},"backdrop":{"small":300,"medium":1920,"large":1920},
             "still":{"small":300,"medium":500,"large":780},"logo":{"small":500,"medium":500,"large":1280},
             "profile":{"small":300,"medium":500,"large":500}},
   "original_max_width_px":1920,"storage_backend":"local","delivery":"server"}
  ```
  Only send `image_size` when `state == "available"`.
- **Placeholders:** an empty URL means no image; show a placeholder. `*_thumbhash` is a ThumbHash for placeholders and is optional.
- **Season lists:** `include_artwork=false` skips posters.
- **Trickplay:** `GET /api/v2/watch/{id}/trickplay?file_id=` returns signed sheet URLs and is optional.

---

## 8. Playback

Files:
- `S/network/apiv2/PlaybackV2Api.kt`
- `S/model/playback/PlaybackProtocolV3.kt`, `S/model/playback/PlaybackModels.kt`
- `S/repository/SequencedPlayback.kt`, `S/repository/PlaybackRepository.kt`
- `A/android-shared/.../common/player/PlaybackSessionManager.kt:296–380`, `PlaybackCapabilityDetector.kt:420–640`, `PlaybackSessionLifecycle.kt` (progress loop)
- `A/docs/playback/sequenced-api-v2.md`
- Server: `SV/docs/playback-api.md`, `SV/docs/architecture/playback-protocol-v3.md`, `SV/docs/design/schemas/playback-v3/v3/*.schema.json`

### 8.1 Pre-flight
1. Get the item: watch detail (`/api/v2/watch/{id}`) or item detail. Choose `file_id`:
   - the user's chosen version, otherwise
   - `user_data.last_file_id`, otherwise
   - the first version, or the `playback_variants[].default_file_id`.

   Resume position is `user_data.position_seconds`.
2. `GET /api/v2/playback/capabilities` (bearer + `X-Profile-Id`):
   ```json
   {"revision":"...","state":"available","allowed":true,"installation_id":"11111111-1111-4111-8111-111111111111",
    "protocol_versions":[3],
    "features":["playback_plan_v3","neutral_playback_v3_contract_v1","layout_aware_passthrough","device_quirks_v1","output_display_evidence_v1","direct_stream_resume_v1","software_video_decode_v1","plan_source_duration_v1","sequenced_progress_v1"],
    "deliveries":["original_http","server_transcode_hls"]}
   ```
   - Requirements (`SequencedPlayback.kt:200–205`): `state=="available"`, `allowed`, `3 ∈ protocol_versions`, `"sequenced_progress_v1" ∈ features`, and a non-blank `installation_id`.
   - **Keep `installation_id`.** Every playback mutation must echo it. A mismatch returns 409 `installation_changed`; refetch capabilities and start a new attempt.

### 8.2 Start: `POST /api/v2/playback/start` → **201**
Headers: bearer, `X-Profile-Id` (required), `X-Profile-Token` if locked, and the device headers. The request body is capped at 256 KiB.

**Body structure** (required fields marked *):
```text
protocol_version* = 3
installation_id*                 (from capabilities)
file_id*                         (STRING, e.g. "42")
profile_id*                      (must equal X-Profile-Id)
playback_attempt_id*             (fresh UUID per user "Play"; reuse only to retry a lost reply with the byte-identical body)
client_features*                 Android: ["playback_plan_v3","client_video_transformations_v1","device_quirks_v1","seek_reanchor_v1","direct_stream_resume_v1"] (+ embedded_subtitles_v1 / layout_aware_passthrough when applicable)
quality_preference*              "auto" | "original" | "720p" | "1080p" | "2160p" | a label from available_qualities
subtitle_fidelity_preference*    "preserve" | "compatible"      (TV uses "preserve"; Cast uses "compatible")
metered*                         bool
start_position                   seconds; OMIT = server uses saved resume; 0 = start over
progress_persistence             "server" (default) | "client"
audio_track_id / audio_track_index        omit = profile preference; id form "file:<file_id>:audio:<n>"
subtitle_track_id / subtitle_track_index  omit = off/profile default; never send -1; id form "file:<file_id>:subtitle:<n>"
bandwidth_estimate_kbps, bandwidth_cap_kbps
allow_alternate_versions         bool, optional
client_capabilities*:
  video_evidence*, audio_evidence*   "exact" | "platform_attested" | "declared"
  codecs_video*, codecs_video_hardware*, codecs_audio*, containers*   (lowercase names)
  hdr*  bool
  max_resolution  "1080p" | "2160p" …
  hdr_details {hdr10*, hdr10_plus*, hlg*, dolby_vision_profiles*[], dolby_vision_profile_levels[{profile,max_level,bl_compatibility_ids}], hdr10_max_*}
  audio_passthrough {passthrough_codecs*[], spatializer_enabled*, max_channels*, entries[{codec,channel_counts[],layouts[]}]}
  video_decode[] {codec*, hardware*, profiles[], levels[], bit_depths[], max_width, max_height, max_frame_rate, max_bitrate_kbps, decoder_name}
client_playback_context*:
  protocol_version* = 3, form_factor* ("tv"), app_version*, app_build, app_channel
  device* {platform, os_version, manufacturer, model, platform_details{string:string}}
  output* {hdr_details, audio_passthrough, current_sink, sink_type, output_context_id, display{hdr_evidence*: "exact"|"unknown", display_id, hdr_types}}
  deliveries*  map keyed by CLASS "original_http" | "progressive" | "hls":
     {enabled*, supported_on_device*, failure_reason, containers*[], video_codecs*[], audio_decode_codecs*[],
      audio_passthrough_codecs*[], max_channels, hdr_details,
      subtitles* {sidecar_text*, embedded_text*, ass_styling*, embedded_bitmap*, sidecar_bitmap*, font_attachments*, native_embedded[]},
      features*[], transformations*[], validated_claims*[], auth_header_refresh*}
```
Rules:
- A class missing from `deliveries` is treated as unavailable.
- A body that is not the final v3 shape (protocol_version 3 plus both evidence fields) returns **426 client_upgrade_required**.
- 404 means the file is missing or hidden from this profile.
- 409 means the attempt id was reused with a different body.

**Evidence tier for Roku: use `"declared"`.** With `declared`, the server matches only against the flat lists and never walks `video_decode[]` (`playback-protocol-v3.md` §3).
- The `exact` and `platform_attested` tiers require full `video_decode[]` entries with `hardware:true`. Without them the plan falls back to transcode with reason `evidence_insufficient_for_direct`.
- Audio passthrough is honoured only at `exact`. Under `declared`, list AC3/EAC3 as decode codecs.

**Minimal Roku example** (H.264/HEVC, AAC/AC3/EAC3, MP4/MKV direct play, HLS for remux and transcode, WebVTT sidecars):
```json
{
  "protocol_version": 3,
  "installation_id": "11111111-1111-4111-8111-111111111111",
  "file_id": "42",
  "profile_id": "p-owner",
  "playback_attempt_id": "6f1c2a8e-6c2b-4c55-9d2a-0a8e2f6b1d11",
  "client_features": ["playback_plan_v3"],
  "quality_preference": "auto",
  "subtitle_fidelity_preference": "compatible",
  "metered": false,
  "start_position": 1325.5,
  "client_capabilities": {
    "video_evidence": "declared",
    "audio_evidence": "declared",
    "codecs_video": ["h264", "hevc"],
    "codecs_video_hardware": ["h264", "hevc"],
    "codecs_audio": ["aac", "ac3", "eac3", "mp3"],
    "containers": ["mp4", "m4v", "mkv", "mov"],
    "max_resolution": "2160p",
    "hdr": false,
    "hdr_details": {"hdr10": false, "hdr10_plus": false, "hlg": false, "dolby_vision_profiles": []}
  },
  "client_playback_context": {
    "protocol_version": 3,
    "form_factor": "tv",
    "app_version": "1.0.0",
    "device": {"platform": "roku", "os_version": "14.0", "manufacturer": "Roku", "model": "4800X"},
    "output": {"output_context_id": "1", "display": {"hdr_evidence": "unknown"}},
    "deliveries": {
      "original_http": {
        "enabled": true, "supported_on_device": true,
        "containers": ["mp4", "m4v", "mkv", "mov"],
        "video_codecs": ["h264", "hevc"],
        "audio_decode_codecs": ["aac", "ac3", "eac3", "mp3"],
        "audio_passthrough_codecs": [],
        "subtitles": {"sidecar_text": true, "embedded_text": false, "ass_styling": false,
                      "embedded_bitmap": false, "sidecar_bitmap": false, "font_attachments": false},
        "features": [], "transformations": [], "validated_claims": [], "auth_header_refresh": false
      },
      "hls": {
        "enabled": true, "supported_on_device": true,
        "containers": ["m3u8", "hls"],
        "video_codecs": ["h264", "hevc"],
        "audio_decode_codecs": ["aac", "ac3", "eac3"],
        "audio_passthrough_codecs": [],
        "subtitles": {"sidecar_text": true, "embedded_text": false, "ass_styling": false,
                      "embedded_bitmap": false, "sidecar_bitmap": false, "font_attachments": false},
        "features": ["hls"], "transformations": [], "validated_claims": [], "auth_header_refresh": false
      }
    }
  }
}
```
- Set `hdr` / `hdr_details.hdr10` / `hlg` / `dolby_vision_profiles` from `roDeviceInfo.GetDisplayProperties()` / `CanDecodeVideo`.
- For an HDR display you may set `output.display: {"hdr_evidence":"exact","hdr_types":{...}}`.
- Omit `"progressive"`; Android sends it disabled.
- References: the server's golden example is `SV/docs/design/schemas/playback-v3/v3/fixtures/valid/start_request.json`. The web client's `declared` context is `SV/web/src/player/client-context-v3.ts`.

**Response 201** (fixture `playback_start_opaque_ids.json`, abridged):
```json
{"protocol_version":3,"server_features":["playback_plan_v3","neutral_playback_v3_contract_v1","...","sequenced_progress_v1"],
 "outcome":"playable","session_id":"1111...",
 "playback_plan":{
   "protocol_version":3,"plan_id":"plan:4786...","plan_attempt_key":"v3:f0144c47fa349e3e","session_id":"1111...","expires_at":"2030-01-01T00:00:00Z",
   "delivery":"original_http",
   "stream":{"url":"/api/v2/stream/1111...?st=...","protocol":"http_progressive","container":"mp4","mime_type":"video/mp4","headers":{},"header_refresh":"none"},
   "timeline":{"source_start_seconds":12.5,"stream_origin_seconds":0,"player_start_seconds":12.5,"timeline_offset_seconds":0,"can_seek_anywhere":true,"seek_restoration":"player_position"},
   "selected_tracks":{"audio":{"id":"file:42:audio:0","index":0}},
   "effective_recipe":{"video_codec":"h264","audio_codec":"aac","width":1920,"height":1080,"frame_rate":23.976,"bitrate_kbps":8000,"dynamic_range":"sdr","audio_channels":2,"audio_layout":"stereo"},
   "claims":{...},
   "subtitle":{"mode":"off","inventory":[
      {"track_id":"file:42:subtitle:0","combined_index":0,"source":"external","codec":"srt","language":"eng","label":"English","forced":false,"default":false,"hearing_impaired":false,
       "delivery":"sidecar","url":"/api/v2/stream/1111.../subtitles/0.vtt?file_id=42&external_subtitle_key=f903...","sync_key":"external-f903..."},
      {"track_id":"file:42:subtitle:1","combined_index":1,"source":"embedded","codec":"ass","language":"eng","label":"English (Signs)","forced":true,"delivery":"sidecar",
       "url":"/api/v2/stream/1111.../subtitles/1.ass?file_id=42&embedded_stream_index=0","font_bundle_url":"..."},
      {"track_id":"file:42:subtitle:2","combined_index":2,"codec":"pgs","delivery":"sidecar","url":".../subtitles/2.sup?file_id=42&embedded_stream_index=1"},
      {"track_id":"file:42:subtitle:3","combined_index":3,"codec":"dvd_subtitle","delivery":"burn_in_only"}]},
   "available_qualities":[{"label":"original","height":1080,"bitrate_kbps":8000,"preserves_source":true}],
   "transformations":[],"applied_quirks":[],"runtime_corrections":[],"degradation_warnings":[],
   "decision_reason":"validated_original_playback","requested_media_file_id":"42","effective_media_file_id":"42",
   "source":{"media_file_id":"42","duration_seconds":7200,"container":"mp4","video_codec":"h264","width":1920,"height":1080,"dynamic_range":"sdr","audio_codec":"aac","audio_channels":2,"...":"..."},
   "subtitle_fidelity_policy":"allow_simplified_rendering"}}
```
- If the media can't be played you still get 201, with `{"outcome":"adaptation_unavailable","terminal":{"reason":"...","message":"...","retryable":false}}`. Reasons include `session_expired` (retryable: mint a new attempt), `source_metadata_incomplete` and `source_unreadable`.
- **Direct play vs transcode:** read `playback_plan.delivery`:
  - `original_http`: direct play of the original file. `stream.protocol = http_progressive`.
  - `server_remux_progressive`: progressive remux.
  - `server_remux_hls`: HLS remux, codecs copied.
  - `server_transcode_hls`: HLS transcode. `stream.protocol = hls`, URL `/api/v2/playback/transcode/{session}/master.m3u8?st=...`.
- Client checks before playing (`validateForMedia3`, `PlaybackProtocolV3.kt`):
  - `protocol_version == 3`, and `server_features` contains `playback_plan_v3` and `neutral_playback_v3_contract_v1`.
  - `plan_attempt_key` is non-empty.
  - The subtitle inventory is gap-free, 0..n-1.
  - `header_refresh != "refresh_endpoint"`.
- **Stream URL resolution and auth:**
  - URLs are root-relative under `/api/v2/...`. Resolve them against the server origin. Replay them byte-for-byte and never edit the query. Absolute proxy URLs may appear.
  - Without `header_authenticated_media_v1` in `client_features` (Android does not send it), media URLs carry a signed `st` query.
  - **Account auth is still required on every media request:** send `Authorization: Bearer <access>` (Roku: `ContentNode.HttpHeaders` / `Video` node headers, which also apply to HLS segments). `X-Profile-Id` is optional on these routes (`ProfileOptional: true`, `SV/internal/apiv2/playback_delivery.go:152`).
  - Fallback for players that cannot set headers: append `&token=<access_token>` (`SV/internal/api/middleware/auth.go:320–333`; documented in `SV/docs/playback-api.md` §Delivery). Relative HLS segment URIs will not inherit it, so prefer headers.
  - `stream.headers` never contains the bearer token.
  - Ended or stopped sessions return 410 `playback_session_ended`.
- **Timeline:**
  - Seek the player to `timeline.player_start_seconds`.
  - Source position = player position + `timeline_offset_seconds`.
  - If `can_seek_anywhere:false` (HLS copy-remux), seeking needs a `seek_reanchor` replan.
  - Use `source.duration_seconds` as the runtime. It is omitted when unknown, and you must not use the player's duration on remux HLS.
- **Subtitles:**
  - Pick from `subtitle.inventory`.
  - `delivery:"sidecar"` comes with `url`: `.vtt`, `.srt`, `.ass` or `.sup`. External and downloaded SRT are served as `.vtt`.
  - `burn_in_only` has no URL; it needs a replan with `subtitle_track_id` to get a burned-in transcode.
  - Subtitle URLs carry **no `st`**, so they require `Authorization` (or `token=`).
  - A VTT URL may take `timestamp_offset=<seconds>`.
  - For Roku, only use `.vtt`/`.srt` sidecars, and send `subtitle_fidelity_preference:"compatible"`.
- **Track change or quality change:** `POST /api/v2/playback/{session_id}/replan` → 200, same decision shape. Body:
  ```text
  protocol_version, installation_id, client_features, operation ("track_change"|"quality_change"|"seek_reanchor"|"failure_recovery"|"seek_failure_recovery"|"output_change"),
  playback_attempt_id, replan_request_id (new UUID), failed_plan_id (= current plan_id), plan_attempt_id (UUID), plan_attempt_key (current),
  attempted_plan_keys [..], attempt_count, quality_preference, position_seconds, metered,
  selected_tracks {audio:{id,index}, subtitle:{id,index}}, failure {classification, message} (failure ops only),
  client_capabilities, client_playback_context
  ```
- Optional diagnostics: `POST /api/v2/playback/route-events` with `{... ,installation_id, event_id}` → 202. Do not retry.

### 8.3 Progress reporting
- **Interval: every 10 s** while a session is active (`PlaybackSessionLifecycle.kt:931`, `PROGRESS_REPORT_INTERVAL_MS = 10_000`). Also send a final sample on pause, exit, or episode change.
- `POST /api/v2/playback/{session_id}/progress`:
  ```json
  {"installation_id":"1111...","sequence":42,"position":120.0,"is_paused":false}
  ```
  - `additionalProperties:false`: send exactly these fields.
  - `position` is in source seconds.
  - `sequence` is a strictly increasing positive integer per session. On a lost reply, resend the same sample.
  - → 200 `{"outcome":"applied","accepted":{"sequence":42,"position":120,"is_paused":false}}`.
  - Other outcomes: `stale_sample` (lower sequence) and `replayed` (same sample).
  - 409 `progress_conflict` (same sequence, different payload), 403 (another profile), 404 (stopped or unknown session).
  - Progress also writes the item's resume position and scrobbles when `progress_persistence` is `server`.
- **Stop:** `DELETE /api/v2/playback/{session_id}` with a JSON body:
  ```json
  {"installation_id":"1111...","stop_id":"44444444-4444-4444-8444-444444444444","sequence":43,"position":130.0,"is_paused":true}
  ```
  - `stop_id` is a UUID minted once and reused on retries.
  - The final `sequence`/`position`/`is_paused` sample is optional, but `sequence` and `position` must appear together.
  - → 200 `{"outcome":"stopped","stop_id":"...","accepted":{...},"history_id":"..."}`. Later stops return `{"outcome":"replayed",...}`.
  - The server expires sessions nobody stops.
- **Resume position:** `user_data.position_seconds` from watch or item detail, or `position_seconds` on continue-watching cards. Pass it as `start_position`, or omit `start_position` and the server uses saved resume.
- `GET /api/v2/progress?status=in_progress|completed&library_id=&limit=&cursor=` → `{"items":[{"media_item_id","position_seconds","duration_seconds","completed","updated_at"}]}`.
- Client-owned progress (audiobooks) is written with `POST /api/v2/sync/progress`. A Roku video player does not need it.

### 8.4 Watched, favorite and rating
| Action | Request | Response |
|---|---|---|
| Mark watched | `POST /api/v2/watched/{content_id}` | 204 |
| Mark unwatched | `DELETE /api/v2/watched/{content_id}` | 204 |
| Set rating | `PUT /api/v2/ratings/{content_id}` with `{"rating":1..5}` | 204 |
| Clear rating | `DELETE /api/v2/ratings/{content_id}` | 204 |

- Watched/unwatched have no body. A season or series expands to all of its episodes.
- Source: `S/repository/port/PersonalWrite.kt`.
- Favorite and watchlist toggles are in §6.

### 8.5 Skip intro and credits
- Markers come from watch detail (`intro`/`credits`/`recap`/`preview` as `{start_seconds,end_seconds}`, plus per-version `marker_segments[]`) or from item detail (`{start,end}`).
- The `marker_segments_v1` capability feature advertises them. `GET /api/v2/markers/items/{item_id}` and `/markers/files/{file_id}` also exist.
- Behaviour setting: `playback.intro_skip_mode` = `never|ask|always` (default `ask`). It replaces the old profile flags `auto_skip_intro` / `auto_skip_credits`.
  - Read it with `GET /api/v2/settings/values/effective?keys=playback.intro_skip_mode` → `{"items":[{"key","value","source",...}],"revision":8}`.
  - Docs: `A/docs/playback/intro-skip.md`.
  - The client implements the skip as a plain player seek.

### 8.6 Next episode
This is computed entirely on the client (`S/playback/NextEpisodeResolver.kt`):
- Build a pool from the current season's episodes plus the next regular season's episodes (`/catalog/series/{id}/seasons` + `/seasons/{n}/episodes`).
- Sort by (season, episode) and take the first item after the current one.
- Specials (season 0) are only "next" when the current item is itself a special.
- Then start a new playback attempt for that episode's file.
- For a series card, play `play_content_id` (and `play_season_number`).
- On the server side, the Next Up rows are the `continue_watching` sections with `item_source:"next_up"`.

---

## 9. WebSockets: all optional

None is needed for login, browsing or playback. REST is the source of truth everywhere.

- **Events** (home refresh and notification badge): `POST /api/v2/events/ws-ticket` → `{ticket, protocol:"silo.events.v2", expires_in, max_connection_seconds}`.
  - Then `GET wss://.../api/v2/events/ws?channels=user_state,catalog,...`.
  - The handshake uses `Sec-WebSocket-Protocol: silo.events.v2, silo.ticket.<ticket>` and no bearer header (`S/network/apiv2/EventsSocketV2Api.kt`).
  - The TV refreshes Home on resume instead.
- **Playback control socket** (remote control and `plan_invalidated`): `POST /api/v2/playback/sessions/{id}/control/ws-ticket` with body `{installation_id}`, then `.../control/ws` with protocol `silo.playback-control.v2` (`S/network/PlaybackRealtimeClient.kt`).
  - Without it, sessions keep working; progress is the heartbeat. Don't advertise `plan_invalidated_v1`.
- Watch Together room sockets: transport only; no UI in either Android app.

---

## 9b. Settings: the effective cascade (Android TV parity)

Android TV's Settings screen is mostly server-synced per profile (`shared/.../network/apiv2/SettingsV2Api.kt`, `TvSettingsViewModel.kt`). Siku does the same in `components/common/Settings.brs`.

- **Probe:** `GET /api/v2/settings/contract/capabilities` → `{api_version, manifest_revision, scopes[], client_families[], supports_batched_effective, ...}`. Filter the keys you ask for by `introduced_in <= manifest_revision` (contracts/settings/v1/manifest.json): an unknown key makes the whole effective request fail with 422 `validation_failed`.
- **Read:** `GET /api/v2/settings/values/effective?keys=a&keys=b` (one `keys` parameter per key; `X-Profile-Id` required) → `{"items":[{"key","value","source":"default|profile|profile_device|profile_client|...","scope"?,"profile_id"?,"device_id"?,"client_family"?,"stored_value"?,"constrained"?,"suggested_values"?[]}],"revision":16}`. The `X-Silo-Device-Id` header selects the `profile_device` rows and `X-Silo-Client-Family` the `profile_client` rows; `ApiTask` sends both on every call.
- **Write:** `PUT /api/v2/settings/values/{key}?scope=profile|profile_device|profile_client` with `{"value": ...}` → 200, the stored row `{key, scope, profile_id, device_id?, client_family?, value, revision, updated_at}`. `DELETE` with the same query → 204 (404 when nothing was stored there, which callers treat as done). A language tag is cleared with DELETE, never written as `""`.
- **Scopes the TV app uses** (and Siku copies): `profile` for `playback.subtitle_language`, `playback.subtitle_mode`, `playback.show_forced_subtitles`, `catalog.metadata_language`, `player.video_skip_back/forward_seconds` (revision 9) and `ui.title_art` while "Apply to all devices" is on; `profile_device` for `playback.preferred_quality` + `playback.max_bitrate_kbps` (one Quality preset = both axes), `playback.audio_language`, `playback.intro_skip_mode`, `playback.auto_skip_credits`, `playback.auto_play_next`, `playback.next_up_prompt_seconds`, `playback.subtitle_appearance` (the whole object; `textOpacity` only when `manifest_revision >= 14`) and `player.dolby_vision_enabled`; `profile_client` for `ui.card_presentation` (`{poster_size, caption}`), `profile_device` while "Only This Device" is on. "Reset Playback Overrides" deletes every `profile_device` row above.
- **Client-local (contract `client_local`, never written):** `nav.show_audiobooks`, `player.resume_rewind_seconds`, `player.passout_threshold`, `subtitle.matches_device`, and the Home row order / hidden set (`prefs`).
- `tools/mock_server.py` serves all of this with the contract defaults and a per-scope store.

## 10. Recommended Roku call sequence

1. User enters a URL → normalize → probe `/api/v2/system/info`, `/system/setup`, `/auth/signup` (https first, then http).
2. Sign in:
   - Device code: `/auth/device/capability` → `/start` → poll `/poll` every `interval` s → tokens. Or `/auth/login`.
   - Store `access_token`, `refresh_token`, `expires_in`, `server_id`.
3. `GET /api/v2/profiles` → choose a profile, with `/profiles/{id}/verify-pin` if `has_pin` → send `X-Profile-Id` (+ `X-Profile-Token`) from now on.
4. `GET /api/v2/user/libraries`, then `GET /api/v2/home/sections?image_size=medium`.
5. Optional: `GET /api/v2/images/capabilities` and `GET /api/v2/playback/capabilities` (cache `installation_id`).
6. Detail: `/api/v2/catalog/items/{id}` (+ `/catalog/series/{id}/seasons`, `/seasons/{n}/episodes`, `/recommendations/similar/{id}`).
7. Play:
   1. `/api/v2/watch/{id}` → choose `file_id` and resume position.
   2. `POST /api/v2/playback/start` → play `stream.url` with Authorization headers.
   3. Progress every 10 s.
   4. `DELETE /api/v2/playback/{session}` on exit.
   5. Resolve the next episode on the client.
8. On any 401: refresh once with the rotating refresh token, then retry.

---

## Discrepancies and caveats
- `/health` (root) is called by the client, but this server checkout registers it only at `/api/v1/health`. Use `/api/v2/system/info` and `/api/v2/system/identity` for reachability.
- Integer vs string IDs:
  - The server returns `media_file_id` / `requested_media_file_id` as **strings** in v2. Android's internal model parses them as Int.
  - The golden v3 schema fixture uses an integer `file_id`, but the v2 openapi says `file_id` is a string. Send a string.
- Marker field names differ by endpoint: `{start,end}` on `/catalog/items/{id}`, but `{start_seconds,end_seconds}` on `/watch/{id}` and `marker_segments`.
- `SV/docs/architecture/playback-protocol-v3.md` §2 describes the `/api/v1` error envelope. v2 uses problem+json. Its path list (`/stream/...`) is relative to the API prefix; in v2 the paths are `/api/v2/stream/...`.
- Not verified here: whether a Roku Video node forwards `HttpHeaders` to sidecar subtitle fetches. The server accepts `?token=` on subtitle routes as a fallback.
