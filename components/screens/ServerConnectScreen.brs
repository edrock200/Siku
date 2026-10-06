' ServerConnectScreen: type a Silo server address, probe it over /api/v2, save it.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.chrome = m.top.findNode("chrome")
    m.copy = m.top.findNode("copy")
    m.headline = m.top.findNode("headline")
    m.body = m.top.findNode("body")
    m.field = m.top.findNode("field")
    m.errorLabel = m.top.findNode("error")
    m.chipsGroup = m.top.findNode("chips")
    m.chips = [m.top.findNode("chipHttps"), m.top.findNode("chipHttp"), m.top.findNode("chipCom")]
    m.note = m.top.findNode("note")
    m.connectButton = m.top.findNode("connect")
    m.card = m.top.findNode("card")
    m.cardBg = m.top.findNode("cardBg")
    m.cardRing = m.top.findNode("cardRing")
    m.infoCard = m.top.findNode("infoCard")
    m.infoBody = m.top.findNode("infoBody")
    m.savedCard = m.top.findNode("savedCard")
    m.savedRowsGroup = m.top.findNode("savedRows")

    m.busy = false
    m.rows = []        ' saved-server rows: {group, bg, ring, name, host, server}
    m.focusZone = "field"
    m.focusIndex = 0
    m.lastFocus = "field"
    m.confirmDialog = invalid

    di = CreateObject("roDeviceInfo")
    tvName = di.GetFriendlyName()
    if tvName = invalid or tvName = "" then tvName = "Roku"
    m.chrome.chipText = tvName

    m.field.observeField("text", "onFieldText")
    m.field.observeField("submitted", "onFieldSubmitted")
    m.connectButton.observeField("buttonSelected", "onConnectPressed")
    for each c in m.chips
        c.observeField("buttonSelected", "onChipPressed")
        c.observeField("width", "layoutChips")
    end for

    ' Prefill with the last server, if one was used before.
    saved = Session_savedServers()
    if saved.Count() > 0 and saved[0].url <> invalid then m.field.text = saved[0].url
    buildSavedRows(saved)
    layoutChips()
    layout()
end sub

sub onScreenShown()
    applyFocus()
end sub

sub onScreenHidden()
    Api_cancelAll()
end sub

' ---------- Layout ----------

sub layoutChips()
    x = 0
    for each c in m.chips
        c.translation = [x, 0]
        x = x + c.width + 14
    end for
end sub

sub layout()
    ' Copy column: stacked, then centered vertically in the body area (124..1020).
    y = 0
    m.headline.translation = [0, y]
    y = y + Int(m.headline.boundingRect().height) + 22
    m.body.translation = [0, y]
    y = y + Int(m.body.boundingRect().height) + 40
    m.field.translation = [0, y]
    y = y + 84
    if m.errorLabel.visible then
        y = y + 16
        m.errorLabel.translation = [0, y]
        y = y + Int(m.errorLabel.boundingRect().height)
    end if
    y = y + 22
    m.chipsGroup.translation = [0, y]
    y = y + 61 + 18
    m.note.translation = [0, y]
    y = y + Int(m.note.boundingRect().height) + 40
    m.connectButton.translation = [0, y]
    y = y + 76
    top = 124 + (896 - y) \ 2
    if top < 124 then top = 124
    m.copy.translation = [90, top]

    ' Card.
    if m.rows.Count() > 0 then
        h = 158 + m.rows.Count() * 96 + (m.rows.Count() - 1) * 14 + 52
    else
        m.infoBody.translation = [52, 198 + Int(infoTitleHeight()) + 18]
        h = 198 + Int(infoTitleHeight()) + 18 + Int(m.infoBody.boundingRect().height) + 52
    end if
    m.cardBg.height = h
    m.cardRing.height = h
    m.card.translation = [1190, 124 + (896 - h) \ 2]
end sub

function infoTitleHeight() as float
    t = m.top.findNode("infoTitle")
    return t.boundingRect().height
end function

