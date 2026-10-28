' Server-synced settings: the Silo "effective settings cascade" the Android TV client reads
' through GET /api/v2/settings/values/effective and writes through PUT/DELETE
' /api/v2/settings/values/{key}?scope=... (shared/.../network/apiv2/SettingsV2Api.kt).
'
' The loaded snapshot lives on m.global.settings:
'   { ready, available, identity, revision, items: { key: {value, source, scope, ...} }, error }
' Screens observe m.global "settings" to re-render. Every getter below falls back to the
' device prefs (m.global.prefs) when the server has not answered, so playback never waits.
'
' Scopes, as the TV app uses them (TvSettingsViewModel + PlayerSettingsStore):
'   profile         subtitle language/mode, forced subtitles, metadata language, skip intervals,
'                   title art when "Apply to all devices" is on, subtitle appearance and (manifest
'                   revision 19+) subtitle timing unless "Only on This Device" is on (Silo Android #680)
'   profile_device  quality, bitrate cap, audio language, intro skip, auto-skip credits,
'                   auto-play next, Up Next prompt seconds, Dolby Vision, subtitle appearance and
'                   timing while "Only on This Device" is on (timing always below revision 19)
'   profile_client  cards & posters (roams between TVs), profile_device with "Only This Device"
' The device half of profile_device rides the X-Silo-Device-Id header ApiTask always sends.
' SPDX-License-Identifier: AGPL-3.0-or-later

' ---------- Keys ----------

' Every key Siku reads, with the manifest revision that introduced it (a server answers 422 for
' a key it does not know, so the request is filtered by its manifest_revision) and the
' contract default (contracts/settings/v1/manifest.json).
function Settings_keyDefs() as object
    if m.siku_settingKeys <> invalid then return m.siku_settingKeys
    m.siku_settingKeys = [
        { key: "playback.preferred_quality", rev: 1, def: "auto" }
        { key: "playback.max_bitrate_kbps", rev: 1, def: invalid }
        { key: "playback.audio_language", rev: 1, def: "" }
        { key: "playback.subtitle_language", rev: 1, def: "" }
        { key: "playback.subtitle_mode", rev: 1, def: "auto" }
        { key: "playback.show_forced_subtitles", rev: 1, def: true }
        { key: "playback.intro_skip_mode", rev: 7, def: "ask" }
        { key: "playback.buffering_quality_mode", rev: 21, def: "always" }
        { key: "playback.auto_skip_credits", rev: 1, def: false }
        { key: "playback.auto_play_next", rev: 1, def: true }
        { key: "playback.next_up_prompt_seconds", rev: 1, def: 30 }
        { key: "playback.subtitle_appearance", rev: 1, def: Settings_defaultAppearance() }
        { key: "player.subtitle_sync_ms", rev: 1, def: 0 }
        { key: "player.hdr_enabled", rev: 1, def: true }
        { key: "player.dolby_vision_enabled", rev: 1, def: true }
        { key: "player.dv_profile7_hdr10_fallback", rev: 1, def: false }
        { key: "player.video_skip_back_seconds", rev: 9, def: 10 }
        { key: "player.video_skip_forward_seconds", rev: 9, def: 30 }
        { key: "catalog.metadata_language", rev: 1, def: "" }
        { key: "home.hide_watched_items", rev: 12, def: false }
        { key: "ui.card_presentation", rev: 5, def: { poster_size: "standard", caption: Settings_retiredCardCaption() } }
        { key: "ui.title_art", rev: 16, def: true }
        { key: "ui.disabled_library_ids", rev: 1, def: invalid }
        { key: "ui.theme_music_enabled", rev: 11, def: false }
        { key: "ui.theme_music_loop", rev: 11, def: false }
        ' Spoiler protection (Spoilers.brs). "optional": a server can reach the revision without the
        ' keys (upstream #427 saw revision 16 taken by other settings), so a refused read retries without them.
        { key: "catalog.hide_unwatched_episode_images", rev: 17, def: false, optional: true }
        { key: "catalog.hide_unwatched_episode_overviews", rev: 17, def: false, optional: true }
    ]
    return m.siku_settingKeys
end function

' The keys written at profile_device scope; "Reset Playback Overrides" deletes each of them.
function Settings_deviceKeys() as object
    return ["playback.preferred_quality", "playback.max_bitrate_kbps", "playback.audio_language", "playback.intro_skip_mode", "playback.buffering_quality_mode", "playback.auto_skip_credits", "playback.auto_play_next", "playback.next_up_prompt_seconds", "playback.subtitle_appearance", "player.subtitle_sync_ms", "player.hdr_enabled", "player.dolby_vision_enabled", "player.dv_profile7_hdr10_fallback"]
end function

function Settings_defaultAppearance() as object
    return { fontSize: "large", fontFamily: "sans-serif", fontColor: "#ffffff", textOpacity: 100, backgroundColor: "#000000", backgroundStyle: "shadow", backgroundOpacity: 75, textOutline: false, textOutlineColor: "#000000", position: "bottom" }
end function

