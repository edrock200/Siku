' SPDX-License-Identifier: AGPL-3.0-or-later
' Hold-to-seek while the controls are hidden (silo-android TvPlayerScreen "clean seek" and
' TvHoldSeekIndicator, after the tvOS HoldSeekIndicator). A Left/Right tap still skips by the
' profile's skip intervals; a press held 0.3 s starts a seek session instead: a preview time runs
' at a signed rate from the ladder 1x, 2x, 4x ... 32x (2 s of media per 100 ms at 1x), climbing
' 1x -> 2x -> 4x -> 8x every 1.2 s until the viewer taps Left/Right to change it. OK or Play seeks
' there and shows the controls; Back cancels. The video keeps playing meanwhile. The indicator at
' the top of the screen shows the server's preview of the landing point (PlayerTrickplay.brs,
' "frame" mode) above the rate chip, a progress bar and a hint row.
' A press is classified by its release, so the skip of a tap now fires on release.
' Needs these nodes in PlayerScreen.xml: holdSeek, hsChip, hsChipBg, hsRate, hsTime, hsTrack,
' hsFill, hsHint, hsPressTimer, hsTickTimer, hsRampTimer.

function HS_HOLD_MS() as integer
    return 300
end function

sub HoldSeek_init()
    m.holdSeek = m.top.findNode("holdSeek")
    m.hsChip = m.top.findNode("hsChip")
    m.hsChipBg = m.top.findNode("hsChipBg")
    m.hsRate = m.top.findNode("hsRate")
    m.hsTime = m.top.findNode("hsTime")
    m.hsTrack = m.top.findNode("hsTrack")
    m.hsFill = m.top.findNode("hsFill")
    m.hsHint = m.top.findNode("hsHint")
    m.hsPressTimer = m.top.findNode("hsPressTimer")
    m.hsTickTimer = m.top.findNode("hsTickTimer")
    m.hsRampTimer = m.top.findNode("hsRampTimer")
    m.hsPressTimer.observeField("fire", "HoldSeek_onPressTimer")
    m.hsTickTimer.observeField("fire", "HoldSeek_onTick")
    m.hsRampTimer.observeField("fire", "HoldSeek_onRamp")
    m.hsClock = CreateObject("roTimespan")
    m.hs = { active: false, pendingDir: 0, pendingAt: 0, becameHold: false, rate: 0, preview: 0.0, lastTick: 0, rampStep: 0, adjDir: 0, adjAt: 0 }
end sub

function HoldSeek_active() as boolean
    return m.hs <> invalid and m.hs.active
end function

function HoldSeek_now() as integer
    return m.hsClock.TotalMilliseconds()
end function

' Left/Right pressed with the controls hidden.
sub HoldSeek_press(direction as integer)
    if m.plan = invalid then return
    m.hs.pendingDir = direction
    m.hs.pendingAt = HoldSeek_now()
    m.hs.becameHold = false
    m.hsPressTimer.control = "stop"
    m.hsPressTimer.control = "start"
end sub

sub HoldSeek_onPressTimer()
    m.hsPressTimer.control = "stop"
    if m.hs.pendingDir = 0 or m.hs.active then return
    if m.controls.visible or m.upNext.visible or m.hud.visible or m.errorGroup.visible or m.closing then return
    HoldSeek_begin(m.hs.pendingDir)
end sub

' Left/Right released: a tap skips (or, in a session, steps the rate); a hold has already begun.
sub HoldSeek_release(direction as integer)
    if m.hs.active then
        if m.hs.adjDir = direction and HoldSeek_now() - m.hs.adjAt < HS_HOLD_MS() then HoldSeek_bump(direction)
        m.hs.adjDir = 0
        if m.hs.pendingDir = direction then m.hs.pendingDir = 0
        return
    end if
    if m.hs.pendingDir <> direction then return
    m.hsPressTimer.control = "stop"
    held = HoldSeek_now() - m.hs.pendingAt
    becameHold = m.hs.becameHold
    m.hs.pendingDir = 0
    if becameHold then return
    if held >= HS_HOLD_MS() and not m.controls.visible then
        ' The timer was late (a busy render thread); the press was a hold all the same.
        HoldSeek_begin(direction)
        return
    end if
    if direction < 0 then onSkipBack() else onSkipForward()
end sub

sub HoldSeek_begin(direction as integer)
    if m.plan = invalid then return
    m.hs.becameHold = true
    m.hs.active = true
    sign = 1
    if direction < 0 then sign = -1
    m.hs.rate = sign
    m.hs.preview = m.position
    if m.hs.preview < 0 then m.hs.preview = 0
    m.hs.lastTick = HoldSeek_now()
    m.hs.rampStep = 0
    m.hs.adjDir = 0
    hideFeedback()
    m.holdSeek.visible = true
    m.hsTickTimer.control = "start"
    m.hsRampTimer.control = "start"
    HoldSeek_render()
end sub

sub HoldSeek_onTick()
    if not m.hs.active then return
    now = HoldSeek_now()
    elapsed = now - m.hs.lastTick
    m.hs.lastTick = now
    if elapsed < 0 then elapsed = 0
    p = m.hs.preview + m.hs.rate * 2.0 * elapsed / 100.0
    if p < 0 then p = 0
    if m.duration > 0 and p > m.duration then p = m.duration
    m.hs.preview = p
    HoldSeek_render()
end sub

' Sustained ramp (Apple startHoldSeekAutoRamp): 1 -> 2 -> 4 -> 8, each step only while the rate is
' still the one the previous step left, so a tap in the meantime wins.
sub HoldSeek_onRamp()
    ramp = [2, 4, 8]
    if not m.hs.active or m.hs.rampStep >= ramp.Count() then
        m.hsRampTimer.control = "stop"
        return
    end if
    sign = 1
    if m.hs.rate < 0 then sign = -1
    expected = 1
    if m.hs.rampStep > 0 then expected = ramp[m.hs.rampStep - 1]
    if Abs(m.hs.rate) <> expected then
        m.hsRampTimer.control = "stop"
        return
    end if
    m.hs.rate = ramp[m.hs.rampStep] * sign
    m.hs.rampStep = m.hs.rampStep + 1
    HoldSeek_render()
end sub

' A tap steps along the signed ladder -32 ... -1, 1 ... 32 (clamped; past 1x it reverses).
sub HoldSeek_bump(delta as integer)
    m.hsRampTimer.control = "stop"
    ladder = [-32, -16, -8, -4, -2, -1, 1, 2, 4, 8, 16, 32]
    idx = -1
    for i = 0 to ladder.Count() - 1
        if ladder[i] = m.hs.rate then idx = i
    end for
    if idx < 0 then return
    idx = idx + delta
    if idx < 0 then idx = 0
    if idx > ladder.Count() - 1 then idx = ladder.Count() - 1
    m.hs.rate = ladder[idx]
    HoldSeek_render()
end sub

' Keys while a session runs. Returns true for every key: the session owns the remote.
function HoldSeek_handleKey(key as string) as boolean
    if key = "OK" or key = "play" then
        HoldSeek_commit()
    else if key = "back" then
        HoldSeek_stop()
    else if key = "left" or key = "right" then
        m.hs.adjDir = 1
        if key = "left" then m.hs.adjDir = -1
        m.hs.adjAt = HoldSeek_now()
    end if
    return true
end function

sub HoldSeek_commit()
    target = m.hs.preview
    HoldSeek_stop()
    seekToSource(target)
    m.controlsZone = "scrubber"
    showControls()
end sub

sub HoldSeek_stop()
    m.hsPressTimer.control = "stop"
    m.hsTickTimer.control = "stop"
    m.hsRampTimer.control = "stop"
    wasActive = m.hs.active
    m.hs.active = false
    m.hs.pendingDir = 0
    m.hs.adjDir = 0
    m.holdSeek.visible = false
    if wasActive then Trickplay_show(invalid, "")
end sub

function HoldSeek_rateText(rate as integer) as string
    if rate = 0 then return "Paused"
    sign = ""
    if rate < 0 then sign = "-"
    return sign + Abs(rate).ToStr() + Chr(215)
end function

sub HoldSeek_render()
    m.hsRate.text = HoldSeek_rateText(m.hs.rate)
    t = Time_clock(m.hs.preview)
    if m.duration >= 3600 and m.hs.preview < 3600 then t = "0:" + Str_padLeft(t, 5)
    m.hsTime.text = t
    frac = 0
    if m.duration > 0 then frac = m.hs.preview / m.duration
    if frac > 1 then frac = 1
    m.hsFill.width = Int(520 * frac)
    Trickplay_show(m.hs.preview, "frame")
    HoldSeek_layout()
end sub

' Top-centred column, 160 px from the top, 16 px apart: the preview frame (when a picture has shown
' in this session), the rate chip, the 520 px bar and the hint row.
sub HoldSeek_layout()
    if m.hs = invalid or not m.hs.active then return
    y = 160
    if Trickplay_shown() or m.tp.slotKept then
        m.tpView.translation = [(1920 - 480) / 2, y]
        y = y + 270 + 16
    end if
    rw = Int(Label_width(m.hsRate))
    tw = Int(Label_width(m.hsTime))
    cw = 28 + rw + 18 + tw + 28
    m.hsChipBg.width = cw
    m.hsRate.translation = [28, 0]
    m.hsTime.translation = [28 + rw + 18, 0]
    m.hsChip.translation = [Int((1920 - cw) / 2), y]
    y = y + 70 + 16
    m.hsTrack.translation = [700, y]
    m.hsFill.translation = [700, y]
    y = y + 4 + 16
    m.hsHint.translation = [0, y]
end sub