sub buildSavedRows(saved as object)
    m.rows = []
    m.savedRowsGroup.removeChildrenIndex(m.savedRowsGroup.getChildCount(), 0)
    nameFont = CreateObject("roSGNode", "Font")
    nameFont.uri = "pkg:/fonts/Inter-semibold.otf"
    nameFont.size = 29
    hostFont = CreateObject("roSGNode", "Font")
    hostFont.uri = "pkg:/fonts/Inter-regular.otf"
    hostFont.size = 22
    y = 0
    for each srv in saved
        if srv <> invalid and not Str_isEmpty(srv.url) and m.rows.Count() < 4 then
            g = m.savedRowsGroup.createChild("Group")
            g.translation = [0, y]
            g.focusable = true
            bg = g.createChild("Poster")
            bg.uri = "pkg:/images/ui/r20.9.png"
            bg.width = 536
            bg.height = 96
            ring = g.createChild("Poster")
            ring.uri = "pkg:/images/ui/r20_ring2.9.png"
            ring.width = 536
            ring.height = 96
            ring.blendColor = "0xFFFFFF24"
            icon = g.createChild("Poster")
            icon.uri = "pkg:/images/icons/dns.png"
            icon.width = 36
            icon.height = 36
            icon.translation = [26, 30]
            nm = g.createChild("Label")
            nm.font = nameFont
            nm.translation = [82, 14]
            nm.width = 430
            nm.height = 38
            name = Str_orEmpty(srv.name)
            if name = "" then name = Url_host(srv.url)
            nm.text = name
            host = g.createChild("Label")
            host.font = hostFont
            host.translation = [82, 52]
            host.width = 430
            host.height = 30
            host.text = srv.url
            m.rows.Push({ group: g, bg: bg, ring: ring, icon: icon, name: nm, host: host, server: srv })
            y = y + 96 + 14
        end if
    end for
    m.savedCard.visible = m.rows.Count() > 0
    m.infoCard.visible = m.rows.Count() = 0
    renderRows()
end sub

sub renderRows()
    for i = 0 to m.rows.Count() - 1
        r = m.rows[i]
        focused = (m.focusZone = "saved" and m.focusIndex = i)
        if focused then
            r.bg.blendColor = "0xEDEDEDFF"
            r.ring.visible = false
            r.name.color = "0x000000FF"
            r.host.color = "0x00000099"
            r.icon.blendColor = "0x000000FF"
        else
            r.bg.blendColor = "0xFFFFFF14"
            r.ring.visible = true
            r.name.color = "0xEDEDEDFF"
            r.host.color = "0xEDEDED66"
            r.icon.blendColor = "0xEDEDED9E"
        end if
    end for
end sub

' ---------- State ----------

sub onFieldText()
    clearError()
    t = LCase(m.field.text.Trim())
    if Left(t, 7) = "http://" then
        m.note.text = "This address uses unencrypted HTTP. Fine on a trusted home network; avoid it on public Wi-Fi."
        m.note.color = "0xF4C869FF"
    else
        m.note.text = "Secure HTTPS is tried automatically."
        m.note.color = "0xEDEDED66"
    end if
    layout()
end sub

sub showError(msg as string)
    m.errorLabel.text = msg
    m.errorLabel.visible = true
    m.field.error = true
    layout()
end sub

sub clearError()
    if not m.errorLabel.visible then return
    m.errorLabel.visible = false
    m.field.error = false
    layout()
end sub

sub setBusy(busy as boolean)
    m.busy = busy
    if busy then m.connectButton.text = "Connecting…" else m.connectButton.text = "Connect"
    m.field.disabled = busy
end sub

' ---------- Focus ----------

sub applyFocus()
    if m.focusZone = "field" then
        m.field.setFocus(true)
    else if m.focusZone = "chips" then
        m.chips[m.focusIndex].setFocus(true)
    else if m.focusZone = "connect" then
        m.connectButton.setFocus(true)
    else if m.focusZone = "saved" and m.rows.Count() > 0 then
        m.rows[m.focusIndex].group.setFocus(true)
    end if
    renderRows()
end sub

