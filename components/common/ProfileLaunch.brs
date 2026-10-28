' Profile Selection: when Siku asks "Who's watching?" at launch instead of reopening the last
' profile (Android TV #498 / #542, ProfileLaunchPreferences.kt). Device-wide, never sent to the
' server, and it survives sign-out. The choice and the pending "remember" offer live in the
' device prefs (m.global.prefs.profileLaunch / profileLaunchOffer); the time Siku was last in use
' with a profile is its own registry key, written by MainScene's heartbeat (at most every 5-10
' minutes, ProfileLaunch_heartbeat), so the away clock does not rewrite the prefs.
'
' Roku has no background state: a channel is either running or closed. The away interval is
' therefore "since Siku was last seen in use", recorded on exit through Back and every few
' minutes while it runs (pressing Home closes a channel without telling it).
' Needs Utils.brs and Session.brs (Prefs_save).
' SPDX-License-Identifier: AGPL-3.0-or-later

' The four choices, with upstream's stored values (silo-apple raw values) and copy.
function ProfileLaunch_behaviors() as object
    return [
        { id: "automatic", title: "Automatic", detail: "Use the last profile selected on this Roku. A protected profile can reopen without asking for its PIN.", awaySeconds: 0 }
        { id: "askEveryLaunch", title: "Every Time", detail: "Show Who's Watching whenever you return to Siku.", awaySeconds: 0 }
        { id: "afterOneHour", title: "After 1 Hour", detail: "Show Who's Watching when you've been away from Siku for 1 hour.", awaySeconds: 3600 }
        { id: "afterTwelveHours", title: "After 12 Hours", detail: "Show Who's Watching when you've been away from Siku for 12 hours.", awaySeconds: 43200 }
    ]
end function

' The saved choice; unknown or missing values read as Automatic (today's behaviour).
function ProfileLaunch_behavior() as object
    raw = ""
    p = m.global.prefs
    if p <> invalid then raw = Str_orEmpty(p.profileLaunch)
    list = ProfileLaunch_behaviors()
    for each b in list
        if b.id = raw then return b
    end for
    return list[0]
end function

' The first launch on this Roku saves a starting choice: a Roku that already opens a profile (it
' predates the setting) keeps Automatic; a new one asks every time and offers to remember the
' first profile picked. Later launches keep what is saved.
sub ProfileLaunch_settleFirstLaunch(hasRememberedProfile as boolean)
    p = m.global.prefs
    if p <> invalid and not Str_isEmpty(p.profileLaunch) then return
    c = AA_copy(p)
    if hasRememberedProfile then
        c.profileLaunch = "automatic"
        c.profileLaunchOffer = false
    else
        c.profileLaunch = "askEveryLaunch"
        c.profileLaunchOffer = true
    end if
    Prefs_save(c)
end sub

' Cold start: Every Time always asks; the timed choices ask once the recorded away interval has
' run out, or when the clock is behind the recorded time (it cannot say how long Siku was away).
function ProfileLaunch_requiresSelectionAtLaunch() as boolean
    b = ProfileLaunch_behavior()
    if b.id = "askEveryLaunch" then return true
    if b.awaySeconds <= 0 then return false
    since = ProfileLaunch_lastActive()
    if since <= 0 then return false
    now = Time_nowSeconds()
    if now < since then return true
    return now - since >= b.awaySeconds
end function

' Choosing a behaviour answers the offer; Automatic keeps no away interval.
sub ProfileLaunch_setBehavior(id as string)
    c = AA_copy(m.global.prefs)
    c.profileLaunch = id
    c.profileLaunchOffer = false
    Prefs_save(c)
    if id = "automatic" then Registry_delete("profileLastActive")
end sub

function ProfileLaunch_offerPending() as boolean
    p = m.global.prefs
    return p <> invalid and p.profileLaunchOffer = true
end function

' The answer to the new-Roku offer: Remember switches to Automatic, Ask every time keeps asking.
sub ProfileLaunch_answerOffer(remember as boolean)
    if not ProfileLaunch_offerPending() then return
    if remember then
        ProfileLaunch_setBehavior("automatic")
    else
        c = AA_copy(m.global.prefs)
        c.profileLaunchOffer = false
        Prefs_save(c)
    end if
end sub

' Epoch seconds Siku was last in use with a profile; 0 when unknown.
function ProfileLaunch_lastActive() as integer
    v = Registry_read("profileLastActive", 0)
    return Int(Num_or(v, 0))
end function

' Records "in use now" for a timed choice (no-op otherwise, and without a profile). `minGap`
' throttles registry writes: callers on frequent events pass a gap, exit passes 0.
sub ProfileLaunch_markActive(minGap = 0 as integer)
    if ProfileLaunch_behavior().awaySeconds <= 0 then return
    if Str_isEmpty(m.global.session.profileId) then return
    now = Time_nowSeconds()
    if minGap > 0 and now - ProfileLaunch_lastActive() < minGap and now >= ProfileLaunch_lastActive() then return
    Registry_write("profileLastActive", now)
end sub

' MainScene's heartbeat (every ProfileLaunch_heartbeatSeconds while Siku runs). Each registry
' write wears flash, so the time is rewritten only as often as the away rule needs it: a twelfth
' of the away interval, 5 to 10 minutes (After 1 Hour: 5 min, After 12 Hours: 10 min). Pressing
' Home closes Siku without notice, so Who's Watching may then come back that much early at most.
sub ProfileLaunch_heartbeat()
    gap = ProfileLaunch_heartbeatGap()
    if gap <= 0 then return
    ' A tick that lands a few seconds early (timer drift) still counts as the full gap.
    ProfileLaunch_markActive(gap - 30)
end sub

function ProfileLaunch_heartbeatGap() as integer
    away = ProfileLaunch_behavior().awaySeconds
    if away <= 0 then return 0
    gap = Int(away / 12)
    if gap < 300 then gap = 300
    if gap > 600 then gap = 600
    return gap
end function

function ProfileLaunch_heartbeatSeconds() as integer
    return 300
end function
