' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.shadow = m.top.findNode("shadow")
    m.bg = m.top.findNode("bg")
    m.sheen = m.top.findNode("sheen")
    m.ring = m.top.findNode("ring")
    m.profileHead = m.top.findNode("profileHead")
    m.avatarBg = m.top.findNode("avatarBg")
    m.avatarMask = m.top.findNode("avatarMask")
    m.avatarImg = m.top.findNode("avatarImg")
    m.avatarInitials = m.top.findNode("avatarInitials")
    m.profileName = m.top.findNode("profileName")
    m.profileSub = m.top.findNode("profileSub")
    m.profileDivider = m.top.findNode("profileDivider")
    m.headerLabel = m.top.findNode("headerLabel")
    m.rowsGroup = m.top.findNode("rowsGroup")
    m.footerDivider = m.top.findNode("footerDivider")
    m.footerLabel = m.top.findNode("footerLabel")
    m.rowNodes = []
    m.rowMeta = []
    m.winStart = 0
    m.winEnd = 0
    m.padX = 32
    m.rowH = 64
    m.top.focusable = true
    m.top.observeField("focusedChild", "applyFocus")
    rebuild()
end sub

' Creates (or reuses) one row group: bg capsule, icon, label, trailing glyph.
function rowNode(i as integer) as object
    if i < m.rowNodes.Count() then return m.rowNodes[i]
    g = m.rowsGroup.createChild("Group")
    bg = g.createChild("Poster")
    bg.id = "bg"
    bg.uri = "pkg:/images/ui/r14.9.png"
    bg.blendColor = Theme().colors.ink
    bg.visible = false
    divider = g.createChild("Rectangle")
    divider.id = "divider"
    divider.height = 1
    divider.color = "0xFFFFFF1F"
    divider.visible = false
    icon = g.createChild("Poster")
    icon.id = "icon"
    icon.width = 36
    icon.height = 36
    lbl = g.createChild("Label")
    lbl.id = "label"
    Label_setFont(lbl, "medium", 26)
    lbl.vertAlign = "center"
    lbl.height = m.rowH
    sub1 = g.createChild("Label")
    sub1.id = "sub"
    sub1.font = ThemeFont("medium", 22)
    sub1.color = "0xEDEDED9E"
    sub1.vertAlign = "center"
    sub1.height = m.rowH
    sub1.horizAlign = "right"
    trailing = g.createChild("Poster")
    trailing.id = "trailing"
    trailing.width = 28
    trailing.height = 28
    m.rowNodes.Push(g)
    return g
end function

