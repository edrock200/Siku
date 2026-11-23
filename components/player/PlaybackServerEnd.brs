' SPDX-License-Identifier: AGPL-3.0-or-later
' Why the server ended a playback session for good (Silo Android #1043 PlaybackServerEnd, silo-roku
' #107 playback.results "ended" / "pausedTimeout"). Both answer progress posts and replans with 410:
'   playback_session_ended           an administrator stopped the session while the server could
'                                    not tell the player directly
'   playback_session_paused_timeout  the session stayed paused past the administrator's limit
'                                    (playback.paused_session_timeout_minutes); only an attempt that
'                                    advertised paused_timeout_v1 gets it, others get the first
' Either way the session is over: no stop (DELETE), no renewal, no new attempt, and the player
' leaves, saying why. Pure: no SceneGraph, so tests/test_paused_timeout.py runs it in brs-cli.

' The client feature that asks for the paused-timeout answer. Attempt-sticky on the server, so every
' video start and replan sends it (PlaybackCaps_clientFeatures); audiobook and music starts do not
' (AudioCaps_startBody): the server times out only video sessions, as Android sends it only from its
' own video players.
function PlaybackEnd_feature() as string
    return "paused_timeout_v1"
end function

' "paused_timeout", "session_ended", or "" when the answer does not say the server ended the session.
function PlaybackEnd_reason(resp as dynamic) as string
    if resp = invalid or Type(resp) <> "roAssociativeArray" then return ""
    if Num_or(resp.status, 0) <> 410 then return ""
    e = resp.error
    if e = invalid or Type(e) <> "roAssociativeArray" then return ""
    code = Str_orEmpty(e.code)
    if code = "playback_session_paused_timeout" then return "paused_timeout"
    if code = "playback_session_ended" then return "session_ended"
    return ""
end function

' The notice shown on the screen the player returns to (player.notice.pausedTimeout for a paused
' timeout; Android keeps its English admin wording for the other).
function PlaybackEnd_notice(reason as string) as string
    if reason = "paused_timeout" then return Tx("Playback stopped because it was paused for too long.")
    return Tx("An administrator ended this playback session.")
end function

' features without the video-only paused_timeout_v1 (a new array; the input is left as it was).
function PlaybackEnd_withoutFeature(features as dynamic) as object
    out = []
    for each f in Arr_or(features)
        if Str_orEmpty(f) <> PlaybackEnd_feature() then out.Push(f)
    end for
    return out
end function
