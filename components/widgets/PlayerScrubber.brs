' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.capsule = m.top.findNode("capsule")
    m.capsuleRing = m.top.findNode("capsuleRing")
    m.elapsed = m.top.findNode("elapsed")
    m.trackGroup = m.top.findNode("trackGroup")
    m.track = m.top.findNode("track")
    m.ranges = m.top.findNode("ranges")
    m.ticks = m.top.findNode("ticks")
    m.fill = m.top.findNode("fill")
    m.puck = m.top.findNode("puck")
    m.remaining = m.top.findNode("remaining")
    m.rateChip = m.top.findNode("rateChip")
    m.rateText = m.top.findNode("rateText")
    m.top.focusable = true
    m.top.observeField("focusedChild", "redraw")
    redraw()
end sub

sub redraw()
    w = m.top.width
    h = 84
    focused = m.top.hasFocus()
    scrubbing = m.top.scrubbing
    m.capsule.width = w
    m.capsuleRing.width = w
    if focused then m.capsuleRing.blendColor = "0xFFFFFF66" else m.capsuleRing.blendColor = "0xFFFFFF24"

    dur = m.top.duration
    cur = m.top.position
    if scrubbing then cur = m.top.scrubPosition
    if cur < 0 then cur = 0
    if dur > 0 and cur > dur then cur = dur

    labelW = 130
    pad = 28
    trackX = pad + labelW + 24
    trackW = w - trackX * 2
    if trackW < 100 then trackW = 100
    trackH = 7
    if scrubbing then trackH = 12
    puckS = 30
    if focused or scrubbing then puckS = 42

    m.elapsed.translation = [pad, 0]
    m.elapsed.text = Time_clock(cur)
    m.remaining.translation = [w - pad - labelW, 0]
    if dur > 0 then m.remaining.text = "-" + Time_clock(dur - cur) else m.remaining.text = ""

    m.trackGroup.translation = [trackX, 0]
    trackY = (h - trackH) / 2
    m.track.translation = [0, trackY]
    m.track.width = trackW
    m.track.height = trackH
    frac = 0
    if dur > 0 then frac = cur / dur
    if frac > 1 then frac = 1
    m.fill.translation = [0, trackY]
    m.fill.width = Int(trackW * frac)
    m.fill.height = trackH
    m.puck.width = puckS
    m.puck.height = puckS
    m.puck.translation = [Int(trackW * frac) - puckS / 2, (h - puckS) / 2]

    ' Marker ranges (intro / credits / recap) and chapter ticks.
    m.ranges.removeChildrenIndex(m.ranges.getChildCount(), 0)
    m.ticks.removeChildrenIndex(m.ticks.getChildCount(), 0)
    if dur > 0 then
        for each mk in Arr_or(m.top.markers)
            s = mk.start
            e = mk["end"]
            if s <> invalid and e <> invalid and e > s then
                r = m.ranges.createChild("Rectangle")
                x0 = Int(trackW * (s / dur))
                x1 = Int(trackW * (e / dur))
                r.translation = [x0, trackY]
                r.width = x1 - x0
                r.height = trackH
                r.color = "0xFFFFFF66"
            end if
        end for
        for each ch in Arr_or(m.top.chapters)
            s = ch.start_seconds
            if s <> invalid and s > 0 and s < dur then
                tick = m.ticks.createChild("Rectangle")
                tick.translation = [Int(trackW * (s / dur)), trackY - 3]
                tick.width = 3
                tick.height = trackH + 6
                tick.color = "0xFFFFFFCC"
            end if
        end for
    end if

    rl = m.top.rateLabel
    m.rateChip.visible = scrubbing and rl <> ""
    if m.rateChip.visible then
        m.rateText.text = rl
        m.rateChip.translation = [trackX + Int(trackW * frac) - 32, -44]
    end if
end sub