' ---------- State ----------

function Settings_empty() as object
    return { ready: false, available: false, identity: "", revision: 0, manifestRevision: 0, items: {}, error: "", loadSeq: 0 }
end function

' The server + profile the snapshot belongs to.
function Settings_identity() as string
    s = m.global.session
    if s = invalid then return ""
    return Str_orEmpty(s.serverUrl) + "|" + Str_orEmpty(s.profileId)
end function

function Settings_state() as object
    st = m.global.settings
    if st = invalid or Type(st) <> "roAssociativeArray" then return Settings_empty()
    return st
end function

' True once the server answered for the current server + profile.
function Settings_available() as boolean
    st = Settings_state()
    return st.available = true and st.identity = Settings_identity()
end function

function Settings_manifestRevision() as integer
    st = Settings_state()
    if st.manifestRevision = invalid then return 0
    return Int(st.manifestRevision)
end function

' One resolved entry {value, source, scope, ...} or invalid.
function Settings_item(key as string) as dynamic
    if not Settings_available() then return invalid
    items = Settings_state().items
    if items = invalid then return invalid
    return items[key]
end function

' The effective value, or `fallback` when the server has not answered (or the key is unknown).
function Settings_value(key as string, fallback as dynamic) as dynamic
    it = Settings_item(key)
    if it = invalid then return fallback
    if it.value = invalid then return fallback
    return it.value
end function

' Where the effective value came from: "default", "profile", "profile_device", "profile_client", ...
function Settings_source(key as string) as string
    it = Settings_item(key)
    if it = invalid then return ""
    if not Str_isEmpty(it.scope) then return it.scope
    return Str_orEmpty(it.source)
end function

sub Settings_clear()
    m.global.settings = Settings_empty()
end sub

' ---------- Loading (call from a component; needs Api.brs) ----------

' Probes the contract (capabilities), then resolves every key the server knows in one request.
' Publishes the result on m.global.settings; observe that field to react.
' Every load gets the next number of an app-wide sequence (m.global.settingsLoadSeq), and the
' published snapshot remembers the number it came from (`loadSeq`). Loads from several screens and
' the reload after a write overlap: an answer older than the snapshot already published is dropped,
' so it cannot put back values that were changed meanwhile.
sub Settings_load()
    if not m.global.hasField("settingsLoadSeq") then m.global.addFields({ settingsLoadSeq: 0 })
    seq = m.global.settingsLoadSeq + 1
    m.global.settingsLoadSeq = seq
    Api_call({ method: "GET", path: "/api/v2/settings/contract/capabilities", context: { identity: Settings_identity(), seq: seq } }, "Settings_onCaps")
end sub

' True when an answer must not be published: it is for another server or profile, or a newer load
' has already published (pure apart from the notify; tests/test_settings_load_seq.py). The screen
' that started a superseded load is still told, so it re-reads the current snapshot.
function Settings_superseded(context as dynamic, identity as string) as boolean
    if identity <> Settings_identity() then return true
    seq = Settings_contextSeq(context)
    published = Int(Content_numOr(Settings_state().loadSeq, 0))
    if seq >= published then return false
    print "[Settings] load "; seq; " dropped: load "; published; " already published"
    Settings_notify()
    return true
end function

function Settings_contextSeq(context as dynamic) as integer
    if Type(context) <> "roAssociativeArray" then return 0
    return Int(Content_numOr(context.seq, 0))
end function

sub Settings_onCaps(event as object)
    resp = Api_result(event)
    identity = ""
    if resp.context <> invalid then identity = Str_orEmpty(resp.context.identity)
    if Settings_superseded(resp.context, identity) then return
    seq = Settings_contextSeq(resp.context)
    if not resp.ok or Type(resp.data) <> "roAssociativeArray" then
        Settings_publishError(identity, Api_errorText(resp), Settings_contextSeq(resp.context))
        return
    end if
    rev = Int(Content_numOr(resp.data.manifest_revision, 1))
    Settings_readEffective(identity, rev, true, seq)
end sub

' One batched read of every key the manifest revision knows; withOptional = false leaves out the
' keys a server at that revision may still refuse.
sub Settings_readEffective(identity as string, rev as integer, withOptional as boolean, seq as integer)
    keys = []
    hasOptional = false
    for each d in Settings_keyDefs()
        if d.rev <= rev then
            if d.optional = true then
                hasOptional = true
                if withOptional then keys.Push(d.key)
            else
                keys.Push(d.key)
            end if
        end if
    end for
    mayRetry = withOptional and hasOptional
    Api_call({ method: "GET", path: "/api/v2/settings/values/effective", query: { keys: keys }, context: { identity: identity, manifestRevision: rev, canRetry: mayRetry, seq: seq } }, "Settings_onEffective")
end sub

