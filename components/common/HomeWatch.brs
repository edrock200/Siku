' SPDX-License-Identifier: AGPL-3.0-or-later
' Home's watch state (Silo Android #1009 and Silo's Roku app c1841ae / #102): Home reads its rows
' again when it is shown again, when another device changes this profile's watch state, and retries
' a refresh that failed for a transient reason. Pure helpers here (host-tested in
' tests/test_home_watch.py); the socket is HomeEventsTask, the page side
' components/screens/home/HomeLive.brs and HomePage.brs.
'
' The server's events socket (silo-server docs/realtime-api.md, "Session-bound socket handshake"):
'   POST /api/v2/events/ws-ticket -> { ticket, expires_in (<= 30), max_connection_seconds (300),
'                                      protocol: "silo.events.v2" }
'   GET  /api/v2/events/ws?channels=user_state, offering exactly the subprotocols
'        "silo.events.v2, silo.ticket.<ticket>"; the server selects silo.events.v2.
'   Frames: hello, subscribed { channels, rejected }, snapshot (null for user_state), event, error,
'   access_changed (then close 4001). The one Home uses:
'   { "type": "event", "channel": "user_state", "event": "user_state.changed",
'     "data": { "profile_id", "content_id", "series_id", "change" } }
'   change: progress | favorite | watchlist | history | watched | home_dismissal | not_interested.
' The event names what changed, never the new value, so Home re-reads its rows (both upstream apps
' do the same; nothing is patched from the frame). Delivery is at most once and nothing is replayed,
' so a reconnect after a drop re-reads once (Android's "Connected" catch-up).

function HomeWatch_protocol() as string
    return "silo.events.v2"
end function

' The events socket's URL for a server URL (session.serverUrl, which may carry a path prefix):
' https -> wss, http -> ws, the user_state channel declared in the query; "" for anything else.
function HomeWatch_socketUrl(serverUrl as dynamic) as string
    base = Str_orEmpty(serverUrl)
    while Right(base, 1) = "/"
        base = Left(base, Len(base) - 1)
    end while
    if LCase(Left(base, 8)) = "https://" then
        base = "wss://" + Mid(base, 9)
    else if LCase(Left(base, 7)) = "http://" then
        base = "ws://" + Mid(base, 8)
    else
        return ""
    end if
    if Len(base) <= 6 then return ""
    return base + "/api/v2/events/ws?channels=user_state"
end function

' roWebSocket.SetProtocols' value: exactly these two, in this order.
function HomeWatch_protocols(ticket as string) as string
    return HomeWatch_protocol() + ", silo.ticket." + ticket
end function

function HomeWatch_isNumber(v as dynamic) as boolean
    t = Type(v)
    return t = "Integer" or t = "roInt" or t = "roInteger" or t = "LongInteger" or t = "roLongInteger" or t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble"
end function

