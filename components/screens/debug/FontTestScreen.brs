' SPDX-License-Identifier: AGPL-3.0-or-later
' Round 2: exact clones of the capsule widgets that draw blank on a real Roku (top-bar tab,
' Search chip, Calendar badge) next to the PillButton pattern that works, then one-property
' variations of the tab. Whichever rows are blank isolate the failing property.

sub init()
    y = 60
    m.top.findNode("hdr").text = "Round 2: capsule clones. Blank text = failing setup."

    ' A: tab clone — exactly as ShellTopBar.tabNode + rebuild + applyState (unselected state).
    y = addRow(y, "A tab clone (bg.height set before width; label width 0 then w)", "tab", "A tab clone")
    ' B: tab clone but the label width is set only once (no width=0 step).
    y = addRow(y, "B tab clone, no width=0 step", "tabNoZero", "B no zero")
    ' C: tab clone, selected state (bg visible, solid fill) like the broken tabs showed.
    y = addRow(y, "C tab clone, selected (solid bg)", "tabSelected", "C selected")
    ' D: tab clone but bg.width set BEFORE bg.height.
    y = addRow(y, "D tab clone, width before height", "tabWidthFirst", "D width first")
    ' E: Search chip clone (label created with CreateObject, appended after posters).
    y = addRow(y, "E search chip clone", "chip", "E chip")
    ' F: PillButton pattern (XML-style: posters then label all pre-existing, widths set together).
    y = addRow(y, "F pill pattern (known to work)", "pill", "F pill")
    ' G: plain 9-patch fill stretched to 400x60 with NO label at all (does the capsule stretch?).
    y = addRow(y, "G 9-patch alone, 400x60, no label", "patchOnly", "")
    ' H: tab clone with the ring poster removed.
    y = addRow(y, "H tab clone without ring", "tabNoRing", "H no ring")

    ' Round 3: the real screens re-run applyState on every focus change, replacing each label's
    ' Font with a new node each time. Mutate rows A and E the same way once a second.
    m.mutants = m.top.findNode("mutants")
    m.tick = 0
    m.timer = m.top.findNode("mutateTimer")
    m.timer.observeField("fire", "onMutate")
    m.timer.control = "start"

    di = CreateObject("roDeviceInfo")
    m.top.findNode("report").translation = [100, y + 20]
    m.top.findNode("report").text = "OS " + di.GetOSVersion().major + "." + di.GetOSVersion().minor + " model " + di.GetModel() + ". Photograph this screen."
end sub