sub Settings_onEffective(event as object)
    resp = Api_result(event)
    identity = ""
    rev = 0
    if resp.context <> invalid then
        identity = Str_orEmpty(resp.context.identity)
        rev = Int(Content_numOr(resp.context.manifestRevision, 0))
    end if
    if Settings_superseded(resp.context, identity) then return
    ' 404 unknown_setting / 422: the server does not know an optional key; read the rest.
    if not resp.ok and (resp.status = 404 or resp.status = 422) and resp.context <> invalid and resp.context.canRetry = true then
        Settings_readEffective(identity, rev, false, Settings_contextSeq(resp.context))
        return
    end if
    if not resp.ok or Type(resp.data) <> "roAssociativeArray" then
        Settings_publishError(identity, Api_errorText(resp), Settings_contextSeq(resp.context))
        return
    end if
    items = {}
    for each row in Arr_or(resp.data.items)
        if Type(row) = "roAssociativeArray" and not Str_isEmpty(row.key) then
            items[row.key] = {
                value: row.value
                source: Str_orEmpty(row.source)
                scope: Str_orEmpty(row.scope)
                storedValue: row.stored_value
                constrained: row.constrained = true
                suggested: Arr_or(row.suggested_values)
            }
        end if
    end for
    m.global.settings = {
        ready: true
        available: true
        identity: identity
        revision: Int(Content_numOr(resp.data.revision, 0))
        manifestRevision: rev
        items: items
        error: ""
        loadSeq: Settings_contextSeq(resp.context)
    }
    Settings_notify()
end sub

' Tells the component that called Settings_load that the snapshot changed: it declares a
' boolean `settingsLoaded` field (alwaysNotify) whose onChange re-renders. Components that did
' not start the load re-read m.global.settings when they are shown again.
sub Settings_notify()
    if m.top <> invalid and m.top.hasField("settingsLoaded") then m.top.settingsLoaded = true
end sub

sub Settings_publishError(identity as string, message as string, seq as integer)
    prev = Settings_state()
    st = Settings_empty()
    st.ready = true
    st.identity = identity
    st.error = message
    st.loadSeq = seq
    ' Keep an earlier successful answer for the same server + profile; a transient failure
    ' should not throw away values playback is using.
    if prev.available = true and prev.identity = identity then
        st.available = true
        st.items = prev.items
        st.revision = prev.revision
        st.manifestRevision = prev.manifestRevision
    end if
    m.global.settings = st
    Settings_notify()
end sub

' ---------- Writes ----------

' PUT /api/v2/settings/values/{key}?scope=... with {"value": ...}. The response is the stored row.
function Settings_put(key as string, scope as string, value as dynamic, callback as string, context = invalid as dynamic) as object
    return Api_call({ method: "PUT", path: "/api/v2/settings/values/" + Str_urlEncode(key), query: { scope: scope }, body: { value: value }, context: context }, callback)
end function

' DELETE /api/v2/settings/values/{key}?scope=... → 204 (404 when nothing was stored there).
function Settings_delete(key as string, scope as string, callback as string, context = invalid as dynamic) as object
    return Api_call({ method: "DELETE", path: "/api/v2/settings/values/" + Str_urlEncode(key), query: { scope: scope }, context: context }, callback)
end function

' ---------- Typed getters (server value, else the device pref, else the contract default) ----------

function Content_numOr(v as dynamic, fallback as float) as float
    if v = invalid then return fallback
    t = Type(v)
    if t = "roInt" or t = "roInteger" or t = "Integer" or t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double" or t = "roLongInteger" or t = "LongInteger" then return v * 1.0
    if t = "roString" or t = "String" then
        if v.Trim() = "" then return fallback
        return Val(v)
    end if
    return fallback
end function

function Settings_prefs() as object
    p = m.global.prefs
    if p = invalid then return {}
    return p
end function

' The resolution axis of the quality choice ("auto" | "480p" | "720p" | "1080p" | "2160p"), as
' QualityPresets.normalizeResolution reads it: there is no Original any more (Silo Android #613),
' so a stored "original" (and "source" / "max") is Auto, which plays the file itself whenever the
' device and connection can. Compound spellings older builds wrote ("1080p-high") keep only
' their resolution; anything unknown is Auto. Video requests therefore never send "original".
function Settings_quality() as string
    q = Settings_value("playback.preferred_quality", invalid)
    if Str_isEmpty(q) then q = Settings_prefs().quality
    return Settings_normalizeResolution(q)
end function

function Settings_normalizeResolution(value as dynamic) as string
    q = LCase(Str_orEmpty(value)).Trim()
    if q = "" or q = "auto" or q = "original" or q = "source" or q = "max" then return "auto"
    dash = Instr(1, q, "-")
    if dash > 0 then q = Left(q, dash - 1)
    if q = "4k" then return "2160p"
    if q = "480p" or q = "720p" or q = "1080p" or q = "2160p" then return q
    return "auto"
end function

' The bandwidth axis in kbps; 0 = uncapped (the setting is null or absent).
function Settings_maxBitrateKbps() as integer
    return Int(Content_numOr(Settings_value("playback.max_bitrate_kbps", invalid), 0))
end function

