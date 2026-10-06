' Home Sections editor (Android TV TvHomeSectionsEditor): a full-screen overlay of the populated
' Home rows with an eye button per row (visible / hidden) and, in edit mode, move up / move down
' buttons. The layout is device-local per server + profile, saved in prefs.hiddenSections and
' prefs.sectionOrder and applied by HomePage through Settings_arrangeSections.
' Included by SettingsScreen.xml; shares the screen's m scope.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub Hs_init()
    m.hsEditor = m.top.findNode("hsEditor")
    m.hsHeader = m.top.findNode("hsHeader")
    m.hsRows = m.top.findNode("hsRows")
    m.hsMessage = m.top.findNode("hsMessage")
    m.hsFooter = m.top.findNode("hsFooter")
    Label_setFont(m.top.findNode("hsTitle"), "semibold", 38)
    Label_setFont(m.top.findNode("hsEyebrow"), "semibold", 24)
    Label_setFont(m.hsMessage, "regular", 24)
    Label_setFont(m.hsFooter, "regular", 24)
    m.hsVisible = false
    m.hsEditing = false
    m.hsLoading = false
    m.hsError = ""
    m.hsSections = []
    m.hsRow = -1          ' -1 = header buttons, else a section row
    m.hsCol = 1           ' header: 0 Edit, 1 Done; row: [up, down,] eye
    m.hsWidth = 1120
end sub

sub Hs_open()
    m.hsVisible = true
    m.hsEditing = false
    m.hsRow = -1
    m.hsCol = 1
    m.hsSections = []
    m.hsLoading = true
    m.hsError = ""
    m.hsEditor.visible = true
    Hs_render()
    Api_get("/api/v2/home/sections", { image_size: "medium" }, "Hs_onSections")
end sub

sub Hs_close()
    m.hsVisible = false
    m.hsEditor.visible = false
    m.top.setFocus(true)
end sub

sub Hs_onSections(event as object)
    resp = Api_result(event)
    m.hsLoading = false
    if not resp.ok or Type(resp.data) <> "roAssociativeArray" then
        m.hsError = Api_errorText(resp)
    else
        ' Every populated row, including hidden ones, in this Roku's saved order.
        list = []
        for each s in Settings_arrangeSections(Arr_or(resp.data.sections), true)
            items = Arr_or(s.items)
            total = Int(Content_numOr(s.total_count, 0))
            if items.Count() > total then total = items.Count()
            if total > 0 then list.Push({ id: Str_orEmpty(s.id), title: Str_orEmpty(s.title), count: total })
        end for
        m.hsSections = list
    end if
    if not m.hsVisible then return
    Hs_render()
end sub

' ---------- Rendering ----------

' A small control: an icon or a label on a 6 px-radius tile. Returns the Group.
function Hs_button(parent as object, w as integer, h as integer, iconUri as string, text as string) as object
    g = parent.createChild("Group")
    bg = g.createChild("Poster")
    bg.id = "bg"
    bg.uri = "pkg:/images/ui/r6.9.png"
    bg.width = w
    bg.height = h
    ring = g.createChild("Poster")
    ring.id = "ring"
    ring.uri = "pkg:/images/ui/r6_ring2.9.png"
    ring.width = w
    ring.height = h
    if iconUri <> "" then
        icon = g.createChild("Poster")
        icon.id = "icon"
        icon.uri = iconUri
        icon.width = 36
        icon.height = 36
        icon.translation = [(w - 36) / 2, (h - 36) / 2]
        icon.scaleRotateCenter = [18, 18]
    end if
    if text <> "" then
        lbl = g.createChild("Label")
        lbl.id = "text"
        lbl.text = text
        Label_setFont(lbl, "semibold", 24)
        lbl.width = w
        lbl.height = h
        lbl.horizAlign = "center"
        lbl.vertAlign = "center"
    end if
    return g
end function

sub Hs_styleButton(g as object, focused as boolean, enabled as boolean)
    bg = Node_find(g, "bg")
    ring = Node_find(g, "ring")
    icon = Node_find(g, "icon")
    lbl = Node_find(g, "text")
    if focused then
        bg.blendColor = "0xEDEDEDFF"
        ring.visible = false
        ink = "0x000000FF"
    else if enabled then
        bg.blendColor = "0xFFFFFF17"
        ring.visible = true
        ring.blendColor = "0xFFFFFF1A"
        ink = "0xEDEDEDFF"
    else
        bg.blendColor = "0xFFFFFF0A"
        ring.visible = false
        ink = "0xEDEDED47"
    end if
    if icon <> invalid then icon.blendColor = ink
    if lbl <> invalid then lbl.color = ink
