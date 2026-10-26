' SPDX-License-Identifier: AGPL-3.0-or-later
' Audio and subtitle choices remembered for a whole series (or one movie), as Silo Android #680
' saves them (SeriesSubtitleChoice.kt, SeriesAudioChoice.kt, SeriesTrackChoiceWriter.kt):
'   PUT    /api/v2/subtitle-prefs/{series_id}  {subtitle_language, subtitle_track_index, subtitle_mode, track_signature?}
'   DELETE /api/v2/subtitle-prefs/{series_id}  back to automatic (204, also when nothing was stored)
'   PUT    /api/v2/audio-prefs/{series_id}     {audio_track_index, audio_language?, track_signature?}
'   DELETE /api/v2/audio-prefs/{series_id}
' The id is the series for an episode and the item's own content id for a movie. Only a viewer's
' own pick is written (player menus, detail-page selectors); automatic choices never are. The
' server answers with effective_subtitle_language / _mode / _track_signature and
' effective_audio_track_index on the watch and item details, which playback starts from.
'
' Writes go through a small queue on m.global.seriesChoices so they land in the order picked
' (one request in flight per series and kind; a newer pick waits for it), survive a closed screen
' (the next player start or detail page resends what is left) and expire after ten minutes, so a
' late retry never overwrites a newer choice made on another device. A write only goes out while
' the profile it was made under is active; a refused one (4xx) is dropped.
' Needs Utils.brs, Api.brs and Session.brs.

' The id a choice is remembered under: the series for an episode, else the content id; "" when neither.
function SeriesChoice_key(seriesId as dynamic, contentId as dynamic) as string
    s = Str_orEmpty(seriesId).Trim()
    if s <> "" then return s
    return Str_orEmpty(contentId).Trim()
end function

' ---------- Bodies ----------

' A track language as the server's audio_language / subtitle_language accept it: a BCP 47 tag or
' ISO 639 code as recorded, an English language name older files carry ("English") as its tag,
' and "" for unknown ("und") or anything else, which the server would refuse with a 422.
function SeriesChoice_langTag(language as dynamic) as string
    v = Str_orEmpty(language).Trim()
    if v = "" or LCase(v) = "und" then return ""
    re = CreateObject("roRegex", "^[A-Za-z]{2,3}([-_][0-9A-Za-z]{1,8})*$", "")
    if re.IsMatch(v) then return v
    names = { english: "en", spanish: "es", french: "fr", german: "de", italian: "it", portuguese: "pt", japanese: "ja", korean: "ko", chinese: "zh", russian: "ru", dutch: "nl", swedish: "sv", norwegian: "no", danish: "da", finnish: "fi", polish: "pl", turkish: "tr", czech: "cs", greek: "el", hebrew: "he", hungarian: "hu", arabic: "ar", hindi: "hi", thai: "th", vietnamese: "vi", ukrainian: "uk", romanian: "ro", indonesian: "id" }
    tag = names[LCase(v)]
    if tag <> invalid then return tag
    return ""
end function

function SeriesChoice_clean(v as dynamic) as dynamic
    s = Str_orEmpty(v).Trim()
    if s = "" then return invalid
    return s
end function

' Subtitles off for the series (the web and Apple spelling). show_forced_subtitles is never
' sent: it would pin the profile's forced toggle on this series.
function SeriesChoice_subtitleOff() as object
    return { subtitle_language: "", subtitle_track_index: -1, subtitle_mode: "off" }
end function

