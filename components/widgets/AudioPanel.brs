' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.titleLabel = m.top.findNode("panelTitle")
    m.list = m.top.findNode("panelList")
    m.list.observeField("itemSelected", "onSelected")
    m.top.observeField("focusedChild", "onFocusChanged")
end sub

sub onTitle()
    m.titleLabel.text = m.top.title
end sub

sub rebuild()
    root = CreateObject("roSGNode", "ContentNode")
    focusAt = 0
    rows = Arr_or(m.top.rows)
    for i = 0 to rows.Count() - 1
        AudioList_rowNode(root, rows[i])
        if rows[i].isCurrent = true then focusAt = i
    end for
    m.list.content = root
    if rows.Count() > 0 then m.list.jumpToItem = focusAt
end sub

' Forward focus from the panel to its list.
sub onFocusChanged()
    if m.top.hasFocus() then m.list.setFocus(true)
end sub

sub onSelected()
    rows = Arr_or(m.top.rows)
    i = m.list.itemSelected
    if i >= 0 and i < rows.Count() then m.top.chosen = Str_orEmpty(rows[i].id)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return true
    if key = "back" or key = "left" then
        m.top.dismissed = true
    end if
    ' Swallow everything while the panel is up.
    return true
end function
