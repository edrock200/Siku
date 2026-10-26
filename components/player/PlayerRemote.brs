' The player's side of remote control from Silo's phone app (SiloCast; components/remote/).
' PlayerScreen registers itself as the remote's player (m.global.castPlayer), publishes its
' SiloCastPlaybackState every second and on every change, and runs the commands RemoteControl
' forwards through the remoteCommand field. Track ids in the state: the audio ordinal (the
' server's list when the stream carries one track, else the Video node's), and the subtitle's
' index in the player's own list; the phone sends them back unchanged.
' What a Roku cannot do is declared in the hello (volume_mute_only, no_playback_speed): mute is
' the Video node's `mute` field, the level stays the TV's.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub Remote_init()
    m.remoteMeta = invalid
    m.remoteLastJson = ""
    if not m.global.hasField("castPlayer") or not m.global.hasField("lanTask") then return
    m.global.castPlayer = m.top
    m.remoteTimer = CreateObject("roSGNode", "Timer")
    m.remoteTimer.duration = 1
    m.remoteTimer.repeat = true
    m.remoteTimer.observeField("fire", "Remote_publish")
    m.top.appendChild(m.remoteTimer)
    m.remoteTimer.control = "start"
    m.top.observeField("remoteCommand", "Remote_onCommand")
end sub

' The player is closing: nothing is registered any more (RemoteControl then publishes "Ready").
sub Remote_release()
    if m.remoteTimer <> invalid then m.remoteTimer.control = "stop"
    if not m.global.hasField("castPlayer") then return
    cur = m.global.castPlayer
    if cur <> invalid and cur.isSameNode(m.top) then m.global.castPlayer = invalid
end sub

' Poster and synopsis for the state (SiloCastNowPlayingMetadata): an episode sends its series'
' 2:3 poster, never its own still (spoiler protection may hide it).
sub Remote_loadMetadata()
    if m.remoteTimer = invalid or m.itemId = "" then return
    m.remoteMeta = { forItem: m.itemId, posterUrl: "", overview: "" }
    Api_get("/api/v2/catalog/items/" + Str_urlEncode(m.itemId), { image_size: "medium" }, "Remote_onItem", { itemId: m.itemId })
end sub

sub Remote_onItem(event as object)
    resp = Api_result(event)
    if m.remoteMeta = invalid or resp.context = invalid or resp.context.itemId <> m.remoteMeta.forItem then return
    if not resp.ok or Type(resp.data) <> "roAssociativeArray" then return
    d = resp.data
    m.remoteMeta.overview = Str_orEmpty(d.overview).Trim()
    if LCase(Str_orEmpty(d["type"])) = "episode" and not Str_isEmpty(d.series_id) then
        Api_get("/api/v2/catalog/items/" + Str_urlEncode(Str_orEmpty(d.series_id)), { image_size: "medium" }, "Remote_onSeries", { itemId: m.remoteMeta.forItem })
    else
        m.remoteMeta.posterUrl = Url_resolve(d.poster_url)
    end if
end sub

sub Remote_onSeries(event as object)
    resp = Api_result(event)
    if m.remoteMeta = invalid or resp.context = invalid or resp.context.itemId <> m.remoteMeta.forItem then return
    if not resp.ok or Type(resp.data) <> "roAssociativeArray" then return
    m.remoteMeta.posterUrl = Url_resolve(resp.data.poster_url)
    if m.remoteMeta.overview = "" then m.remoteMeta.overview = Str_orEmpty(resp.data.overview).Trim()
end sub

' ---------- State ----------

