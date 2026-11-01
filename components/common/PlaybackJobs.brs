' Durable playback stops: the DELETE /api/v2/playback/{session} that carries the final position.
' The player hands each one to MainScene (callFunc "playbackStop"), which outlives the player
' screen, so a stop that got no answer or a 5xx is sent again with the same body (same stop_id and
' sequence, which the server treats as one stop) after 2, 4, 8, 16 and then every 30 s, at most 8
' tries (about 2 minutes). Continue Watching then resumes at the right place after a brief network
' or server hiccup at the moment the viewer left. A stop for an account, profile or server that is
' no longer the active one is dropped (its token is gone). Adapted from Silo-Server/silo-roku,
' AGPL-3.0 (source/playback/jobs.bs: stops kept as durable jobs with back-off).
' The player learns that the first try was answered through its stopAnswered field.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub PlaybackJobs_init()
    m.playbackJobs = []
    m.pjClock = CreateObject("roTimespan")
    m.pjTimer = CreateObject("roSGNode", "Timer")
    m.pjTimer.duration = 1
    m.pjTimer.repeat = true
    m.pjTimer.observeField("fire", "PlaybackJobs_onTick")
    m.top.appendChild(m.pjTimer)
end sub

' MainScene interface function. job: { sid, body, baseUrl, identity, player (the PlayerScreen
' node, told when the first try is answered) }.
function playbackStop(job as dynamic) as boolean
    if job = invalid or Type(job) <> "roAssociativeArray" or Str_isEmpty(job.sid) then return false
    j = {
        sid: Str_orEmpty(job.sid)
        body: job.body
        baseUrl: Str_orEmpty(job.baseUrl)
        identity: Str_orEmpty(job.identity)
        player: job.player
        tries: 0
        dueAt: 0.0
    }
    PlaybackJobs_send(j)
    return true
end function

' Who a playback request belongs to: the server and the profile (their token sends it).
function PlaybackJobs_identity(s as dynamic) as string
    if s = invalid or Type(s) <> "roAssociativeArray" then return ""
    return Str_orEmpty(s.serverUrl) + "|" + Str_orEmpty(s.profileId)
end function

' Statuses worth sending the same stop again for: no answer, a timeout, rate limiting, 5xx.
function PlaybackJobs_retriable(status as dynamic) as boolean
    st = Int(Num_or(status, 0))
    if st = 0 or st = 408 or st = 425 or st = 429 then return true
    return st >= 500 and st <= 599
end function

' Seconds before retry n (after try n failed): 2, 4, 8, 16, then 30.
function PlaybackJobs_retryDelay(tries as integer) as integer
    d = 2
    n = 1
    while n < tries
        d = d * 2
        if d >= 30 then return 30
        n = n + 1
    end while
    return d
end function

function PlaybackJobs_maxTries() as integer
    return 8
end function

sub PlaybackJobs_send(job as object)
    job.tries = job.tries + 1
    req = { method: "DELETE", path: "/api/v2/playback/" + Str_urlEncode(job.sid), body: job.body, context: job }
    if job.baseUrl <> "" then req.baseUrl = job.baseUrl
    Api_call(req, "PlaybackJobs_onAnswer")
end sub

sub PlaybackJobs_onAnswer(event as object)
    resp = Api_result(event)
    job = resp.context
    if job = invalid or Type(job) <> "roAssociativeArray" then return
    if job.tries = 1 and job.player <> invalid then
        ' The player waits (at most its stopTimeout) for this before it closes.
        player = job.player
        job.player = invalid
        if player.hasField("stopAnswered") then player.stopAnswered = job.sid
    end if
    if not PlaybackJobs_retriable(resp.status) then
        if job.tries > 1 then print "[siku-playback] stop delivered status=" + Str_orEmpty(resp.status) + " tries=" + job.tries.ToStr()
        return
    end if
    if job.tries >= PlaybackJobs_maxTries() then
        print "[siku-playback] stop not delivered after " + job.tries.ToStr() + " tries status=" + Str_orEmpty(resp.status) + "; giving up"
        return
    end if
    delay = PlaybackJobs_retryDelay(job.tries)
    job.dueAt = m.pjClock.TotalMilliseconds() / 1000.0 + delay
    m.playbackJobs.Push(job)
    print "[siku-playback] stop not delivered status=" + Str_orEmpty(resp.status) + "; try " + (job.tries + 1).ToStr() + " in " + delay.ToStr() + " s"
    m.pjTimer.control = "start"
end sub

sub PlaybackJobs_onTick()
    now = m.pjClock.TotalMilliseconds() / 1000.0
    waiting = []
    due = []
    for i = 0 to m.playbackJobs.Count() - 1
        job = m.playbackJobs[i]
        if job.dueAt <= now then due.Push(job) else waiting.Push(job)
    end for
    m.playbackJobs = waiting
    if waiting.Count() = 0 then m.pjTimer.control = "stop"
    current = PlaybackJobs_identity(m.global.session)
    for i = 0 to due.Count() - 1
        job = due[i]
        if job.identity <> current then
            print "[siku-playback] stop dropped: the account, profile or server changed"
        else
            PlaybackJobs_send(job)
        end if
    end for
end sub
