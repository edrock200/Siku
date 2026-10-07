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
    m.bufferedFill = m.top.findNode("bufferedFill")
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
    ' Buffered-ahead segment (the Android TV player's lighter buffered track): from the played
    ' position to the furthest downloaded second; hidden when nothing reports one (< 0).
    buf = m.top.buffered
    m.bufferedFill.visible = false
    if dur > 0 and buf > cur then
        if buf > dur then buf = dur
        bx = Int(trackW * frac)
        bw = Int(trackW * (buf / dur)) - bx
        if bw > 0 then
            m.bufferedFill.translation = [bx, trackY]
            m.bufferedFill.width = bw
            m.bufferedFill.height = trackH
            m.bufferedFill.visible = true
        end if
    end if
    m.puck.width = puckS
    m.puck.height = puckS
    m.puck.translation = [Int(trackW * frac) - puckS / 2, (h - puckS) / 2]

    ' Marker ranges (intro / credits / recap) and chapter ticks. redraw() runs on every position
    ' tick, so the Rectangles are reused and only re-laid out; they are created or removed only
    ' when the number of marks changes.
    rangeSpecs = []
    tickSpecs = []
    if dur > 0 then
        for each mk in Arr_or(m.top.markers)
            s = mk.start
            e = mk["end"]
            if s <> invalid and e <> invalid and e > s then
                x0 = Int(trackW * (s / dur))
                x1 = Int(trackW * (e / dur))
                rangeSpecs.Push({ x: x0, w: x1 - x0 })
            end if
        end for
        for each ch in Arr_or(m.top.chapters)
            s = ch.start_seconds
            if s <> invalid and s > 0 and s < dur then tickSpecs.Push({ x: Int(trackW * (s / dur)), w: 3 })
        end for
    end if
    fitMarks(m.ranges, rangeSpecs.Count(), "0xFFFFFF66")
    fitMarks(m.ticks, tickSpecs.Count(), "0xFFFFFFCC")
    for i = 0 to rangeSpecs.Count() - 1
        r = m.ranges.getChild(i)
        r.translation = [rangeSpecs[i].x, trackY]
        r.width = rangeSpecs[i].w
        r.height = trackH
    end for
    for i = 0 to tickSpecs.Count() - 1
        tick = m.ticks.getChild(i)
        tick.translation = [tickSpecs[i].x, trackY - 3]
        tick.width = 3
        tick.height = trackH + 6
    end for

    rl = m.top.rateLabel
    m.rateChip.visible = scrubbing and rl <> ""
    if m.rateChip.visible then
        m.rateText.text = rl
        m.rateChip.translation = [trackX + Int(trackW * frac) - 32, -44]
    end if
end sub

' Keeps exactly `count` Rectangle children under `parent`, creating or dropping as needed.
sub fitMarks(parent as object, count as integer, color as string)
    n = parent.getChildCount()
    if n > count then
        parent.removeChildrenIndex(n - count, count)
    else
        while n < count
            r = parent.createChild("Rectangle")
            r.color = color
            n = n + 1
        end while
    end if
end sub