sub rebuild()
    if m.rowsGroup = invalid then return
    w = m.top.width
    rows = m.top.rows
    if rows = invalid then rows = []
    y = 24

    ' Profile header block.
    prof = m.top.profile
    if prof <> invalid and prof.Count() > 0 then
        m.profileHead.visible = true
        m.profileHead.translation = [m.padX, y]
        m.avatarBg.translation = [0, 0]
        m.avatarMask.translation = [0, 0]
        m.avatarInitials.translation = [0, 0]
        avatar = Str_orEmpty(prof.avatar)
        if avatar <> "" then
            m.avatarImg.uri = Url_resolve(avatar)
            m.avatarMask.visible = true
            m.avatarInitials.visible = false
        else
            m.avatarMask.visible = false
            m.avatarInitials.visible = true
            m.avatarInitials.text = Shell_initials(Str_orEmpty(prof.name))
        end if
        m.profileName.text = Str_orEmpty(prof.name)
        m.profileName.translation = [84, 4]
        m.profileName.width = w - m.padX * 2 - 84
        m.profileSub.text = UCase(Str_orEmpty(prof["sub"]))
        m.profileSub.translation = [84, 36]
        m.profileSub.width = w - m.padX * 2 - 84
        ' No divider between the header and the first row (Silo Android #883, as tvOS and Roku):
        ' the rows' own divider splits the two groups.
        m.profileDivider.visible = false
        y = y + 92
    else
        m.profileHead.visible = false
    end if

    ' The drawn window of rows (maxRows): it always holds the focused row.
    n = rows.Count()
    maxRows = m.top.maxRows
    m.winStart = 0
    m.winEnd = n
    if maxRows > 0 and n > maxRows then
        fi = m.top.focusIndex
        if fi < 0 then fi = 0
        if fi >= n then fi = n - 1
        start = m.prevWinStart
        if start = invalid then start = 0
        if fi < start then start = fi
        if fi > start + maxRows - 1 then start = fi - maxRows + 1
        if start > n - maxRows then start = n - maxRows
        if start < 0 then start = 0
        m.winStart = start
        m.winEnd = start + maxRows
    end if
    m.prevWinStart = m.winStart

    ' Header.
    if not Str_isEmpty(m.top.header) then
        m.headerLabel.visible = true
        hint = ""
        if m.winStart > 0 then hint = "  ↑"
        if m.winEnd < n then hint = hint + "  ↓"
        m.headerLabel.text = m.top.header + hint
        m.headerLabel.translation = [m.padX + 12, y]
        m.headerLabel.width = w - m.padX * 2
        y = y + 44
    else
        m.headerLabel.visible = false
    end if

    ' Rows.
    m.rowMeta = []
    for i = 0 to rows.Count() - 1
        r = rows[i]
        if i < m.winStart or i >= m.winEnd then
            ' Outside the drawn window: kept for focus moves, no node.
            m.rowMeta.Push({ divider: Str_orEmpty(r.id) = "-", id: Str_orEmpty(r.id), hidden: true })
        else
            y = drawRow(rowNode(i - m.winStart), r, y, w)
        end if
    end for
    for i = m.winEnd - m.winStart to m.rowNodes.Count() - 1
        m.rowNodes[i].visible = false
    end for

    ' Footer.
    if not Str_isEmpty(m.top.footer) then
        y = y + 12
        m.footerDivider.visible = true
        m.footerDivider.translation = [m.padX, y]
        m.footerDivider.width = w - m.padX * 2
        y = y + 17
        m.footerLabel.visible = true
        m.footerLabel.text = m.top.footer
        m.footerLabel.translation = [m.padX, y]
        m.footerLabel.width = w - m.padX * 2
        y = y + Label_height(m.footerLabel) + 4
    else
        m.footerDivider.visible = false
        m.footerLabel.visible = false
    end if
    y = y + 24

    m.bg.width = w
    m.bg.height = y
    m.sheen.width = w
    m.sheen.height = Int(y / 2)
    m.ring.width = w
    m.ring.height = y
    m.shadow.width = w + 24
    m.shadow.height = y + 28
    m.shadow.translation = [-12, -4]
    m.top.panelHeight = Int(y + 0.5)

    ' Keep the focus index on a selectable row.
    if m.top.focusIndex >= rows.Count() then m.top.focusIndex = firstSelectable()
    applyFocus()
end sub

' Draws one visible row at y in node g; returns the y below it.
function drawRow(g as object, r as object, y as integer, w as integer) as integer
    g.visible = true
    bg = Node_find(g, "bg")
    divider = Node_find(g, "divider")
    icon = Node_find(g, "icon")
    lbl = Node_find(g, "label")
    sub1 = Node_find(g, "sub")
    trailing = Node_find(g, "trailing")
    if Str_orEmpty(r.id) = "-" then
        g.translation = [m.padX, y]
        divider.visible = true
        divider.translation = [0, 11]
        divider.width = w - m.padX * 2
        bg.visible = false
        icon.visible = false
        lbl.visible = false
        sub1.visible = false
        trailing.visible = false
        m.rowMeta.Push({ divider: true })
        y = y + 24
    else
        g.translation = [m.padX, y]
        divider.visible = false
        bg.width = w - m.padX * 2
        bg.height = m.rowH
        x = 16
        iconName = Str_orEmpty(r.icon)
        if iconName <> "" then
            icon.visible = true
            icon.uri = "pkg:/images/icons/" + iconName + ".png"
            icon.translation = [x, (m.rowH - 36) / 2]
            x = x + 36 + 18
        else
            icon.visible = false
        end if
        lbl.visible = true
        lbl.text = Str_orEmpty(r.label)
        lbl.translation = [x, 0]
        lbl.width = w - m.padX * 2 - x - 60
        subText = Str_orEmpty(r["sub"])
        sub1.visible = subText <> ""
        sub1.text = subText
        sub1.width = 200
        sub1.translation = [w - m.padX * 2 - 16 - 200 - 36, 0]
        tr = Str_orEmpty(r.trailing)
        if tr = "check" then
            trailing.visible = true
            trailing.uri = "pkg:/images/icons/check.png"
        else if tr = "chevron" then
            trailing.visible = true
            trailing.uri = "pkg:/images/icons/chevron_right.png"
        else
            trailing.visible = false
        end if
        trailing.translation = [w - m.padX * 2 - 16 - 28, (m.rowH - 28) / 2]
        m.rowMeta.Push({ divider: false, id: Str_orEmpty(r.id), destructive: Panel_isTrue(r.destructive) })
        y = y + m.rowH + 4
    end if
    return y
