' SPDX-License-Identifier: AGPL-3.0-or-later
' How the player makes Roku draw the sidecar subtitle it chose, and waits for a slow one.
'
' Included by PlayerScreen.xml (m is the screen). Device facts, from Silo's own Roku app
' (Adapted from Silo-Server/silo-roku, AGPL-3.0 (source/playback/sidecars.bs listedName / isTrack /
' drawn, components/player/Player.bs confirmSubtitle / checkSubtitle / drawCaptions), and its
' hardware evidence log):
' - Roku lists a sidecar in Video.availableSubtitleTracks under a TrackName of its own that
'   contains the URL the content gave ("Roku mangles the name a bit"); writing the bare URL to
'   subtitleTrack on playing content left the previous language on screen. So a sidecar is
'   selected by the name Roku lists for it (Subs_listedName), the URL only until it lists one.
' - On MKV originals Roku can play the file's own text track (mkv/3) while the sidecar is selected;
'   one corrective write about 3.5 s after the first frame fixed it, while writing again in the
'   first second stopped the content. So the player checks once after the content settles.
' - Roku draws captions above the UI at a place of its own: a two-line cue covered the scrubber
'   and the time row. Video.suppressCaptions hides them while the controls or the panel show.
' - The server's first extraction of an embedded text track can take 65-279 s; Roku's own fetch of
'   the sidecar gives up long before that, so nothing ever showed. The player asks for the
'   sidecar itself (a long-timeout GET), shows "Loading subtitles..." while it waits, and remounts
'   the plan at the position once the server has it (Subs_probe*).

' ---------- Pure helpers (tests/test_subtitle_select.py) ----------

' Whether NAME (a listed TrackName, subtitleTrack or currentSubtitleTrack) is the sidecar given at
' URL: the URL itself or a name that contains it.
function Subs_isTrack(name as dynamic, url as dynamic) as boolean
    n = Str_orEmpty(name)
    u = Str_orEmpty(url)
    if u = "" or n = "" then return false
    ' A track of the stream (an MKV's mkv/3, an HLS rendition's webvtt/1) is that name alone:
    ' mkv/3 is not mkv/30.
    if not Subs_isFile(u) then return n = u
    return Instr(1, n, u) > 0
end function

' Whether a track name is a sidecar the player gave Roku (a URL, or Roku's path holding one), not a
' track Roku found in the stream.
function Subs_isFile(name as dynamic) as boolean
    return Instr(1, Str_orEmpty(name), ":/") > 0
end function

' The TrackName Roku lists (Video.availableSubtitleTracks) for the sidecar at URL: the exact name,
' else the first that contains it; "" when Roku lists none.
function Subs_listedName(listed as dynamic, url as dynamic) as string
    u = Str_orEmpty(url)
    if u = "" then return ""
    found = ""
    for each a in Arr_or(listed)
        if a <> invalid and Type(a) = "roAssociativeArray" then
            tn = Str_orEmpty(a.TrackName)
            if tn = u then return tn
            if found = "" and Subs_isTrack(tn, u) then found = tn
        end if
    end for
    return found
end function

' Whether Roku draws the sidecar at URL: it reports it selected and plays it, or names nothing as
' playing. Anything else (another sidecar, a track of the file's own) means it does not.
function Subs_drawn(url as dynamic, selected as dynamic, playing as dynamic) as boolean
    p = Str_orEmpty(playing)
    return Subs_isTrack(selected, url) and (p = "" or Subs_isTrack(p, url))
end function

' The index in TRACKS (the player's subtitle tracks) of the sidecar NAME is, or -1: a track Roku
' found in the stream (mkv/3), a rendition, or nothing.
function Subs_trackIndexOf(tracks as dynamic, name as dynamic) as integer
    n = Str_orEmpty(name)
    if n = "" then return -1
    list = Arr_or(tracks)
    for i = 0 to list.Count() - 1
        t = list[i]
        if t <> invalid and (Subs_isTrack(n, t.url) or Subs_isTrack(n, t.streamName)) then return i
    end for
    return -1
end function

