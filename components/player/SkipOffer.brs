' SPDX-License-Identifier: AGPL-3.0-or-later
' The timed offer every skip pill makes (Skip Intro, Skip Recap, Skip Credits, and the Watch pill
' after an automatic skip). Adapted from silo-roku 9b1bccc (#108, source/playback/skipIntro.bs
' playback.skipOffer), which follows silo-server's intro-skip design. Pure: no node access, so
' tests/test_skip_offer.py runs it on the host. PlayerScreen feeds it events and draws
' SkipOffer_view; Siku has one pill node, so one pill is actionable at a time by construction.
'
' The rules:
' - Entering an unresolved range once playback plays shows its pill with a 10 s timer. The timer
'   counts only while playing (a rebuffer keeps it running for 1.5 s) and while nothing covers the
'   pill (Up Next, the player panel, a dialog, the error screen): covered, it hides with its time held.
' - A press resolves the range (it is never offered again for this title) and seeks past it; Back
'   on a timed pill resolves it without seeking and does nothing else.
' - When the timer runs out the pill goes without resolving the range. While the controls show it
'   comes back without a timer (the "returned" pill): it takes no focus and no Back, Up from the
'   scrubber reaches it, OK on it still skips. Leaving the range forgets the timer that ran out (and
'   one held for it), so coming back starts a full timer.
' - Intro goes first, then recap, then credits: a lower pill waits, its timer held, while a higher
'   one shows (timed, or returned with the controls up), and comes back with the time it had left.
' - Automatic skips (playback.intro_skip_mode always, playback.auto_skip_credits) resolve their
'   ranges, land past every overlapping automatic range at once and show "<Kind> skipped" over a
'   Watch pill pinned to that range on the same timer; Watch seeks back to its start (the range stays
'   resolved, so it plays through), Back or the timer hides it.
' - A press or Back while the pill shows acts on it even when its time ran out just before (the
'   tick that would hide it has not run yet).
' - After a seek, positions far from its target (the Video node still reporting where playback is
'   leaving) are ignored for up to 5 s, so they cannot offer the old range again.
'
' Events (SkipOffer_event), now in monotonic milliseconds, each with controls (the controls show)
' and covered (something hides the pill):
'   { type: "position", seconds }   the playing position, source seconds
'   { type: "seek", seconds }       a seek sent (viewer or recovery): taken as the position at once
'   { type: "player", state }       the Video state: playing | paused | buffering | finished | ...
'   { type: "press" }               OK on the pill
'   { type: "back" }                Back while the pill shows; out holds { type: "consumed" } if taken
'   { type: "tick" } / { type: "sync" }   the pill's timer, or a controls/cover change
' Commands out: { type: "seek", seconds, auto } and { type: "consumed" }. Log lines for the
' [siku-playback] console collect in state.log.

function SkipOffer_promptMs() as integer
    return 10000
end function

function SkipOffer_graceMs() as integer
    return 1500
end function

function SkipOffer_seekWaitMs() as integer
    return 5000
end function

' prefs: { mode: never|ask|always (playback.intro_skip_mode), credits: playback.auto_skip_credits }.
function SkipOffer_new(markers as dynamic, prefs as dynamic) as object
    mode = "ask"
    credits = false
    if prefs <> invalid and Type(prefs) = "roAssociativeArray" then
        v = LCase(Str_orEmpty(prefs.mode))
        if v = "never" or v = "always" then mode = v
        credits = SkipOffer_flag(prefs.credits)
    end if
    s = {
        ranges: [], mode: mode, autoCredits: credits,
        resolved: {}, expired: {}, held: {},
        prompt: invalid, position: -1.0,
        playerState: "", played: false, graceUntil: -1, lastNow: -1,
        controls: false, covered: false,
        seekTarget: -1.0, seekUntil: -1,
        log: []
    }
    SkipOffer_setMarkers(s, markers)
    return s
end function

' The playing file's ranges changed: what was resolved stays, the pill shown for a range that is gone goes.
sub SkipOffer_setMarkers(s as object, markers as dynamic)
    ranges = []
    for each kind in ["intro", "recap", "credits"]
        for each r in Markers_ranges(markers, kind)
            r.key = SkipOffer_keyOf(r)
            ranges.Push(r)
        end for
    end for
    s.ranges = ranges
    p = s.prompt
    if p <> invalid then
        found = false
        for each r in ranges
            if r.key = p.key then found = true
        end for
        if not found then s.prompt = invalid
    end if
end sub

' A boolean read loosely: anything but true is false (pitfall 16: invalid = true throws).
function SkipOffer_flag(v as dynamic) as boolean
    if v = invalid then return false
    t = Type(v)
    if t = "Boolean" or t = "roBoolean" then return v
    return false
end function

function SkipOffer_keyOf(r as object) as string
    return r.kind + ":" + Int(r.start * 1000).ToStr() + "-" + Int(r["end"] * 1000).ToStr()
end function

' Whether the profile skips this kind automatically.
function SkipOffer_isAuto(s as object, kind as string) as boolean
    if kind = "credits" then return s.autoCredits
    return s.mode = "always"
