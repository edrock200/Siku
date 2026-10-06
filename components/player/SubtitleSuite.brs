' Subtitle suite of the player's HUD Subtitles pane, ported from the Android TV player
' (TvPlayerHud subtitle pane, TvSubtitleSearchDialog, TvAiTranslateDialog and the shared
' SubtitleSyncController): provider search and download, AI translation / transcription,
' server-side "Sync to audio" / "Reset timing", and the subtitle delay.
'
' Included by PlayerScreen.xml, so everything here runs in PlayerScreen's scope (m is the
' screen). State lives in m.subs (see Subs_init / Subs_resetPlayback).
'
' Endpoints (docs/api-spec.md §8, silo-server contracts/api/v2/openapi.json):
'   GET  /api/v2/subtitles/ai/status                 gate for "Translate with AI" (enabled | transcribe_enabled)
'   GET  /api/v2/subtitles/ai/quota                  transcription budget, read when the dialog opens
'   POST /api/v2/subtitles/ai/translate              202 {job}; then GET /api/v2/subtitles/ai/jobs/{id} until terminal
'   POST /api/v2/subtitles/ai/jobs/{id}/cancel       204
'   POST /api/v2/subtitles/search                    {media_file_id, languages[]} → {results[], warnings[]}
'   POST /api/v2/subtitles/download                  → {subtitle} stored on the server (never on the device)
'   GET  /api/v2/subtitles/sync/status               gate for the Timing row
'   GET  /api/v2/subtitles/{file}/sync               every syncable subtitle's timing and latest job
'   POST /api/v2/subtitles/{file}/sync/{key}         202: start a sync; GET …/sync/{key} polls it
'   PUT  /api/v2/subtitles/{file}/sync/{key}/timing  {offset_ms:0, scale:1} + If-Match resets the timing
'   POST /api/v2/playback/{session}/replan           "track_change": a fresh inventory that lists a new stored subtitle
' SPDX-License-Identifier: AGPL-3.0-or-later

' ---------- State ----------

sub Subs_init()
    m.subsDialog = m.top.findNode("subsDialog")
    m.subsSyncTimer = m.top.findNode("subsSyncTimer")
    m.subsAiTimer = m.top.findNode("subsAiTimer")
    m.subsDialog.observeField("chosen", "Subs_onDialogChosen")
    m.subsDialog.observeField("cycled", "Subs_onDialogCycled")
    m.subsDialog.observeField("dismissed", "Subs_onDialogDismissed")
    m.subsSyncTimer.observeField("fire", "Subs_onSyncPoll")
    m.subsAiTimer.observeField("fire", "Subs_onAiPoll")
    m.subs = {
        aiStatusRequested: false
        aiStatus: { enabled: false, transcribeEnabled: false }
    }
    Subs_resetPlayback()
end sub

' Per playback attempt (a new file drops everything in flight).
sub Subs_resetPlayback()
    s = m.subs
    s.dialog = ""
    s.subtitleInventory = []
    s.syncLoaded = false
    s.sync = { available: false, external: false, entries: {}, polledMs: {}, loadedTiming: {} }
    s.search = { language: "en", searching: false, hasSearched: false, results: [], warnings: [], error: "", downloadingKey: "" }
    s.ai = { phase: "idle", error: "", job: invalid, progress: 0.0, message: "", quota: invalid, mode: "subtitles", subPos: 0, audioPos: 0, targetPos: -1 }
    s.adoptId = ""
    s.adoptOrigin = ""
    if m.subsSyncTimer <> invalid then m.subsSyncTimer.control = "stop"
    if m.subsAiTimer <> invalid then m.subsAiTimer.control = "stop"
end sub

function Subs_filePath(suffix as string) as string
    return "/api/v2/subtitles/" + Str_urlEncode(m.fileId) + suffix
end function

' ---------- Languages (shared LanguageNames: the 2-letter codes the subtitle APIs accept) ----------

function Subs_languageOptions() as object
    if m.subsLanguages <> invalid then return m.subsLanguages
    codes = ["en", "es", "fr", "de", "it", "pt", "nl", "pl", "ru", "zh", "ja", "ko", "ar", "tr", "sv", "da", "no", "fi", "hu", "cs", "ro", "he", "th", "vi", "el", "bg", "hr", "sk", "sl", "uk", "id", "ms", "hi", "ta", "te", "bn", "fa"]
    opts = []
    for each c in codes
        opts.Push({ code: c, name: Tracks_languageName(c) })
    end for
    ' Sorted by display name, like LanguageNames.dropdownOptions.
    for i = 1 to opts.Count() - 1
        j = i
        while j > 0 and LCase(opts[j - 1].name) > LCase(opts[j].name)
            tmp = opts[j - 1]
            opts[j - 1] = opts[j]
            opts[j] = tmp
            j = j - 1
        end while
    end for
    m.subsLanguages = opts
    return opts
end function

' Normalizes a profile / track code to a 2-letter picker code; unmappable codes become "en".
function Subs_searchCode(code as dynamic) as string
    c = LCase(Str_orEmpty(code)).Trim()
    dash = Instr(1, c, "-")
    if dash > 0 then c = Left(c, dash - 1)
    if c = "" then return "en"
    for each o in Subs_languageOptions()
        if o.code = c then return c
    end for
    name = Tracks_languageName(c)
    if name <> "" then
        for each o in Subs_languageOptions()
            if o.name = name then return o.code
        end for
    end if
    return "en"
end function

function Subs_languageIndex(code as dynamic) as integer
    c = Subs_searchCode(code)
    opts = Subs_languageOptions()
    for i = 0 to opts.Count() - 1
        if opts[i].code = c then return i
    end for
    return 0
end function

function Subs_languageName(code as dynamic) as string
    c = LCase(Str_orEmpty(code)).Trim()
    if c = "" then return "Unknown"
    n = Tracks_languageName(c)
    if n = "" then return UCase(c)
    return n
end function

' Whether a track's code names the picker language ("bul" vs "bg"); unknown codes never match.
function Subs_isSameLanguage(source as dynamic, target as string) as boolean
    c = LCase(Str_orEmpty(source)).Trim()
    if c = "" then return false
    if Tracks_languageName(c) = "" then return false
    return Subs_searchCode(c) = Subs_searchCode(target)
end function

function Subs_preferredLanguage() as string
    code = ""
    if m.watch <> invalid then code = Str_orEmpty(m.watch.effective_subtitle_language)
    if code = "" and m.watch <> invalid then code = Str_orEmpty(m.watch.subtitle_language)
    return Subs_searchCode(code)
end function

' ---------- Sidecar tracks ----------

' The Video-node track for an inventory item, or invalid when Roku can't render it.
' Only WebVTT/SRT sidecars play. Sidecar routes have no signed `st`, and the Video node may not
' forward HttpHeaders to sidecar fetches, so the documented `token=` fallback is appended
' (docs/api-spec.md §8.2). A `.vtt` URL also takes `timestamp_offset=<seconds>`: the negative
' timeline offset (so cues line up with a stream that starts mid-file) plus the viewer's delay.
function Subs_buildTrack(t as object) as dynamic
    if Str_orEmpty(t.delivery) <> "sidecar" or Str_isEmpty(t.url) then return invalid
    path = LCase(t.url)
    q = Instr(1, path, "?")
    if q > 0 then path = Left(path, q - 1)
    isVtt = Right(path, 4) = ".vtt"
    if not isVtt and Right(path, 4) <> ".srt" then return invalid
    s = m.global.session
    su = Url_resolve(t.url)
    shift = -m.timelineOffset + Subs_delayMs() / 1000.0
    if isVtt and Abs(shift) > 0.0005 then
        su = Subs_appendQuery(su, "timestamp_offset=" + Subs_formatSeconds(shift))
    end if
    su = Subs_appendQuery(su, "token=" + s.accessToken)
    ' Language name first, as Android TV shows it; the server's label can be a bare codec
    ' name ("SUBRIP" was seen on device), so it is only a fallback.
    label = ""
    if not Str_isEmpty(t.language) then label = Subs_languageName(t.language)
    if label = "" or label = "Unknown" then label = Str_orEmpty(t.label)
    if label = "" then label = "Unknown"
    if t.forced = true then label = label + " (Forced)"
    if t.hearing_impaired = true then label = label + " (SDH)"
    storedId = Subs_storedIdOf(t)
    if storedId <> "" and Instr(1, label, "(") = 0 then label = label + " (Downloaded)"
    return {
        label: label
        url: su
        language: Str_orEmpty(t.language)
        trackId: Str_orEmpty(t.track_id)
        syncKey: Str_orEmpty(t.sync_key)
        source: Str_orEmpty(t.source)
        codec: Str_orEmpty(t.codec)
        combinedIndex: t.combined_index
        isVtt: isVtt
        storedId: storedId
        forced: t.forced = true
        hearingImpaired: t.hearing_impaired = true or Subs_labelIsSdh(Str_orEmpty(t.label))
    }
end function

' ---------- Automatic subtitle choice ----------
' Android TV's resolveAutoSubtitle (shared/model/playback/AutoSubtitleResolver.kt), over the tracks
' this Roku can render. Returns the m.subtitleTracks index to turn on, -1 for "subtitles off", or
' -2 when the preferences pick nothing (the server's own selection, if any, then stands).
'   mode off, or no tracks                → off / nothing
'   no preferred language                 → only "always" picks (the best track of any language)
'   "auto" and the audio is that language → off, or that language's forced track if forced subs are on
'   otherwise                             → the best track in that language, else any forced track
' Best within a pool: full dialogue (not forced, not SDH) → not forced → any.
function Subs_autoChoice(audioLanguage as string) as integer
    tracks = m.subtitleTracks
    if tracks.Count() = 0 then return -2
    prefs = Subs_autoPrefs()
    if prefs.mode = "off" then return -1
    target = Subs_autoLangKey(prefs.language)
    if target = "" then
        if prefs.mode <> "always" then return -2
        return Subs_autoBest(tracks, "")
    end if
    if prefs.mode = "auto" and Subs_autoLangKey(audioLanguage) = target then
        if prefs.showForced then
            for i = 0 to tracks.Count() - 1
                if tracks[i].forced and Subs_autoLangKey(tracks[i].language) = target and not tracks[i].hearingImpaired then return i
            end for
            for i = 0 to tracks.Count() - 1
                if tracks[i].forced and Subs_autoLangKey(tracks[i].language) = target then return i
            end for
        end if
        return -1
    end if
    best = Subs_autoBest(tracks, target)
    if best >= 0 then return best
    if prefs.showForced then
        for i = 0 to tracks.Count() - 1
            if tracks[i].forced then return i
        end for
    end if
    return -2