end sub

sub Hs_render()
    m.hsHeader.removeChildrenIndex(m.hsHeader.getChildCount(), 0)
    m.hsRows.removeChildrenIndex(m.hsRows.getChildCount(), 0)
    w = m.hsWidth
    m.hsHeaderButtons = []
    m.hsRowNodes = []

    ' Header card: the explanation on the left, Edit / Done Editing and Done on the right.
    card = m.hsHeader.createChild("Poster")
    card.uri = "pkg:/images/ui/r14.9.png"
    card.blendColor = "0xFFFFFF12"
    card.width = w
    card.height = 96
    ring = m.hsHeader.createChild("Poster")
    ring.uri = "pkg:/images/ui/r14_ring2.9.png"
    ring.blendColor = "0xFFFFFF17"
    ring.width = w
    ring.height = 96
    t1 = m.hsHeader.createChild("Label")
    t1.text = "Home Sections"
    t1.color = "0xEDEDEDFF"
    Label_setFont(t1, "medium", 26)
    t1.translation = [24, 18]
    t2 = m.hsHeader.createChild("Label")
    if m.hsEditing then t2.text = "Move rows into your preferred order." else t2.text = "Choose which rows appear on Home."
    t2.color = "0xEDEDED9E"
    Label_setFont(t2, "regular", 24)
    t2.translation = [24, 52]
    editLabel = "Edit"
    if m.hsEditing then editLabel = "Done Editing"
    editBtn = Hs_button(m.hsHeader, 220, 56, "", editLabel)
    editBtn.translation = [w - 24 - 140 - 16 - 220, 20]
    doneBtn = Hs_button(m.hsHeader, 140, 56, "", "Done")
    doneBtn.translation = [w - 24 - 140, 20]
    m.hsHeaderButtons = [editBtn, doneBtn]

    if m.hsSections.Count() = 0 then
        m.hsMessage.visible = true
        if m.hsLoading then
            m.hsMessage.text = "Loading Home sections…"
        else if m.hsError <> "" then
            m.hsMessage.text = "Silo couldn't refresh the Home rows. Try again when the server is reachable."
        else
            m.hsMessage.text = "Home has no populated rows to arrange yet."
        end if
        m.hsFooter.text = ""
    else
        m.hsMessage.visible = false
        y = 0
        for i = 0 to m.hsSections.Count() - 1
            sec = m.hsSections[i]
            hidden = Settings_sectionHidden(sec.id)
            row = m.hsRows.createChild("Group")
            row.translation = [0, y]
            bg = row.createChild("Poster")
            bg.uri = "pkg:/images/ui/r14.9.png"
            bg.blendColor = "0xFFFFFF12"
            bg.width = w
            bg.height = 84
            rring = row.createChild("Poster")
            rring.uri = "pkg:/images/ui/r14_ring2.9.png"
            rring.blendColor = "0xFFFFFF17"
            rring.width = w
            rring.height = 84
            title = row.createChild("Label")
            title.text = sec.title
            title.color = "0xEDEDEDFF"
            Label_setFont(title, "medium", 26)
            title.translation = [24, 12]
            title.width = w - 24 - 260
            countLbl = row.createChild("Label")
            if sec.count = 1 then countLbl.text = "1 item" else countLbl.text = sec.count.ToStr() + " items"
            countLbl.color = "0xEDEDED9E"
            Label_setFont(countLbl, "regular", 22)
            countLbl.translation = [24, 46]
            if hidden then
                title.opacity = 0.42
                countLbl.opacity = 0.42
            end if
            buttons = []
            x = w - 24 - 56
            eyeUri = "pkg:/images/icons/visibility.png"
            if hidden then eyeUri = "pkg:/images/icons/visibility_off.png"
            eye = Hs_button(row, 56, 56, eyeUri, "")
            eye.translation = [x, 14]
            if m.hsEditing then
                x = x - 56 - 12
                down = Hs_button(row, 56, 56, "pkg:/images/icons/expand_more.png", "")
                down.translation = [x, 14]
                x = x - 56 - 12
                up = Hs_button(row, 56, 56, "pkg:/images/icons/expand_more.png", "")
                upIcon = Node_find(up, "icon")
                upIcon.rotation = 3.14159265
                up.translation = [x, 14]
                buttons = [up, down, eye]
            else
                buttons = [eye]
            end if
            m.hsRowNodes.Push({ node: row, buttons: buttons, title: title })
            y = y + 92
        end for
        if m.hsEditing then
            m.hsFooter.text = "Use the arrow buttons to move rows. The new order saves immediately."
        else
            m.hsFooter.text = "Open eye: visible on Home. Closed eye: hidden. Hidden rows leave no gap."
        end if
    end if
    Hs_updateFocus()