sub focusOn(zone as string, index = 0 as integer)
    if zone <> "saved" then m.lastFocus = zone
    m.focusZone = zone
    m.focusIndex = index
    applyFocus()
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    z = m.focusZone
    if key = "back" then return false
    if z = "field" then
        if key = "down" then
            focusOn("chips", 0)
        else if key = "right" and m.rows.Count() > 0 then
            focusOn("saved", 0)
        end if
        return true
    else if z = "chips" then
        if key = "up" then
            focusOn("field")
        else if key = "down" then
            focusOn("connect")
        else if key = "left" and m.focusIndex > 0 then
            focusOn("chips", m.focusIndex - 1)
        else if key = "right" then
            if m.focusIndex < m.chips.Count() - 1 then
                focusOn("chips", m.focusIndex + 1)
            else if m.rows.Count() > 0 then
                m.lastFocus = "chips"
                focusOn("saved", 0)
            end if
        end if
        return true
    else if z = "connect" then
        if key = "up" then
            focusOn("chips", 0)
        else if key = "right" and m.rows.Count() > 0 then
            focusOn("saved", 0)
        end if
        return true
    else if z = "saved" then
        if key = "up" and m.focusIndex > 0 then
            focusOn("saved", m.focusIndex - 1)
        else if key = "down" and m.focusIndex < m.rows.Count() - 1 then
            focusOn("saved", m.focusIndex + 1)
        else if key = "left" then
            focusOn(m.lastFocus, 0)
        else if key = "OK" then
            pickSaved(m.focusIndex)
        end if
        return true
    end if
    return false
end function

' ---------- Actions ----------

sub onChipPressed(event as object)
    if m.busy then return
    chip = event.getRoSGNode()
    shortcut = chip.text
    value = m.field.text
    lower = LCase(value)
    if Right(shortcut, 3) = "://" then
        if Left(lower, 7) = "http://" or Left(lower, 8) = "https://" then return
        m.field.text = shortcut + value.Trim()
    else
        m.field.text = value + shortcut
    end if
end sub

sub onFieldSubmitted()
    ' Keyboard "OK": connect right away when there is an address.
    if not Str_isEmpty(m.field.text) then
        focusOn("connect")
        startConnect(m.field.text)
    end if
end sub

sub onConnectPressed()
    startConnect(m.field.text)
end sub

sub pickSaved(i as integer)
    if m.busy then return
    srv = m.rows[i].server
    m.field.text = srv.url
    startConnect(srv.url)
end sub

sub startConnect(raw as string)
    if m.busy then return
    raw = raw.Trim()
    if raw = "" then
        showError("Enter your server address.")
        return
    end if
    clearError()
    lower = LCase(raw)
    if Left(lower, 7) = "http://" or Left(lower, 8) = "https://" then
        m.candidates = [Url_normalize(raw)]
    else if Instr(1, raw, "://") > 0 then
        showError("Use an http:// or https:// address.")
        return
    else
        m.candidates = [Url_normalize("https://" + raw), Url_normalize("http://" + raw)]
    end if
    m.candidateIndex = 0
    m.updateNeeded = false
    setBusy(true)
    probeNext()
end sub

sub probeNext()
    if m.candidateIndex >= m.candidates.Count() then
        setBusy(false)
        if m.updateNeeded then
            showError("This server needs an update to work with Siku.")
        else
            showError("Can't reach that server. Check the address and try again.")
        end if
        return
    end if
    base = m.candidates[m.candidateIndex]
    Api_call({ method: "GET", path: "/api/v2/system/info", baseUrl: base, auth: false, profile: false, timeout: 8, context: { base: base } }, "onInfo")
end sub

sub onInfo(event as object)
    resp = Api_result(event)
    base = resp.context.base
    if resp.ok and resp.data <> invalid and Type(resp.data) = "roAssociativeArray" then
        if isApiMajor2(resp.data.api_major) then
            onReachable(base)
            return
        end if
        ' Answers, but not API v2.
        m.updateNeeded = true
        m.candidateIndex = m.candidates.Count()
        probeNext()
        return
    end if
    if resp.status = 404 and resp.text <> invalid and resp.text.Trim() = "404 page not found" then
        ' A Silo server without API v2: no point trying the other scheme.
        m.updateNeeded = true
        m.candidateIndex = m.candidates.Count()
        probeNext()
        return
    end if
    m.candidateIndex = m.candidateIndex + 1
    probeNext()