' The ticket of a POST /api/v2/events/ws-ticket answer, or "" when the answer is outside the
' server's documented bounds (Android's validTicket): protocol silo.events.v2, expires_in 1..30,
' max_connection_seconds 1..300, and a ticket that is an HTTP token (it goes into a header as is).
function HomeWatch_ticket(body as dynamic) as string
    if Type(body) <> "roAssociativeArray" then return ""
    if Str_orEmpty(body.protocol) <> HomeWatch_protocol() then return ""
    if not HomeWatch_isNumber(body.expires_in) or not HomeWatch_isNumber(body.max_connection_seconds) then return ""
    if body.expires_in < 1 or body.expires_in > 30 then return ""
    if body.max_connection_seconds < 1 or body.max_connection_seconds > 300 then return ""
    t = body.ticket
    if Type(t) <> "roString" and Type(t) <> "String" then return ""
    if Len(t) = 0 or Len(t) > 512 then return ""
    extra = "!#$%&'*+-.^_`|~"
    for i = 1 to Len(t)
        ch = Mid(t, i, 1)
        c = Asc(ch)
        ok = (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or Instr(1, extra, ch) > 0
        if not ok then return ""
    end for
    return t
end function

' How long the socket may stay open (seconds), from a ticket answer HomeWatch_ticket accepted.
function HomeWatch_lifetime(body as dynamic) as integer
    if Type(body) <> "roAssociativeArray" or not HomeWatch_isNumber(body.max_connection_seconds) then return 300
    n = Int(body.max_connection_seconds)
    if n < 1 or n > 300 then return 300
    return n
end function

' What a refused or unusable ticket means: "unsupported" (an older server without the events
' socket, 404 / 405 / 501, or a 403 the profile cannot get past; also a 2xx with an unusable ticket)
' stops trying while Home shows, and Home polls instead; anything else (no answer, 408, 429, 5xx, a
' 401 the token refresh did not fix) retries with back-off.
function HomeWatch_ticketVerdict(status as dynamic) as string
    s = Int(Num_or(status, 0))
    if s = 403 or s = 404 or s = 405 or s = 501 then return "unsupported"
    if s >= 200 and s < 300 then return "unsupported"
    return "retry"
end function

' One server text frame as { kind, change }: kind "subscribed" (the subscription to user_state is
' confirmed), "rejected" (the server refused user_state), "changed" (this profile's watch state
' changed; change names what), "access_changed" (the viewer's access changed; the server closes
' with 4001 next) or "" (hello, snapshots, other channels and profiles, errors, broken JSON).
function HomeWatch_frame(text as dynamic, profileId as string) as object
    out = { kind: "", change: "" }
    if Type(text) <> "roString" and Type(text) <> "String" then return out
    f = ParseJson(text)
    if Type(f) <> "roAssociativeArray" then return out
    t = Str_orEmpty(f["type"])
    if t = "access_changed" then
        out.kind = "access_changed"
    else if t = "subscribed" then
        if HomeWatch_listsChannel(f["channels"]) then
            out.kind = "subscribed"
        else if HomeWatch_listsChannel(f["rejected"]) then
            out.kind = "rejected"
        end if
    else if t = "event" then
        if Str_orEmpty(f["channel"]) <> "user_state" or Str_orEmpty(f["event"]) <> "user_state.changed" then return out
        d = f["data"]
        if Type(d) <> "roAssociativeArray" then return out
        ' The server sends a profile's events only to that profile's sockets; check anyway (an
        ' unknown active profile refreshes rather than risk staleness, as Android's homeRefreshTrigger).
        pid = Str_orEmpty(d.profile_id)
        if profileId <> "" and pid <> profileId then return out
        out.kind = "changed"
        out.change = LCase(Str_orEmpty(d.change))
    end if
    return out
end function

' Whether a subscribed frame's channels (strings) or rejected list ({ channel, code }) names user_state.
function HomeWatch_listsChannel(list as dynamic) as boolean
    if Type(list) <> "roArray" then return false
    for each c in list
        if Type(c) = "roAssociativeArray" then
            if Str_orEmpty(c.channel) = "user_state" then return true
        else if Str_orEmpty(c) = "user_state" then
            return true
        end if
    end for
    return false
end function

' What Home does once the socket ended for reason (HomeEventsTask): "stop" (this Roku or server
' cannot do it: Home polls), "now" (the planned end of the connection, or an access change: reconnect
' at once, as the server asks) or "backoff" (a drop: reconnect after the back-off, then re-read once).
function HomeWatch_afterClose(reason as string) as string
    if reason = "unsupported" or reason = "protocol" or reason = "rejected" or reason = "shutdown" or reason = "owner" or reason = "url" then return "stop"
    if reason = "max_age" or reason = "access_changed" then return "now"
    return "backoff"
end function

' The next reconnect delay after one of current seconds: 1, 2, 4 ... 30 (Android's coordinator).
function HomeWatch_nextBackoff(current as integer) as integer
    if current < 1 then return 1
    n = current * 2
    if n > 30 then n = 30
    return n
end function

' Whether a failed read is worth retrying (Android's isTransientHomeReadFailure): no answer, 408,
' 429 or a 5xx.
function HomeWatch_isTransient(status as dynamic) as boolean
    s = Int(Num_or(status, 0))
    return s <= 0 or s = 408 or s = 429 or (s >= 500 and s <= 599)
end function

' The wait before refresh retry attempt (0-based): 1, 2 and 4 s, then -1 (no more; Android's
' refreshFromRealtime tries four times in all).
function HomeWatch_retryDelay(attempt as integer) as integer
    if attempt < 0 or attempt > 2 then return -1
    if attempt = 0 then return 1
    if attempt = 1 then return 2
    return 4
end function

' Seconds until Home re-reads after a change event: 2 s (Android's debounce, which also gathers a
' burst), but a progress-only change (another device playing reports one about every 10 s) waits
' until 30 s after Home's last read began, so a Roku does not re-read every few seconds beside
' someone else's playback. sinceLoadMs is the time since that read began (-1: none yet).
function HomeWatch_eventDelay(progressOnly as boolean, sinceLoadMs as integer) as integer
    if not progressOnly or sinceLoadMs < 0 then return 2
    wait = 30 - Int(sinceLoadMs / 1000)
    if wait < 2 then wait = 2
    return wait
end function

' Seconds between Home's reads while the socket is not live (an older Roku OS without roWebSocket,
' a server without the socket, or a reconnect in progress), as Silo's Roku app polls.
function HomeWatch_pollSeconds() as integer
    return 120
end function
