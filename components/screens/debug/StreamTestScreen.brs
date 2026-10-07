' SPDX-License-Identifier: AGPL-3.0-or-later
' Plays known streams and whatever Siku last played, and reports the Video node's view of each:
' state changes, the audio tracks it found, subtitle tracks, buffering and errors. Built to settle
' whether this Roku takes audio from fMP4 HLS segments (Roku's spec: not when muxed with video).

sub init()
    m.list = m.top.findNode("list")
    m.video = m.top.findNode("video")
    m.status = m.top.findNode("status")
    m.list.observeField("itemSelected", "onPick")
    m.video.observeField("state", "onVideo")
    m.video.observeField("availableAudioTracks", "onVideo")
    m.video.observeField("availableSubtitleTracks", "onVideo")
    m.video.observeField("bufferingStatus", "onVideo")
    m.presets = []
    m.lines = []
    m.current = ""
end sub

sub onScreenShown()
    buildPresets()
    m.list.setFocus(true)
end sub

sub buildPresets()
    m.presets = []
    m.presets.Push({ label: "Apple sample: HEVC fMP4, demuxed audio (expected: sound)", url: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_adv_example_hevc/master.m3u8", fmt: "hls" })
    m.presets.Push({ label: "Apple sample: H.264 fMP4, demuxed audio (expected: sound)", url: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8", fmt: "hls" })
    m.presets.Push({ label: "Apple sample: H.264 MPEG-TS, muxed audio (expected: sound)", url: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8", fmt: "hls" })
    last = invalid
    if m.global.hasField("lastStream") then last = m.global.lastStream
    if last <> invalid and not Str_isEmpty(last.url) then
        m.presets.Push({ label: "Siku: last Silo stream (" + Str_orEmpty(last.label) + ")", url: last.url, fmt: Str_orEmpty(last.format), headers: last.headers })
    end if
    p = m.top.params
    if p <> invalid and not Str_isEmpty(p.url) then
        fmt = "mp4"
        if Instr(1, LCase(p.url), ".m3u8") > 0 then fmt = "hls"
        m.presets.Push({ label: "Custom URL (debugUrl)", url: p.url, fmt: fmt })
    end if
    root = CreateObject("roSGNode", "ContentNode")
    for each pr in m.presets
        n = root.createChild("ContentNode")
        n.title = pr.label
    end for
    m.list.content = root
end sub

sub onPick()
    idx = m.list.itemSelected
    if idx < 0 or idx >= m.presets.Count() then return
    pr = m.presets[idx]
    m.video.control = "stop"
    m.lines = []
    m.current = pr.label
    c = CreateObject("roSGNode", "ContentNode")
    c.Url = pr.url
    c.Title = pr.label
    c.StreamFormat = pr.fmt
    if pr.headers <> invalid then c.HttpHeaders = pr.headers
    if LCase(Left(pr.url, 5)) = "https" then c.HttpCertificatesFile = "common:/certs/ca-bundle.crt"
    m.video.content = c
    m.video.control = "play"
    note("play " + pr.fmt + " " + pr.url)
end sub

sub onVideo()
    st = Str_orEmpty(m.video.state)
    tracks = Arr_or(m.video.availableAudioTracks)
    names = []
    for each t in tracks
        names.Push(Str_orEmpty(t.Language) + "/" + Str_orEmpty(t.Name) + "/" + Str_orEmpty(t.Track))
    end for
    subs = Arr_or(m.video.availableSubtitleTracks).Count()
    line = "state=" + st + " audioTracks=" + tracks.Count().ToStr() + " [" + Str_joinDots(names, "; ") + "] subtitleTracks=" + subs.ToStr()
    bs = m.video.bufferingStatus
    if bs <> invalid and bs.percentage <> invalid then line = line + " buffering=" + Str_orEmpty(bs.percentage) + "%"
    if st = "error" then
        line = line + " ERROR code=" + Str_orEmpty(m.video.errorCode) + " msg=" + Str_orEmpty(m.video.errorMsg) + " " + Str_orEmpty(m.video.errorStr)
    end if
    if m.lines.Count() = 0 or m.lines[m.lines.Count() - 1] <> line then note(line)
end sub

sub note(line as string)
    print "[siku-streamtest] " + m.current + " | " + line
    m.lines.Push(line)
    while m.lines.Count() > 12
        m.lines.Shift()
    end while
    text = m.current
    for each l in m.lines
        text = text + Chr(10) + l
    end for
    m.status.text = text
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "back" then
        m.video.control = "stop"
        Nav_close()
        return true
    end if
    return false
end function