end function

' Whether this kind gets a pill (mode never offers none, except credits skipped automatically).
function SkipOffer_isOffered(s as object, kind as string) as boolean
    if SkipOffer_isAuto(s, kind) then return false
    return s.mode <> "never"
end function

function SkipOffer_contains(r as object, seconds as float) as boolean
    return seconds >= r.start and seconds < r["end"] - 1
end function

function SkipOffer_event(s as object, ev as object) as object
    out = []
    t = Str_orEmpty(ev.type)
    now = Int(Num_or(ev.now, 0))
    if (t = "press" or t = "back") and SkipOffer_view(s) <> invalid then
        ' Routed to the pill as drawn: it acts on that pill even if its time just ran out.
        s.lastNow = now
    else
        SkipOffer_advance(s, now)
    end if
    s.controls = SkipOffer_flag(ev.controls)
    s.covered = SkipOffer_flag(ev.covered)
    if t = "player" then
        SkipOffer_onPlayer(s, Str_orEmpty(ev.state), now)
    else if t = "position" then
        at = Num_or(ev.seconds, -1)
        if s.seekTarget >= 0 then
            if Abs(at - s.seekTarget) <= 2 or now >= s.seekUntil then
                s.seekTarget = -1.0
            else
                ' The Video node still reports where playback is leaving.
                return out
            end if
        end if
        s.position = at
    else if t = "seek" then
        SkipOffer_noteSeek(s, Num_or(ev.seconds, 0), now)
        if s.prompt <> invalid and s.prompt.watch then
            ' A seek of the viewer's own settles the Watch pill.
            s.log.Push("skip pill gone kind=" + s.prompt.kind + " watch=yes reason=seek")
            s.prompt = invalid
        end if
    else if t = "press" then
        SkipOffer_press(s, now, out)
    else if t = "back" then
        v = SkipOffer_view(s)
        if v <> invalid and v.timed then
            p = s.prompt
            if p.watch then
                s.log.Push("skip pill gone kind=" + p.kind + " watch=yes reason=back")
                s.prompt = invalid
            else
                SkipOffer_resolve(s, p, "back")
            end if
            out.Push({ type: "consumed" })
        end if
    end if
    SkipOffer_evaluate(s, now, out)
    return out
end function

sub SkipOffer_noteSeek(s as object, seconds as float, now as integer)
    s.position = seconds
    s.seekTarget = seconds
    s.seekUntil = now + SkipOffer_seekWaitMs()
end sub

sub SkipOffer_press(s as object, now as integer, out as object)
    if SkipOffer_view(s) = invalid then return
    p = s.prompt
    if p.watch then
        s.log.Push("skip pill pressed kind=" + p.kind + " watch=yes; back to " + Int(p.start).ToStr() + " s")
        s.prompt = invalid
        out.Push({ type: "seek", seconds: p.start, auto: false })
        SkipOffer_noteSeek(s, p.start, now)
        return
    end if
    SkipOffer_resolve(s, p, "press")
    out.Push({ type: "seek", seconds: p["end"], auto: false })
    SkipOffer_noteSeek(s, p["end"], now)
end sub

sub SkipOffer_resolve(s as object, p as object, by as string)
    s.resolved[p.key] = true
    s.expired.Delete(p.key)
    s.held.Delete(p.key)
    if s.prompt <> invalid and s.prompt.key = p.key then s.prompt = invalid
    s.log.Push("skip pill resolved kind=" + p.kind + " range=" + SkipOffer_rangeText(p) + " by=" + by)
end sub

function SkipOffer_rangeText(r as object) as string
    return Int(r.start).ToStr() + "-" + Int(r["end"]).ToStr()
end function

sub SkipOffer_onPlayer(s as object, st as string, now as integer)
    if st = "buffering" and s.playerState = "playing" then
        s.graceUntil = now + SkipOffer_graceMs()
    else if st <> "buffering" then
        s.graceUntil = -1
    end if
    s.playerState = st
    if st = "playing" then s.played = true
end sub

' Runs a timed pill's clock from the last event to now, counting only time it played uncovered.
sub SkipOffer_advance(s as object, now as integer)
    last = s.lastNow
    s.lastNow = now
    p = s.prompt
    if p = invalid or not p.timed or s.covered or last < 0 or now <= last then return
    stopAt = last
    if s.playerState = "playing" then
        stopAt = now
    else if s.playerState = "buffering" and s.graceUntil >= 0 then
        stopAt = s.graceUntil
        if now < stopAt then stopAt = now
    end if
    if stopAt <= last then return
    p.remainingMs = p.remainingMs - (stopAt - last)
    if p.remainingMs > 0 then return
    s.prompt = invalid
    if p.watch then
        s.log.Push("skip pill timed out kind=" + p.kind + " watch=yes")
    else
        ' The range keeps playing unresolved; with the controls up the pill returns untimed.
        s.expired[p.key] = true
        s.log.Push("skip pill timed out kind=" + p.kind + " range=" + SkipOffer_rangeText(p))
    end if