end function

function Subs_autoBest(tracks as object, target as string) as integer
    for pass = 0 to 2
        for i = 0 to tracks.Count() - 1
            t = tracks[i]
            if target = "" or Subs_autoLangKey(t.language) = target then
                if pass = 2 then return i
                if not t.forced and (pass = 1 or not t.hearingImpaired) then return i
            end if
        end for
    end for
    return -2
end function

' The cascaded preferences, as Android TV's player reads them: the watch detail's effective values
' for this title, then the profile settings. A blank language means "no preference".
function Subs_autoPrefs() as object
    w = m.watch
    if w = invalid then w = {}
    lang = Str_orEmpty(w.effective_subtitle_language).Trim()
    if lang = "" then lang = Str_orEmpty(Settings_value("playback.subtitle_language", "")).Trim()
    mode = LCase(Str_orEmpty(w.effective_subtitle_mode).Trim())
    if mode = "" then mode = LCase(Str_orEmpty(Settings_value("playback.subtitle_mode", "auto")).Trim())
    if mode = "" then mode = "auto"
    forced = w.effective_show_forced_subtitles
    if Type(forced) <> "roBoolean" and Type(forced) <> "Boolean" then forced = Settings_value("playback.show_forced_subtitles", true)
    return { language: lang, mode: mode, showForced: forced = true }
end function

' ISO-639 folding for "is this the language asked for" (Android's autoSubtitleLanguageKey).
function Subs_autoLangKey(code as dynamic) as string
    c = LCase(Str_orEmpty(code).Trim()).Replace("_", "-")
    dash = Instr(1, c, "-")
    if dash > 0 then c = Left(c, dash - 1)
    if c = "" or c = "und" then return ""
    folds = { eng: "en", spa: "es", fre: "fr", fra: "fr", ger: "de", deu: "de", dut: "nl", nld: "nl", jpn: "ja", dan: "da", ita: "it", por: "pt", rus: "ru", chi: "zh", zho: "zh", kor: "ko", swe: "sv", nor: "no", fin: "fi", pol: "pl" }
    if folds.DoesExist(c) then return folds[c]
    return c
end function

function Subs_labelIsSdh(label as string) as boolean
    l = LCase(label)
    return Instr(1, l, "sdh") > 0 or Instr(1, l, "hearing impaired") > 0 or Instr(1, l, "cc") = 1
end function

function Subs_appendQuery(u as string, pair as string) as string
    if Instr(1, u, "?") > 0 then return u + "&" + pair
    return u + "?" + pair
end function

' Seconds with millisecond precision and no exponent, e.g. "-0.3" / "12.5".
function Subs_formatSeconds(v as float) as string
    ms = Int(Abs(v) * 1000 + 0.5)
    whole = ms \ 1000
    frac = ms mod 1000
    out = whole.ToStr()
    if frac > 0 then
        f = Str_padLeft(frac.ToStr(), 3)
        while Right(f, 1) = "0"
            f = Left(f, Len(f) - 1)
        end while
        out = out + "." + f
    end if
    if v < 0 then out = "-" + out
    return out
end function

' The stored-subtitle id an inventory item names: its "stored-<id>" sync key, or the
' downloaded_subtitle_id pin in its URL.
function Subs_storedIdOf(t as object) as string
    key = Str_orEmpty(t.sync_key)
    if Left(key, 7) = "stored-" then return Mid(key, 8)
    u = Str_orEmpty(t.url)
    p = Instr(1, u, "downloaded_subtitle_id=")
    if p > 0 then
        rest = Mid(u, p + 23)
        amp = Instr(1, rest, "&")
        if amp > 0 then rest = Left(rest, amp - 1)
        return rest
    end if
    return ""
end function

' The track showing, or the one chosen for a plan the player hasn't started yet (a remount).
function Subs_selectedTrack() as dynamic
    if m.subtitleIndex >= 0 and m.subtitleIndex < m.subtitleTracks.Count() then return m.subtitleTracks[m.subtitleIndex]
    if m.pendingSubtitleTrackId <> "" then
        for each t in m.subtitleTracks
            if t.trackId = m.pendingSubtitleTrackId then return t
        end for
    end if
    return invalid
end function

function Subs_selectedTrackId() as string
    t = Subs_selectedTrack()
    if t = invalid then return ""
    return t.trackId
end function

' ---------- HUD rows ----------

' Called when the Subtitles pane is shown: re-reads the sync state so a job that finished
' meanwhile shows, and asks once whether the server offers AI subtitles (any failure hides the row).
sub Subs_onPaneShown()
    Subs_syncReload()
    if m.subs.aiStatusRequested then return
    m.subs.aiStatusRequested = true
    Api_get("/api/v2/subtitles/ai/status", invalid, "Subs_onAiStatus")
end sub

sub Subs_onAiStatus(event as object)
    resp = Api_result(event)
    if resp.ok and resp.data <> invalid then
        m.subs.aiStatus = { enabled: resp.data.enabled = true, transcribeEnabled: resp.data.transcribe_enabled = true }
    else
        m.subs.aiStatus = { enabled: false, transcribeEnabled: false }
    end if
    Subs_refreshHud()
end sub

function Subs_aiAvailable() as boolean
    if m.fileId = "" then return false
    return m.subs.aiStatus.enabled or m.subs.aiStatus.transcribeEnabled
end function