' playback.buffering_quality_mode (settings contract revision 21, Silo Android #636): what happens
' on Auto when playback keeps buffering. "never" | "ask" | "always" (the default, also on a server
' that does not know the key).
function Settings_bufferingQualityMode() as string
    v = LCase(Str_orEmpty(Settings_value("playback.buffering_quality_mode", invalid)))
    if v = "never" or v = "ask" then return v
    return "always"
end function

' The server knows playback.buffering_quality_mode (manifest revision 21 or later).
function Settings_supportsBufferingQualityMode() as boolean
    return Settings_state().manifestRevision >= 21
end function

' "never" | "ask" | "always"
function Settings_introSkipMode() as string
    v = Settings_value("playback.intro_skip_mode", invalid)
    if Str_isEmpty(v) then v = Settings_prefs().skipIntro
    v = LCase(Str_orEmpty(v))
    if v <> "never" and v <> "always" then v = "ask"
    return v
end function

function Settings_autoSkipCredits() as boolean
    return Settings_value("playback.auto_skip_credits", false) = true
end function

function Settings_autoPlayNext() as boolean
    v = Settings_value("playback.auto_play_next", invalid)
    if v = invalid then v = Settings_prefs().autoPlayNext
    return v <> false
end function

' Seconds before the end of an episode to show Up Next (0 = at the end).
function Settings_nextUpPromptSeconds() as integer
    return Int(Content_numOr(Settings_value("playback.next_up_prompt_seconds", invalid), 30))
end function

function Settings_skipBackSeconds() as integer
    v = Int(Content_numOr(Settings_value("player.video_skip_back_seconds", invalid), 0))
    if v <= 0 then v = Int(Content_numOr(Settings_prefs().skipBack, 0))
    if v <= 0 then v = 10
    return v
end function

function Settings_skipForwardSeconds() as integer
    v = Int(Content_numOr(Settings_value("player.video_skip_forward_seconds", invalid), 0))
    if v <= 0 then v = Int(Content_numOr(Settings_prefs().skipForward, 0))
    if v <= 0 then v = 30
    return v
end function

' Off plays the HDR10 base layer of a Dolby Vision file (PlaybackCaps stops advertising DV).
function Settings_dolbyVision() as boolean
    return Settings_value("player.dolby_vision_enabled", true) <> false
end function

' player.hdr_enabled (Android TV's HUD "HDR" toggle): off declares no HDR type at all, so the
' server tone-maps HDR sources to SDR.
function Settings_hdrEnabled() as boolean
    return Settings_value("player.hdr_enabled", true) <> false
end function

' player.dv_profile7_hdr10_fallback: on Android TV, on asks for dual-layer Dolby Vision (profile 7)
' as its HDR10 base layer. Siku never declares profile 7 (Roku decodes DV profiles 5 and 8 only),
' so it reads the same either way; the row stays for parity. Contract default false.
function Settings_dvProfile7Fallback() as boolean
    return Settings_value("player.dv_profile7_hdr10_fallback", false) = true
end function

' Force HDR Passthrough: device-local on Android TV too (PlaybackSettingsKeys.ForceHdrPassthrough
' is never synced). Declares HDR10 / HDR10+ / HLG even when the TV does not report them.
function Settings_forceHdrPassthrough() as boolean
    return Settings_prefs().forceHdrPassthrough = true
end function

' Force Dolby Audio Passthrough (device-local, Siku only): declare Dolby Digital and Dolby Digital
' Plus as playable even when the Roku reports that the HDMI device accepts neither. A Roku app
' cannot switch passthrough on; this only changes what Siku tells the server, so the server sends
' the original track and the Roku OS attempts it. Useful when a TV or receiver does decode Dolby
' but does not advertise it (a wrong HDMI audio mode on the TV, a switch in the chain).
function Settings_forceDolbyPassthrough() as boolean
    return Settings_prefs().forceDolbyPassthrough = true
end function

' Experimental: MPEG-TS Copy (device-local, Siku only, on by default): offer the server's
' hls_copy_mpegts_v1 route, which keeps the original H.264/HEVC video and repackages it as MPEG-TS.
' Not yet verified on a Roku; turning it off restores the H.264/SDR/AAC-only HLS declaration.
function Settings_tsCopy() as boolean
    return Settings_prefs().tsCopyDisabled <> true
end function