' A track name as it may be printed: our sidecar by its track id, "none", a URL masked (it carries
' the token), else Roku's own name (mkv/3, eia608/1, ...).
function Subs_nameForLog(tracks as dynamic, name as dynamic) as string
    n = Str_orEmpty(name)
    if n = "" then return "none"
    idx = Subs_trackIndexOf(tracks, n)
    if idx >= 0 then
        list = Arr_or(tracks)
        if Str_isEmpty(list[idx].url) then return n + "(" + Str_orEmpty(list[idx].trackId) + ")"
        return "sidecar:" + Str_orEmpty(list[idx].trackId)
    end if
    if Instr(1, n, "://") > 0 or Instr(1, LCase(n), "token") > 0 then return "url"
    return n
end function

' Video.suppressCaptions: captions hidden while the controls or the panel show, but only once the
' content has settled (no writes while Roku opens it).
' HOLD: the content draws nothing at all until its first selection is checked (Subs_holdsUntilChecked).
function Subs_captionsSuppressed(controlsShown as boolean, hudShown as boolean, settled as boolean, hold = false as boolean) as boolean
    if hold and not settled then return true
    return settled and (controlsShown or hudShown)
end function

' ---------- Tracks of the stream (pure; tests/test_subtitle_stream.py) ----------
' Adapted from Silo-Server/silo-roku, AGPL-3.0 (source/playback/sidecars.bs rokuPlace /
' renditionName / preselectName / holdsUntilChecked, and its hardware evidence of 2026-10-29 to
' 2026-11-01):
' - An MKV original's own text tracks are listed as "mkv/<Matroska TrackNumber>" (the server's
'   container_track_id) 35-90 ms after buffering starts, before the first frame. Content
'   SubtitleConfig { TrackName: "mkv/N" } selects one before play; writing subtitleTrack switches
'   mid-play with a 150-250 ms rebuffer and no reload.
' - Roku names an HLS stream's WebVTT renditions "webvtt/<n>", the playlist's DEFAULT first and
'   the others after it in playlist order, each with Description = its NAME (TCL, OS 15.3.4).
' - Left alone, Roku opened such a stream on a rendition of its own (English, by the caption
'   language), even beside a DEFAULT for another track or a selected sidecar, until the check
'   3 s after the first frame; naming the plan's rendition by Roku's number in SubtitleConfig
'   opened on it.

' Roku's number for the INDEX-th rendition (1-based, playlist order) of a stream whose DEFAULT is
' the DEFAULTINDEX-th (0 for none): the DEFAULT is 1, the ones before it move up by one.
function Subs_rokuPlace(index as integer, defaultIndex as integer) as integer
    if defaultIndex < 1 or index > defaultIndex then return index
    if index = defaultIndex then return 1
    return index + 1
end function

' The TrackName Roku lists a rendition under, as { name, by }: the one listed track whose
' Description is the rendition's NAME (by "name"); else "webvtt/<place>" (Roku's number) when Roku
' lists it in the row's LANGUAGE and not with a Description naming another of the stream's
' renditions (NAMES, every rendition's NAME as keys) (by "index", or "ambiguous" when another
' rendition shares the row's language: SHARED); else "" (by "unlisted"). A sidecar's name (a
' URL) and closed captions never match.
function Subs_renditionName(listed as dynamic, renditionName as dynamic, place as integer, language as dynamic, names as dynamic, shared as boolean) as object
    unlisted = { name: "", by: "unlisted" }
    if Type(listed) <> "roArray" or place < 1 then return unlisted
    want = Str_orEmpty(renditionName).Trim()
    fallback = "webvtt/" + place.ToStr()
    rowKey = Subs_autoLangKey(language)
    known = {}
    if names <> invalid and Type(names) = "roAssociativeArray" then known = names
    found = ""
    matches = 0
    indexed = false
    for each a in listed
        if a <> invalid and Type(a) = "roAssociativeArray" then
            tn = Str_orEmpty(a.TrackName)
            lt = LCase(tn)
            if tn <> "" and not Subs_isFile(tn) and Left(lt, 6) <> "eia608" and Left(lt, 6) <> "eia708" then
                desc = Str_orEmpty(a.Description).Trim()
                if want <> "" and desc = want then
                    matches = matches + 1
                    found = tn
                end if
                another = desc <> "" and desc <> want and known.DoesExist(desc)
                if tn = fallback and rowKey <> "" and Subs_autoLangKey(a.Language) = rowKey and not another then indexed = true
            end if
        end if
    end for
    if matches = 1 then return { name: found, by: "name" }
    if indexed and shared then return { name: fallback, by: "ambiguous" }
    if indexed then return { name: fallback, by: "index" }
    return unlisted
end function

' Whether Roku lists the track NAME (an MKV's mkv/N) in LISTED.
function Subs_listsName(listed as dynamic, name as dynamic) as boolean
    n = Str_orEmpty(name)
    if n = "" then return false
    for each a in Arr_or(listed)
        if a <> invalid and Type(a) = "roAssociativeArray" and Str_orEmpty(a.TrackName) = n then return true
    end for
    return false
