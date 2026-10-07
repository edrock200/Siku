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
'                   title art when "Apply to all devices" is on
'   profile_device  quality, bitrate cap, audio language, intro skip, auto-skip credits,
'                   auto-play next, Up Next prompt seconds, subtitle appearance, Dolby Vision
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
        { key: "playback.auto_skip_credits", rev: 1, def: false }
        { key: "playback.auto_play_next", rev: 1, def: true }
        { key: "playback.next_up_prompt_seconds", rev: 1, def: 30 }
        { key: "playback.subtitle_appearance", rev: 1, def: Settings_defaultAppearance() }
        { key: "player.hdr_enabled", rev: 1, def: true }
        { key: "player.dolby_vision_enabled", rev: 1, def: true }
        { key: "player.dv_profile7_hdr10_fallback", rev: 1, def: false }
        { key: "player.video_skip_back_seconds", rev: 9, def: 10 }
        { key: "player.video_skip_forward_seconds", rev: 9, def: 30 }
        { key: "catalog.metadata_language", rev: 1, def: "" }
        { key: "home.hide_watched_items", rev: 12, def: false }
        { key: "ui.card_presentation", rev: 5, def: { poster_size: "standard", caption: "title_metadata" } }
        { key: "ui.title_art", rev: 16, def: true }
    ]
    return m.siku_settingKeys
end function

' The keys written at profile_device scope; "Reset Playback Overrides" deletes each of them.
function Settings_deviceKeys() as object
    return ["playback.preferred_quality", "playback.max_bitrate_kbps", "playback.audio_language", "playback.intro_skip_mode", "playback.auto_skip_credits", "playback.auto_play_next", "playback.next_up_prompt_seconds", "playback.subtitle_appearance", "player.hdr_enabled", "player.dolby_vision_enabled", "player.dv_profile7_hdr10_fallback"]
end function

function Settings_defaultAppearance() as object
    return { fontSize: "large", fontFamily: "sans-serif", fontColor: "#ffffff", textOpacity: 100, backgroundColor: "#000000", backgroundStyle: "shadow", backgroundOpacity: 75, textOutline: false, textOutlineColor: "#000000", position: "bottom" }
end function

' ---------- State ----------

function Settings_empty() as object
    return { ready: false, available: false, identity: "", revision: 0, manifestRevision: 0, items: {}, error: "" }
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
sub Settings_load()
    Api_call({ method: "GET", path: "/api/v2/settings/contract/capabilities", context: { identity: Settings_identity() } }, "Settings_onCaps")
end sub

sub Settings_onCaps(event as object)
    resp = Api_result(event)
    identity = ""
    if resp.context <> invalid then identity = Str_orEmpty(resp.context.identity)
    if identity <> Settings_identity() then return
    if not resp.ok or Type(resp.data) <> "roAssociativeArray" then
        Settings_publishError(identity, Api_errorText(resp))
        return
    end if
    rev = Int(Content_numOr(resp.data.manifest_revision, 1))
    keys = []
    for each d in Settings_keyDefs()
        if d.rev <= rev then keys.Push(d.key)
    end for
    Api_call({ method: "GET", path: "/api/v2/settings/values/effective", query: { keys: keys }, context: { identity: identity, manifestRevision: rev } }, "Settings_onEffective")
end sub

sub Settings_onEffective(event as object)
    resp = Api_result(event)
    identity = ""
    rev = 0
    if resp.context <> invalid then
        identity = Str_orEmpty(resp.context.identity)
        rev = Int(Content_numOr(resp.context.manifestRevision, 0))
    end if
    if identity <> Settings_identity() then return
    if not resp.ok or Type(resp.data) <> "roAssociativeArray" then
        Settings_publishError(identity, Api_errorText(resp))
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
    }
    Settings_notify()
end sub

' Tells the component that called Settings_load that the snapshot changed: it declares a
' boolean `settingsLoaded` field (alwaysNotify) whose onChange re-renders. Components that did
' not start the load re-read m.global.settings when they are shown again.
sub Settings_notify()
    if m.top <> invalid and m.top.hasField("settingsLoaded") then m.top.settingsLoaded = true
end sub

sub Settings_publishError(identity as string, message as string)
    prev = Settings_state()
    st = Settings_empty()
    st.ready = true
    st.identity = identity
    st.error = message
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

