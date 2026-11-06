' SPDX-License-Identifier: AGPL-3.0-or-later
' What the audio player does when the server answers about its playback session (Silo Android #708,
' AudiobookPlayerViewModel audiobookReplanRecovery / canRetryPlayback). Pure: no SceneGraph, so
' tests/test_audio_session_recovery.py runs it in brs-cli.

' The server has forgotten the session (reaped after the player was cut off past its grace, or a
' restart): 404 with the v1 code playback_session_not_found, or v2's generic not_found whose detail
' names the session. Other 404s ("Source media file is missing") say nothing about the session.
function AudioSession_isMissing(resp as dynamic) as boolean
    if resp = invalid or Type(resp) <> "roAssociativeArray" then return false
    if Num_or(resp.status, 0) <> 404 then return false
    e = resp.error
    if e = invalid or Type(e) <> "roAssociativeArray" then return false
    if Str_orEmpty(e.code) = "playback_session_not_found" then return true
    return Str_orEmpty(e.detail) = "Playback session not found" or Str_orEmpty(e.title) = "Playback session not found"
end function

' 410 playback_session_ended: an administrator stopped the session. Starting a fresh one, even from
' Retry, would undo that stop. The same rule as PlayerScreen's isSessionEndedByServer.
function AudioSession_isEnded(resp as dynamic) as boolean
    if resp = invalid or Type(resp) <> "roAssociativeArray" then return false
    if Num_or(resp.status, 0) <> 410 then return false
    e = resp.error
    if e = invalid or Type(e) <> "roAssociativeArray" then return false
    return Str_orEmpty(e.code) = "playback_session_ended"
end function

' A progress answer about the session playing now:
'   "ended"          the server ended it: stop, say so, no Retry
'   "renew"          an audiobook's session expired while playing: a fresh one at the position now
'   "renew_on_play"  it expired while paused: the fresh one starts when Play is pressed
'   "stop_reporting" another 404/410, music, or 3 renewals in a row without a good progress answer
'   ""               anything else (keep reporting)
function AudioSession_progressAction(resp as dynamic, mode as string, paused as boolean, renewals as integer) as string
    if AudioSession_isEnded(resp) then return "ended"
    if AudioSession_isMissing(resp) then
        if mode <> "audiobook" or renewals >= 3 then return "stop_reporting"
        if paused then return "renew_on_play"
        return "renew"
    end if
    if resp = invalid or Type(resp) <> "roAssociativeArray" then return ""
    st = Num_or(resp.status, 0)
    if st = 404 or st = 410 then return "stop_reporting"
    return ""
end function

' Playback stopped on an error: Play (and the Try again button) start it again at the position the
' player last held, unless the server ended the session or the player is closing.
function AudioSession_canRetry(errorShown as boolean, endedByServer as boolean, closing as boolean) as boolean
    return errorShown and not endedByServer and not closing
end function
