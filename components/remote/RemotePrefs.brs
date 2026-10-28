' Remote Control settings, device-local (registry "remoteControl"), and the helpers screens use
' to reach the receiver. Any component may include this file.
'   enabled  Remote Control on (default on): Siku listens for Silo's phone app.
'   sealed   Require pairing (default on): only a phone that scanned Connect a Phone's code
'            (holding the pairing key) can connect; off = any device on this network whose
'            hello names this Roku's server (nothing proves it is signed in to it).
' SPDX-License-Identifier: AGPL-3.0-or-later

function RemotePrefs_load() as object
    p = { enabled: true, sealed: true }
    saved = Registry_read("remoteControl")
    if saved <> invalid and Type(saved) = "roAssociativeArray" then
        if Type(saved.enabled) = "Boolean" or Type(saved.enabled) = "roBoolean" then p.enabled = saved.enabled
        if Type(saved.sealed) = "Boolean" or Type(saved.sealed) = "roBoolean" then p.sealed = saved.sealed
    end if
    return p
end function

sub RemotePrefs_save(p as object)
    Registry_write("remoteControl", { enabled: p.enabled, sealed: p.sealed })
    rc = RemoteControl_node()
    if rc <> invalid then rc.reloadPrefs = true
end sub

function RemoteControl_node() as dynamic
    if not m.global.hasField("remoteControl") then return invalid
    return m.global.remoteControl
end function

function RemoteControl_lanTask() as dynamic
    if not m.global.hasField("lanTask") then return invalid
    return m.global.lanTask
end function

' The server and sign-in screens accept a phone while they are up: mode "setup" (no server yet)
' or "login" with srv = the server's deployment identity; "" stops it.
sub RemoteControl_setPairing(mode as string, srv = "" as string)
    rc = RemoteControl_node()
    if rc <> invalid then rc.pairing = { mode: mode, srv: srv }
end sub

sub RemoteControl_pairSend(conn as string, message as object)
    t = RemoteControl_lanTask()
    if t <> invalid then t.command = { kind: "pairSend", conn: conn, message: message }
end sub

sub RemoteControl_pairClose(conn as string, reason as string)
    t = RemoteControl_lanTask()
    if t <> invalid then t.command = { kind: "pairClose", conn: conn, reason: reason }
end sub

' The player's state for every controller (SiloCastPlaybackState, camelCase keys).
sub RemoteState_publish(state as object)
    t = RemoteControl_lanTask()
    if t <> invalid then t.castState = state
end sub

' What a controller sees while nothing plays (TvSiloCastReceiver.idleState).
function RemoteState_idle() as object
    return { "title": "Ready", "isPlaying": false, "isLoading": false, "isBuffering": false, "currentTime": 0, "duration": 0
        "audioTracks": [], "subtitleTracks": [], "qualityOptions": [], "activeQualityId": "auto", "isQualitySwitching": false
        "playbackSpeed": 1.0, "videoGravity": "fit", "hdrEnabled": false, "supportsVideoGravity": false, "supportsHDRToggle": false
        "volume": 1.0, "isMuted": false, "hasNextEpisode": false }
end function