' Experimental: declare Silo's "progressive" delivery (a fragmented MP4 streamed over plain HTTP,
' video copied, audio converted when needed). Roku's spec lists fragmented MP4 only under DASH
' and HLS, so whether the Video node plays it progressively is what this switch finds out.
function Settings_progressiveRemux() as boolean
    return Settings_prefs().progressiveRemux = true
end function

' Optimistic local update of one server value, for a screen that writes a setting and needs the
' new value at once (the player replans right after a toggle). The next Settings_load replaces it.
sub Settings_setLocal(key as string, scope as string, value as dynamic)
    st = AA_copy(Settings_state())
    items = {}
    if st.items <> invalid then
        for each k in st.items
            items[k] = st.items[k]
        end for
    end if
    items[key] = { value: value, source: scope, scope: scope, storedValue: value, constrained: false, suggested: [] }
    st.items = items
    ' Loads already in flight may have read the old value: only a load started from now on publishes.
    if m.global.hasField("settingsLoadSeq") then st.loadSeq = Int(Content_numOr(m.global.settingsLoadSeq, 0)) + 1
    m.global.settings = st
end sub

function Settings_hideWatched() as boolean
    return Settings_value("home.hide_watched_items", false) = true
end function

function Settings_showTitleArt() as boolean
    return Settings_value("ui.title_art", true) <> false
end function

' Theme music on detail pages (ui.theme_music_enabled / ui.theme_music_loop, revision 11, both
' default off; profile and profile_device scopes, the device value wins).
function Settings_themeMusicEnabled() as boolean
    return Settings_value("ui.theme_music_enabled", false) = true
end function

function Settings_themeMusicLoop() as boolean
    return Settings_value("ui.theme_music_loop", false) = true
end function

' {posterSize}: ui.card_presentation, else the legacy posterSize pref. The stored caption is
' ignored: the caption choice is retired (Silo Android #700, settings revision 24) and every card
' shows its title and details.
function Settings_cardPresentation() as object
    out = { posterSize: "standard" }
    v = Settings_value("ui.card_presentation", invalid)
    if Type(v) = "roAssociativeArray" then
        if not Str_isEmpty(v.poster_size) then out.posterSize = LCase(v.poster_size)
    else
        ps = Settings_prefs().posterSize
        if not Str_isEmpty(ps) then out.posterSize = LCase(ps)
    end if
    return out
end function

' The schema still requires ui.card_presentation's caption (additionalProperties false, both
' fields required), so Siku always writes this member and never offers the choice.
function Settings_retiredCardCaption() as string
    return "title_metadata"
end function

' The whole ui.card_presentation object Siku writes for a poster size.
function Settings_cardPresentationBody(posterSize as string) as object
    return { poster_size: posterSize, caption: Settings_retiredCardCaption() }
end function

' The subtitle appearance the profile stores (the full object with defaults filled in).
function Settings_appearance() as object
    out = Settings_defaultAppearance()
    v = Settings_value("playback.subtitle_appearance", invalid)
    if Type(v) = "roAssociativeArray" then
        for each k in v
            if v[k] <> invalid then out[k] = v[k]
        end for
    end if
    return out
end function

' "Only on This Device" for subtitles (Silo Android #680): this Roku keeps its own subtitle
' appearance and timing. On while the appearance resolves from this device's own row; turning it
' on pins the appearance on screen there, turning it off deletes this device's rows.
function Settings_subtitleDeviceOnly() as boolean
    return Settings_source("playback.subtitle_appearance") = "profile_device"
end function

' The manifest revision from which player.subtitle_sync_ms is accepted at profile scope; older
' servers store it per device only and refuse scope=profile with a 422
' (PlaybackSettingsKeys.SubtitleSyncProfileMinRevision).
function Settings_subtitleSyncProfileMinRevision() as integer
    return 19
end function

' The scope a subtitle delay saved now goes to: the profile's (every device) unless "Only on This
' Device" is on or the server stores timing per device only.
function Settings_subtitleSyncScope() as string
    if Settings_subtitleDeviceOnly() then return "profile_device"
    if Settings_manifestRevision() < Settings_subtitleSyncProfileMinRevision() then return "profile_device"
    return "profile"
end function

' player.subtitle_sync_ms (ms, -10000..10000): the server's value, else this Roku's last one.
function Settings_subtitleSyncMs() as integer
    v = Settings_value("player.subtitle_sync_ms", invalid)
    if v = invalid then v = Settings_prefs().subtitleDelayMs
    return Int(Content_numOr(v, 0))
end function

' Device-local (contract "client_local") playback feel: seconds to skip back when resuming.
function Settings_resumeRewindSeconds() as integer
    v = Settings_prefs().resumeRewind
    if v = invalid then return 7
    return Int(Content_numOr(v, 7))
end function

' Device-local: consecutive auto-advances before the Up Next card waits for a key (0 = never).
function Settings_passoutThreshold() as integer
    v = Settings_prefs().passoutThreshold
    if v = invalid then return 3
    return Int(Content_numOr(v, 3))
end function

' A signature of the settings that change how browse screens draw (tabs, cards, Home rows).
function Settings_uiSignature() as string
    cp = Settings_cardPresentation()
    sig = cp.posterSize + "|" + Str_orEmpty(Settings_hideWatched()) + "|" + Str_orEmpty(Settings_showTitleArt())
    ' Spoiler protection changes what episode cards draw (Spoilers.brs).
    spoilers = Spoilers_prefs()
    sig = sig + "|" + Str_orEmpty(spoilers.hideImages) + "|" + Str_orEmpty(spoilers.hideOverviews)
    hidden = []
    for each id in Settings_hiddenLibraryIds()
        hidden.Push(id)
    end for
    hidden.Sort()
    return sig + "|" + hidden.Join(",")
end function

' ---------- Hidden libraries (ui.disabled_library_ids) ----------
' The libraries the profile hid from its own navigation (the web's Settings > Libraries > "Visible
' in navigation"; Android TV HiddenLibrariesStore, upstream #517). A preference, not access control:
' the server still lists them in GET /api/v2/user/libraries, so the client leaves them out.
' Nothing is hidden until the server answered for this profile.

' A set { "<id>": true } of normalised ids. The value is the canonical array, or the legacy JSON
' string of one; entries may be numbers or numeric strings.
function Settings_hiddenLibraryIds() as object
    out = {}
    v = Settings_value("ui.disabled_library_ids", invalid)
    if v = invalid then return out
    t = Type(v)
    if t = "roString" or t = "String" then
        if v.Trim() = "" then return out
        v = ParseJson(v)
        if v = invalid then return out
    end if
    if Type(v) <> "roArray" then return out
    for each e in v
        id = Settings_libraryIdKey(e)
        if id <> "" then out[id] = true
    end for
    return out
end function

' The comparable form of a library id: positive whole numbers as plain digits ("7" for 7, 7.0 or
' " 7 "), any other non-empty string as itself, "" for anything else.
function Settings_libraryIdKey(v as dynamic) as string
    if v = invalid then return ""
    t = Type(v)
    if t = "roString" or t = "String" then
        s = v.Trim()
        if s = "" then return ""
        re = CreateObject("roRegex", "^[0-9]+(\.0+)?$", "")
        if re.IsMatch(s) then
            parts = s.Split(".")
            digits = parts[0]
            while Len(digits) > 1 and Left(digits, 1) = "0"
                digits = Mid(digits, 2)
            end while
            return digits
        end if
        return s
    end if
    n = Content_numOr(v, -1)
    if n < 1 or n <> Int(n) then return ""
    return Int(n).ToStr()
end function

' `libraries` minus the ones the profile hid.
function Settings_withoutHiddenLibraries(libraries as object) as object
    hidden = Settings_hiddenLibraryIds()
    if hidden.Count() = 0 then return libraries
    out = []
    for each lib in libraries
        if Type(lib) = "roAssociativeArray" then
            if not hidden.DoesExist(Settings_libraryIdKey(lib.id)) then out.Push(lib)
        end if
    end for
    return out
end function

' ---------- Home Sections layout (device-local, like Android TV's TvHomeSectionPreferences) ----------

' Applies the saved order, then (unless includingHidden) the hidden set, to the server's sections.
function Settings_arrangeSections(sections as object, includingHidden = false as boolean) as object
    p = Settings_prefs()
    rank = {}
    i = 0
    for each id in Arr_or(p.sectionOrder)
        rank[Str_orEmpty(id)] = i
        i = i + 1
    end for
    hidden = {}
    for each h in Arr_or(p.hiddenSections)
        hidden[Str_orEmpty(h)] = true
    end for
    ranked = []
    rest = []
    for each s in Arr_or(sections)
        sid = Str_orEmpty(s.id)
        if includingHidden or not hidden.DoesExist(sid) then
            if rank.DoesExist(sid) then ranked.Push({ r: rank[sid], s: s }) else rest.Push(s)
        end if
    end for
    ' Insertion sort by saved rank (the list is short).
    for a = 1 to ranked.Count() - 1
        b = a
        while b > 0 and ranked[b].r < ranked[b - 1].r
            tmp = ranked[b]
            ranked[b] = ranked[b - 1]
            ranked[b - 1] = tmp
            b = b - 1
        end while
    end for
    out = []
    for each e in ranked
        out.Push(e.s)
    end for
    for each s in rest
        out.Push(s)
    end for
    return out
end function

function Settings_sectionHidden(sectionId as string) as boolean
    for each h in Arr_or(Settings_prefs().hiddenSections)
        if Str_orEmpty(h) = sectionId then return true
    end for
    return false
end function

sub Settings_setSectionHidden(sectionId as string, hidden as boolean)
    p = AA_copy(Settings_prefs())
    list = []
    for each h in Arr_or(p.hiddenSections)
        if Str_orEmpty(h) <> sectionId then list.Push(h)
    end for
    if hidden then list.Push(sectionId)
    p.hiddenSections = list
    Prefs_save(p)
    m.global.homeDirty = true
end sub

' Replaces the order of the known rows, keeping remembered rows that are absent right now.
sub Settings_setSectionOrder(sectionIds as object)
    p = AA_copy(Settings_prefs())
    seen = {}
    list = []
    for each id in sectionIds
        sid = Str_orEmpty(id)
        if sid <> "" and not seen.DoesExist(sid) then
            seen[sid] = true
            list.Push(sid)
        end if
    end for
    for each id in Arr_or(p.sectionOrder)
        sid = Str_orEmpty(id)
        if sid <> "" and not seen.DoesExist(sid) then
            seen[sid] = true
            list.Push(sid)
        end if
    end for
    p.sectionOrder = list
    Prefs_save(p)
    m.global.homeDirty = true
end sub

' ---------- Option tables (ported from the shared Kotlin models) ----------

' QualityChoices.kt (Silo Android #613): the main quality is two independent pickers, as the
' Android TV app and the web app show them, a resolution ceiling (playback.preferred_quality) and a
' bitrate ceiling (playback.max_bitrate_kbps, null for no limit). There is no Original choice:
' Auto plays the original file whenever the device and connection can. (The phone's cellular
' quality pair is phone-only and not ported.)
function Settings_resolutionChoices() as object
    return [
        { value: "auto", label: "Auto" }
        { value: "2160p", label: "4K" }
        { value: "1080p", label: "1080p" }
        { value: "720p", label: "720p" }
        { value: "480p", label: "480p" }
    ]
end function

' The bitrate ceilings offered, highest first (the web app's BITRATE_CHOICES_KBPS).
function Settings_bitrateChoicesKbps() as object
    return [200000, 100000, 60000, 40000, 20000, 15000, 10000, 6000, 4000, 2000, 1500]