sub Subs_refreshHud()
    tabNames = hudTabNames()
    if m.hud.visible and tabNames[m.hudTab] = "Subtitles" then buildHudRows()
end sub

' Rows under "Track" in the Subtitles pane: Delay, Timing (+ its detail line), Search, Translate.
sub Subs_appendHudRows(rows as object)
    delayValue = Subs_delayLabel(Subs_delayMs())
    delayOn = Subs_delayEnabled()
    if not delayOn then delayValue = "Unavailable for this track"
    rows.Push({ id: "subdelay", label: "Delay", value: delayValue, actionable: delayOn })
    timing = Subs_timingActions()
    if timing <> invalid then
        rows.Push({ id: "subtiming", label: "Timing", value: Subs_timingValue(timing), actionable: not timing.forbidden and timing.actionsEnabled and (timing.canSync or timing.canReset) })
        detail = Subs_timingDetail(timing)
        if detail.text <> "" then rows.Push({ id: "subtimingdetail", label: detail.text, value: "", actionable: false, muted: true, color: detail.color })
    end if
    if m.fileId <> "" then rows.Push({ id: "subsearch", label: "Search subtitles", value: "", actionable: true })
    if Subs_aiAvailable() then rows.Push({ id: "subai", label: "Translate with AI", value: "", actionable: true })
end sub

' True when a HUD row id belongs to this suite and was handled.
function Subs_activateHudRow(id as string) as boolean
    if id = "subdelay" then
        if Subs_delayEnabled() then Subs_openDelay()
    else if id = "subtiming" then
        Subs_openTiming()
    else if id = "subsearch" then
        closeHud()
        Subs_openSearch()
    else if id = "subai" then
        closeHud()
        Subs_openAi()
    else
        return false
    end if
    return true
end function

' ---------- Dialog plumbing ----------

sub Subs_showDialog(kind as string, title as string, rows as object)
    m.subs.dialog = kind
    m.hideTimer.control = "stop"
    m.subsDialog.title = title
    m.subsDialog.rows = rows
    if not m.subsDialog.visible then m.subsDialog.visible = true
    m.subsDialog.setFocus(true)
end sub

sub Subs_closeDialog()
    m.subs.dialog = ""
    m.subsDialog.visible = false
    if m.hud.visible then
        buildHudRows()
        focusHud()
    else if m.controls.visible then
        focusControls()
        rearmHide()
    else if m.skipGroup.visible and m.skipBtn.visible then
        m.skipBtn.setFocus(true)
    else
        m.focusSink.setFocus(true)
    end if
end sub

sub Subs_onDialogDismissed()
    ' A running AI job keeps polling; reopening the dialog shows its progress.
    Subs_closeDialog()
end sub

sub Subs_onDialogChosen()
    id = m.subsDialog.chosen
    kind = m.subs.dialog
    if kind = "delay" then
        Subs_setDelay(Int(Val(id)))
        Subs_closeDialog()
    else if kind = "search" then
        Subs_searchChosen(id)
    else if kind = "ai" then
        Subs_aiChosen(id)
    end if
end sub

sub Subs_onDialogCycled()
    c = m.subsDialog.cycled
    if c = invalid then return
    direction = 1
    if c.direction <> invalid then direction = c.direction
    kind = m.subs.dialog
    if kind = "search" then
        Subs_searchCycled(Str_orEmpty(c.id), direction)
    else if kind = "ai" then
        Subs_aiCycled(Str_orEmpty(c.id), direction)
    end if
end sub

' ---------- Delay ----------

function Subs_delayMs() as integer
    p = m.global.prefs
    if p = invalid or p.subtitleDelayMs = invalid then return 0
    return Int(p.subtitleDelayMs)
end function

' Signed label with a true minus sign, like the TV's delayLabel.
function Subs_delayLabel(ms as integer) as string
    if ms > 0 then return "+" + ms.ToStr() + " ms"
    if ms < 0 then return "−" + (-ms).ToStr() + " ms"
    return "0 ms"
end function

' The delay is applied by reloading the sidecar with timestamp_offset, which only `.vtt` routes
' take; an original `.srt` sidecar can't be delayed.
function Subs_delayEnabled() as boolean
    t = Subs_selectedTrack()
    if t = invalid then return true
    return t.isVtt = true
end function

sub Subs_openDelay()
    ' −2000 … +2000 ms in 100 ms steps (the TV's delay picker), plus the current value when it is off the grid.
    current = Subs_delayMs()
    values = []
    inserted = false
    for v = -2000 to 2000 step 100
        if not inserted and current < v then
            values.Push(current)
            inserted = true
        end if
        if v = current then inserted = true
        values.Push(v)
    end for
    if not inserted then values.Push(current)
    rows = []
    for each v in values
        rows.Push({ kind: "option", id: v.ToStr(), label: Subs_delayLabel(v), checked: v = current })
    end for
    Subs_showDialog("delay", "Subtitle Delay", rows)
end sub

sub Subs_setDelay(ms as integer)
    if ms > 10000 then ms = 10000
    if ms < -10000 then ms = -10000
    if ms = Subs_delayMs() then return
    p = AA_copy(m.global.prefs)
    p.subtitleDelayMs = ms
    Prefs_save(p)
    ' Already-fetched cues keep their times, so the mounted sidecar is fetched again.
    if m.subtitleIndex >= 0 then remountSubtitles()
end sub

' ---------- Sync to audio (SubtitleSyncController) ----------

function Subs_inventorySyncKeys() as object
    keys = []
    for each t in m.subs.subtitleInventory
        if not Str_isEmpty(t.sync_key) then keys.Push(t.sync_key)
    end for
    return keys
end function

' Re-reads the capability and the file's syncable subtitles.
sub Subs_syncReload()
    if m.fileId = "" or m.sessionId = "" then return
    if Subs_inventorySyncKeys().Count() = 0 and m.subs.sync.entries.Count() = 0 then return
    m.subs.syncLoaded = true
    m.subs.sync.polledMs = {}
    for each key in m.subs.sync.entries
        m.subs.sync.entries[key].pollExpired = false
    end for
    Api_get("/api/v2/subtitles/sync/status", invalid, "Subs_onSyncStatus", { fileId: m.fileId })
    Api_get(Subs_filePath("/sync"), invalid, "Subs_onSyncList", { fileId: m.fileId })
end sub

function Subs_sameFile(resp as object) as boolean
    return resp.context <> invalid and Str_orEmpty(resp.context.fileId) = m.fileId and m.fileId <> ""
end function

sub Subs_onSyncStatus(event as object)
    resp = Api_result(event)
    if m.closing or not Subs_sameFile(resp) then return
    ' A probe that failed keeps what the last one said.
    if resp.ok and resp.data <> invalid then
        avail = Str_orEmpty(resp.data.state) = "available" and resp.data.allowed = true
        m.subs.sync.available = avail
        m.subs.sync.external = avail and resp.data.external = true
        Subs_refreshHud()
    end if
end sub

sub Subs_onSyncList(event as object)
    resp = Api_result(event)
    if m.closing or not Subs_sameFile(resp) then return
    if resp.ok and resp.data <> invalid then
        for each st in Arr_or(resp.data.subtitles)
            Subs_observe(st, "")
        end for
    end if
    Subs_startPolling()
    Subs_refreshHud()
end sub

' Records a subtitle returned by a download, following the automatic sync the server starts.
sub Subs_remember(stored as object)
    if stored = invalid or Str_orEmpty(stored.media_file_id) <> m.fileId then return
    st = {
        key: "stored-" + Str_orEmpty(stored.id)
        media_file_id: Str_orEmpty(stored.media_file_id)
        source: "downloaded"
        stored_subtitle_id: Str_orEmpty(stored.id)
        language: Str_orEmpty(stored.language)
        format: Str_orEmpty(stored.format)
        label: Str_orEmpty(stored.release_name)
        timing: stored.timing
        sync: stored.sync
    }
    if st.label = "" then st.label = Str_orEmpty(stored.provider)
    watch = ""
    if stored.sync <> invalid and Subs_jobInProgress(stored.sync) then watch = Str_orEmpty(stored.sync.id)
    m.subs.sync.polledMs.Delete(st.key)
    Subs_observe(st, watch)
    Subs_startPolling()
