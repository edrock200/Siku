' Theme music on detail pages: a port of Android's ThemeMusicCoordinator / ThemeMusicPlayer
' (silo-android #678) for one page's own Audio node.
'
' Nothing plays unless the profile's `ui.theme_music_enabled` setting is on (settings revision 11,
' default off) and GET /api/v2/catalog/themes/capabilities says `state: available` and
' `allowed != false` (cached on m.global.themeCaps for 60 s per server+profile, as upstream). The
' page plays the first theme of the item detail's `themes` set through a short-lived grant,
' POST /api/v2/catalog/items/{owner_id}/themes/{theme_id}/playback with the formats the Roku Audio
' node decodes, so the server converts anything else to AAC in MP4. The grant URL is a credential:
' it is never printed. `ui.theme_music_loop` repeats an original in place (Audio.loop); a
' converted stream cannot seek back, so it is replayed with a fresh grant. A failed start is
' retried once.
' The theme stops when the page is covered or closed (a player opening covers it, so it never
' plays under video) and starts over when the page is shown again.
' Roku differences: the Audio node has no volume control, so there is no fade and the theme plays
' at the TV's volume (upstream plays at 35 % with a 300 ms fade); and Roku has no API to ask whether
' another app is playing audio (inside Siku, music and audiobooks play on full screens of their own).
'
' The page calls ThemeMusic_init(audioNode) once, ThemeMusic_show(item) when its detail loads or
' it is shown again, and ThemeMusic_stop() when it is hidden or starts playback.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub ThemeMusic_init(audio as object)
    m.themeAudio = audio
    m.themeSel = invalid       ' { ownerId, themeId } the page wants
    m.themeGen = 0             ' bumped by every stop; stale answers are dropped
    m.themeRetry = 0
    m.themeConverted = false
    m.themePlaying = false
    audio.observeField("state", "ThemeMusic_onState")
end sub

function ThemeMusic_enabled() as boolean
    return Settings_themeMusicEnabled()
end function

' The theme the item's detail names: { ownerId, themeId } or invalid.
function ThemeMusic_selection(item as dynamic) as dynamic
    if item = invalid or Type(item) <> "roAssociativeArray" then return invalid
    t = item.themes
    if t = invalid or Type(t) <> "roAssociativeArray" then return invalid
    owner = Str_orEmpty(t.owner_id)
    items = Arr_or(t.items)
    if owner = "" or items.Count() = 0 or Type(items[0]) <> "roAssociativeArray" then return invalid
    tid = Str_orEmpty(items[0].id)
    if tid = "" then return invalid
    return { ownerId: owner, themeId: tid }
end function

sub ThemeMusic_show(item as dynamic)
    if m.themeAudio = invalid then return
    sel = ThemeMusic_selection(item)
    if sel = invalid or not ThemeMusic_enabled() then
        ThemeMusic_stop()
        return
    end if
    if m.themePlaying and m.themeSel <> invalid and m.themeSel.ownerId = sel.ownerId and m.themeSel.themeId = sel.themeId then return
    ThemeMusic_stop()
    m.themeSel = sel
    m.themeRetry = 0
    caps = ThemeMusic_cachedCaps()
    if caps = invalid then
        Api_get("/api/v2/catalog/themes/capabilities", invalid, "ThemeMusic_onCaps", { gen: m.themeGen, key: ThemeMusic_capsKey() })
    else if caps.available = true then
        ThemeMusic_requestGrant()
    else
        print "[siku-theme] server reports theme music unavailable"
    end if
end sub

sub ThemeMusic_stop()
    m.themeGen = m.themeGen + 1
    m.themeSel = invalid
    m.themePlaying = false
    if m.themeAudio <> invalid then
        st = LCase(Str_orEmpty(m.themeAudio.state))
        if st <> "" and st <> "none" and st <> "stopped" then m.themeAudio.control = "stop"
    end if
end sub

function ThemeMusic_capsKey() as string
    s = m.global.session
    return Str_orEmpty(s.serverId) + "|" + Str_orEmpty(s.profileId)
end function

function ThemeMusic_cachedCaps() as dynamic
    if not m.global.hasField("themeCaps") then return invalid
    c = m.global.themeCaps
    if c = invalid or Type(c) <> "roAssociativeArray" or c.key <> ThemeMusic_capsKey() then return invalid
    if Time_nowSeconds() - Int(Num_or(c.fetchedAt, 0)) >= 60 then return invalid
    return c
end function

sub ThemeMusic_onCaps(event as object)
    resp = Api_result(event)
    ctx = resp.context
    if not resp.ok or Type(resp.data) <> "roAssociativeArray" then
        ' A failed read is not an answer (upstream keeps asking); stay silent for this page.
        print "[siku-theme] capability read failed status=" + Str_orEmpty(resp.status)
        return
    end if
    d = resp.data
    available = LCase(Str_orEmpty(d.state)) = "available" and d.allowed <> false
    key = ""
    if ctx <> invalid then key = Str_orEmpty(ctx.key)
    entry = { key: key, available: available, fetchedAt: Time_nowSeconds() }
    if m.global.hasField("themeCaps") then m.global.themeCaps = entry else m.global.addFields({ themeCaps: entry })
    print "[siku-theme] capability state=" + Str_orEmpty(d.state) + " allowed=" + Str_orEmpty(d.allowed) + " transcode=" + Str_orEmpty(d.transcode)
    if ctx = invalid or ctx.gen <> m.themeGen or m.themeSel = invalid then return
    if available then ThemeMusic_requestGrant()
end sub

' Container/codec pairs the Roku Audio node plays (docs/catalog-api.md "Local theme songs"). Raw
' ADTS AAC, Ogg and Opus are left out, so the server converts those to AAC in MP4.
function ThemeMusic_acceptedFormats() as object
    out = [
        { container: "mp3", audio_codec: "mp3" }
        { container: "mp4", audio_codec: "aac" }
        { container: "m4a", audio_codec: "aac" }
    ]
    di = CreateObject("roDeviceInfo")
    for each pair in [["flac", "flac"], ["wav", "pcm"]]
        ok = false
        try
            r = di.CanDecodeAudio({ "codec": pair[1] })
            ok = r <> invalid and r.result = true
        catch err
            print "[siku-theme] CanDecodeAudio failed: "; err.message
        end try
        if ok then out.Push({ container: pair[0], audio_codec: pair[1] })
    end for
    return out
end function

sub ThemeMusic_requestGrant()
    sel = m.themeSel
    if sel = invalid then return
    path = "/api/v2/catalog/items/" + Str_urlEncode(sel.ownerId) + "/themes/" + Str_urlEncode(sel.themeId) + "/playback"
    Api_send("POST", path, { accepted_formats: ThemeMusic_acceptedFormats() }, "ThemeMusic_onGrant", { gen: m.themeGen })
end sub

sub ThemeMusic_onGrant(event as object)
    resp = Api_result(event)
    ctx = resp.context
    if ctx = invalid or ctx.gen <> m.themeGen or m.themeSel = invalid then return
    if not resp.ok or Type(resp.data) <> "roAssociativeArray" or Str_isEmpty(resp.data.url) then
        ' 406: nothing this Roku decodes; 503: no route. Themes are optional, so stay silent.
        print "[siku-theme] grant refused status=" + Str_orEmpty(resp.status)
        return
    end if
    g = resp.data
    if not ThemeMusic_enabled() then return
    m.themeConverted = LCase(Str_orEmpty(g.delivery)) = "converted"
    url = Url_resolve(g.url)
    content = CreateObject("roSGNode", "ContentNode")
    content.Url = url
    fmt = ThemeMusic_streamFormat(g.content_type)
    if fmt <> "" then content.StreamFormat = fmt
    if LCase(Left(url, 5)) = "https" then content.HttpCertificatesFile = "common:/certs/ca-bundle.crt"
    loopIt = Settings_themeMusicLoop() and not m.themeConverted
    m.themeAudio.loop = loopIt
    m.themeAudio.content = content
    m.themeAudio.control = "play"
    m.themePlaying = true
    print "[siku-theme] playing delivery=" + Str_orEmpty(g.delivery) + " type=" + Str_orEmpty(g.content_type) + " loop=" + Str_orEmpty(loopIt)
end sub

function ThemeMusic_streamFormat(contentType as dynamic) as string
    ct = LCase(Str_orEmpty(contentType))
    if ct = "audio/mpeg" or ct = "audio/mp3" then return "mp3"
    if ct = "audio/flac" or ct = "audio/x-flac" then return "flac"
    if ct = "audio/wav" or ct = "audio/x-wav" or ct = "audio/wave" then return "wav"
    if ct = "audio/aac" then return "es.aac-adts"
    if Instr(1, ct, "mp4") > 0 or Instr(1, ct, "m4a") > 0 then return "mp4"
    return ""
end function

sub ThemeMusic_onState()
    if not m.themePlaying or m.themeSel = invalid then return
    st = LCase(Str_orEmpty(m.themeAudio.state))
    if st = "playing" then
        m.themeRetry = 0
    else if st = "finished" then
        ' A converted stream cannot loop in place: replay it with a fresh grant.
        if m.themeConverted and Settings_themeMusicLoop() then
            ThemeMusic_requestGrant()
        else
            m.themePlaying = false
        end if
    else if st = "error" then
        print "[siku-theme] audio error " + Str_orEmpty(m.themeAudio.errorCode) + " " + Str_orEmpty(m.themeAudio.errorMsg)
        if m.themeRetry = 0 then
            m.themeRetry = 1
            ThemeMusic_requestGrant()
        else
            m.themePlaying = false
        end if
    end if
end sub
