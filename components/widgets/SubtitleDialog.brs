' SPDX-License-Identifier: AGPL-3.0-or-later
' See SubtitleDialog.xml for the row contract.

sub init()
    m.card = m.top.findNode("card")
    m.cardBg = m.top.findNode("cardBg")
    m.cardRing = m.top.findNode("cardRing")
    m.titleLabel = m.top.findNode("titleLabel")
    m.viewport = m.top.findNode("viewport")
    m.list = m.top.findNode("list")
    m.width = 680
    m.pad = 28
    m.gap = 12
    m.rowH = 84
    m.resultH = 116
    m.maxListH = 760
    m.entries = []      ' [{node, spec, y, h, focusable}]
    m.index = -1
    m.scrollY = 0
    m.top.focusable = true
    m.top.observeField("visible", "onVisible")
    rebuild()
end sub

sub onVisible()
    if not m.top.visible then return
    if m.index < 0 then focusFirst()
    applyFocus()
end sub

function focusedId() as string
    if m.index < 0 or m.index >= m.entries.Count() then return ""
    return Str_orEmpty(m.entries[m.index].spec.id)
end function

sub focusFirst()
    m.index = -1
    ' A checked option (pickers) first, else the first focusable row.
    for i = 0 to m.entries.Count() - 1
        if m.entries[i].focusable and m.entries[i].spec.checked = true then
            m.index = i
            return
        end if
    end for
    for i = 0 to m.entries.Count() - 1
        if m.entries[i].focusable then
            m.index = i
            return
        end if
    end for
end sub

sub rebuild()
    keepId = focusedId()
    m.list.removeChildrenIndex(m.list.getChildCount(), 0)
    m.entries = []
    specs = m.top.rows
    if specs = invalid then specs = []
    w = m.width
    rowW = w - m.pad * 2

    m.titleLabel.text = UCase(m.top.title)
    m.titleLabel.translation = [m.pad + 16, m.pad]
    m.titleLabel.width = rowW - 32
    titleH = 0
    if m.top.title <> "" then titleH = 34 + 16

    y = 0
    for each spec in specs
        kind = LCase(Str_orEmpty(spec.kind))
        node = m.list.createChild("Group")
        node.translation = [0, y]
        h = m.rowH
        focusable = true
        if kind = "text" then
            h = buildText(node, spec, rowW)
            focusable = false
        else if kind = "progress" then
            h = buildProgress(node, spec, rowW)
            focusable = false
        else if kind = "result" then
            h = m.resultH
            buildResult(node, spec, rowW, h)
        else if kind = "cycler" then
            buildCycler(node, spec, rowW, h)
        else if kind = "option" then
            if not Str_isEmpty(spec.detail) then h = 104
            buildOption(node, spec, rowW, h)
        else
            buildAction(node, spec, rowW, h)
        end if
        m.entries.Push({ node: node, spec: spec, y: y, h: h, focusable: focusable, kind: kind })
        y = y + h + m.gap
    end for
    listH = y - m.gap
    if listH < 0 then listH = 0
    viewH = listH
    if viewH > m.maxListH then viewH = m.maxListH
    m.viewport.translation = [m.pad, m.pad + titleH]
    m.viewport.clippingRect = [0, 0, rowW, viewH + 4]
    m.listH = listH
    m.viewH = viewH
    h = m.pad + titleH + viewH + m.pad
    m.cardBg.width = w
    m.cardBg.height = h
    m.cardRing.width = w
    m.cardRing.height = h
    m.card.translation = [Int((1920 - w) / 2), Int((1080 - h) / 2)]

    ' Keep the focus on the same row across a rebuild (a value cycled, a result list arrived).
    m.index = -1
    if keepId <> "" then
        for i = 0 to m.entries.Count() - 1
            if m.entries[i].focusable and Str_orEmpty(m.entries[i].spec.id) = keepId then m.index = i
        end for
    end if
    if m.index < 0 then focusFirst()
    applyFocus()
end sub

function makeFont(weight as string, size as integer) as object
    f = CreateObject("roSGNode", "Font")
    f.uri = "pkg:/fonts/Inter-" + weight + ".otf"
    f.size = size
    return f
end function