end function

function Settings_resolutionLabel(value as dynamic) as string
    r = Settings_normalizeResolution(value)
    for each c in Settings_resolutionChoices()
        if c.value = r then return c.label
    end for
    return r
end function

' "No limit", "40 Mbps", "1.5 Mbps"; a cap one decimal of Mbps can't show exactly reads in kbps.
function Settings_bitrateLabel(kbps as integer) as string
    if kbps <= 0 then return "No limit"
    if kbps mod 100 <> 0 then return kbps.ToStr() + " kbps"
    return Settings_formatKbps(kbps)
end function

' formatPlaybackQualityBitrate: Mbps to one decimal, dropping a zero decimal ("40 Mbps",
' "1.5 Mbps"); below 1 Mbps in kbps; "" when unknown.
function Settings_formatKbps(kbps as integer) as string
    if kbps <= 0 then return ""
    if kbps < 1000 then return kbps.ToStr() + " kbps"
    tenths = (kbps + 50) \ 100
    frac = tenths mod 10
    if frac = 0 then return (tenths \ 10).ToStr() + " Mbps"
    return (tenths \ 10).ToStr() + "." + frac.ToStr() + " Mbps"
end function

' "No limit", then the choices; a stored cap that is not one of them is listed in its place by
' size, so it stays visible and selected. Values: kbps as integers, 0 for no limit.
function Settings_bitrateChoices(current as integer) as object
    values = []
    stored = current
    for each v in Settings_bitrateChoicesKbps()
        if stored > 0 and stored > v then
            values.Push(stored)
            stored = 0
        end if
        if v = stored then stored = 0
        values.Push(v)
    end for
    if stored > 0 then values.Push(stored)
    out = [{ value: 0, label: "No limit" }]
    for each v in values
        out.Push({ value: v, label: Settings_bitrateLabel(v) })
    end for
    return out
