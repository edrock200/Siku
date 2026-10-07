' Notifications inbox card (see NotificationRow.xml). Geometry follows TvInboxScreen.kt
' at 1 dp = 2 px, 1 sp = 1.72 px: 14 dp padding, 16 dp gaps, titleMedium 20/26 sp,
' bodyMedium 18/24 sp (2 lines), labelMedium 16 sp time, 10 dp unread dot.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.body = m.top.findNode("body")
    m.bg = m.top.findNode("bg")
    m.posterBg = m.top.findNode("posterBg")
    m.posterMask = m.top.findNode("posterMask")
    m.poster = m.top.findNode("poster")
    m.titleLabel = m.top.findNode("title")
    m.subtitle = m.top.findNode("subtitle")
    m.timeLabel = m.top.findNode("time")
    m.dot = m.top.findNode("dot")
    m.ring = m.top.findNode("ring")
end sub

sub layout()
    c = m.top.card
    if c = invalid then return
    w = m.top.width
    kind = rowStr(c.kind, "row")
    rich = c.isRich = true
    unread = c.isUnread = true

    m.titleLabel.text = rowStr(c.title, "")
    m.subtitle.text = rowStr(c.subtitle, "")
    m.timeLabel.text = rowStr(c.relativeTime, "")

    if kind = "markAll" or kind = "error" then
        ' MarkAllReadCard: 18 dp x 16 dp padding, one titleMedium line.
        m.titleLabel.font = semibold(34)
        m.titleLabel.translation = [36, 32]
        m.titleLabel.width = w - 72
        m.titleLabel.height = 45
        m.titleLabel.vertAlign = "center"
        m.subtitle.visible = false
        m.timeLabel.visible = false
        m.dot.visible = false
        m.posterMask.visible = false
        m.posterBg.visible = false
        h = 32 + 45 + 32
        m.bgIdle = "0x15171CCC"
        finish(w, h)
        return
    end if

    ' Weight: SemiBold while unread, Regular once read.
    if unread then
        m.titleLabel.font = semibold(34)
    else
        m.titleLabel.font = regular(34)
    end if
    m.bgIdle = "0x15171C99"
    if unread then m.bgIdle = "0x15171CEB"

    pad = 28
    x = pad
    m.posterMask.visible = rich
    m.posterBg.visible = rich
    if rich then
        m.poster.uri = rowStr(c.posterUrl, "")
        x = pad + 112 + 32
    end if

    ' Trailing column: relative time over the unread dot, right-aligned.
    trailW = 0
    if m.timeLabel.text <> "" or unread then trailW = 132
    m.timeLabel.visible = m.timeLabel.text <> ""
    m.dot.visible = unread

    textW = w - x - pad - trailW
    if trailW > 0 then textW = textW - 32
    m.titleLabel.width = textW
    m.titleLabel.height = 0
    m.titleLabel.vertAlign = "top"
    m.subtitle.width = textW

    textH = 45
    subH = 0
    if m.subtitle.text <> "" then
        m.subtitle.visible = true
        subH = 41
        if Label_height(m.subtitle) > 60 then subH = 82
        textH = textH + 8 + subH
    else
        m.subtitle.visible = false
    end if

    contentH = textH
    if rich and 168 > contentH then contentH = 168
    h = pad * 2 + contentH

    textTop = pad + Int((contentH - textH) / 2)
    m.titleLabel.translation = [x, textTop]
    m.subtitle.translation = [x, textTop + 45 + 8]
    if rich then
        m.posterMask.translation = [pad, pad + Int((contentH - 168) / 2)]
        m.posterBg.translation = m.posterMask.translation
    end if

    colH = 0
    if m.timeLabel.visible then colH = 34
    if unread then
        if colH > 0 then colH = colH + 16
        colH = colH + 20
    end if
    colTop = Int((h - colH) / 2)
    m.timeLabel.width = trailW
    m.timeLabel.translation = [w - pad - trailW, colTop]
    dotY = colTop
    if m.timeLabel.visible then dotY = colTop + 34 + 16
    m.dot.translation = [w - pad - 20, dotY]
    finish(w, h)
end sub

sub finish(w as float, h as float)
    m.bg.width = w
    m.bg.height = h
    m.ring.width = w + 4
    m.ring.height = h + 4
    m.ring.translation = [-2, -2]
    m.body.scaleRotateCenter = [w / 2, h / 2]
    m.top.rowHeight = h
    applyFocus()
end sub

sub applyFocus()
    if m.bgIdle = invalid then return
    f = m.top.focused
    m.ring.visible = f
    if f then
        m.body.scale = [1.02, 1.02]
    else
        m.body.scale = [1.0, 1.0]
    end if
    m.bg.blendColor = m.bgIdle
end sub

function semibold(size as integer) as object
    f = CreateObject("roSGNode", "Font")
    f.uri = "pkg:/fonts/Inter-semibold.otf"
    f.size = size
    return f
end function

function regular(size as integer) as object
    f = CreateObject("roSGNode", "Font")
    f.uri = "pkg:/fonts/Inter-regular.otf"
    f.size = size
    return f
end function

function rowStr(v as dynamic, fallback as string) as string
    if v = invalid then return fallback
    if GetInterface(v, "ifString") = invalid then return fallback
    return v
end function