sub addRowBg(node as object, rowW as integer, h as integer, rest as string)
    bg = node.createChild("Poster")
    bg.id = "bg"
    bg.uri = "pkg:/images/ui/r16.9.png"
    bg.width = rowW
    bg.height = h
    bg.blendColor = rest
    ring = node.createChild("Poster")
    ring.id = "ring"
    ring.uri = "pkg:/images/ui/r16_ring2.9.png"
    ring.width = rowW
    ring.height = h
    ring.blendColor = "0xFFFFFFFA"
    ring.visible = false
end sub

sub buildCycler(node as object, spec as object, rowW as integer, h as integer)
    addRowBg(node, rowW, h, "0xFFFFFF0A")
    lbl = node.createChild("Label")
    lbl.id = "label"
    lbl.text = Str_orEmpty(spec.label)
    lbl.translation = [32, 0]
    lbl.width = 230
    lbl.height = h
    lbl.vertAlign = "center"
    lbl.font = makeFont("semibold", 29)
    lbl.color = "0xEDEDEDFF"
    valLbl = node.createChild("Label")
    valLbl.id = "value"
    valLbl.text = "‹  " + Str_orEmpty(spec.value) + "  ›"
    valLbl.translation = [262, 0]
    valLbl.width = rowW - 262 - 32
    valLbl.height = h
    valLbl.vertAlign = "center"
    valLbl.horizAlign = "right"
    valLbl.font = makeFont("medium", 27)
    valLbl.color = "0xEDEDEDCC"
end sub

sub buildAction(node as object, spec as object, rowW as integer, h as integer)
    addRowBg(node, rowW, h, "0xFFFFFF14")
    lbl = node.createChild("Label")
    lbl.id = "label"
    lbl.text = Str_orEmpty(spec.label)
    lbl.translation = [32, 0]
    lbl.width = rowW - 64
    lbl.height = h
    lbl.vertAlign = "center"
    lbl.horizAlign = "center"
    lbl.font = makeFont("semibold", 30)
    if spec.disabled = true then lbl.color = "0xEDEDED6B" else lbl.color = "0xEDEDEDFF"
end sub

sub buildOption(node as object, spec as object, rowW as integer, h as integer)
    addRowBg(node, rowW, h, "0xFFFFFF0A")
    lbl = node.createChild("Label")
    lbl.id = "label"
    lbl.text = Str_orEmpty(spec.label)
    lbl.translation = [32, 0]
    lbl.width = rowW - 64 - 48
    lbl.font = makeFont("medium", 28)
    lbl.color = "0xEDEDEDFF"
    detail = Str_orEmpty(spec.detail)
    if detail <> "" then
        lbl.height = 56
        lbl.vertAlign = "bottom"
        det = node.createChild("Label")
        det.id = "detail"
        det.text = detail
        det.translation = [32, 58]
        det.width = rowW - 64 - 48
        det.height = 32
        det.font = makeFont("regular", 22)
        det.color = "0xEDEDED9E"
    else
        lbl.height = h
        lbl.vertAlign = "center"
    end if
    chk = node.createChild("Poster")
    chk.id = "check"
    chk.uri = "pkg:/images/icons/check.png"
    chk.width = 36
    chk.height = 36
    chk.translation = [rowW - 32 - 36, Int((h - 36) / 2)]
    chk.blendColor = "0xEDEDEDFF"
    chk.visible = spec.checked = true
end sub

