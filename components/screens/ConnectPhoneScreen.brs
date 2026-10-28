' ConnectPhoneScreen: Remote Control settings and the pairing link's QR code (see the XML).
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.body = m.top.findNode("body")
    m.buttonsGroup = m.top.findNode("buttons")
    m.enabledButton = m.top.findNode("enabledButton")
    m.sealedButton = m.top.findNode("sealedButton")
    m.resetButton = m.top.findNode("resetButton")
    m.disconnectButton = m.top.findNode("disconnectButton")
    m.statusLabel = m.top.findNode("statusLabel")
    m.qr = m.top.findNode("qr")
    m.qrHint = m.top.findNode("qrHint")
    m.keyLabel = m.top.findNode("keyLabel")
    m.keyText = m.top.findNode("keyText")
    m.addressText = m.top.findNode("addressText")
    m.focusIndex = 0
    m.prefs = RemotePrefs_load()

    m.enabledButton.observeField("buttonSelected", "onEnabledPressed")
    m.sealedButton.observeField("buttonSelected", "onSealedPressed")
    m.resetButton.observeField("buttonSelected", "onResetPressed")
    m.disconnectButton.observeField("buttonSelected", "onDisconnectPressed")
    for each b in [m.enabledButton, m.sealedButton, m.resetButton, m.disconnectButton]
        b.observeField("width", "layout")
    end for
    t = RemoteControl_lanTask()
    if t <> invalid then
        t.observeField("pairingInfo", "render")
        t.observeField("status", "render")
    end if
    render()
end sub

sub onScreenShown()
    applyFocus()
end sub

sub onScreenHidden()
    t = RemoteControl_lanTask()
    if t <> invalid then
        t.unobserveField("pairingInfo")
        t.unobserveField("status")
    end if
end sub

function visibleButtons() as object
    out = [m.enabledButton]
    if m.prefs.enabled then
        out.Push(m.sealedButton)
        if m.prefs.sealed then out.Push(m.resetButton)
        if m.disconnectButton.visible then out.Push(m.disconnectButton)
    end if
    return out
end function

sub render()
    t = RemoteControl_lanTask()
    info = invalid
    st = invalid
    if t <> invalid then
        info = t.pairingInfo
        st = t.status
    end if
    server = Str_orEmpty(m.global.session.serverName)
    if server = "" then server = "your server"
    m.body.text = "Control Siku from Silo's app on your phone or tablet: start a title, pause, seek, and change audio and subtitles. On the phone, sign in to " + server + ", tap the cast button, and choose this Roku, or scan this code with the phone's camera."

    if m.prefs.enabled then m.enabledButton.text = "Remote Control: On" else m.enabledButton.text = "Remote Control: Off"
    if m.prefs.sealed then m.sealedButton.text = "Require pairing: On" else m.sealedButton.text = "Require pairing: Off"
    m.sealedButton.visible = m.prefs.enabled
    m.resetButton.visible = m.prefs.enabled and m.prefs.sealed
    phones = []
    if st <> invalid then
        for each c in Arr_or(st.controllers)
            if not Lan_flag(c.passive) then phones.Push(Str_orEmpty(c.name))
        end for
    end if
    m.disconnectButton.visible = m.prefs.enabled and phones.Count() > 0
    if phones.Count() = 1 then
        m.disconnectButton.text = "Disconnect " + phones[0]
    else
        m.disconnectButton.text = "Disconnect " + phones.Count().ToStr() + " phones"
    end if

    status = ""
    ready = info <> invalid and Lan_flag(info.listening)
    if not m.prefs.enabled then
        status = "Remote Control is off. Phones can't find or control this Roku."
    else if not ready then
        status = "Starting…"
    else
        status = "Listening at " + Str_orEmpty(info.ip) + ":" + Str_orEmpty(info.port) + "."
        if st <> invalid and Str_orEmpty(st.mdns) = "ok" then
            status = status + " Phones on this network can find this Roku by themselves."
        else if st <> invalid and Str_orEmpty(st.mdns) = "unavailable" then
            status = status + " This Roku can't announce itself on the network, so scan the code to add it."
        end if
        if m.prefs.sealed then
            status = status + " Only a phone that scanned this code can connect."
        else
            status = status + " Without pairing, any device on this network that names " + server + " can connect."
        end if
    end if
    m.statusLabel.text = status

    showCode = m.prefs.enabled and ready
    m.qr.visible = showCode
    m.keyLabel.visible = showCode and m.prefs.sealed
    m.keyText.visible = showCode and m.prefs.sealed
    m.addressText.visible = showCode
    if showCode then
        if m.qr.text <> Str_orEmpty(info.link) then m.qr.text = Str_orEmpty(info.link)
        m.keyText.text = Str_orEmpty(info.keyText)
        m.addressText.text = Str_orEmpty(info.ip) + ":" + Str_orEmpty(info.port)
        m.qrHint.text = "Scan with your phone's camera to add this Roku to Silo"
    else
        m.qrHint.text = ""
    end if
    layout()
    applyFocus()
end sub

function Lan_flag(v as dynamic) as boolean
    t = Type(v)
    if t = "Boolean" or t = "roBoolean" then return v
    return false
end function

sub layout()
    y = 104 + Int(Label_height(m.body)) + 40
    m.buttonsGroup.translation = [0, y]
    by = 0
    for each b in visibleButtons()
        b.translation = [0, by]
        by = by + 96
    end for
    m.statusLabel.translation = [0, y + by + 20]
end sub

sub applyFocus()
    btns = visibleButtons()
    if m.focusIndex >= btns.Count() then m.focusIndex = btns.Count() - 1
    if m.focusIndex < 0 then m.focusIndex = 0
    btn = btns[m.focusIndex]
    if m.top.active then btn.setFocus(true)
end sub

sub savePrefs()
    RemotePrefs_save(m.prefs)
    render()
end sub

sub onEnabledPressed()
    m.prefs.enabled = not m.prefs.enabled
    savePrefs()
end sub

sub onSealedPressed()
    m.prefs.sealed = not m.prefs.sealed
    savePrefs()
end sub

sub onResetPressed()
    t = RemoteControl_lanTask()
    if t <> invalid then t.command = { kind: "resetKey" }
    m.global.toast = "New pairing code. Phones paired before have to scan it again."
end sub

sub onDisconnectPressed()
    rc = RemoteControl_node()
    if rc <> invalid then rc.disconnectAll = true
    m.focusIndex = 0
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    btns = visibleButtons()
    if key = "up" and m.focusIndex > 0 then
        m.focusIndex = m.focusIndex - 1
        applyFocus()
        return true
    else if key = "down" and m.focusIndex < btns.Count() - 1 then
        m.focusIndex = m.focusIndex + 1
        applyFocus()
        return true
    end if
    return false
end function
