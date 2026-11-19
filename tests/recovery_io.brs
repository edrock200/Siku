' SPDX-License-Identifier: AGPL-3.0-or-later
' Test-only wrapper for tests/test_playback_network.py (RetryWindow): replays connection events
' through PlaybackRecovery's pure window helpers the way Recovery_reconnect, Recovery_notePlaying
' and Recovery_onTick use them, and returns one outcome per step.
'   ["drop", t]: "new:<tries>" | "continued:<tries>" | "open:<tries>" (a reconnect scheduled), or
'                "gave_up" (the 2 minutes are used up: the ladder takes over)
'   ["play", t]: "held" when an outage was open, else ""
'   ["tick", lastPos, pos]: "renewed" when that playback renews the window, else ""
function RecoveryT_run(steps as object) as object
    rec = { outageAt: -1.0, tries: 0, heldAt: -1.0, heldTries: 0, progress: 0.0, outagePaused: false }
    out = []
    for each st in steps
        kind = st[0]
        if kind = "drop" then
            now = st[1] * 1.0
            opened = Recovery_openOutage(rec, now, false)
            if Recovery_outageExpired(rec, now) then
                rec.outageAt = -1.0
                rec.heldAt = -1.0
                out.Push("gave_up")
            else
                rec.tries = rec.tries + 1
                out.Push(opened + ":" + rec.tries.ToStr())
            end if
        else if kind = "play" then
            if rec.outageAt >= 0 then
                Recovery_holdOutage(rec)
                out.Push("held")
            else
                out.Push("")
            end if
        else
            if Recovery_addProgress(rec, Recovery_progressGain(st[1], st[2])) then
                out.Push("renewed")
            else
                out.Push("")
            end if
        end if
    end for
    return out
end function