' Draws a caption on the left and the test capsule at x=900; returns the next y.
function addRow(y as integer, caption as string, kind as string, text as string) as integer
    cap = m.top.createChild("Label")
    cap.translation = [100, y]
    cap.width = 760
    cap.height = 60
    cap.vertAlign = "center"
    cap.color = "0xEDEDED9E"
    Label_setFont(cap, "regular", 22)
    cap.text = caption

    g = m.top.createChild("Group")
    g.translation = [900, y]
    g.id = "row_" + kind
    h = 60
    if kind = "tab" or kind = "tabNoZero" or kind = "tabSelected" or kind = "tabWidthFirst" or kind = "tabNoRing" then
        bg = g.createChild("Poster")
        bg.uri = "pkg:/images/ui/r30.9.png"
        if kind = "tabWidthFirst" then bg.width = 300
        bg.height = h
        if kind <> "tabNoRing" then
            ring = g.createChild("Poster")
            ring.uri = "pkg:/images/ui/r30_ring2.9.png"
            ring.height = h
        end if
        lbl = g.createChild("Label")
        lbl.height = h
        lbl.vertAlign = "center"
        lbl.horizAlign = "center"
        Label_setFont(lbl, "semibold", 26)
        ' rebuild():
        Label_setFont(lbl, "semibold", 26)
        lbl.text = text
        if kind <> "tabNoZero" then lbl.width = 0
        tw = Int(Label_width(lbl))
        w = tw + 29 * 2
        bg.width = w
        if kind <> "tabNoRing" then ring.width = w
        lbl.width = w
        lbl.translation = [0, 0]
        ' applyState():
        c = Theme().colors
        if kind = "tabSelected" then
            bg.visible = true
            bg.blendColor = c.ink
            if kind <> "tabNoRing" then ring.visible = false
            lbl.color = c.onInk
            Label_setFont(lbl, "semibold", 26)
        else
            bg.visible = false
            if kind <> "tabNoRing" then ring.visible = false
            lbl.color = c.inkMuted
            Label_setFont(lbl, "medium", 26)
        end if
    else if kind = "chip" then
        lbl = CreateObject("roSGNode", "Label")
        Label_setFont(lbl, "medium", 24)
        lbl.text = text
        w = Int(Label_width(lbl)) + 80
        bg = g.createChild("Poster")
        bg.uri = "pkg:/images/ui/r28.9.png"
        bg.width = w
        bg.height = 56
        bg.blendColor = "0xFFFFFF14"
        ring = g.createChild("Poster")
        ring.uri = "pkg:/images/ui/r28_ring2.9.png"
        ring.width = w
        ring.height = 56
        ring.blendColor = "0xFFFFFF1F"
        lbl.width = w
        lbl.height = 56
        lbl.horizAlign = "center"
        lbl.vertAlign = "center"
        lbl.color = "0xEDEDEDFF"
        g.appendChild(lbl)
    else if kind = "pill" then
        bg = g.createChild("Poster")
        ring = g.createChild("Poster")
        lbl = g.createChild("Label")
        lbl.vertAlign = "center"
        lbl.horizAlign = "center"
        f = CreateObject("roSGNode", "Font")
        f.uri = "pkg:/fonts/Inter-semibold.otf"
        lbl.font = f
        f.size = 25
        lbl.text = text
        lbl.width = 0
        tw = Label_width(lbl)
        w = tw + 80
        bg.uri = "pkg:/images/ui/r30.9.png"
        ring.uri = "pkg:/images/ui/r30_ring2.9.png"
        bg.width = w
        bg.height = h
        ring.width = w
        ring.height = h
        bg.blendColor = "0xFFFFFF14"
        ring.blendColor = "0xFFFFFF24"
        lbl.translation = [(w - tw) / 2, 0]
        lbl.width = tw + 2
        lbl.height = h
        lbl.color = "0xEDEDEDFF"
    else if kind = "patchOnly" then
        bg = g.createChild("Poster")
        bg.uri = "pkg:/images/ui/r30.9.png"
        bg.width = 400
        bg.height = h
        bg.blendColor = "0xFFFFFF60"
    end if
    return y + 76
end function

sub onScreenShown()
    m.top.setFocus(true)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    ' Parameters are part of the SceneGraph signature; this screen handles no keys itself.
    if key = "" and press then return false
    return false
end function

' Re-fonts and recolours the tab and chip clones every second, like the live top bar does
' on each focus change. If they go blank after a few ticks, repeated Font replacement is the bug.
sub onMutate()
    m.tick = m.tick + 1
    c = Theme().colors
    for each kind in ["tab", "tabNoZero", "tabWidthFirst", "tabNoRing", "chip"]
        g = m.top.findNode("row_" + kind)
        if g <> invalid then
            lbl = invalid
            for i = 0 to g.getChildCount() - 1
                ch = g.getChild(i)
                if ch.subtype() = "Label" then lbl = ch
            end for
            if lbl <> invalid then
                if (m.tick mod 2) = 0 then
                    Label_setFont(lbl, "semibold", 26)
                    lbl.color = c.ink
                else
                    Label_setFont(lbl, "medium", 26)
                    lbl.color = c.inkMuted
                end if
            end if
        end if
    end for
    m.top.findNode("hdr").text = "Round 3: rows re-fonted " + m.tick.ToStr() + " times (live app does this per focus move)."
end sub
