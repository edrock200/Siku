' AuthPinDialog: remote-first four-digit PIN prompt with its own D-pad focus.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.nameLabel = m.top.findNode("name")
    m.avatar = m.top.findNode("avatar")
    m.dotsGroup = m.top.findNode("dots")
    m.status = m.top.findNode("status")
    m.keysGroup = m.top.findNode("keys")
    m.cancel = m.top.findNode("cancel")
    m.pin = ""
    m.showError = false
    m.focusIndex = 4 ' the "5" key

    m.keySize = 100
    m.gapX = 24
    m.gapY = 20
    ' Slots 0-11 in reading order; slot 9 is empty, 10 is "0", 11 is backspace.
    m.labels = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "<"]
    gridW = m.keySize * 3 + m.gapX * 2
    startX = (1920 - gridW) / 2
    m.keys = []
    m.digitFont = CreateObject("roSGNode", "Font")
    m.digitFont.uri = "pkg:/fonts/Inter-regular.otf"
    m.digitFont.size = 38
    for i = 0 to 11
        col = i mod 3
        row = i \ 3
        g = CreateObject("roSGNode", "Group")
        g.translation = [startX + col * (m.keySize + m.gapX), row * (m.keySize + m.gapY)]
        g.scaleRotateCenter = [m.keySize / 2, m.keySize / 2]
        if m.labels[i] <> "" then
            fill = g.createChild("Poster")
            fill.uri = "pkg:/images/ui/circle.png"
            fill.width = m.keySize
            fill.height = m.keySize
            ring = g.createChild("Poster")
            ring.uri = "pkg:/images/ui/circle_ring.png"
            ring.width = m.keySize
            ring.height = m.keySize
            ring.blendColor = "0xFFFFFF1A"
            if m.labels[i] = "<" then
                ico = g.createChild("Poster")
                ico.uri = "pkg:/images/icons/backspace.png"
                ico.width = 34
                ico.height = 34
                ico.translation = [33, 33]
                m.keys.Push({ group: g, fill: fill, ring: ring, icon: ico, label: invalid })
            else
                lbl = g.createChild("Label")
                lbl.font = m.digitFont
                lbl.text = m.labels[i]
                lbl.width = m.keySize
                lbl.height = m.keySize
                lbl.horizAlign = "center"
                lbl.vertAlign = "center"
                m.keys.Push({ group: g, fill: fill, ring: ring, icon: invalid, label: lbl })
            end if
        else
            m.keys.Push(invalid)
        end if
        m.keysGroup.appendChild(g)
    end for
    keypadH = m.keySize * 4 + m.gapY * 3
    m.cancelY = 448 + keypadH + 30
    m.cancel.observeField("width", "placeCancel")
    m.cancel.observeField("buttonSelected", "onCancel")
    placeCancel()

    m.dots = []
    dotSize = 26
    dotGap = 28
    dotsW = dotSize * 4 + dotGap * 3
    for i = 0 to 3
        d = CreateObject("roSGNode", "Group")
        d.translation = [(1920 - dotsW) / 2 + i * (dotSize + dotGap), 0]
        fill = d.createChild("Poster")
        fill.uri = "pkg:/images/ui/circle.png"
        fill.width = dotSize
        fill.height = dotSize
        ring = d.createChild("Poster")
        ring.uri = "pkg:/images/ui/circle_ring.png"
        ring.width = dotSize
        ring.height = dotSize
        m.dotsGroup.appendChild(d)
        m.dots.Push({ fill: fill, ring: ring })
    end for

    m.top.observeField("focusedChild", "onFocusChanged")
    renderDots()
    renderStatus()
    renderKeys()
end sub

sub placeCancel()
    m.cancel.translation = [(1920 - m.cancel.width) / 2, m.cancelY]
end sub

sub onCancel()
    m.top.dismissed = true
end sub

