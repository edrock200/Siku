' SPDX-License-Identifier: AGPL-3.0-or-later
' Home's watch state across devices (Silo's Roku app c1841ae / #102, Silo Android's
' HomeRealtimeCoordinator; helpers in components/common/HomeWatch.brs). While Home (not a library's
' Recommended page) shows, after its first server answer: mint a ticket (POST /api/v2/events/ws-ticket),
' open the events socket in HomeEventsTask and re-read Home when this profile's watch state changes
' elsewhere. A drop reconnects after 1, 2, 4 ... 30 s and re-reads once subscribed again; the planned
' end of a connection (max_connection_seconds) reconnects at once without a re-read. Without the
' socket (no roWebSocket before Roku OS 16, a server without it, or a reconnect in progress) Home
' re-reads every 120 s while it shows. Everything stops when Home hides: covered by another screen,
' another tab, sign-out or a profile change (MainScene hides the stack). A phone's borrowed profile
' gets no socket (HomeCache_ownerSource is "" for it).

sub HomeLive_init()
    m.hw = { task: invalid, minting: false, gen: 0, owner: "", backoff: 1, supported: true, live: false, reconnecting: false, changes: 0, others: 0 }
    m.hwClock = CreateObject("roTimespan")
    m.hwDueAt = -1
    m.hwLoadAt = -1
    m.hwDueReason = ""
    m.hwRetry = HomeLive_timer("HomeLive_open", false, 1)
    m.hwPoll = HomeLive_timer("HomeLive_onPoll", true, HomeWatch_pollSeconds())
    m.hwDebounce = HomeLive_timer("HomeLive_onDue", false, 2)
end sub

function HomeLive_timer(callback as string, repeats as boolean, seconds as integer) as object
    t = CreateObject("roSGNode", "Timer")
    t.repeat = repeats
    t.duration = seconds
    t.observeField("fire", callback)
    return t
end function

' Home only, and only for this Roku's own session.
function HomeLive_applies() as boolean
    return libraryId() = "" and m.top.active
end function

sub HomeLive_show()
    if libraryId() <> "" then return
    m.hwPoll.control = "start"
    HomeLive_open()
end sub

sub HomeLive_hide()
    if libraryId() <> "" then return
    m.hwPoll.control = "stop"
    m.hwRetry.control = "stop"
    m.hwDebounce.control = "stop"
    m.hwDueAt = -1
    hw = m.hw
    ' A ticket on its way is dropped when it lands (another generation).
    hw.gen = hw.gen + 1
    hw.minting = false
    wasOpen = hw.task <> invalid
    HomeLive_release()
    hw.live = false
    hw.reconnecting = false
    hw.backoff = 1
    if wasOpen then Diag_log("[siku-home] watch events stopped: Home is hidden")
end sub

sub HomeLive_release()
    hw = m.hw
    if hw.task = invalid then return
    hw.task.unobserveField("signal")
    hw.task.shutdown = true
    hw.task = invalid
end sub

' Called when Home shows and after each server answer (the socket waits for Home's first answer, as
' Silo's Roku app waits for Home to be drawn).
sub HomeLive_open()
    hw = m.hw
    if not HomeLive_applies() or not m.serverAnswered or not hw.supported or hw.minting or hw.task <> invalid then return
    s = m.global.session
    owner = HomeCache_ownerSource(s)
    if owner = "" then return
    if HomeWatch_socketUrl(s.serverUrl) = "" then return
    hw.owner = owner
    hw.minting = true
    hw.gen = hw.gen + 1
    Api_send("POST", "/api/v2/events/ws-ticket", invalid, "HomeLive_onTicket", { gen: hw.gen, owner: owner })
end sub

sub HomeLive_onTicket(event as object)
    resp = Api_result(event)
    hw = m.hw
    ctx = resp.context
    if ctx = invalid or ctx.gen <> hw.gen then return
    hw.minting = false
    s = m.global.session
    if not HomeLive_applies() or HomeCache_ownerSource(s) <> ctx.owner then return
    ticket = ""
    if resp.ok then ticket = HomeWatch_ticket(resp.data)
    if ticket = "" then
        status = Int(Num_or(resp.status, 0))
        if HomeWatch_ticketVerdict(status) = "unsupported" then
            hw.supported = false
            Diag_log("[siku-home] watch events unavailable: ticket status=" + status.ToStr() + "; reading Home every " + HomeWatch_pollSeconds().ToStr() + " s while it shows")
            return
        end if
        hw.reconnecting = true
        Diag_log("[siku-home] watch events ticket failed status=" + status.ToStr() + "; trying again in " + hw.backoff.ToStr() + " s")
        HomeLive_retry()
        return
    end if
    task = CreateObject("roSGNode", "HomeEventsTask")
    task.observeField("signal", "HomeLive_onSignal")
    task.request = { url: HomeWatch_socketUrl(s.serverUrl), protocols: HomeWatch_protocols(ticket), profileId: Str_orEmpty(s.profileId), lifetime: HomeWatch_lifetime(resp.data) }
    hw.task = task
    hw.changes = 0
    hw.others = 0
    task.control = "RUN"
    Diag_log("[siku-home] watch events connecting lifetime=" + HomeWatch_lifetime(resp.data).ToStr() + " s")
