' The diagnostics log viewer (see DiagnosticsScreen.xml).
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    Label_setFont(m.top.findNode("title"), "black", 41)
    Label_setFont(m.top.findNode("hint"), "regular", 22)
    m.position = m.top.findNode("position")
    m.empty = m.top.findNode("empty")
    Label_setFont(m.position, "regular", 22)
    Label_setFont(m.empty, "regular", 24)
    m.visibleRows = 26
    m.rows = []
    group = m.top.findNode("lines")
    for i = 0 to m.visibleRows - 1
        lbl = group.createChild("Label")
        lbl.translation = [0, i * 30]
        lbl.width = 1720
        lbl.height = 30
        lbl.color = "0xEDEDEDCC"
        Label_setFont(lbl, "regular", 22)
        m.rows.Push(lbl)
    end for
    m.lines = []
    m.first = 0
    m.task = m.global.diagTask
    if m.task <> invalid then
        m.task.observeField("logText", "onLogText")
        m.task.command = { action: "read" }
    end if
end sub

sub onScreenShown()
    m.top.setFocus(true)
    A11y_say("diag-log", Tx("Diagnostics Log"), "", 0, 0)
end sub

sub onScreenHidden()
    if m.task <> invalid then m.task.unobserveField("logText")
end sub

sub onLogText()
    ' 130 characters fit the 1720 px width at 22 px; the newest 1500 lines are shown.
    m.lines = Diag_viewLines(m.task.logText, 130, 1500)
    m.first = m.lines.Count() - m.visibleRows
    if m.first < 0 then m.first = 0
    render()
end sub

sub render()
    for i = 0 to m.visibleRows - 1
        k = m.first + i
        if k < m.lines.Count() then m.rows[i].text = m.lines[k] else m.rows[i].text = ""
    end for
    m.empty.visible = m.lines.Count() = 0
    if m.lines.Count() = 0 then
        m.position.text = ""
    else
        last = m.first + m.visibleRows
        if last > m.lines.Count() then last = m.lines.Count()
        m.position.text = TxF("Lines {0}–{1} of {2}", [m.first + 1, last, m.lines.Count()])
    end if
end sub

sub scrollBy(delta as integer)
    maxFirst = m.lines.Count() - m.visibleRows
    if maxFirst < 0 then maxFirst = 0
    n = m.first + delta
    if n < 0 then n = 0
    if n > maxFirst then n = maxFirst
    if n = m.first then return
    m.first = n
    render()
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "up" then
        scrollBy(-1)
        return true
    else if key = "down" then
        scrollBy(1)
        return true
    else if key = "rewind" or key = "left" then
        scrollBy(-(m.visibleRows - 1))
        return true
    else if key = "fastforward" or key = "right" then
        scrollBy(m.visibleRows - 1)
        return true
    end if
    return false
end function