sub onProfile()
    p = m.top.profile
    if p = invalid then p = {}
    m.avatar.profile = p
    name = p.name
    if name = invalid then name = ""
    m.nameLabel.text = name
    m.pin = ""
    m.showError = false
    m.focusIndex = 4
    renderDots()
    renderStatus()
    renderKeys()
end sub

sub onError()
    if m.top.error <> "" then
        m.pin = ""
        m.showError = true
    else
        m.showError = false
    end if
    renderDots()
    renderStatus()
end sub

sub renderStatus()
    if m.showError and m.top.error <> "" then
        m.status.text = m.top.error
        m.status.color = "0xFF6961FF"
    else if m.top.verifying then
        m.status.text = "Checking…"
        m.status.color = "0xEDEDED9E"
    else
        m.status.text = "Enter your PIN"
        m.status.color = "0xEDEDED9E"
    end if
end sub

sub renderDots()
    errorState = m.showError and m.pin = ""
    if errorState then c = "0xFF6961" else c = "0xEDEDED"
    for i = 0 to 3
        d = m.dots[i]
        filled = errorState or i < Len(m.pin)
        d.fill.visible = filled
        d.fill.blendColor = c + "FF"
        if filled then d.ring.blendColor = c + "FF" else d.ring.blendColor = c + "B3"
    end for
end sub

sub renderKeys()
    hasFocus = m.top.isInFocusChain()
    for i = 0 to 11
        k = m.keys[i]
        if k <> invalid then
            focused = hasFocus and m.focusIndex = i
            if focused then
                k.fill.blendColor = "0xEDEDEDFF"
                k.ring.visible = false
                k.group.scale = [1.08, 1.08]
                ink = "0x000000FF"
            else
                k.fill.blendColor = "0xFFFFFF21"
                k.ring.visible = true
                k.group.scale = [1.0, 1.0]
                ink = "0xEDEDEDFF"
            end if
            if k.label <> invalid then k.label.color = ink
            if k.icon <> invalid then k.icon.blendColor = ink
        end if
    end for
end sub

sub onFocusChanged()
    ' Keep keyboard focus on this Group (or on Cancel) and redraw the keypad.
    if m.top.hasFocus() and m.focusIndex = 12 then m.cancel.setFocus(true)
    renderKeys()
end sub

sub pressKey(i as integer)
    label = m.labels[i]
    if label = "<" then
        if m.pin <> "" and not m.top.verifying then
            m.pin = Left(m.pin, Len(m.pin) - 1)
            renderDots()
        end if
        return
    end if
    if label = "" or m.top.verifying then return
    if Len(m.pin) >= 4 then return
    if m.showError then
        m.showError = false
        renderStatus()
    end if
    m.pin = m.pin + label
    renderDots()
    if Len(m.pin) = 4 then m.top.pinEntered = m.pin
end sub

sub moveTo(i as integer)
    m.focusIndex = i
    if i = 12 then
        m.cancel.setFocus(true)
    else
        m.top.setFocus(true)
    end if
    renderKeys()
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "back" then
        m.top.dismissed = true
        return true
    end if
    i = m.focusIndex
    if i = 12 then
        if key = "OK" then
            m.top.dismissed = true
        else if key = "up" then
            moveTo(10)
        end if
        return true
    end if
    col = i mod 3
    row = i \ 3
    if key = "OK" then
        pressKey(i)
    else if key = "left" then
        if col > 0 and m.keys[i - 1] <> invalid then moveTo(i - 1)
    else if key = "right" then
        if col < 2 then moveTo(i + 1)
    else if key = "up" then
        if row > 0 then
            target = i - 3
            if m.keys[target] = invalid then target = target + 1
            moveTo(target)
        end if
    else if key = "down" then
        if row < 3 then
            target = i + 3
            if m.keys[target] = invalid then target = target + 1
            moveTo(target)
        else
            moveTo(12)
        end if
    else if key = "replay" then
        pressKey(11)
    end if
    return true
end function