end sub

function Subs_jobInProgress(job as dynamic) as boolean
    if job = invalid then return false
    st = Str_orEmpty(job.status)
    return st = "pending" or st = "running"
end function

function Subs_timing(state as object) as object
    t = state.timing
    if t = invalid then t = {}
    offset = 0
    if t.offset_ms <> invalid then offset = Int(t.offset_ms)
    scale = 1.0
    if t.scale <> invalid then scale = t.scale * 1.0
    return { offsetMs: offset, scale: scale }
end function

function Subs_timingIsIdentity(timing as object) as boolean
    return timing.offsetMs = 0 and Abs(timing.scale - 1.0) < 0.0000001
end function

function Subs_timingEquals(a as object, b as object) as boolean
    return a.offsetMs = b.offsetMs and Abs(a.scale - b.scale) < 0.0000001
end function

' Records a server view of a subtitle; `watch` marks a job this viewer started.
sub Subs_observe(state as object, watch as string)
    key = Str_orEmpty(state.key)
    if key = "" then return
    sy = m.subs.sync
    timing = Subs_timing(state)
    previous = sy.loadedTiming[key]
    sy.loadedTiming[key] = timing
    inProgress = Subs_jobInProgress(state.sync)
    if not inProgress then sy.polledMs.Delete(key)
    entry = sy.entries[key]
    if entry = invalid then
        entry = { busy: false, forbidden: false, unsupported: false, error: "", pollExpired: false, watchedJobId: "", announcedJobId: "" }
        sy.entries[key] = entry
    end if
    entry.state = state
    entry.timing = timing
    entry.inProgress = inProgress
    if not inProgress then entry.pollExpired = false
    if watch <> "" then entry.watchedJobId = watch
    ' A job this viewer started has ended: say how (the TV's sync card).
    if state.sync <> invalid and not inProgress and entry.watchedJobId <> "" and Str_orEmpty(state.sync.id) = entry.watchedJobId and entry.announcedJobId <> entry.watchedJobId then
        entry.announcedJobId = entry.watchedJobId
        Subs_announceSync(state, timing)
    end if
    if previous <> invalid and not Subs_timingEquals(previous, timing) then Subs_onTimingChanged(key)
end sub

sub Subs_announceSync(state as object, timing as object)
    job = state.sync
    st = Str_orEmpty(job.status)
    name = Subs_languageName(state.language)
    if st = "synced" then
        if Subs_timingIsIdentity(timing) then
            m.global.toast = name + " subtitles: original timing kept"
        else
            m.global.toast = name + " subtitles synced to the audio: " + Subs_describeTiming(timing)
        end if
    else if st = "already_synced" then
        m.global.toast = name + " subtitles already match the audio."
    else if st = "no_match" then
        m.global.toast = name + " subtitles don't match this video's audio."
    else if st = "failed" then
        m.global.toast = Subs_failureMessage(job.failure)
    end if
end sub

' A syncable subtitle's timing changed: the Video node keeps the cues it already parsed, so the
' mounted sidecar is fetched again at the same position.
sub Subs_onTimingChanged(key as string)
    t = Subs_selectedTrack()
    if t <> invalid and t.syncKey = key then remountSubtitles()
end sub

function Subs_canSync(entry as object) as boolean
    sy = m.subs.sync
    if not sy.available or entry.unsupported then return false
    if Str_orEmpty(entry.state.source) = "external" and not sy.external then return false
    return true
end function

' The timing section for the selected subtitle, or invalid when it has none.
function Subs_timingActions() as dynamic
    t = Subs_selectedTrack()
    if t = invalid or t.syncKey = "" then return invalid
    entry = m.subs.sync.entries[t.syncKey]
    if entry = invalid then return invalid
    canSync = Subs_canSync(entry)
    canReset = not Subs_timingIsIdentity(entry.timing)
    if not entry.forbidden and not canSync and not canReset and entry.error = "" then return invalid
    job = entry.state.sync
    result = invalid
    if not entry.inProgress and entry.error = "" then result = Subs_resultLine(entry.timing, job)
    note = ""
    if not entry.forbidden and canSync and not entry.inProgress and result = invalid then
        if Str_orEmpty(entry.state.source) = "external" then
            note = "Matches the timing to the audio for everyone. The file itself isn't changed."
        else
            note = "Matches the timing to the audio for everyone watching."
        end if
    end if
    return {
        key: t.syncKey
        statusLabel: Subs_statusLabel(entry.timing, job)
        canSync: canSync
        canReset: canReset
        inProgress: entry.inProgress
        percent: Subs_progressPercent(job)
        phaseLabel: Subs_phaseLabel(job)
        result: result
        note: note
        busy: entry.busy
        forbidden: entry.forbidden
        error: entry.error
        actionsEnabled: not entry.busy and not entry.inProgress
    }
end function

function Subs_timingValue(timing as object) as string
    if timing.forbidden then return "Not allowed"
    if timing.busy then return "Working…"
    if timing.error <> "" then return timing.error
    if timing.statusLabel <> "" then return timing.statusLabel
    return "Not synced"
end function

' What the Timing row cannot fit: progress and phase, the last result, what a sync does, or why
' the actions are missing. {text, color}.
function Subs_timingDetail(timing as object) as object
    if timing.inProgress then
        parts = []
        if timing.percent >= 0 then parts.Push("Syncing " + timing.percent.ToStr() + "%")
        if timing.phaseLabel <> "" then parts.Push(timing.phaseLabel)
        return { text: Str_joinDots(parts), color: "" }
    end if
    if timing.forbidden then return { text: "This server doesn't allow changing subtitle timing.", color: "" }
    if timing.error <> "" then return { text: timing.error, color: "0xFCA5A5FF" }
    if timing.result <> invalid then
        color = ""
        if timing.result.warning then color = "0xFDE68AFF"
        return { text: timing.result.text, color: color }
    end if
    return { text: timing.note, color: "" }
end function

' "+2.3 s" / "−0.4 s".
function Subs_formatOffset(offsetMs as integer) as string
    tenths = (Abs(offsetMs) + 50) \ 100
    sign = "+"
    if offsetMs < 0 then sign = "−"
    return sign + (tenths \ 10).ToStr() + "." + (tenths mod 10).ToStr() + " s"
end function

' A scale as the frame-rate conversion it most likely is, else a speed factor; "" for none.
function Subs_describeScale(scale as float) as string
    if Abs(scale - 1.0) < 0.0000001 then return ""
    rates = [[23.976, "23.976"], [24.0, "24"], [25.0, "25"], [29.97, "29.97"], [30.0, "30"], [50.0, "50"], [59.94, "59.94"], [60.0, "60"]]
    for each a in rates
        for each b in rates
            if a[0] <> b[0] and Abs(a[0] / b[0] - scale) <= 0.000001 then return a[1] + "→" + b[1] + " fps"
        end for
    end for
    tenThousandths = Int(scale * 10000 + 0.5)
    whole = tenThousandths \ 10000
    frac = Str_padLeft((tenThousandths mod 10000).ToStr(), 4)
    while Right(frac, 1) = "0" and Len(frac) > 0
        frac = Left(frac, Len(frac) - 1)
    end while
    if frac = "" then return "×" + whole.ToStr() + " speed"
    return "×" + whole.ToStr() + "." + frac + " speed"
end function

function Subs_describeTiming(timing as object) as string
    scale = Subs_describeScale(timing.scale)
    parts = []
    if timing.offsetMs <> 0 or scale = "" then parts.Push(Subs_formatOffset(timing.offsetMs))
    if scale <> "" then parts.Push(scale)
    return Str_joinDots(parts)
end function

function Subs_progressPercent(job as dynamic) as integer
    if not Subs_jobInProgress(job) then return -1
    p = 0.0
    if job.progress <> invalid then p = job.progress * 1.0
    if p < 0 then p = 0
    if p > 1 then p = 1
    return Int(p * 100 + 0.5)