end function

' The TrackName new content names in its SubtitleConfig so Roku opens it on TRACK (the player's
' pick for the mount), or "": an MKV's own track by its fixed name, and an every-track rendition
' by Roku's number for it from the stream's DEFAULT (DEFAULTINDEX). A sidecar or a single plan
' rendition gets none (a sidecar's path did not keep Roku off a rendition of its own).
function Subs_preselectName(track as dynamic, defaultIndex as integer) as string
    if track = invalid or Type(track) <> "roAssociativeArray" then return ""
    if not Str_isEmpty(track.native) then return track.native
    if PlaybackCaps_truthy(track.allRend) then
        idx = Int(Num_or(track.renditionIndex, 0))
        if idx >= 1 then return "webvtt/" + Subs_rokuPlace(idx, defaultIndex).ToStr()
    end if
    return ""
end function

' Whether new content draws nothing until its first selection is checked: a sidecar pick on a
' stream that carries subtitle renditions (STREAMRENDITIONS), which Roku showed by the caption
' language until the check, or a stream track it cannot open on by name (no PRESELECT).
function Subs_holdsUntilChecked(track as dynamic, preselect as string, streamRenditions as boolean) as boolean
    if track = invalid or Type(track) <> "roAssociativeArray" or preselect <> "" then return false
    if not Str_isEmpty(track.url) then return streamRenditions
    return PlaybackCaps_truthy(track.allRend)
end function

' Whether the selected sidecar must be fetched first to know it is ready: an embedded text track
' (the server extracts it from the file on first use), not a rendition, on the server's own origin.
function Subs_needsReadyCheck(track as dynamic, origin as dynamic) as boolean
    if track = invalid or Type(track) <> "roAssociativeArray" then return false
    if not Str_isEmpty(track.rendition) then return false
    if LCase(Str_orEmpty(track.source)) <> "embedded" then return false
    u = Str_orEmpty(track.url)
    o = Str_orEmpty(origin)
    if u = "" or o = "" then return false
    return LCase(Left(u, Len(o) + 1)) = LCase(o + "/")
end function