end sub

sub onReachable(base as string)
    m.pendingBase = base
    if LCase(Left(base, 7)) = "http://" then
        askCleartext(base)
    else
        finishConnect()
    end if
end sub

' ---------- Cleartext consent ----------

sub askCleartext(base as string)
    scene = m.top.getScene()
    msg = "Your password and what you watch will be sent unencrypted to " + Url_host(base) + ". Only do this on a network you trust."
    dlg = CreateObject("roSGNode", "StandardMessageDialog")
    if dlg <> invalid then
        dlg.title = "Connect without encryption?"
        dlg.message = [msg]
    else
        dlg = CreateObject("roSGNode", "Dialog")
        dlg.title = "Connect without encryption?"
        dlg.message = msg
    end if
    dlg.buttons = ["Connect", "Cancel"]
    dlg.observeField("buttonSelected", "onCleartextButton")
    dlg.observeField("wasClosed", "onCleartextClosed")
    m.confirmDialog = dlg
    scene.dialog = dlg
end sub

sub onCleartextButton()
    dlg = m.confirmDialog
    if dlg = invalid then return
    choice = dlg.buttonSelected
    closeConfirm()
    if choice = 0 then
        finishConnect()
    else
        setBusy(false)
        applyFocus()
    end if
end sub

sub onCleartextClosed()
    if m.confirmDialog = invalid then return
    closeConfirm()
    setBusy(false)
    applyFocus()
end sub

sub closeConfirm()
    dlg = m.confirmDialog
    m.confirmDialog = invalid
    if dlg = invalid then return
    dlg.unobserveField("buttonSelected")
    dlg.unobserveField("wasClosed")
    dlg.close = true
    scene = m.top.getScene()
    if scene.dialog <> invalid and scene.dialog.isSameNode(dlg) then scene.dialog = invalid
end sub

' ---------- Identity and branding (best-effort), then save ----------

sub finishConnect()
    base = m.pendingBase
    m.serverId = ""
    m.serverName = ""
    m.pendingLookups = 2
    Api_call({ method: "GET", path: "/api/v2/system/identity", baseUrl: base, auth: false, profile: false, timeout: 8 }, "onIdentity")
    Api_call({ method: "GET", path: "/api/v2/theme/branding", baseUrl: base, auth: false, profile: false, timeout: 6 }, "onBranding")
end sub

sub onIdentity(event as object)
    resp = Api_result(event)
    if resp.ok and resp.data <> invalid and Type(resp.data) = "roAssociativeArray" then
        m.serverId = Str_orEmpty(resp.data.server_id)
    end if
    lookupDone()
end sub

sub onBranding(event as object)
    resp = Api_result(event)
    if resp.ok and resp.data <> invalid and Type(resp.data) = "roAssociativeArray" then
        m.serverName = Str_orEmpty(resp.data.server_name).Trim()
    end if
    lookupDone()
end sub

sub lookupDone()
    m.pendingLookups = m.pendingLookups - 1
    if m.pendingLookups > 0 then return
    base = m.pendingBase
    name = m.serverName
    if name = "" then name = Url_host(base)
    s = AA_copy(m.global.session)
    s.serverUrl = base
    s.serverOrigin = Url_origin(base)
    s.serverId = m.serverId
    s.serverName = name
    s.accessToken = ""
    s.refreshToken = ""
    s.expiresAt = 0
    s.user = {}
    s.profileId = ""
    s.profileToken = ""
    s.profileName = ""
    s.profileAvatar = ""
    Session_save(s)
    setBusy(false)
    Nav_reset("LoginScreen")
end sub

' True when api_major is 2 (JSON numbers can arrive as Integer, roInteger, LongInteger, Float or Double).
function isApiMajor2(v as dynamic) as boolean
    t = Type(v)
    if t = "String" or t = "roString" then return v.Trim() = "2"
    numeric = ["Integer", "roInt", "roInteger", "LongInteger", "roLongInteger", "Float", "roFloat", "Double", "roDouble"]
    for each n in numeric
        if t = n then return v = 2
    end for
    return false
end function