end function

function Subs_phaseLabel(job as dynamic) as string
    if not Subs_jobInProgress(job) then return ""
    ph = Str_orEmpty(job.phase)
    if ph = "matching" then return "Matching lines to speech…"
    if ph = "analyzing" then return "Listening to the audio…"
    return "Waiting to start…"
end function

function Subs_failureMessage(failure as dynamic) as string
    f = Str_orEmpty(failure)
    if f = "subtitle_changed" then return "The subtitle changed while it was syncing. Try again."
    if f = "no_audio" then return "This video has no audio Silo can read."
    if f = "unavailable" then return "The server is busy. Try again in a few minutes."
    return "Sync failed. Try again."
end function

' One short line describing a subtitle's timing, or "" when there is nothing to say.
function Subs_statusLabel(timing as object, job as dynamic) as string
    st = ""
    if job <> invalid then st = Str_orEmpty(job.status)
    if st = "pending" or st = "running" then
        pct = Subs_progressPercent(job)
        if pct > 0 then return "Syncing… " + pct.ToStr() + "%"
        return "Syncing…"
    else if st = "no_match" then
        return "Doesn't match this video"
    else if st = "failed" then
        return "Sync failed"
    else if st = "already_synced" then
        if Subs_timingIsIdentity(timing) then return "Already in sync"
    else if st = "synced" then
        if Subs_timingIsIdentity(timing) then return "Original timing"
        if job.result <> invalid and Subs_timingEquals(Subs_timing({ timing: job.result }), timing) then return "Synced " + Subs_describeTiming(timing)
    end if
    if Subs_timingIsIdentity(timing) then return ""
    return "Timing adjusted " + Subs_describeTiming(timing)
end function

' The sync status of a track in the picker (its detail line), or "".
function Subs_trackStatus(track as object) as string
    if track = invalid or Str_isEmpty(track.syncKey) then return ""
    entry = m.subs.sync.entries[track.syncKey]
    if entry = invalid then return ""
    return Subs_statusLabel(entry.timing, entry.state.sync)
end function

' The last finished job's outcome for the timing section: {text, warning} or invalid.
function Subs_resultLine(timing as object, job as dynamic) as dynamic
    if job = invalid then return invalid
    st = Str_orEmpty(job.status)
    if st = "synced" then
        if Subs_timingIsIdentity(timing) then return invalid
        return { text: "Synced to the audio: " + Subs_describeTiming(timing), warning: false }
    else if st = "already_synced" then
        return { text: "Already matches the audio.", warning: false }
    else if st = "no_match" then
        return { text: "Doesn't match this video's audio; probably for another release.", warning: true }
    else if st = "failed" then
        return { text: Subs_failureMessage(job.failure), warning: true }
    end if
    return invalid
end function

sub Subs_openTiming()
    timing = Subs_timingActions()
    if timing = invalid or timing.forbidden or not timing.actionsEnabled or not (timing.canSync or timing.canReset) then return
    acts = []
    if timing.canSync then acts.Push({ id: "sync", label: "Sync to audio", checked: false })
    if timing.canReset then acts.Push({ id: "reset", label: "Reset timing", checked: false })
    m.pickerKind = "subtiming"
    m.picker.title = "Subtitle Timing"
    m.picker.actions = acts
    m.picker.visible = true
    m.picker.setFocus(true)
    m.hideTimer.control = "stop"
end sub

sub Subs_timingChosen(id as string)
    timing = Subs_timingActions()
    if timing = invalid then return
    if id = "sync" then
        Subs_requestSync(timing.key)
    else if id = "reset" then
        Subs_resetTiming(timing.key)
    end if
end sub

function Subs_entry(key as string) as dynamic
    return m.subs.sync.entries[key]
end function

sub Subs_requestSync(key as string)
    entry = Subs_entry(key)
    if entry = invalid or entry.busy then return
    m.subs.sync.polledMs.Delete(key)
    entry.busy = true
    entry.error = ""
    entry.pollExpired = false
    Api_send("POST", Subs_filePath("/sync/" + Str_urlEncode(key)), invalid, "Subs_onSyncStarted", { fileId: m.fileId, key: key })
    Subs_refreshHud()
end sub

sub Subs_onSyncStarted(event as object)
    resp = Api_result(event)
    if m.closing or not Subs_sameFile(resp) then return
    key = Str_orEmpty(resp.context.key)
    if resp.ok and resp.data <> invalid and resp.data.subtitle <> invalid then
        watch = ""
        if resp.data.subtitle.sync <> invalid then watch = Str_orEmpty(resp.data.subtitle.sync.id)
        Subs_observe(resp.data.subtitle, watch)
        entry = Subs_entry(key)
        if entry <> invalid then entry.busy = false
        Subs_startPolling()
    else
        Subs_syncFail(key, resp, "Sync failed")
    end if
    Subs_refreshHud()
end sub

' Reset: the PUT needs the validator a read returns (If-Match), so read first.
sub Subs_resetTiming(key as string)
    entry = Subs_entry(key)
    if entry = invalid or entry.busy then return
    entry.busy = true
    entry.error = ""
    Api_get(Subs_filePath("/sync/" + Str_urlEncode(key)), invalid, "Subs_onSyncReadForReset", { fileId: m.fileId, key: key })
    Subs_refreshHud()
end sub

function Subs_etag(resp as object) as string
    if resp.headers = invalid then return ""
    for each k in resp.headers
        if LCase(k) = "etag" then return Str_orEmpty(resp.headers[k])
    end for
    return ""
end function

sub Subs_onSyncReadForReset(event as object)
    resp = Api_result(event)
    if m.closing or not Subs_sameFile(resp) then return
    key = Str_orEmpty(resp.context.key)
    if not resp.ok or resp.data = invalid or resp.data.subtitle = invalid then
        Subs_syncFail(key, resp, "Couldn't reset timing")
        Subs_refreshHud()
        return
    end if
    etag = Subs_etag(resp)
    if etag = "" then
        entry = Subs_entry(key)
        if entry <> invalid then
            entry.busy = false
            entry.error = "Couldn't read the subtitle's current version."
        end if
        Subs_refreshHud()
        return
    end if
    Api_call({ method: "PUT", path: Subs_filePath("/sync/" + Str_urlEncode(key) + "/timing"), body: { offset_ms: 0, scale: 1.0 }, headers: { "If-Match": etag }, context: { fileId: m.fileId, key: key } }, "Subs_onTimingSet")
end sub

sub Subs_onTimingSet(event as object)
    resp = Api_result(event)
    if m.closing or not Subs_sameFile(resp) then return
    key = Str_orEmpty(resp.context.key)
    if resp.ok and resp.data <> invalid and resp.data.subtitle <> invalid then
        Subs_observe(resp.data.subtitle, "")
        entry = Subs_entry(key)
        if entry <> invalid then entry.busy = false
    else
        Subs_syncFail(key, resp, "Couldn't reset timing")
    end if
    Subs_refreshHud()
end sub

sub Subs_syncFail(key as string, resp as object, fallback as string)
    entry = Subs_entry(key)
    if entry = invalid then return
    entry.busy = false
    if resp.status = 403 then
        entry.forbidden = true
        entry.error = ""
    else if resp.status = 422 then
        entry.unsupported = true
        entry.error = "This format can't be synced."
    else if resp.status = 412 then
        entry.error = "The subtitle changed. Try again."
    else
        msg = ""
        if resp.error <> invalid then msg = Str_orEmpty(resp.error.title)
        if msg = "" then msg = fallback
        entry.error = msg
    end if
end sub

function Subs_pollableKeys() as object
    keys = []
    for each key in m.subs.sync.entries
        e = m.subs.sync.entries[key]
        if e.inProgress and not e.pollExpired then keys.Push(key)
    end for
    return keys
end function

' Polls every running job every 3 s until it ends or 5 minutes pass.
sub Subs_startPolling()
    if Subs_pollableKeys().Count() = 0 then
        m.subsSyncTimer.control = "stop"
        return
    end if
    m.subsSyncTimer.control = "start"