' Score badge · release name / provider badge · HI · "N downloads · Language".
sub buildResult(node as object, spec as object, rowW as integer, h as integer)
    addRowBg(node, rowW, h, "0xFFFFFF0A")
    score = 0
    if spec.score <> invalid then score = Int(spec.score)
    badge = node.createChild("Poster")
    badge.id = "scoreBg"
    badge.uri = "pkg:/images/ui/r8.9.png"
    badge.width = 64
    badge.height = 44
    badge.translation = [28, Int((h - 44) / 2)]
    badge.blendColor = scoreColor(score)
    sc = node.createChild("Label")
    sc.text = score.ToStr()
    sc.translation = [28, Int((h - 44) / 2)]
    sc.width = 64
    sc.height = 44
    sc.horizAlign = "center"
    sc.vertAlign = "center"
    sc.font = makeFont("bold", 25)
    sc.color = "0xFFFFFFFF"

    name = Str_orEmpty(spec.releaseName)
    if name = "" then name = "Unnamed release"
    lbl = node.createChild("Label")
    lbl.id = "label"
    lbl.text = name
    lbl.translation = [112, 16]
    lbl.width = rowW - 112 - 28
    lbl.height = 40
    lbl.maxLines = 1
    lbl.font = makeFont("semibold", 27)
    lbl.color = "0xEDEDEDFF"

    provider = Str_orEmpty(spec.provider)
    pb = node.createChild("Poster")
    pb.uri = "pkg:/images/ui/r6.9.png"
    pb.height = 30
    pb.width = 60
    pb.translation = [112, 64]
    pb.blendColor = providerColor(provider)
    pl = node.createChild("Label")
    pl.text = providerAbbreviation(provider)
    pl.translation = [112, 64]
    pl.width = 60
    pl.height = 30
    pl.horizAlign = "center"
    pl.vertAlign = "center"
    pl.font = makeFont("bold", 18)
    pl.color = "0xFFFFFFFF"
    x = 112 + 60 + 14
    if spec.hearingImpaired = true then
        hi = node.createChild("Label")
        hi.id = "hi"
        hi.text = "HI"
        hi.translation = [x, 64]
        hi.width = 40
        hi.height = 30
        hi.vertAlign = "center"
        hi.font = makeFont("bold", 19)
        hi.color = "0xEDEDEDA8"
        x = x + 40
    end if
    meta = node.createChild("Label")
    meta.id = "detail"
    downloads = 0
    if spec.downloads <> invalid then downloads = Int(spec.downloads)
    metaText = downloads.ToStr() + " downloads"
    lang = Str_orEmpty(spec.languageName)
    if lang <> "" then metaText = metaText + " · " + lang
    if spec.busy = true then metaText = "Downloading…"
    meta.text = metaText
    meta.translation = [x, 64]
    meta.width = rowW - x - 28
    meta.height = 30
    meta.vertAlign = "center"
    meta.font = makeFont("regular", 22)
    meta.color = "0xEDEDED8F"
end sub

function buildText(node as object, spec as object, rowW as integer) as integer
    lbl = node.createChild("Label")
    lbl.text = Str_orEmpty(spec.text)
    lbl.translation = [16, 0]
    lbl.width = rowW - 32
    lbl.wrap = true
    lbl.maxLines = 4
    lbl.lineSpacing = 4
    lbl.font = makeFont("regular", 24)
    color = Str_orEmpty(spec.color)
    if color = "" then color = "0xEDEDEDA8"
    lbl.color = color
    h = Int(Label_height(lbl))
    if h < 30 then h = 30
    return h + 8
end function

function buildProgress(node as object, spec as object, rowW as integer) as integer
    percent = 0
    if spec.percent <> invalid then percent = Int(spec.percent)
    if percent < 0 then percent = 0
    if percent > 100 then percent = 100
    title = node.createChild("Label")
    title.text = Str_orEmpty(spec.title)
    title.translation = [16, 0]
    title.width = rowW - 32
    title.height = 40
    title.font = makeFont("semibold", 29)
    title.color = "0xEDEDEDFF"
    track = node.createChild("Poster")
    track.uri = "pkg:/images/ui/r6.9.png"
    track.translation = [16, 52]
    track.width = rowW - 32
    track.height = 12
    track.blendColor = "0xFFFFFF24"
    fillW = Int((rowW - 32) * percent / 100)
    if fillW > 0 then
        fill = node.createChild("Poster")
        fill.uri = "pkg:/images/ui/r6.9.png"
        fill.translation = [16, 52]
        fill.width = fillW
        fill.height = 12
        fill.blendColor = "0xFFFFFFEB"
    end if
    h = 72
    msg = Str_orEmpty(spec.message)
    if msg <> "" then
        ml = node.createChild("Label")
        ml.text = msg
        ml.translation = [16, 76]
        ml.width = rowW - 32
        ml.wrap = true
        ml.maxLines = 2
        ml.font = makeFont("regular", 23)
        ml.color = "0xEDEDEDA8"
        h = 76 + Int(Label_height(ml)) + 6
    end if
    return h