end function

function firstSelectable() as integer
    for i = 0 to m.rowMeta.Count() - 1
        if not m.rowMeta[i].divider then return i
    end for
    return 0
end function

sub applyFocus()
    if m.rowMeta = invalid then return
    focused = m.top.hasFocus()
    fi = m.top.focusIndex
    ' A focus outside the drawn window moves the window (rebuild calls back here).
    if m.top.maxRows > 0 and fi >= 0 and fi < m.rowMeta.Count() and (fi < m.winStart or fi >= m.winEnd) then
        rebuild()
        return
    end if
    for i = m.winStart to m.winEnd - 1
        g = m.rowNodes[i - m.winStart]
        if m.rowMeta[i].divider then
            ' nothing
        else
            isF = focused and i = fi
            Node_find(g, "bg").visible = isF
            lbl = Node_find(g, "label")
            icon = Node_find(g, "icon")
            trailing = Node_find(g, "trailing")
            sub1 = Node_find(g, "sub")
            if isF then
                lbl.color = Theme().colors.onInk
                Label_setFont(lbl, "semibold", 26)
                icon.blendColor = Theme().colors.onInk
                trailing.blendColor = Theme().colors.onInk
                sub1.color = "0x000000B3"
            else
                ' A destructive row (Sign Out) is the error red at rest and inverts like the
                ' others on focus (Silo Android #883).
                ink = Theme().colors.ink
                if Panel_isTrue(m.rowMeta[i].destructive) then ink = Theme().colors.error
                lbl.color = ink
                Label_setFont(lbl, "medium", 26)
                icon.blendColor = ink
                trailing.blendColor = "0xEDEDED9E"
                sub1.color = "0xEDEDED9E"
            end if
        end if
    end for
end sub

sub moveFocus(delta as integer)
    n = m.rowMeta.Count()
    if n = 0 then return
    i = m.top.focusIndex
    tries = 0
    while tries < n
        i = i + delta
        if i < 0 then i = 0
        if i >= n then i = n - 1
        if not m.rowMeta[i].divider then exit while
        tries = tries + 1
    end while
    if m.rowMeta[i].divider then return
    if i <> m.top.focusIndex then
        m.top.focusIndex = i
        m.top.rowFocused = i
    end if
end sub

' A row flag that may be missing (pitfall 16: comparing invalid with a boolean throws on a Roku).
function Panel_isTrue(v as dynamic) as boolean
    t = Type(v)
    if t = "Boolean" or t = "roBoolean" then return v
    return false
end function

' Initials for an avatar fallback: "Ed Smith" -> "ES".
function Shell_initials(name as string) as string
    out = ""
    for each part in name.Trim().Split(" ")
        if Len(part) > 0 and Len(out) < 2 then out = out + UCase(Left(part, 1))
    end for
    return out
end function

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "up" then
        moveFocus(-1)
        return true
    else if key = "down" then
        moveFocus(1)
        return true
    else if key = "OK" then
        fi = m.top.focusIndex
        if fi >= 0 and fi < m.rowMeta.Count() and not m.rowMeta[fi].divider then
            m.top.rowSelected = m.rowMeta[fi].id
        end if
        return true
    else if key = "right" then
        m.top.exitRight = true
        return true
    else if key = "left" then
        m.top.exitLeft = true
        return true
    end if
    return false
end function
