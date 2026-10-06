' SPDX-License-Identifier: AGPL-3.0-or-later
' Each case changes one thing. Whichever rows are blank on a real Roku identify the culprit.

sub init()
    lines = []

    ' 3: code Font, text set, width never touched (like PillButton minus the width dance).
    l = m.top.findNode("t3")
    Label_setFont(l, "semibold", 30)
    l.text = "3 code font, no width"
    lines.Push("t3 w=" + Str(l.boundingRect().width))

    ' 4: code Font, width 0 then restored to a positive width, center aligned (tab pattern).
    l = m.top.findNode("t4")
    Label_setFont(l, "semibold", 30)
    l.text = "4 code font, width 0 then 600, center"
    l.width = 0
    w = Label_width(l)
    l.width = 600
    l.horizAlign = "center"
    l.height = 60
    l.vertAlign = "center"
    lines.Push("t4 measured=" + Str(w))

    ' 5: as 4, but the Font is replaced AFTER width/text are set (applyState pattern).
    l = m.top.findNode("t5")
    Label_setFont(l, "medium", 30)
    l.text = "5 code font replaced after layout"
    l.width = 600
    l.height = 60
    l.horizAlign = "center"
    l.vertAlign = "center"
    Label_setFont(l, "semibold", 30)

    ' 6: code Font set BEFORE text, left aligned, explicit positive width only.
    l = m.top.findNode("t6")
    Label_setFont(l, "semibold", 30)
    l.width = 600
    l.height = 60
    l.vertAlign = "center"
    l.text = "6 code font, width 600, left"

    ' 7: Font created via CreateObject and assigned, then uri/size set AFTER assignment.
    l = m.top.findNode("t7")
    f = CreateObject("roSGNode", "Font")
    l.font = f
    f.uri = "pkg:/fonts/Inter-semibold.otf"
    f.size = 30
    l.text = "7 font props set after assignment"
    l.width = 600
    l.height = 60
    l.vertAlign = "center"

    ' 8: Label created in code (CreateObject) and appended, like the Search chips.
    l = CreateObject("roSGNode", "Label")
    Label_setFont(l, "semibold", 30)
    l.text = "8 label created in code, appended"
    l.width = 600
    l.height = 60
    l.horizAlign = "center"
    l.vertAlign = "center"
    l.color = "0xEDEDEDFF"
    l.translation = [100, 600]
    m.top.appendChild(l)
    m.top.findNode("t8").visible = false

    di = CreateObject("roDeviceInfo")
    lines.Push("OS " + di.GetOSVersion().major + "." + di.GetOSVersion().minor + " model " + di.GetModel())
    m.top.findNode("report").text = "Photograph this screen. Rows that are blank identify the failing Label setup. " + Str_joinDots(lines)
end sub

sub onScreenShown()
    m.top.setFocus(true)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    return false
end function