function Remote_state() as object
    st = Str_orEmpty(m.video.state)
    title = Str_orEmpty(m.titleLabel.text)
    if title = "" and m.watch <> invalid then title = Str_orEmpty(m.watch.title)
    s = {
        "contentId": m.itemId
        "title": title
        "isPlaying": st = "playing"
        "isLoading": m.plan = invalid and not m.errorGroup.visible
        "isBuffering": st = "buffering"
        "currentTime": m.position
        "duration": m.duration
        "audioTracks": []
        "subtitleTracks": []
        "qualityOptions": []
        "activeQualityId": "auto"
        "isQualitySwitching": m.replanKind = "quality"
        "playbackSpeed": 1.0
        "videoGravity": "fit"
        "hdrEnabled": false
        "supportsVideoGravity": false
        "supportsHDRToggle": false
        "volume": 1.0
        "isMuted": Remote_isMuted()
        "hasNextEpisode": m.nextEpisode <> invalid
    }
    if m.sessionId <> "" then s["sessionId"] = m.sessionId
    if m.epTag.visible and m.epTag.text <> "" then s["subtitle"] = m.epTag.text
    if m.nextEpisode <> invalid and not Str_isEmpty(m.nextEpisode.title) then s["nextEpisodeTitle"] = Str_orEmpty(m.nextEpisode.title)
    if m.errorGroup.visible then s["error"] = Str_orEmpty(m.errorLabel.text)
    ' Audio: the server's list when the stream carries one track, else the Video node's.
    if useServerAudioList() then
        tracks = serverAudioTracks()
        for i = 0 to tracks.Count() - 1
            s.audioTracks.Push({ "kind": "audio", "trackId": i, "title": Tracks_audioTitle(tracks[i], i), "detail": Tracks_audioDetail(tracks[i]) })
        end for
        cur = currentServerAudioIndex()
        if cur >= 0 then s["selectedAudioTrackId"] = cur
    else
        tracks = Arr_or(m.video.availableAudioTracks)
        cur = Str_orEmpty(m.video.audioTrack)
        for i = 0 to tracks.Count() - 1
            s.audioTracks.Push({ "kind": "audio", "trackId": i, "title": audioTrackLabel(tracks[i]) })
            if Str_orEmpty(tracks[i].Track) = cur or (cur = "" and i = 0) then s["selectedAudioTrackId"] = i
        end for
    end if
    for i = 0 to m.subtitleTracks.Count() - 1
        s.subtitleTracks.Push({ "kind": "subtitle", "trackId": i, "title": Str_orEmpty(m.subtitleTracks[i].label), "detail": Subs_sourceLabel(m.subtitleTracks[i]) })
    end for
    if m.subtitleIndex >= 0 then s["selectedSubtitleTrackId"] = m.subtitleIndex
    menu = qualityMenu()
    for each o in menu
        q = { "id": o.id, "label": o.name }
        if o.bitrate <> "" then q["detail"] = o.bitrate
        s.qualityOptions.Push(q)
    end for
    active = activeQualityId(menu, m.qualityPref)
    if active <> "" then s["activeQualityId"] = active
    if m.remoteMeta <> invalid and m.remoteMeta.forItem = m.itemId then
        if m.remoteMeta.posterUrl <> "" then s["posterUrl"] = m.remoteMeta.posterUrl
        if m.remoteMeta.overview <> "" then s["overview"] = m.remoteMeta.overview
    end if
    return s
end function

sub Remote_publish()
    if m.remoteTimer = invalid or m.closing then return
    if m.remoteMeta = invalid or m.remoteMeta.forItem <> m.itemId then Remote_loadMetadata()
    RemoteState_publish(Remote_state())
end sub

function Remote_isMuted() as boolean
    if not m.video.hasField("mute") then return false
    return PlaybackCaps_truthy(m.video.mute)
end function

' ---------- Commands ----------

sub Remote_onCommand()
    c = m.top.remoteCommand
    if c = invalid or m.closing then return
    name = Str_orEmpty(c.name)
    print "[siku-cast] command " + name
    st = Str_orEmpty(m.video.state)
    if name = "stop" then
        exitPlayer()
        return
    else if name = "play" then
        if st = "paused" then m.video.control = "resume"
    else if name = "pause" then
        if st = "playing" or st = "buffering" then m.video.control = "pause"
    else if name = "play_pause" then
        togglePlay()
    else if name = "seek" then
        if m.plan <> invalid and c.seconds <> invalid then seekToSource(Num_or(c.seconds, m.position))
    else if name = "select_audio_track" then
        Remote_selectAudio(Int(Num_or(c.trackId, -1)))
    else if name = "select_subtitle_track" then
        ' A null trackId turns subtitles off.
        idx = -1
        if c.trackId <> invalid then idx = Int(Num_or(c.trackId, -1))
        setSubtitle(idx)
    else if name = "set_muted" then
        Remote_setMuted(PlaybackCaps_truthy(c.enabled))
    else if name = "set_volume" then
        ' A Roku has no level a channel can set: 0 mutes, anything else unmutes.
        Remote_setMuted(Num_or(c.volume, 1) <= 0)
    else if name = "set_quality" then
        q = Str_orEmpty(c.value)
        if q <> "" and q <> PlaybackCaps_videoQuality(m.qualityPref) then requestQualityChange(q)
    else if name = "play_next" then
        if m.nextEpisode <> invalid then playNext()
    end if
    Remote_publish()
end sub

sub Remote_selectAudio(idx as integer)
    if idx < 0 then return
    if useServerAudioList() then
        requestAudioTrackChange(idx)
    else
        tracks = Arr_or(m.video.availableAudioTracks)
        if idx < tracks.Count() then m.video.audioTrack = tracks[idx].Track
    end if
end sub

sub Remote_setMuted(muted as boolean)
    if not m.video.hasField("mute") then return
    m.video.mute = muted
end sub