end function

' QualityChoices.description: what both choices do, shown under them.
function Settings_qualityDescription(resolution as dynamic, kbps as integer) as string
    r = Settings_normalizeResolution(resolution)
    if r = "auto" then
        text = "Plays the original file whenever your Roku and connection can handle it."
    else
        text = "Plays the original file up to " + Settings_resolutionLabel(r) + ". Larger files are converted."
    end if
    if kbps > 0 then text = text + " Files above this bitrate are converted to fit."
    return text
end function

' LanguageOptions: the contract's language floor (revision 7, two-letter tags) plus the
' server's suggestions and the current value, each with an English name.
function Settings_languageName(tag as string) as string
    names = {
        ar: "Arabic", bn: "Bengali", bg: "Bulgarian", zh: "Chinese", hr: "Croatian", cs: "Czech", da: "Danish", nl: "Dutch"
        en: "English", fi: "Finnish", fr: "French", de: "German", el: "Greek", he: "Hebrew", hi: "Hindi", hu: "Hungarian"
        id: "Indonesian", it: "Italian", ja: "Japanese", ko: "Korean", ms: "Malay", no: "Norwegian", fa: "Persian", pl: "Polish"
        pt: "Portuguese", ro: "Romanian", ru: "Russian", sk: "Slovak", sl: "Slovenian", es: "Spanish", sv: "Swedish", ta: "Tamil"
        te: "Telugu", th: "Thai", tr: "Turkish", uk: "Ukrainian", vi: "Vietnamese"
    }
    regional = {
        "zh-hans": "Chinese (Simplified)", "zh-hant": "Chinese (Traditional)", "en-us": "English (United States)", "en-gb": "English (United Kingdom)"
        "fr-ca": "French (Canada)", "pt-br": "Portuguese (Brazil)", "pt-pt": "Portuguese (Portugal)", "es-419": "Spanish (Latin America)", "es-es": "Spanish (Spain)"
    }
    t = LCase(tag.Trim())
    if t = "" then return ""
    r = regional[t]
    if r <> invalid then return r
    base = t
    dash = Instr(1, t, "-")
    if dash > 0 then base = Left(t, dash - 1)
    n = names[base]
    if n <> invalid then
        if dash > 0 then return n + " (" + UCase(Mid(t, dash + 1)) + ")"
        return n
    end if
    return UCase(tag)