end sub

sub Subs_onSyncPoll()
    if m.closing or m.fileId = "" then
        m.subsSyncTimer.control = "stop"
        return
    end if
    keys = Subs_pollableKeys()
    if keys.Count() = 0 then
        m.subsSyncTimer.control = "stop"
        return
    end if
    for each key in keys
        polled = 3000
        if m.subs.sync.polledMs[key] <> invalid then polled = m.subs.sync.polledMs[key] + 3000
        m.subs.sync.polledMs[key] = polled
        if polled > 300000 then
            m.subs.sync.polledMs.Delete(key)
            m.subs.sync.entries[key].pollExpired = true
        else
            Api_get(Subs_filePath("/sync/" + Str_urlEncode(key)), invalid, "Subs_onSyncRead", { fileId: m.fileId, key: key })
        end if
    end for
end sub

sub Subs_onSyncRead(event as object)
    resp = Api_result(event)
    if m.closing or not Subs_sameFile(resp) then return
    key = Str_orEmpty(resp.context.key)
    if resp.ok and resp.data <> invalid and resp.data.subtitle <> invalid then
        Subs_observe(resp.data.subtitle, "")
    else if resp.status <> 0 then
        ' A subtitle the server stops answering for is not polled again until a reload.
        entry = Subs_entry(key)
        if entry <> invalid then entry.pollExpired = true
    end if
    Subs_startPolling()
    Subs_refreshHud()
end sub

' ---------- Search subtitles (TvSubtitleSearchDialog) ----------

sub Subs_openSearch()
    if m.fileId = "" then return
    sr = m.subs.search
    ' Keep prior results and language when reopening mid-session.
    if not sr.hasSearched then sr.language = Subs_preferredLanguage()
    Subs_renderSearch()
end sub

sub Subs_renderSearch()
    sr = m.subs.search
    rows = []
    opts = Subs_languageOptions()
    rows.Push({ kind: "cycler", id: "lang", label: "Language", value: opts[Subs_languageIndex(sr.language)].name })
    label = "Search"
    if sr.searching then label = "Searching…"
    rows.Push({ kind: "action", id: "search", label: label, disabled: sr.searching or sr.downloadingKey <> "" })
    if sr.error <> "" then rows.Push({ kind: "text", text: sr.error, color: "0xEF4444FF" })
    for each w in sr.warnings
        rows.Push({ kind: "text", text: Str_orEmpty(w), color: "0xFBBF24FF" })
    end for
    if sr.hasSearched and not sr.searching and sr.results.Count() = 0 and sr.error = "" then
        rows.Push({ kind: "text", text: "No subtitles found", color: "0xEDEDED8F" })
    end if
    for each r in sr.results
        key = Str_orEmpty(r.provider) + ":" + Str_orEmpty(r.id)
        rows.Push({ kind: "result", id: "r:" + key, score: r.score, releaseName: Str_orEmpty(r.release_name), provider: Str_orEmpty(r.provider), hearingImpaired: r.hearing_impaired = true, downloads: r.downloads, languageName: Subs_languageName(r.language), busy: sr.downloadingKey = key })
    end for
    Subs_showDialog("search", "Search subtitles", rows)
end sub

sub Subs_searchCycled(id as string, direction as integer)
    if id <> "lang" then return
    opts = Subs_languageOptions()
    i = Subs_languageIndex(m.subs.search.language) + direction
    if i < 0 then i = opts.Count() - 1
    if i >= opts.Count() then i = 0
    m.subs.search.language = opts[i].code
    Subs_renderSearch()
end sub

sub Subs_searchChosen(id as string)
    if id = "search" then
        Subs_search()
    else if Left(id, 2) = "r:" then
        key = Mid(id, 3)
        for each r in m.subs.search.results
            if Str_orEmpty(r.provider) + ":" + Str_orEmpty(r.id) = key then Subs_download(r, key)
        end for
    end if
end sub

sub Subs_search()
    sr = m.subs.search
    if sr.searching or m.fileId = "" then return
    sr.searching = true
    sr.hasSearched = true
    sr.error = ""
    sr.results = []
    sr.warnings = []
    Api_send("POST", "/api/v2/subtitles/search", { media_file_id: m.fileId, languages: [sr.language] }, "Subs_onSearch", { fileId: m.fileId })
    Subs_renderSearch()
end sub

sub Subs_onSearch(event as object)
    resp = Api_result(event)
    if m.closing or not Subs_sameFile(resp) then return
    sr = m.subs.search
    sr.searching = false
    if resp.ok and resp.data <> invalid then
        sr.results = Arr_or(resp.data.results)
        sr.warnings = Arr_or(resp.data.warnings)
    else
        ' No capability probe exists: "no providers configured" arrives as a plain server error.
        sr.error = Subs_errorText(resp, "Subtitle search failed")
    end if
    if m.subs.dialog = "search" then Subs_renderSearch()
end sub

function Subs_errorText(resp as object, fallback as string) as string
    if resp.status = 0 then return Api_errorText(resp)
    if resp.error <> invalid then
        d = Str_orEmpty(resp.error.detail)
        if d <> "" then return d
        t = Str_orEmpty(resp.error.title)
        if t <> "" then return t
    end if
    return fallback
end function

' Downloads a provider hit to the server (SubtitleDownloadBody), then adopts the stored subtitle.
sub Subs_download(r as object, key as string)
    sr = m.subs.search
    if sr.downloadingKey <> "" or m.fileId = "" then return
    sr.downloadingKey = key
    sr.error = ""
    body = {
        media_file_id: m.fileId
        provider: Str_orEmpty(r.provider)
        subtitle_id: Str_orEmpty(r.id)
        language: Str_orEmpty(r.language)
        release_name: Str_orEmpty(r.release_name)
        score: 0.0
        hearing_impaired: r.hearing_impaired = true
    }
    if r.score <> invalid then body.score = r.score * 1.0
    Api_send("POST", "/api/v2/subtitles/download", body, "Subs_onDownloaded", { fileId: m.fileId, sessionId: m.sessionId })
    Subs_renderSearch()
end sub

sub Subs_onDownloaded(event as object)
    resp = Api_result(event)
    if m.closing or not Subs_sameFile(resp) or Str_orEmpty(resp.context.sessionId) <> m.sessionId then return
    sr = m.subs.search
    if resp.ok and resp.data <> invalid and resp.data.subtitle <> invalid then
        stored = resp.data.subtitle
        Subs_remember(stored)
        Subs_adoptStored(Str_orEmpty(stored.id), "search")
    else
        sr.downloadingKey = ""
        sr.error = Subs_errorText(resp, "Subtitle download failed")
        if m.subs.dialog = "search" then Subs_renderSearch()
    end if
end sub

' ---------- Adopting a stored subtitle ----------

' A subtitle the server just stored (a download or an AI result) is not in the session's
' inventory yet. The TV app re-lists and re-prepares its player in place; a Roku Video node can't
' take a new sidecar mid-stream, so a "track_change" replan fetches an inventory that lists it
' and the plan is remounted at the current position with that track selected.
sub Subs_adoptStored(storedId as string, origin as string)
    if m.plan = invalid or m.sessionId = "" or storedId = "" then
        Subs_adoptFailed(origin, "The subtitle list could not be refreshed.")
        return
    end if
    inst = installationId()
    if inst = "" then
        Subs_adoptFailed(origin, "The subtitle list could not be refreshed.")
        return
    end if
    m.subs.adoptId = storedId
    m.subs.adoptOrigin = origin
    selected = {}
    if m.plan.selected_tracks <> invalid then selected = m.plan.selected_tracks
    body = PlaybackCaps_replanBody(inst, m.attemptId, m.plan, "track_change", m.qualityPref, m.position, selected)
    Api_send("POST", "/api/v2/playback/" + Str_urlEncode(m.sessionId) + "/replan", body, "Subs_onAdoptReplan", { fileId: m.fileId, sessionId: m.sessionId, storedId: storedId })