end sub

sub SkipOffer_evaluate(s as object, now as integer, out as object)
    at = s.position
    if at < 0 then return
    inRange = []
    for each r in s.ranges
        if SkipOffer_contains(r, at) then
            inRange.Push(r)
        else
            ' Left (or never in) this range: a timer that ran out or was held there is forgotten.
            s.expired.Delete(r.key)
            s.held.Delete(r.key)
        end if
    end for
    p = s.prompt
    if p <> invalid and not p.watch then
        still = false
        for each r in inRange
            if r.key = p.key then still = true
        end for
        if not still then
            s.prompt = invalid
            p = invalid
        end if
    end if

    ' Automatic skips: every unresolved automatic range at the position, and any the landing point
    ' falls into, resolved together; one seek past all of them.
    if s.played then
        target = at
        first = invalid
        changed = true
        while changed
            changed = false
            for each r in s.ranges
                if SkipOffer_isAuto(s, r.kind) and not s.resolved.DoesExist(r.key) and (SkipOffer_contains(r, at) or SkipOffer_contains(r, target)) then
                    s.resolved[r.key] = true
                    if first = invalid then first = r
                    if r["end"] > target then target = r["end"]
                    changed = true
                    s.log.Push("skip auto-skipped kind=" + r.kind + " range=" + SkipOffer_rangeText(r))
                end if
            end for
        end while
        if first <> invalid then
            out.Push({ type: "seek", seconds: target, auto: true })
            SkipOffer_noteSeek(s, target, now)
            s.prompt = { key: first.key, kind: first.kind, start: first.start, "end": first["end"], timed: true, watch: true, remainingMs: SkipOffer_promptMs() }
            s.log.Push("skip pill offered kind=" + first.kind + " watch=yes remaining=10 s")
            return
        end if
    end if
    if p <> invalid and p.watch then return

    ' The pill for the first offered, unresolved range: with the controls up it may be one whose
    ' timer ran out (untimed); with them hidden, the first whose timer has not run out.
    cands = []
    for each r in inRange
        if SkipOffer_isOffered(s, r.kind) and not s.resolved.DoesExist(r.key) then cands.Push(r)
    end for
    choice = invalid
    returned = false
    if s.controls and not s.covered then
        if cands.Count() > 0 then
            choice = cands[0]
            returned = s.expired.DoesExist(choice.key)
        end if
    else
        for each r in cands
            if choice = invalid and not s.expired.DoesExist(r.key) then choice = r
        end for
    end if
    if p <> invalid and choice <> invalid and p.key = choice.key and p.timed <> returned then return
    if p <> invalid then
        ' Replaced or gone: a timed pill keeps its time for when it shows again.
        if p.timed then s.held[p.key] = p.remainingMs
        s.prompt = invalid
    end if
    if choice = invalid then return
    if returned then
        s.prompt = { key: choice.key, kind: choice.kind, start: choice.start, "end": choice["end"], timed: false, watch: false, remainingMs: 0 }
        s.log.Push("skip pill returned kind=" + choice.kind + " range=" + SkipOffer_rangeText(choice) + " (no timer, controls up)")
        return
    end if
    if s.held.DoesExist(choice.key) then
        left = s.held[choice.key]
        s.held.Delete(choice.key)
        s.prompt = { key: choice.key, kind: choice.kind, start: choice.start, "end": choice["end"], timed: true, watch: false, remainingMs: left }
        return
    end if
    ' A new timer starts only once playback plays and nothing covers the pill.
    if s.playerState <> "playing" or s.covered then return
    s.prompt = { key: choice.key, kind: choice.kind, start: choice.start, "end": choice["end"], timed: true, watch: false, remainingMs: SkipOffer_promptMs() }
    s.log.Push("skip pill offered kind=" + choice.kind + " range=" + SkipOffer_rangeText(choice) + " remaining=10 s")
end sub

' What to draw: invalid while hidden, else { key, kind, timed, watch, progress } with progress the
' timer's fill (0 to 1; 0 for the returned pill).
function SkipOffer_view(s as dynamic) as dynamic
    if s = invalid then return invalid
    p = s.prompt
    if p = invalid or s.covered then return invalid
    progress = 0.0
    if p.timed then
        progress = 1.0 - p.remainingMs / SkipOffer_promptMs()
        if progress < 0 then progress = 0.0
        if progress > 1 then progress = 1.0
    end if
    return { key: p.key, kind: p.kind, timed: p.timed, watch: p.watch, progress: progress }
end function

' Host tests: runs events in order and returns { view, out, log, resolved, expired, held }.
function SkipOffer_run(markers as dynamic, prefs as dynamic, events as object) as object
    s = SkipOffer_new(markers, prefs)
    out = []
    views = []
    for each ev in events
        for each c in SkipOffer_event(s, ev)
            out.Push(c)
        end for
        views.Push(SkipOffer_view(s))
    end for
    return { view: SkipOffer_view(s), views: views, out: out, log: s.log, resolved: s.resolved, expired: s.expired, held: s.held }
end function