end function

function Settings_languageFloor() as object
    return ["ar", "bn", "bg", "zh", "hr", "cs", "da", "nl", "en", "fi", "fr", "de", "el", "he", "hi", "hu", "id", "it", "ja", "ko", "ms", "no", "fa", "pl", "pt", "ro", "ru", "sk", "sl", "es", "sv", "ta", "te", "th", "tr", "uk", "vi"]
end function

' SettingPresentationMetadata.unsetLabel per key.
function Settings_languageUnsetLabel(key as string) as string
    if key = "playback.audio_language" then return "No preference"
    if key = "playback.subtitle_language" then return "None"
    if key = "catalog.metadata_language" then return "Library default"
    return "Unset"
end function

function Settings_languageLabel(tag as dynamic, key as string) as string
    t = Str_orEmpty(tag).Trim()
    if t = "" then return Settings_languageUnsetLabel(key)
    return Settings_languageName(t)
end function

' Picker options [{value, label}] for a language key; "" leads as the unset choice.
function Settings_languageOptions(key as string) as object
    out = [{ value: "", label: Settings_languageUnsetLabel(key) }]
    seen = {}
    current = Str_orEmpty(Settings_value(key, "")).Trim()
    all = []
    for each t in Settings_languageFloor()
        all.Push(t)
    end for
    it = Settings_item(key)
    if it <> invalid then
        for each t in Arr_or(it.suggested)
            all.Push(Str_orEmpty(t))
        end for
    end if
    if current <> "" then all.Push(current)
    for each t in all
        k = LCase(t.Trim())
        if k <> "" and not seen.DoesExist(k) then
            seen[k] = true
            out.Push({ value: t, label: Settings_languageName(t) })
        end if
    end for
    return out
end function

' TvSubtitleAppearanceOptions.kt
function Settings_appearanceOptions(field as string) as object
    if field = "fontSize" then
        return [{ value: "small", label: "Small" }, { value: "medium", label: "Medium" }, { value: "large", label: "Large" }, { value: "xlarge", label: "X-Large" }, { value: "xxlarge", label: "XX-Large" }]
    else if field = "fontFamily" then
        return [{ value: "sans-serif", label: "Sans-serif" }, { value: "serif", label: "Serif" }, { value: "monospace", label: "Monospace" }]
    else if field = "backgroundStyle" then
        return [{ value: "none", label: "No background" }, { value: "box", label: "Box" }, { value: "shadow", label: "Drop Shadow" }, { value: "outline", label: "Outline" }]
    else if field = "position" then
        return [{ value: "bottom", label: "Bottom" }, { value: "lower-third", label: "Lower Third" }, { value: "top", label: "Top" }]
    else if field = "fontColor" then
        return [{ value: "#ffffff", label: "White" }, { value: "#facc15", label: "Yellow" }, { value: "#22c55e", label: "Green" }, { value: "#06b6d4", label: "Cyan" }, { value: "#d946ef", label: "Magenta" }, { value: "#ef4444", label: "Red" }, { value: "#3b82f6", label: "Blue" }, { value: "#9ca3af", label: "Gray" }, { value: "#000000", label: "Black" }]
    else if field = "backgroundColor" or field = "textOutlineColor" then
        return [{ value: "#000000", label: "Black" }, { value: "#374151", label: "Dark Gray" }, { value: "#1e3a5f", label: "Navy" }, { value: "#7f1d1d", label: "Dark Red" }, { value: "#14532d", label: "Dark Green" }]
    end if
    return []
end function

' Percent steps (every 5) plus the current value when it falls between steps.
function Settings_percentOptions(firstStep as integer, current as integer) as object
    out = []
    v = firstStep
    inserted = false
    while v <= 100
        if not inserted and current < v and current >= firstStep - 5 then
            out.Push({ value: current, label: current.ToStr() + "%" })
            inserted = true
        end if
        if current = v then inserted = true
        out.Push({ value: v, label: v.ToStr() + "%" })
        v = v + 5
    end while
    return out
end function

function Settings_optionLabel(options as object, value as dynamic) as string
    key = LCase(Str_orEmpty(value))
    for each o in options
        if LCase(Str_orEmpty(o.value)) = key then return o.label
    end for
    return Str_orEmpty(value)
end function

' A JSON-safe "#rrggbb" to 0xRRGGBBAA for SceneGraph, with an alpha percent.
function Settings_hexToColor(hex as dynamic, alphaPercent = 100 as integer) as string
    h = LCase(Str_orEmpty(hex)).Trim()
    if Left(h, 1) = "#" then h = Mid(h, 2)
    if Len(h) <> 6 then h = "ffffff"
    a = Int(alphaPercent * 255 / 100 + 0.5)
    if a < 0 then a = 0
    if a > 255 then a = 255
    hexDigits = "0123456789abcdef"
    aa = Mid(hexDigits, (a \ 16) + 1, 1) + Mid(hexDigits, (a mod 16) + 1, 1)
    return "0x" + UCase(h) + UCase(aa)
end function