end sub

sub HomeLive_retry()
    hw = m.hw
    if not HomeLive_applies() or not hw.supported then return
    m.hwRetry.duration = hw.backoff
    m.hwRetry.control = "start"
    hw.backoff = HomeWatch_nextBackoff(hw.backoff)
end sub

sub HomeLive_onSignal(event as object)
    hw = m.hw
    if hw.task = invalid or not hw.task.isSameNode(event.getRoSGNode()) then return
    sig = event.getData()
    if Type(sig) <> "roAssociativeArray" then return
    kind = Str_orEmpty(sig.kind)
    if kind = "closed" then
        HomeLive_onClosed(Str_orEmpty(sig.reason))
        return
    end if
    if not HomeLive_applies() or HomeCache_ownerSource(m.global.session) <> hw.owner then return
    if kind = "subscribed" then
        hw.live = true
        hw.backoff = 1
        catchUp = hw.reconnecting
        hw.reconnecting = false
        Diag_log("[siku-home] watch events subscribed channel=user_state catch_up=" + HomeLive_yesNo(catchUp))
        ' Nothing is replayed: after a drop, read once for what was missed meanwhile (the read Home
        ' made when it was shown again covers the time it was hidden).
        if catchUp then HomeLive_queue("reconnect", 0)
    else if kind = "changed" then
        changes = Int(Num_or(sig.changes, 0))
        others = Int(Num_or(sig.others, 0))
        if changes <= hw.changes then return
        progressOnly = others <= hw.others
        hw.changes = changes
        hw.others = others
        since = -1
        if m.hwLoadAt >= 0 then since = m.hwClock.TotalMilliseconds() - m.hwLoadAt
        delay = HomeWatch_eventDelay(progressOnly, since)
        Diag_log("[siku-home] watch state changed elsewhere change=" + Str_orEmpty(sig.change) + " events=" + changes.ToStr() + "; reading Home in " + delay.ToStr() + " s")
        HomeLive_queue("changed", delay)
    else if kind = "access_changed" then
        Diag_log("[siku-home] watch events: access changed; reading Home and reconnecting")
        HomeLive_queue("access_changed", 0)
    end if
end sub

sub HomeLive_onClosed(reason as string)
    hw = m.hw
    hw.task = invalid
    hw.live = false
    if not HomeLive_applies() then return
    action = HomeWatch_afterClose(reason)
    if action = "stop" then
        if reason = "unsupported" or reason = "protocol" or reason = "rejected" then
            hw.supported = false
            Diag_log("[siku-home] watch events unavailable: " + reason + "; reading Home every " + HomeWatch_pollSeconds().ToStr() + " s while it shows")
        end if
        return
    end if
    if action = "now" then
        Diag_log("[siku-home] watch events closed reason=" + reason + "; reconnecting now")
        if reason = "access_changed" then HomeLive_queue("access_changed", 0)
        HomeLive_open()
        return
    end if
    ' A drop (or a socket that never opened): anything sent before the socket is back is lost, so
    ' read once when it is.
    hw.reconnecting = true
    Diag_log("[siku-home] watch events closed reason=" + reason + "; reconnecting in " + hw.backoff.ToStr() + " s")
    HomeLive_retry()
end sub

' Re-read Home in `seconds` (0 = now) unless an earlier read is already due.
sub HomeLive_queue(reason as string, seconds as integer)
    if not m.top.active then return
    now = m.hwClock.TotalMilliseconds()
    due = now + seconds * 1000
    if m.hwDueAt >= 0 and m.hwDueAt <= due then return
    if seconds <= 0 then
        m.hwDebounce.control = "stop"
        m.hwDueAt = -1
        requestRefresh(reason)
        return
    end if
    m.hwDueAt = due
    m.hwDueReason = reason
    m.hwDebounce.control = "stop"
    m.hwDebounce.duration = seconds
    m.hwDebounce.control = "start"
end sub

sub HomeLive_onDue()
    reason = Str_orEmpty(m.hwDueReason)
    m.hwDueAt = -1
    if reason = "" then reason = "changed"
    if m.top.active then requestRefresh(reason)
end sub

' Every 120 s while Home shows and the socket is not live.
sub HomeLive_onPoll()
    if not HomeLive_applies() or m.hw.live or not m.serverAnswered then return
    if HomeCache_ownerSource(m.global.session) = "" then return
    HomeLive_queue("poll", 0)
end sub

' Home began a read (HomePage.load): progress-only events wait 30 s from here.
sub HomeLive_noteLoad()
    m.hwLoadAt = m.hwClock.TotalMilliseconds()
end sub

function HomeLive_yesNo(v as boolean) as string
    if v then return "yes"
    return "no"
end function
