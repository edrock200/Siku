' AuthTextField: first-run text field that edits through the Roku on-screen keyboard.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.body = m.top.findNode("body")
    m.bg = m.top.findNode("bg")
    m.ring = m.top.findNode("ring")
    m.icon = m.top.findNode("icon")
    m.value = m.top.findNode("value")
    m.dialog = invalid
    m.top.focusable = true
    m.top.observeField("focusedChild", "render")
    layout()
end sub

sub layout()
    w = m.top.fieldWidth
    m.bg.width = w
    m.ring.width = w
    m.body.scaleRotateCenter = [w / 2, 42]
    render()
end sub

sub render()
    focused = m.top.hasFocus()
    hasIcon = m.top.iconUri <> ""
    textX = 30
    if hasIcon then
        m.icon.uri = m.top.iconUri
        m.icon.visible = true
        textX = 30 + 32 + 18
    else
        m.icon.visible = false
    end if
    m.value.translation = [textX, 0]
    m.value.width = m.top.fieldWidth - textX - 30

    t = m.top.text
    empty = (t = "")
    if empty then
        m.value.text = m.top.placeholder
    else if m.top.secure and not m.top.revealed then
        dots = ""
        for i = 1 to Len(t)
            dots = dots + "•"
        end for
        m.value.text = dots
    else
        m.value.text = t
    end if

    if focused then
        m.bg.blendColor = "0xEDEDEDFF"
        m.ring.visible = false
        m.icon.blendColor = "0x00000073"       ' black 45%
        if empty then m.value.color = "0x00000066" else m.value.color = "0x000000FF"
        m.body.scale = [1.04, 1.04]
    else
        if m.top.error then m.bg.blendColor = "0xFFFFFF0F" else m.bg.blendColor = "0xFFFFFF14"
        m.ring.visible = true
        if m.top.error then m.ring.blendColor = "0xFF6961BF" else m.ring.blendColor = "0xFFFFFF1F"
        m.icon.blendColor = "0xEDEDED66"
        if empty then m.value.color = "0xEDEDED66" else m.value.color = "0xEDEDEDFF"
        m.body.scale = [1.0, 1.0]
    end if
    if m.top.disabled then m.body.opacity = 0.5 else m.body.opacity = 1.0
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if press and key = "OK" then
        if not m.top.disabled then openKeyboard()
        return true
    end if
    return false
end function

' ---------- Keyboard ----------

sub openKeyboard()
    scene = m.top.getScene()
    if scene = invalid then return
    dlg = CreateObject("roSGNode", "StandardKeyboardDialog")
    if dlg <> invalid then
        m.dialogKind = "standard"
        dlg.title = m.top.placeholder
        dlg.text = m.top.text
        dlg.buttons = ["OK", "Cancel"]
        if m.top.secure then
            dlg.keyboardDomain = "password"
            editBox = dlg.textEditBox
            if editBox <> invalid then editBox.secureMode = not m.top.revealed
        end if
    else
        dlg = CreateObject("roSGNode", "KeyboardDialog")
        if dlg = invalid then return
        m.dialogKind = "legacy"
        dlg.title = m.top.placeholder
        dlg.text = m.top.text
        dlg.buttons = ["OK", "Cancel"]
        if m.top.secure and dlg.keyboard <> invalid and dlg.keyboard.textEditBox <> invalid then
            dlg.keyboard.textEditBox.secureMode = not m.top.revealed
        end if
    end if
    dlg.observeField("buttonSelected", "onKeyboardButton")
    dlg.observeField("wasClosed", "onKeyboardClosed")
    m.dialog = dlg
    scene.dialog = dlg
end sub

sub onKeyboardButton()
    dlg = m.dialog
    if dlg = invalid then return
    if dlg.buttonSelected = 0 then
        m.top.text = dlg.text
        closeKeyboard()
        m.top.submitted = true
    else
        closeKeyboard()
    end if
end sub

sub onKeyboardClosed()
    ' Back closes the keyboard without a button.
    if m.dialog <> invalid then
        m.dialog.unobserveField("buttonSelected")
        m.dialog.unobserveField("wasClosed")
        m.dialog = invalid
        m.top.setFocus(true)
    end if
end sub

sub closeKeyboard()
    dlg = m.dialog
    if dlg = invalid then return
    m.dialog = invalid
    dlg.unobserveField("buttonSelected")
    dlg.unobserveField("wasClosed")
    dlg.close = true
    scene = m.top.getScene()
    if scene <> invalid and scene.dialog <> invalid and scene.dialog.isSameNode(dlg) then scene.dialog = invalid
    m.top.setFocus(true)
end sub