end sub

sub Subs_onAdoptReplan(event as object)
    resp = Api_result(event)
    if m.closing or not Subs_sameFile(resp) or Str_orEmpty(resp.context.sessionId) <> m.sessionId then return
    storedId = Str_orEmpty(resp.context.storedId)
    origin = m.subs.adoptOrigin
    m.subs.adoptId = ""
    ok = resp.ok and resp.data <> invalid and resp.data.outcome = "playable" and resp.data.playback_plan <> invalid and PlaybackCaps_planProblem(resp.data) = ""
    if not ok then
        Subs_adoptFailed(origin, Subs_adoptPrefix(origin) + ", but the subtitle list could not be refreshed.")
        return
    end if
    plan = resp.data.playback_plan
    trackId = ""
    renderable = false
    if plan.subtitle <> invalid then
        for each t in Arr_or(plan.subtitle.inventory)
            if Subs_storedIdOf(t) = storedId then
                trackId = Str_orEmpty(t.track_id)
                renderable = Subs_buildTrack(t) <> invalid
            end if
        end for
    end if
    if trackId = "" then
        Subs_adoptFailed(origin, Subs_adoptPrefix(origin) + ", but the subtitle list could not be refreshed.")
        return
    end if
    if not renderable then
        ' Stored on the server, listed in the inventory, but not a WebVTT/SRT sidecar.
        m.global.toast = "Subtitle saved on the server, but Roku can't show this format."
        trackId = Subs_selectedTrackId()
    end if
    m.video.control = "stop"
    applyPlan(plan, { resumeAt: m.position, subtitleTrackId: trackId })
    Subs_adoptDone(origin)
end sub

function Subs_adoptPrefix(origin as string) as string
    if origin = "ai" then return "Translated"
    return "Downloaded"
end function

sub Subs_adoptFailed(origin as string, message as string)
    if origin = "ai" then
        m.subs.ai.phase = "failed"
        m.subs.ai.error = message
        if m.subs.dialog = "ai" then Subs_renderAi()
    else
        m.subs.search.downloadingKey = ""
        m.subs.search.error = message
        if m.subs.dialog = "search" then Subs_renderSearch()
    end if
end sub

' The track merged and was selected: the dialog closes on its own, like the TV's completedNonce.
sub Subs_adoptDone(origin as string)
    if origin = "ai" then
        m.subs.ai.phase = "idle"
        m.subs.ai.error = ""
        m.subs.ai.job = invalid
    else
        m.subs.search.downloadingKey = ""
    end if
    if m.subs.dialog = origin then Subs_closeDialog()
    Subs_syncReload()
end sub

' ---------- Translate with AI (TvAiTranslateDialog) ----------

' Tracks the server can translate: external / downloaded sources in a server-parseable text
' format, embedded non-bitmap tracks (extracted to text via ffmpeg).
function Subs_isTranslatable(t as object) as boolean
    codec = LCase(Str_orEmpty(t.codec))
    if Str_orEmpty(t.source) = "embedded" then
        for each b in ["pgs", "hdmv_pgs_subtitle", "dvd_subtitle", "dvdsub", "dvb_subtitle", "dvbsub"]
            if codec = b then return false
        end for
        return true
    end if
    return codec = "srt" or codec = "subrip" or codec = "vtt" or codec = "webvtt"
end function

function Subs_aiSubtitleSources() as object
    out = []
    for each t in m.subs.subtitleInventory
        if Subs_isTranslatable(t) then out.Push(t)
    end for
    return out
end function

function Subs_aiAudioSources() as object
    if m.version = invalid then return []
    return Arr_or(m.version.audio_tracks)
end function

' "English SRT (External)" — the TV's subtitleChoiceLabel, from the inventory item.
function Subs_aiSubtitleLabel(t as object, position as integer) as string
    name = Subs_languageName(t.language)
    if Str_isEmpty(t.language) then
        name = Str_orEmpty(t.label)
        if name = "" then name = "Track " + (position + 1).ToStr()
    end if
    codec = Tracks_subtitleCodec(t.codec)
    if codec <> "" then name = name + " " + codec
    src = Str_orEmpty(t.source)
    if src = "external" then
        name = name + " (External)"
    else if src = "downloaded" then
        name = name + " (Downloaded)"
    end if
    return name
end function

sub Subs_openAi()
    if not Subs_aiAvailable() then return
    ai = m.subs.ai
    Api_get("/api/v2/subtitles/ai/quota", invalid, "Subs_onAiQuota", { fileId: m.fileId })
    if ai.phase = "failed" then ai.phase = "idle"
    ' The mode row appears only when both modes are available; otherwise the available one is fixed.
    subsOk = m.subs.aiStatus.enabled and Subs_aiSubtitleSources().Count() > 0
    audioOk = m.subs.aiStatus.transcribeEnabled and Subs_aiAudioSources().Count() > 0
    if not subsOk then
        ai.mode = "audio"
    else if not audioOk then
        ai.mode = "subtitles"
    end if
    if ai.audioPos = 0 and m.version <> invalid then
        auto = Tracks_autoAudioOrdinal(m.version)
        if auto > 0 then ai.audioPos = auto
    end if
    if ai.targetPos < 0 then ai.targetPos = Subs_languageIndex(Subs_preferredLanguage())
    Subs_renderAi()
end sub

sub Subs_onAiQuota(event as object)
    resp = Api_result(event)
    if m.closing or not Subs_sameFile(resp) then return
    if resp.ok and resp.data <> invalid then
        m.subs.ai.quota = resp.data
        if m.subs.dialog = "ai" then Subs_renderAi()
    end if
end sub

function Subs_quotaPeriod(period as string) as string
    p = LCase(period)
    if p = "day" then return "today"
    if p = "week" then return "this week"
    if p = "month" then return "this month"
    return "this " + period
end function

function Subs_quotaExhausted() as boolean
    ai = m.subs.ai
    if ai.mode <> "audio" or ai.quota = invalid or ai.quota.limited <> true then return false
    remaining = 0
    if ai.quota.remaining <> invalid then remaining = Int(ai.quota.remaining)
    return remaining <= 0
end function

sub Subs_renderAi()
    ai = m.subs.ai
    rows = []
    subSources = Subs_aiSubtitleSources()
    audioSources = Subs_aiAudioSources()
    subsOk = m.subs.aiStatus.enabled and subSources.Count() > 0
    audioOk = m.subs.aiStatus.transcribeEnabled and audioSources.Count() > 0
    opts = Subs_languageOptions()
    if ai.phase = "running" then
        pct = Int(ai.progress * 100)
        if pct < 0 then pct = 0
        if pct > 100 then pct = 100
        rows.Push({ kind: "progress", title: "Translating… " + pct.ToStr() + "%", percent: pct, message: ai.message })
        rows.Push({ kind: "action", id: "cancel", label: "Cancel" })
    else if ai.phase = "submitting" then
        rows.Push({ kind: "text", text: "Submitting…", color: "0xEDEDEDB8" })
    else if not subsOk and not audioOk then
        rows.Push({ kind: "text", text: "No translatable subtitle tracks, and audio transcription is not available on this server.", color: "0xEDEDEDA8" })
        rows.Push({ kind: "action", id: "close", label: "Close" })
    else
        if subsOk and audioOk then
            modeLabel = "From subtitles"
            if ai.mode = "audio" then modeLabel = "From audio"
            rows.Push({ kind: "cycler", id: "mode", label: "Mode", value: modeLabel })
        end if
        if ai.mode = "subtitles" then
            if ai.subPos >= subSources.Count() then ai.subPos = 0
            rows.Push({ kind: "cycler", id: "source", label: "Source subtitle", value: Subs_aiSubtitleLabel(subSources[ai.subPos], ai.subPos) })
        else
            if ai.audioPos >= audioSources.Count() then ai.audioPos = 0
            rows.Push({ kind: "cycler", id: "source", label: "Source audio", value: Tracks_audioSummary(audioSources[ai.audioPos], ai.audioPos) })
        end if
        if ai.targetPos < 0 or ai.targetPos >= opts.Count() then ai.targetPos = 0
        rows.Push({ kind: "cycler", id: "target", label: "Target language", value: opts[ai.targetPos].name })
        ' Quota applies to the transcribe kinds only; exempt callers (admins) get limited=false.
        if ai.mode = "audio" and ai.quota <> invalid and ai.quota.limited = true then
            q = ai.quota
            period = Subs_quotaPeriod(Str_orEmpty(q.period))
            if Subs_quotaExhausted() then
                rows.Push({ kind: "text", text: "Transcription quota exhausted (" + Str_orEmpty(q.used) + " of " + Str_orEmpty(q.limit) + " used " + period + ")", color: "0xF59E0BFF" })
            else
                rows.Push({ kind: "text", text: Str_orEmpty(q.remaining) + " of " + Str_orEmpty(q.limit) + " transcriptions left " + period, color: "0xEDEDEDA8" })
            end if
        end if
        if ai.phase = "failed" and ai.error <> "" then rows.Push({ kind: "text", text: ai.error, color: "0xEF4444FF" })
        label = "Translate"
        if ai.mode = "audio" then label = "Transcribe"
        rows.Push({ kind: "action", id: "submit", label: label, disabled: Subs_quotaExhausted() })
    end if
    Subs_showDialog("ai", "Translate with AI", rows)