end function

' Web/mobile score buckets: >= 70 green, >= 40 amber, else red.
function scoreColor(score as integer) as string
    if score >= 70 then return "0x22C55EFF"
    if score >= 40 then return "0xEAB308FF"
    return "0xEF4444FF"
end function

function providerAbbreviation(provider as string) as string
    p = LCase(provider)
    if p = "opensubtitles" then return "OS"
    if p = "subdl" then return "SDL"
    if p = "subsource" then return "SS"
    if Len(provider) > 3 then return UCase(Left(provider, 3))
    return UCase(provider)
end function

function providerColor(provider as string) as string
    p = LCase(provider)
    if p = "opensubtitles" then return "0xEAB308FF"
    if p = "subdl" then return "0x3B82F6FF"
    if p = "subsource" then return "0xEF4444FF"
    return "0xFFFFFF66"
end function

sub applyFocus()
    for i = 0 to m.entries.Count() - 1
        e = m.entries[i]
        if e.focusable then
            f = (i = m.index)
            bg = Node_find(e.node, "bg")
            ring = Node_find(e.node, "ring")
            lbl = Node_find(e.node, "label")
            valLbl = Node_find(e.node, "value")
            det = Node_find(e.node, "detail")
            chk = Node_find(e.node, "check")
            hi = Node_find(e.node, "hi")
            if f then
                bg.blendColor = "0xEDEDEDFF"
                ring.visible = true
                if lbl <> invalid then lbl.color = "0x000000FF"
                if valLbl <> invalid then valLbl.color = "0x000000E6"
                if det <> invalid then det.color = "0x000000B3"
                if chk <> invalid then chk.blendColor = "0x000000FF"
                if hi <> invalid then hi.color = "0x000000B3"
            else
                if e.kind = "action" then bg.blendColor = "0xFFFFFF14" else bg.blendColor = "0xFFFFFF0A"
                ring.visible = false
                if lbl <> invalid then
                    if e.kind = "action" and e.spec.disabled = true then lbl.color = "0xEDEDED6B" else lbl.color = "0xEDEDEDFF"
                end if
                if valLbl <> invalid then valLbl.color = "0xEDEDEDCC"
                if det <> invalid then det.color = "0xEDEDED8F"
                if chk <> invalid then chk.blendColor = "0xEDEDEDFF"
                if hi <> invalid then hi.color = "0xEDEDEDA8"
            end if
        end if
    end for
    scrollToFocus()
end sub

' Keeps the focused row inside the viewport.
sub scrollToFocus()
    if m.index < 0 or m.index >= m.entries.Count() or m.viewH = invalid then return
    e = m.entries[m.index]
    rowTop = e.y
    bottom = e.y + e.h
    if rowTop < m.scrollY then m.scrollY = rowTop
    if bottom > m.scrollY + m.viewH then m.scrollY = bottom - m.viewH
    if m.scrollY > m.listH - m.viewH then m.scrollY = m.listH - m.viewH
    if m.scrollY < 0 then m.scrollY = 0
    m.list.translation = [0, -m.scrollY]
end sub

function moveFocus(direction as integer) as boolean
    i = m.index + direction
    while i >= 0 and i < m.entries.Count()
        if m.entries[i].focusable then
            m.index = i
            applyFocus()
            return true
        end if
        i = i + direction
    end while
    return false
end function

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return true
    if key = "back" then
        m.top.dismissed = true
        return true
    end if
    if key = "up" then
        moveFocus(-1)
        return true
    else if key = "down" then
        moveFocus(1)
        return true
    end if
    if m.index < 0 or m.index >= m.entries.Count() then return true
    e = m.entries[m.index]
    id = Str_orEmpty(e.spec.id)
    if e.kind = "cycler" then
        if key = "left" then
            m.top.cycled = { id: id, direction: -1 }
        else if key = "right" or key = "OK" then
            m.top.cycled = { id: id, direction: 1 }
        end if
    else if key = "OK" then
        if e.spec.disabled = true then return true
        m.top.chosen = id
    end if
    ' Swallow everything while the dialog is up.
    return true
end function
