' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.card = m.top.findNode("card")
    m.cardBg = m.top.findNode("cardBg")
    m.cardRing = m.top.findNode("cardRing")
    m.titleLabel = m.top.findNode("titleLabel")
    m.rows = m.top.findNode("rows")
    m.rowNodes = []
    m.index = 0
    m.rowH = 72
    m.pad = 32
    m.top.focusable = true
    m.top.observeField("visible", "onVisible")
    rebuild()
end sub

sub onVisible()
    if not m.top.visible then return
    ' Start on the checked row (pickers) or the first row.
    m.index = 0
    acts = m.top.actions
    if acts <> invalid then
        for i = 0 to acts.Count() - 1
            if acts[i].checked = true then m.index = i
        end for
    end if
    applyFocus()
end sub

sub rebuild()
    m.rows.removeChildrenIndex(m.rows.getChildCount(), 0)
    m.rowNodes = []
    acts = m.top.actions
    if acts = invalid then acts = []
    w = m.top.menuWidth
    rowW = w - m.pad * 2

    m.titleLabel.text = UCase(m.top.title)
    m.titleLabel.translation = [m.pad, m.pad]
    m.titleLabel.width = rowW
    titleH = 0
    if m.top.title <> "" then titleH = 30 + 20

    y = m.pad + titleH
    for i = 0 to acts.Count() - 1
        a = acts[i]
        detail = Str_orEmpty(a.detail)
        rowH = m.rowH
        if detail <> "" then rowH = 96
        row = m.rows.createChild("Group")
        row.translation = [m.pad, y]
        bg = row.createChild("Poster")
        bg.id = "bg"
        bg.uri = "pkg:/images/ui/r14.9.png"
        bg.width = rowW
        bg.height = rowH
        bg.blendColor = "0xEDEDEDFF"
        bg.visible = false
        lbl = row.createChild("Label")
        lbl.id = "label"
        lbl.text = Str_orEmpty(a.label)
        lbl.translation = [24, 0]
        lbl.width = rowW - 48 - 48
        lbl.color = "0xEDEDEDFF"
        f = CreateObject("roSGNode", "Font")
        f.uri = "pkg:/fonts/Inter-medium.otf"
        f.size = 27
        lbl.font = f
        if detail <> "" then
            ' Two-line row: the label sits on top and a muted detail line below it.
            lbl.height = 50
            lbl.vertAlign = "bottom"
            sub_ = row.createChild("Label")
            sub_.id = "detail"
            sub_.text = detail
            sub_.translation = [24, 52]
            sub_.width = rowW - 48 - 48
            sub_.height = 30
            sub_.color = "0xEDEDED9E"
            sf = CreateObject("roSGNode", "Font")
            sf.uri = "pkg:/fonts/Inter-regular.otf"
            sf.size = 22
            sub_.font = sf
        else
            lbl.height = rowH
            lbl.vertAlign = "center"
        end if
        chk = row.createChild("Poster")
        chk.id = "check"
        chk.uri = "pkg:/images/icons/check.png"
        chk.width = 36
        chk.height = 36
        chk.translation = [rowW - 24 - 36, (rowH - 36) / 2]
        chk.blendColor = "0xEDEDEDFF"
        chk.visible = a.checked = true
        m.rowNodes.Push(row)
        y = y + rowH
    end for
    h = y + m.pad
    m.cardBg.width = w
    m.cardBg.height = h
    m.cardRing.width = w
    m.cardRing.height = h
    m.card.translation = [Int((1920 - w) / 2), Int((1080 - h) / 2)]
    if m.index >= m.rowNodes.Count() then m.index = 0
    applyFocus()
end sub

sub applyFocus()
    for i = 0 to m.rowNodes.Count() - 1
        row = m.rowNodes[i]
        focused = (i = m.index)
        Node_find(row, "bg").visible = focused
        det = Node_find(row, "detail")
        if focused then
            Node_find(row, "label").color = "0x000000FF"
            Node_find(row, "check").blendColor = "0x000000FF"
            if det <> invalid then det.color = "0x000000B3"
        else
            Node_find(row, "label").color = "0xEDEDEDFF"
            Node_find(row, "check").blendColor = "0xEDEDEDFF"
            if det <> invalid then det.color = "0xEDEDED9E"
        end if
    end for
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return true
    n = m.rowNodes.Count()
    if key = "up" then
        if m.index > 0 then m.index = m.index - 1
        applyFocus()
    else if key = "down" then
        if m.index < n - 1 then m.index = m.index + 1
        applyFocus()
    else if key = "OK" then
        acts = m.top.actions
        if acts <> invalid and m.index < acts.Count() then m.top.chosen = Str_orEmpty(acts[m.index].id)
    else if key = "back" then
        m.top.dismissed = true
    end if
    ' Swallow everything while the dialog is up.
    return true
end function