end sub

function Hs_canMove(rowIndex as integer, col as integer) as boolean
    if col = 0 then return rowIndex > 0
    if col = 1 then return rowIndex < m.hsSections.Count() - 1
    return true
end function

sub Hs_updateFocus()
    if m.hsRow >= m.hsRowNodes.Count() then m.hsRow = m.hsRowNodes.Count() - 1
    for i = 0 to m.hsHeaderButtons.Count() - 1
        enabled = true
        if i = 0 and m.hsSections.Count() < 2 then enabled = false
        Hs_styleButton(m.hsHeaderButtons[i], m.hsRow = -1 and m.hsCol = i, enabled)
    end for
    for r = 0 to m.hsRowNodes.Count() - 1
        entry = m.hsRowNodes[r]
        for c = 0 to entry.buttons.Count() - 1
            enabled = true
            if m.hsEditing and c < 2 then enabled = Hs_canMove(r, c)
            Hs_styleButton(entry.buttons[c], m.hsRow = r and m.hsCol = c, enabled)
        end for
    end for
    ' Scroll the focused row into the 700 px viewport.
    offset = 0
    if m.hsRow >= 0 then
        rowTop = m.hsRow * 92
        if rowTop + 84 > 700 then offset = rowTop + 84 - 700
    end if
    m.hsRows.translation = [0, -offset]
end sub

' ---------- Keys ----------

function Hs_onKey(key as string) as boolean
    if key = "back" then
        Hs_close()
        return true
    end if
    rows = m.hsRowNodes.Count()
    if key = "up" then
        if m.hsRow > -1 then
            m.hsRow = m.hsRow - 1
            Hs_clampCol()
        end if
    else if key = "down" then
        if m.hsRow < rows - 1 then
            m.hsRow = m.hsRow + 1
            Hs_clampCol()
        end if
    else if key = "left" then
        if m.hsCol > 0 then m.hsCol = m.hsCol - 1
    else if key = "right" then
        if m.hsCol < Hs_colCount() - 1 then m.hsCol = m.hsCol + 1
    else if key = "OK" then
        Hs_activate()
        return true
    else
        return true
    end if
    Hs_updateFocus()
    return true
end function

function Hs_colCount() as integer
    if m.hsRow = -1 then return 2
    if m.hsRow < m.hsRowNodes.Count() then return m.hsRowNodes[m.hsRow].buttons.Count()
    return 1
end function

' Moving between the header (2 buttons) and rows (1 or 3) keeps the column in range; the eye
' (last column) stays on the eye.
sub Hs_clampCol()
    n = Hs_colCount()
    if m.hsCol >= n then m.hsCol = n - 1
    if m.hsCol < 0 then m.hsCol = 0
end sub

sub Hs_activate()
    if m.hsRow = -1 then
        if m.hsCol = 0 then
            if m.hsSections.Count() < 2 then return
            m.hsEditing = not m.hsEditing
            Hs_render()
        else
            Hs_close()
        end if
        return
    end if
    if m.hsRow >= m.hsSections.Count() then return
    sec = m.hsSections[m.hsRow]
    cols = Hs_colCount()
    if m.hsCol = cols - 1 then
        Settings_setSectionHidden(sec.id, not Settings_sectionHidden(sec.id))
        Hs_render()
    else if m.hsEditing then
        offset = 1
        if m.hsCol = 0 then offset = -1
        target = m.hsRow + offset
        if target < 0 or target >= m.hsSections.Count() then return
        swapped = m.hsSections[target]
        m.hsSections[target] = sec
        m.hsSections[m.hsRow] = swapped
        ids = []
        for each s in m.hsSections
            ids.Push(s.id)
        end for
        Settings_setSectionOrder(ids)
        ' Focus follows the moved row; at either end the only usable arrow is the other one.
        m.hsRow = target
        if target = 0 then m.hsCol = 1
        if target = m.hsSections.Count() - 1 then m.hsCol = 0
        Hs_render()
    end if
end sub
