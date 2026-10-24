' YouTube channel hand-off for "Trailers & More" (see YouTubeLaunchTask.xml).
' SPDX-License-Identifier: AGPL-3.0-or-later
'
' Deep-link parameters: Roku's deep-linking spec passes `contentId` and `mediaType` to the target
' channel's main(). YouTube's Roku channel takes the video id as contentId; which mediaType it
' wants is not documented by YouTube. "live" is what integrations known to work use (Home
' Assistant's Roku "launch YouTube video" example sends content_id + media_type "live"); Roku's
' certification list also has "shortFormVideo" and "movie". If a device shows YouTube's home
' screen instead of the video, try another mediaType here first.

sub init()
    m.top.functionName = "runLaunch"
end sub

function youTubeChannelId() as string
    return "837"
end function

function youTubeMediaType() as string
    return "live"
end function

sub runLaunch()
    req = m.top.request
    videoId = ""
    if req <> invalid and req.videoId <> invalid then videoId = req.videoId
    if videoId = "" then
        finish("launch_failed", "no video id")
        return
    end if
    print "[siku-trailer] youtube hand-off start video=" + videoId + " channel=" + youTubeChannelId() + " mediaType=" + youTubeMediaType()

    am = invalid
    try
        am = CreateObject("roAppManager")
    catch err
        print "[siku-trailer] roAppManager unavailable: " + errText(err)
        am = invalid
    end try

    installed = "unknown"
    if am <> invalid then
        try
            if am.IsAppInstalled(youTubeChannelId(), "") = true then installed = "yes" else installed = "no"
        catch err2
            print "[siku-trailer] IsAppInstalled failed: " + errText(err2)
            installed = "unknown"
        end try
    end if
    print "[siku-trailer] youtube installed=" + installed
    if installed = "no" then
        finish("not_installed", "IsAppInstalled(837) returned false")
        return
    end if

    ' 1. The documented API: roAppManager.LaunchApp(channelId, version, params).
    if am <> invalid then
        called = false
        try
            am.LaunchApp(youTubeChannelId(), "", { contentId: videoId, mediaType: youTubeMediaType() })
            called = true
        catch err3
            print "[siku-trailer] LaunchApp threw: " + errText(err3)
        end try
        if called then
            print "[siku-trailer] LaunchApp(837, contentId, mediaType) called; waiting for YouTube to take over"
            ' A successful launch ends this channel during the wait.
            sleep(6000)
            print "[siku-trailer] still running 6 s after LaunchApp: no hand-off; trying ECP"
        end if
    end if

    ' 2. Fallback: the device's own External Control Protocol, as a phone remote would launch it.
    ' Refused (403) when Settings > System > Advanced > Control by mobile apps is Limited/Disabled.
    code = ecpLaunch(videoId)
    print "[siku-trailer] ECP POST /launch/837 status=" + code.ToStr()
    if code >= 200 and code < 300 then
        sleep(6000)
        print "[siku-trailer] still running 6 s after ECP launch: no hand-off"
    end if
    finish("launch_failed", "LaunchApp and ECP did not open YouTube (ECP status " + code.ToStr() + ")")
end sub

function ecpLaunch(videoId as string) as integer
    xfer = invalid
    try
        xfer = CreateObject("roUrlTransfer")
    catch err
        print "[siku-trailer] roUrlTransfer unavailable: " + errText(err)
        return 0
    end try
    if xfer = invalid then return 0
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    url = "http://127.0.0.1:8060/launch/" + youTubeChannelId() + "?contentId=" + xfer.Escape(videoId) + "&mediaType=" + youTubeMediaType()
    xfer.SetUrl(url)
    xfer.SetRequest("POST")
    if not xfer.AsyncPostFromString("") then return 0
    msg = Wait(5000, port)
    if msg = invalid then
        xfer.AsyncCancel()
        return 0
    end if
    if Type(msg) <> "roUrlEvent" then return 0
    return msg.GetResponseCode()
end function

function errText(err as dynamic) as string
    if err = invalid then return "?"
    if Type(err) = "roAssociativeArray" and err.message <> invalid then return err.message
    return "error"
end function

sub finish(outcome as string, detail as string)
    print "[siku-trailer] outcome=" + outcome + " (" + detail + ")"
    m.top.result = { outcome: outcome, detail: detail }
end sub