' The resolution axis of the quality choice ("auto" | "original" | "480p" ... "2160p").
function Settings_quality() as string
    q = Settings_value("playback.preferred_quality", invalid)
    if Str_isEmpty(q) then q = Settings_prefs().quality
    q = LCase(Str_orEmpty(q))
    if q = "4k" then q = "2160p"
    if q = "" then q = "auto"
    return q
end function

' The bandwidth axis in kbps; 0 = uncapped.
function Settings_maxBitrateKbps() as integer
    return Int(Content_numOr(Settings_value("playback.max_bitrate_kbps", invalid), 0))
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

' player.dv_profile7_hdr10_fallback: on, dual-layer Dolby Vision (profile 7) is asked for as its
' HDR10 base layer (PlaybackCaps leaves profile 7 out of the declared profiles). Contract default
' false, as on Android TV after hydration.
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
    m.global.settings = st
end sub

function Settings_hideWatched() as boolean
    return Settings_value("home.hide_watched_items", false) = true
end function

function Settings_showTitleArt() as boolean
    return Settings_value("ui.title_art", true) <> false
end function

' {posterSize, caption}: ui.card_presentation, else the legacy posterSize pref.
function Settings_cardPresentation() as object
    out = { posterSize: "standard", caption: "title_metadata" }
    v = Settings_value("ui.card_presentation", invalid)
    if Type(v) = "roAssociativeArray" then
        if not Str_isEmpty(v.poster_size) then out.posterSize = LCase(v.poster_size)
        if not Str_isEmpty(v.caption) then out.caption = LCase(v.caption)
    else
        ps = Settings_prefs().posterSize
        if not Str_isEmpty(ps) then out.posterSize = LCase(ps)
    end if
    return out
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
    sig = cp.posterSize + "|" + cp.caption + "|" + Str_orEmpty(Settings_hideWatched()) + "|" + Str_orEmpty(Settings_showTitleArt())
    return sig
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

' QualityPresets.kt: one picker over the two axes.
function Settings_qualityPresets() as object
    return [
        { id: "auto", label: "Auto", description: "Silo picks based on your connection.", resolution: "auto", kbps: 0 }
        { id: "original", label: "Original", description: "Never transcode. Needs bandwidth to match the file.", resolution: "original", kbps: 0 }
        { id: "2160p", label: "4K", description: "Up to 2160p.", resolution: "2160p", kbps: 0 }
        { id: "1080p-high", label: "1080p High", description: "1080p at up to 10 Mbps.", resolution: "1080p", kbps: 10000 }
        { id: "1080p", label: "1080p", description: "1080p at up to 6 Mbps.", resolution: "1080p", kbps: 6000 }
        { id: "1080p-low", label: "1080p Low", description: "1080p at up to 3 Mbps, for a slower link.", resolution: "1080p", kbps: 3000 }
        { id: "720p-high", label: "720p High", description: "720p at up to 4 Mbps.", resolution: "720p", kbps: 4000 }
        { id: "720p", label: "720p", description: "720p at up to 2 Mbps.", resolution: "720p", kbps: 2000 }
        { id: "480p", label: "480p", description: "480p at up to 1.5 Mbps, for the tightest connections.", resolution: "480p", kbps: 1500 }
    ]
end function

' The preset for a stored pair, or invalid when no preset covers it.
function Settings_qualityPresetFor(resolution as string, kbps as integer) as dynamic
    r = LCase(resolution)
    if r = "4k" then r = "2160p"
    if r = "" then r = "auto"
    if kbps < 0 then kbps = 0
    for each p in Settings_qualityPresets()
        if p.resolution = r and p.kbps = kbps then return p
    end for
    return invalid
end function

function Settings_qualityPresetById(id as string) as dynamic
    for each p in Settings_qualityPresets()
        if p.id = id then return p
    end for
    return invalid
end function

' QualityPresets.describe(): a label for any pair, including ones no preset covers.
function Settings_describeQuality(resolution as string, kbps as integer) as string
    p = Settings_qualityPresetFor(resolution, kbps)
    if p <> invalid then return p.label
    r = LCase(resolution)
    if r = "" then r = "auto"
    if r = "auto" then
        label = "Auto"
    else if r = "original" then
        label = "Original"
    else if r = "2160p" or r = "4k" then
        label = "4K"
    else
        label = r
    end if
    if kbps <= 0 then return label
    if kbps mod 1000 = 0 then
        mb = (kbps / 1000).ToStr()
    else
        tenths = Int(kbps / 100 + 0.5)
        mb = (tenths \ 10).ToStr() + "." + (tenths mod 10).ToStr()
    end if
    return label + " at " + mb + " Mbps"
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