' A track from the player's renderable list (Subs_buildTrack: language, codec, label, source,
' forced, hearingImpaired, combinedIndex; rawLabel is the inventory label the signature records).
function SeriesChoice_subtitleFromPlayer(t as object) as object
    idx = Int(Num_or(t.combinedIndex, -1))
    if idx < -1 then idx = -1
    src = LCase(Str_orEmpty(t.source))
    if Str_orEmpty(t.storedId) <> "" then src = "downloaded"
    if src <> "embedded" and src <> "external" and src <> "downloaded" then src = ""
    sig = { forced: t.forced = true, hearing_impaired: t.hearingImpaired = true }
    SeriesChoice_setIf(sig, "source", src)
    SeriesChoice_setIf(sig, "language", t.language)
    SeriesChoice_setIf(sig, "codec", t.codec)
    SeriesChoice_setIf(sig, "label", t.rawLabel)
    return { subtitle_language: SeriesChoice_langTag(t.language), subtitle_track_index: idx, subtitle_mode: "always", track_signature: sig }
end function

' A track from a version's catalog subtitle_tracks, at its combined selection index (detail page).
function SeriesChoice_subtitleFromCatalog(t as object, combinedIndex as integer) as object
    src = "embedded"
    if t.external = true then src = "external"
    sig = { source: src, forced: t.forced = true, hearing_impaired: Tracks_subtitleIsSdh(t) }
    SeriesChoice_setIf(sig, "language", t.language)
    SeriesChoice_setIf(sig, "codec", t.codec)
    SeriesChoice_setIf(sig, "label", t.title)
    idx = combinedIndex
    if idx < -1 then idx = -1
    return { subtitle_language: SeriesChoice_langTag(t.language), subtitle_track_index: idx, subtitle_mode: "always", track_signature: sig }
end function

' The track at `ordinal` of a version's catalog audio_tracks. The signature is built from the
' catalog track because the server matches title, embedded title, codec and layout exactly.
function SeriesChoice_audioFromCatalog(t as object, ordinal as integer) as object
    body = { audio_track_index: ordinal }
    tag = SeriesChoice_langTag(t.language)
    if tag <> "" then body.audio_language = tag
    sig = {}
    SeriesChoice_setIf(sig, "language", t.language)
    SeriesChoice_setIf(sig, "title", t.title)
    SeriesChoice_setIf(sig, "embedded_title", t.embedded_title)
    SeriesChoice_setIf(sig, "codec", t.codec)
    SeriesChoice_setIf(sig, "layout", t.layout)
    ch = Int(Num_or(t.channels, 0))
    if ch > 0 then sig.channels = ch
    if sig.Count() > 0 then body.track_signature = sig
    return body
end function

sub SeriesChoice_setIf(aa as object, key as string, value as dynamic)
    v = SeriesChoice_clean(value)
    if v <> invalid then aa[key] = v
end sub

' ---------- Queue ----------

function SeriesChoice_identity() as string
    s = m.global.session
    if s = invalid then return ""
    if Str_isEmpty(s.serverUrl) or Str_isEmpty(s.profileId) then return ""
    return Str_orEmpty(s.serverUrl) + "|" + Str_orEmpty(s.profileId)
end function

function SeriesChoice_state() as object
    if not m.global.hasField("seriesChoices") then m.global.addFields({ seriesChoices: {} })
    st = m.global.seriesChoices
    if st = invalid or Type(st) <> "roAssociativeArray" then st = {}
    return st
end function

sub SeriesChoice_store(st as object)
    m.global.seriesChoices = st
end sub

' Saves a subtitle choice (body) or, with body = invalid, sets the series back to automatic.
sub SeriesChoice_saveSubtitle(key as string, body as dynamic)
    SeriesChoice_save("subtitle", key, body)
end sub

sub SeriesChoice_saveAudio(key as string, body as dynamic)
    SeriesChoice_save("audio", key, body)
end sub

sub SeriesChoice_save(kind as string, key as string, body as dynamic)
    ident = SeriesChoice_identity()
    if ident = "" or key = "" then return
    st = SeriesChoice_state()
    id = ident + "|" + kind + "|" + key
    e = st[id]
    seq = 1
    if e <> invalid then seq = Int(Num_or(e.seq, 0)) + 1
    ne = { identity: ident, kind: kind, key: key, body: body, isDelete: body = invalid, seq: seq, at: Time_nowSeconds(), sentSeq: 0, sentAt: 0 }
    if e <> invalid then
        ne.sentSeq = Int(Num_or(e.sentSeq, 0))
        ne.sentAt = Int(Num_or(e.sentAt, 0))
    end if
    st[id] = ne
    SeriesChoice_store(st)
    print "[siku-playback] series choice " + kind + " key=" + key + " " + SeriesChoice_describe(ne)
    SeriesChoice_send(id)
end sub

function SeriesChoice_describe(e as object) as string
    if e.isDelete = true then return "auto"
    b = e.body
    if e.kind = "subtitle" then
        if Str_orEmpty(b.subtitle_mode) = "off" then return "off"
        return "track=" + Str_orEmpty(b.subtitle_track_index) + " lang=" + Str_orEmpty(b.subtitle_language)
    end if
    return "track=" + Str_orEmpty(b.audio_track_index) + " lang=" + Str_orEmpty(b.audio_language)
end function

' Sends the entry's latest write unless one is already in flight (a request is presumed lost
' after 30 s, e.g. when the screen that sent it closed).
sub SeriesChoice_send(id as string)
    st = SeriesChoice_state()
    e = st[id]
    if e = invalid then return
    if e.identity <> SeriesChoice_identity() then return
    now = Time_nowSeconds()
    if now - Int(Num_or(e.at, 0)) > 600 then
        st.Delete(id)
        SeriesChoice_store(st)
        return
    end if
    if Int(Num_or(e.sentSeq, 0)) > 0 and now - Int(Num_or(e.sentAt, 0)) < 30 then return
    e = AA_copy(e)
    e.sentSeq = e.seq
    e.sentAt = now
    st[id] = e
    SeriesChoice_store(st)
    path = "/api/v2/" + e.kind + "-prefs/" + Str_urlEncode(e.key)
    ctx = { seriesChoiceId: id, seq: e.seq }
    if e.isDelete = true then
        Api_call({ method: "DELETE", path: path, context: ctx }, "SeriesChoice_onSent")
    else
        Api_call({ method: "PUT", path: path, body: e.body, context: ctx }, "SeriesChoice_onSent")
    end if
end sub

sub SeriesChoice_onSent(event as object)
    resp = Api_result(event)
    ctx = resp.context
    if ctx = invalid then return
    id = Str_orEmpty(ctx.seriesChoiceId)
    st = SeriesChoice_state()
    e = st[id]
    if e = invalid then return
    sentSeq = Int(Num_or(ctx.seq, 0))
    landed = resp.ok or (resp.status = 404 and e.isDelete = true)
    refused = not landed and resp.status >= 400 and resp.status < 500 and resp.status <> 408 and resp.status <> 429
    if not landed then print "[siku-playback] series choice " + e.kind + " key=" + e.key + " failed status=" + Str_orEmpty(resp.status)
    e = AA_copy(e)
    e.sentSeq = 0
    e.sentAt = 0
    if Int(Num_or(e.seq, 0)) > sentSeq then
        ' A newer pick came in while this one was in flight: send that one now.
        st[id] = e
        SeriesChoice_store(st)
        SeriesChoice_send(id)
        return
    end if
    if landed or refused then
        st.Delete(id)
    else
        st[id] = e   ' network or server error: the next flush sends it again
    end if
    SeriesChoice_store(st)
end sub

' Resends what has not landed for the active profile (called when a player or detail page opens).
sub SeriesChoice_flush()
    st = SeriesChoice_state()
    for each id in st
        SeriesChoice_send(id)
    end for
end sub

' The not-yet-landed choice for this key and kind: invalid when there is none, else
' { body } with body = invalid for "back to automatic".
function SeriesChoice_pending(kind as string, key as string) as dynamic
    ident = SeriesChoice_identity()
    if ident = "" or key = "" then return invalid
    e = SeriesChoice_state()[ident + "|" + kind + "|" + key]
    if e = invalid then return invalid
    if Time_nowSeconds() - Int(Num_or(e.at, 0)) > 600 then return invalid
    return { body: e.body }
end function

' A watch or item detail with this device's unsent choices laid over its effective fields
' (EffectiveSubtitleFields.withPending / withPendingSeriesAudioChoice): a subtitle track becomes
' its language, mode "always" and signature; Off becomes mode "off"; Auto clears all three, so
' the profile's preferences apply. An audio track resolves on every version; Auto clears it.
function SeriesChoice_overlay(d as dynamic) as dynamic
    if d = invalid or Type(d) <> "roAssociativeArray" then return d
    key = SeriesChoice_key(d.series_id, d.content_id)
    subPend = SeriesChoice_pending("subtitle", key)
    ap = SeriesChoice_pending("audio", key)
    if subPend = invalid and ap = invalid then return d
    out = AA_copy(d)
    if subPend <> invalid then
        b = subPend.body
        if b = invalid then
            out.effective_subtitle_language = invalid
            out.effective_subtitle_mode = invalid
            out.effective_subtitle_track_signature = invalid
        else if Str_orEmpty(b.subtitle_mode) = "off" then
            out.effective_subtitle_mode = "off"
            out.effective_subtitle_track_signature = invalid
        else
            if Str_orEmpty(b.subtitle_language) <> "" then out.effective_subtitle_language = b.subtitle_language
            out.effective_subtitle_mode = b.subtitle_mode
            out.effective_subtitle_track_signature = b.track_signature
        end if
    end if
    if ap <> invalid then
        versions = []
        for each v in Arr_or(d.versions)
            if v <> invalid and Type(v) = "roAssociativeArray" then
                nv = AA_copy(v)
                o = -1
                if ap.body <> invalid then o = SeriesChoice_resolveAudio(ap.body, Arr_or(v.audio_tracks))
                if o >= 0 then nv.effective_audio_track_index = o else nv.Delete("effective_audio_track_index")
                versions.Push(nv)
            end if
        end for
        out.versions = versions
    end if
    return out
end function

' SeriesAudioChoice.resolveOn, simplified: the track the signature describes, else the remembered
' position while it still holds the language, else the first track in that language; -1 for none.
function SeriesChoice_resolveAudio(body as object, tracks as object) as integer
    sig = body.track_signature
    if sig <> invalid and Type(sig) = "roAssociativeArray" then
        for i = 0 to tracks.Count() - 1
            if SeriesChoice_audioMatches(tracks[i], sig) then return i
        end for
    end if
    lang = SeriesChoice_langKey(body.audio_language)
    if lang = "" then return -1
    idx = Int(Num_or(body.audio_track_index, -1))
    if idx >= 0 and idx < tracks.Count() then
        if SeriesChoice_langKey(tracks[idx].language) = lang then return idx
    end if
    for i = 0 to tracks.Count() - 1
        if SeriesChoice_langKey(tracks[i].language) = lang then return i
    end for
    return -1
end function

function SeriesChoice_audioMatches(t as object, sig as object) as boolean
    if t = invalid or Type(t) <> "roAssociativeArray" then return false
    if SeriesChoice_langKey(t.language) <> SeriesChoice_langKey(sig.language) then return false
    if not SeriesChoice_sameText(t.title, sig.title) then return false
    if not SeriesChoice_sameText(t.embedded_title, sig.embedded_title) then return false
    if not SeriesChoice_sameText(t.codec, sig.codec) then return false
    if not SeriesChoice_sameText(t.layout, sig.layout) then return false
    return Int(Num_or(t.channels, 0)) = Int(Num_or(sig.channels, 0))
end function

function SeriesChoice_sameText(a as dynamic, b as dynamic) as boolean
    return LCase(Str_orEmpty(a).Trim()) = LCase(Str_orEmpty(b).Trim())
end function

' ISO 639 folding for comparing languages ("eng" = "en"); "" for none or "und".
function SeriesChoice_langKey(code as dynamic) as string
    c = LCase(Str_orEmpty(code).Trim()).Replace("_", "-")
    dash = Instr(1, c, "-")
    if dash > 0 then c = Left(c, dash - 1)
    if c = "" or c = "und" then return ""
    folds = { eng: "en", spa: "es", fre: "fr", fra: "fr", ger: "de", deu: "de", dut: "nl", nld: "nl", jpn: "ja", dan: "da", ita: "it", por: "pt", rus: "ru", chi: "zh", zho: "zh", kor: "ko", swe: "sv", nor: "no", fin: "fi", pol: "pl", ara: "ar", hin: "hi", tur: "tr", cze: "cs", ces: "cs", gre: "el", ell: "el", heb: "he", hun: "hu", tha: "th", vie: "vi", ukr: "uk", rum: "ro", ron: "ro", ind: "id" }
    if folds.DoesExist(c) then return folds[c]
    return c
end function