' What to do once the readiness GET answers after ELAPSEDMS: "reload" (the server took long enough
' that Roku's own fetch has given up), "ready" (Roku's fetch got it too), or "failed".
function Subs_readyAction(ok as boolean, elapsedMs as integer) as string
    if not ok then return "failed"
    if elapsedMs >= Subs_reloadAfterMs() then return "reload"
    return "ready"
end function

function Subs_reloadAfterMs() as integer
    return 8000
end function

' ---------- Selection on the Video node ----------

' Writes Video.subtitleTrack for sidecar IDX by the name Roku lists for it (else its URL), and
' arms one check that Roku follows it (kind "switch"; the first selection of a mount is turned into
' "settle" by onVideoState).
sub Subs_selectSidecar(idx as integer)
    t = m.subtitleTracks[idx]
    name = Subs_listedName(m.video.availableSubtitleTracks, t.url)
    if name = "" then name = t.url
    m.video.subtitleTrack = name
    Subs_armCheck(idx, "switch")
    Subs_probeIfNeeded(t)
end sub

' An MKV original's own track (native embedded): Roku lists it as mkv/<container_track_id> and
' switches to it on the playing content when subtitleTrack names it, with no reload.
sub Subs_selectNative(idx as integer)
    t = m.subtitleTracks[idx]
    t.streamName = t.native
    m.video.subtitleTrack = t.native
    Diag_log("[siku-playback] subtitle native " + t.native + " selected (track=" + t.trackId + ")")
    Subs_armCheck(idx, "switch")
end sub

sub Subs_armCheck(idx as integer, kind as string)
    m.subsCheck = { idx: idx, kind: kind, trackId: m.subtitleTracks[idx].trackId }
    m.subsCheckTimer.control = "stop"
    m.subsCheckTimer.control = "start"
end sub

' One look at what Roku draws, SUBS_CHECK after the selection: confirmed, written once more (the
' content's first selection, or Roku playing a track of the file's own), or the plan remounted at
' the position (an in-place switch Roku did not follow: it still plays another sidecar).
sub Subs_onCheck()
    ' Before the content's first frame nothing is checked or written (Roku stopped content it was
    ' opening when the player selected again): Subs_onFirstPlaying re-arms the check.
    if not m.subsSettleArmed then return
    c = m.subsCheck
    m.subsCheck = invalid
    if not m.subsSettled then
        ' Captions held for this check (Subs_holdsUntilChecked) show from now on, with the writes below.
        m.subsSettled = true
        m.subsHold = false
        Subs_updateCaptions()
    end if
    if c = invalid or m.closing then return
    if c.idx <> m.subtitleIndex or c.idx < 0 or c.idx >= m.subtitleTracks.Count() then return
    t = m.subtitleTracks[c.idx]
    if t.trackId <> c.trackId then return
    ' A sidecar is known by its URL, a track of the stream by the name Roku lists it under.
    want = Str_orEmpty(t.url)
    if want = "" then want = Str_orEmpty(t.streamName)
    if want = "" then return
    if not Str_isEmpty(t.native) and not Subs_listsName(m.video.availableSubtitleTracks, t.native) then
        Subs_nativeUnlisted(t)
        return
    end if
    selected = Str_orEmpty(m.video.subtitleTrack)
    playing = Str_orEmpty(m.video.currentSubtitleTrack)
    playingLabel = Subs_nameForLog(m.subtitleTracks, playing)
    if Subs_drawn(want, selected, playing) then
        Diag_log("[siku-playback] subtitle check " + c.kind + ": roku plays " + playingLabel + " (ok)")
        return
    end if
    other = Subs_trackIndexOf(m.subtitleTracks, playing)
    ' One reload per switch: the remount's own selection is checked as "settle", which never reloads.
    if c.kind = "switch" and other >= 0 and other <> c.idx then
        Diag_log("[siku-playback] subtitle check switch: roku still plays " + playingLabel + "; reloading at the position")
        remountSubtitles()
        return
    end if
    if m.subsReselected then
        Diag_log("[siku-playback] subtitle check " + c.kind + ": roku plays " + playingLabel + " after a second selection; left as it is")
        return
    end if
    m.subsReselected = true
    name = want
    if not Str_isEmpty(t.url) then name = Subs_listedName(m.video.availableSubtitleTracks, t.url)
    if name = "" then name = want
    listed = (name <> t.url)
    if Str_isEmpty(t.url) then listed = Subs_listsName(m.video.availableSubtitleTracks, name)
    Diag_log("[siku-playback] subtitle check " + c.kind + ": roku plays " + playingLabel + "; selected again (listed=" + Str_orEmpty(listed) + ")")
    m.video.subtitleTrack = name
end sub

' Roku does not list the MKV's own track the plan names (mkv/<id>): the native tracks are given up
' for this playback and the plan is remounted with the server's sidecars instead, once.
sub Subs_nativeUnlisted(t as object)
    if PlaybackCaps_truthy(m.nativeSubsOff) then return
    m.nativeSubsOff = true
    Diag_log("[siku-playback] subtitle native " + t.native + " not listed by roku; using the server's sidecar at the position")
    remountSubtitles()
end sub

' ---------- Captions under the controls ----------

sub Subs_updateCaptions()
    want = Subs_captionsSuppressed(m.controls.visible, m.hud.visible, m.subsSettled = true, PlaybackCaps_truthy(m.subsHold))
    if m.video.suppressCaptions = want then return
    m.video.suppressCaptions = want
end sub

' ---------- A slow first extraction ----------

' Fetches the selected embedded sidecar once (long timeout) to learn when the server has it.
sub Subs_probeIfNeeded(t as object)
    if t = invalid or m.closing then return
    if m.subsReadyIds = invalid then m.subsReadyIds = {}
    if m.subsReadyIds.DoesExist(t.trackId) then return
    if m.subsProbe <> invalid and m.subsProbe.trackId = t.trackId then return
    if not Subs_needsReadyCheck(t, m.global.session.serverOrigin) then return
    if m.subsProbeSeq = invalid then m.subsProbeSeq = 0
    m.subsProbeSeq = m.subsProbeSeq + 1
    clock = CreateObject("roTimespan")
    m.subsProbe = { trackId: t.trackId, seq: m.subsProbeSeq, clock: clock, shown: false }
    ' Range keeps the answer small where the server honours it; the whole file is fine otherwise.
    Api_call({ method: "GET", url: t.url, timeout: 300, noRefresh: true, headers: { "Accept": "text/vtt, application/x-subrip, */*", "Range": "bytes=0-4095" }, context: { seq: m.subsProbeSeq, trackId: t.trackId } }, "Subs_onProbe")
    m.subsLoadTimer.control = "stop"
    m.subsLoadTimer.control = "start"
end sub

' Still waiting after subsLoadTimer: "Loading subtitles..." until the answer.
sub Subs_onLoadTimer()
    p = m.subsProbe
    if p = invalid or m.closing then return
    if Subs_selectedTrackId() <> p.trackId then return
    p.shown = true
    m.subsLoading.visible = true
    Diag_log("[siku-playback] subtitle loading track=" + p.trackId + " (the server is still preparing it)")
end sub

sub Subs_onProbe(event as object)
    resp = Api_result(event)
    p = m.subsProbe
    if p = invalid or resp.context = invalid or resp.context.seq <> p.seq then return
    m.subsProbe = invalid
    m.subsLoadTimer.control = "stop"
    m.subsLoading.visible = false
    if m.closing then return
    elapsed = p.clock.TotalMilliseconds()
    ' An answer too large to keep (a server that ignores Range) still arrived: the sidecar is ready.
    arrived = PlaybackCaps_truthy(resp.ok)
    if resp.error <> invalid and Type(resp.error) = "roAssociativeArray" and Str_orEmpty(resp.error.code) = "too_large" then arrived = true
    action = Subs_readyAction(arrived, elapsed)
    secs = Int(elapsed / 1000).ToStr()
    stillSelected = Subs_selectedTrackId() = p.trackId
    if action = "failed" then
        Diag_log("[siku-playback] subtitle load failed track=" + p.trackId + " status=" + Str_orEmpty(resp.status) + " after " + secs + "s")
        if stillSelected and p.shown then m.global.toast = "Couldn't load these subtitles."
        return
    end if
    m.subsReadyIds[p.trackId] = true
    sel = Subs_selectedTrack()
    if action = "reload" and stillSelected and m.plan <> invalid and sel <> invalid and not Str_isEmpty(sel.url) then
        Diag_log("[siku-playback] subtitle ready track=" + p.trackId + " after " + secs + "s; reloading at the position")
        remountSubtitles()
    else
        Diag_log("[siku-playback] subtitle ready track=" + p.trackId + " after " + secs + "s")
    end if
end sub

' The content's first frame (onVideoState "playing", once per mount): the selection made with it is
' checked once the content settles, and captions may be suppressed from then on.
sub Subs_onFirstPlaying()
    if m.subsSettleArmed then return
    m.subsSettleArmed = true
    if m.subsCheck <> invalid then m.subsCheck.kind = "settle"
    m.subsCheckTimer.control = "stop"
    m.subsCheckTimer.control = "start"
end sub

' A new mount (applyPlan): the content's first selection settles again.
sub Subs_onMount()
    m.subsCheck = invalid
    m.subsCheckTimer.control = "stop"
    m.subsSettled = false
    m.subsSettleArmed = false
    m.subsReselected = false
    Subs_updateCaptions()
end sub