end sub

sub Subs_aiCycled(id as string, direction as integer)
    ai = m.subs.ai
    if ai.phase = "running" or ai.phase = "submitting" then return
    if id = "mode" then
        if ai.mode = "subtitles" then ai.mode = "audio" else ai.mode = "subtitles"
    else if id = "source" then
        if ai.mode = "subtitles" then
            n = Subs_aiSubtitleSources().Count()
            if n > 0 then ai.subPos = (ai.subPos + direction + n) mod n
        else
            n = Subs_aiAudioSources().Count()
            if n > 0 then ai.audioPos = (ai.audioPos + direction + n) mod n
        end if
    else if id = "target" then
        n = Subs_languageOptions().Count()
        ai.targetPos = (ai.targetPos + direction + n) mod n
    end if
    Subs_renderAi()
end sub

sub Subs_aiChosen(id as string)
    if id = "submit" then
        Subs_aiSubmit()
    else if id = "cancel" then
        Subs_aiCancel()
    else if id = "close" then
        Subs_closeDialog()
    end if
end sub

' POST /api/v2/subtitles/ai/translate: source_index is the combined subtitle index for
' "translate" and the audio track index for the transcribe kinds; start_position is the playhead.
' No session_id: like Android, Siku polls the job instead of streaming live cues.
sub Subs_aiSubmit()
    ai = m.subs.ai
    if m.fileId = "" or ai.phase = "running" or ai.phase = "submitting" or Subs_quotaExhausted() then return
    opts = Subs_languageOptions()
    target = opts[ai.targetPos].code
    if ai.mode = "subtitles" then
        sources = Subs_aiSubtitleSources()
        if sources.Count() = 0 then return
        src = sources[ai.subPos]
        kind = "translate"
        sourceIndex = 0
        if src.combined_index <> invalid then sourceIndex = Int(src.combined_index)
        sourceLanguage = Str_orEmpty(src.language)
    else
        sources = Subs_aiAudioSources()
        if sources.Count() = 0 then return
        src = sources[ai.audioPos]
        kind = "transcribe_translate"
        if Subs_isSameLanguage(src.language, target) then kind = "transcribe"
        sourceIndex = ai.audioPos
        if src.index <> invalid then sourceIndex = Int(src.index)
        sourceLanguage = Str_orEmpty(src.language)
    end if
    ai.phase = "submitting"
    ai.error = ""
    body = { media_file_id: m.fileId, kind: kind, source_index: sourceIndex, source_language: sourceLanguage, target_language: target, start_position: m.position }
    Api_send("POST", "/api/v2/subtitles/ai/translate", body, "Subs_onAiCreated", { fileId: m.fileId, sessionId: m.sessionId })
    Subs_renderAi()
end sub

sub Subs_onAiCreated(event as object)
    resp = Api_result(event)
    if m.closing or not Subs_sameFile(resp) or Str_orEmpty(resp.context.sessionId) <> m.sessionId then return
    ai = m.subs.ai
    if resp.ok and resp.data <> invalid and resp.data.job <> invalid then
        job = resp.data.job
        ai.job = job
        ai.phase = "running"
        ai.progress = 0.0
        if job.progress <> invalid then ai.progress = job.progress * 1.0
        ai.message = Str_orEmpty(job.progress_message)
        if ai.message = "" and resp.data.live_delivery_attached <> true then ai.message = "Processing in background"
        Subs_applyAiJob(job)
        if ai.phase = "running" then m.subsAiTimer.control = "start"
    else
        ' 429 = quota exhausted: refresh the quota so the dialog flips to the exhausted state.
        if resp.status = 429 then Api_get("/api/v2/subtitles/ai/quota", invalid, "Subs_onAiQuota", { fileId: m.fileId })
        ai.phase = "failed"
        ai.error = Subs_errorText(resp, "Translation failed")
    end if
    if m.subs.dialog = "ai" then Subs_renderAi()
end sub

sub Subs_onAiPoll()
    ai = m.subs.ai
    if m.closing or ai.phase <> "running" or ai.job = invalid then
        m.subsAiTimer.control = "stop"
        return
    end if
    Api_get("/api/v2/subtitles/ai/jobs/" + Str_urlEncode(Str_orEmpty(ai.job.id)), invalid, "Subs_onAiJob", { fileId: m.fileId, sessionId: m.sessionId, jobId: Str_orEmpty(ai.job.id) })
end sub

sub Subs_onAiJob(event as object)
    resp = Api_result(event)
    if m.closing or not Subs_sameFile(resp) or Str_orEmpty(resp.context.sessionId) <> m.sessionId then return
    ai = m.subs.ai
    if ai.job = invalid or Str_orEmpty(ai.job.id) <> Str_orEmpty(resp.context.jobId) then return
    if resp.ok and resp.data <> invalid and resp.data.job <> invalid then
        Subs_applyAiJob(resp.data.job)
    else if resp.status = 404 then
        m.subsAiTimer.control = "stop"
        ai.phase = "failed"
        ai.error = "The translation job is gone."
    end if
    ' Ordinary transport failures keep polling.
    if m.subs.dialog = "ai" then Subs_renderAi()
end sub

' Applies a job read: progress while it runs, then its terminal outcome.
sub Subs_applyAiJob(job as object)
    ai = m.subs.ai
    st = Str_orEmpty(job.status)
    if job.progress <> invalid then ai.progress = job.progress * 1.0
    msg = Str_orEmpty(job.progress_message)
    if msg <> "" then ai.message = msg
    if st = "completed" then
        m.subsAiTimer.control = "stop"
        ai.phase = "submitting"
        resultId = Str_orEmpty(job.result_subtitle_id)
        if resultId = "" then
            ai.phase = "failed"
            ai.error = "Translated, but the server named no subtitle."
            return
        end if
        Subs_adoptStored(resultId, "ai")
    else if st = "failed" then
        m.subsAiTimer.control = "stop"
        ai.phase = "failed"
        ai.error = Str_orEmpty(job.error_message)
        if ai.error = "" then ai.error = "Translation failed"
    else if st = "cancelled" then
        m.subsAiTimer.control = "stop"
        ai.phase = "idle"
        ai.job = invalid
    end if
end sub

' Cancel row: stop polling, ask the server to cancel, return to the form.
sub Subs_aiCancel()
    ai = m.subs.ai
    m.subsAiTimer.control = "stop"
    if ai.job <> invalid then Api_fire("POST", "/api/v2/subtitles/ai/jobs/" + Str_urlEncode(Str_orEmpty(ai.job.id)) + "/cancel")
    ai.job = invalid
    ai.phase = "idle"
    ai.error = ""
    Subs_renderAi()
end sub
