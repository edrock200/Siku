' ServerConnectScreen: type a Silo server address (or pick one found on this network), probe it
' over /api/v2, save it.
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
    m.findButton = m.top.findNode("find")
    m.advToggle = m.top.findNode("advToggle")
    m.advRow = m.top.findNode("advRow")
    m.schemeButtons = [m.top.findNode("schemeAuto"), m.top.findNode("schemeHttps"), m.top.findNode("schemeHttp")]
    m.schemeIds = ["auto", "https", "http"]
    m.portField = m.top.findNode("portField")
    m.scheme = "auto"
    m.showAdv = false
    m.manage = false
    m.setupDone = false
    m.savedPick = invalid   ' a saved server picked from the card: {url, name, id, session?}
    m.lastServerMessage = ""
    m.foundCard = m.top.findNode("foundCard")
    m.foundStatus = m.top.findNode("foundStatus")
    m.foundRowsGroup = m.top.findNode("foundRows")
    m.card = m.top.findNode("card")
    m.cardBg = m.top.findNode("cardBg")
    m.cardRing = m.top.findNode("cardRing")
    m.infoCard = m.top.findNode("infoCard")
    m.infoBody = m.top.findNode("infoBody")
    m.savedCard = m.top.findNode("savedCard")
    m.savedRowsGroup = m.top.findNode("savedRows")

    m.busy = false
    m.rows = []        ' saved-server rows: {group, bg, ring, name, host, server}
    m.found = []       ' found-server rows, same shape; server = {name, url, address, port, serverId}
    m.foundTop = 0     ' first found row shown (the list scrolls when the card is full)
    m.foundSlots = 0
    m.scan = invalid   ' {token, status, servers, note, noteIsError} once a scan has run
    m.scanSeq = 0
    m.scannedOnce = false
    m.checking = invalid   ' the found server whose identity is being checked
    m.expectedServerId = ""   ' a found server's id: the connect flow must see the same one
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
    m.findButton.observeField("buttonSelected", "onFindPressed")
    m.scanTimer = m.top.createChild("Timer")
    m.scanTimer.duration = 9
    m.scanTimer.repeat = false
    m.scanTimer.observeField("fire", "onScanTimeout")
    m.connectButton.observeField("width", "layout")
    m.advToggle.observeField("buttonSelected", "onAdvToggle")
    m.advToggle.observeField("width", "layout")
    for each b in m.schemeButtons
        b.observeField("buttonSelected", "onSchemePressed")
        b.observeField("width", "layoutAdv")
    end for
    m.portField.observeField("text", "onFieldText")
    for each c in m.chips
        c.observeField("buttonSelected", "onChipPressed")
        c.observeField("width", "layoutChips")
    end for

    buildSavedRows(Session_savedServers())
    renderScheme()
    layoutChips()
    layoutAdv()
    layout()
end sub

' Params arrive after init: Manage Servers (params.manage) or first-run setup.
sub setupMode()
    m.setupDone = true
    p = m.top.params
    m.manage = false
    if Type(p) = "roAssociativeArray" then m.manage = Lan_isTrue(p.manage)
    saved = Session_savedServers()
    if m.manage then
        m.headline.text = "Choose a server"
        m.body.text = "Switch to a saved server, or add another."
        print "[siku-servers] manage servers: " + saved.Count().ToStr() + " saved"
    else if saved.Count() > 0 and saved[0].url <> invalid then
        ' Prefill with the last server, if one was used before.
        m.field.text = saved[0].url
    end if
    buildSavedRows(saved)
    layout()
    ' Manage Servers starts on the list.
    if m.manage and m.rows.Count() > 0 then focusOn("saved", 0)
end sub

sub onScreenShown()
    if not m.setupDone then setupMode()
    Pair_start("setup")
    ' Like Android TV, servers on this network are looked for as soon as setup shows.
    if not m.scannedOnce then startScan()
    applyFocus()
end sub

sub onScreenHidden()
    Pair_stop()
    stopScan()
    Api_cancelAll()
end sub

' Phone sign-in (PhonePairing.brs): setup mode has no code of its own on screen.
function Pair_screenCode() as dynamic
    return invalid
end function

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
    y = y + Int(Label_height(m.headline)) + 22
    m.body.translation = [0, y]
    y = y + Int(Label_height(m.body)) + 40
    m.field.translation = [0, y]
    y = y + 84
    if m.errorLabel.visible then
        y = y + 16
        m.errorLabel.translation = [0, y]
        y = y + Int(Label_height(m.errorLabel))
    end if
    y = y + 22
    m.chipsGroup.translation = [0, y]
    y = y + 61 + 18
    m.note.translation = [0, y]
    y = y + Int(Label_height(m.note)) + 14
    m.advToggle.translation = [0, y]
    y = y + 61
    m.advRow.visible = m.showAdv
    if m.showAdv then
        y = y + 10
        m.advRow.translation = [0, y]
        y = y + 84
    end if
    y = y + 30
    m.connectButton.translation = [0, y]
    m.findButton.translation = [m.connectButton.width + 20, y]
    y = y + 76
    top = 124 + (896 - y) \ 2
    if top < 124 then top = 124
    m.copy.translation = [90, top]

    ' Card: saved servers (or the explanation), then what was found on this network.
    ' With a found section below, the saved list drops its hint line to leave room.
    savedTop = 158
    if m.scan <> invalid then savedTop = 110
    m.top.findNode("savedHint").visible = m.scan = invalid
    m.savedRowsGroup.translation = [52, savedTop]
    if m.rows.Count() > 0 then
        y = savedTop + m.rows.Count() * 96 + (m.rows.Count() - 1) * 14
    else
        m.infoBody.translation = [52, 198 + Int(infoTitleHeight()) + 18]
        y = 198 + Int(infoTitleHeight()) + 18 + Int(Label_height(m.infoBody))
    end if
    m.foundCard.visible = m.scan <> invalid
    if m.scan <> invalid then
        y = y + 40
        m.foundCard.translation = [52, y]
        statusH = Int(Label_height(m.foundStatus))
        rowsY = 48 + statusH + 16
        m.foundRowsGroup.translation = [0, rowsY]
        ' As many 84 px rows (12 apart) as fit in the 896 px body; the rest scroll.
        m.foundSlots = (896 - 52 - (y + rowsY) + 12) \ 96
        if m.foundSlots < 1 then m.foundSlots = 1
        placeFoundRows()
        shown = m.found.Count()
        if shown > m.foundSlots then shown = m.foundSlots
        y = y + 48 + statusH
        if shown > 0 then y = y + 16 + shown * 96 - 12
    end if
    h = y + 52
    if h > 896 then h = 896
    m.cardBg.height = h
    m.cardRing.height = h
    m.card.translation = [1190, 124 + (896 - h) \ 2]
end sub

' The protocol buttons and the Port field on one row (84 px, the field's height).
sub layoutAdv()
    x = 0
    for each b in m.schemeButtons
        b.translation = [x, 11]
        x = x + b.width + 12
    end for
    m.portField.translation = [x + 8, 0]
end sub

sub renderScheme()
    for i = 0 to m.schemeButtons.Count() - 1
        m.schemeButtons[i].selectedState = m.schemeIds[i] = m.scheme
    end for
    if m.showAdv then m.advToggle.text = "Hide advanced options" else m.advToggle.text = "Advanced options"
end sub

sub onAdvToggle()
    if m.busy then return
    m.showAdv = not m.showAdv
    renderScheme()
    layout()
    if m.showAdv then focusOn("adv", 0) else focusOn("advToggle")
end sub

sub onSchemePressed(event as object)
    if m.busy then return
    b = event.getRoSGNode()
    for i = 0 to m.schemeButtons.Count() - 1
        if m.schemeButtons[i].isSameNode(b) then m.scheme = m.schemeIds[i]
    end for
    renderScheme()
    onFieldText()
end sub

function infoTitleHeight() as float
    t = m.top.findNode("infoTitle")
    return Label_height(t)
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
        if srv <> invalid and Type(srv) = "roAssociativeArray" and not Str_isEmpty(srv.url) and m.rows.Count() < Session_maxServers() then
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
            badge = savedBadge(srv)
            if badge <> "" then host.text = badge + " · " + srv.url
            m.rows.Push({ group: g, bg: bg, ring: ring, icon: icon, name: nm, host: host, server: srv })
            y = y + 96 + 14
        end if
    end for
    m.savedCard.visible = m.rows.Count() > 0
    m.infoCard.visible = m.rows.Count() = 0
    renderRows()
end sub

' "Current", "Signed out", both, or "" (adapted from silo-roku's server list badges).
function savedBadge(srv as object) as string
    s = m.global.session
    if Str_orEmpty(srv.url) = Str_orEmpty(s.serverUrl) then
        if Str_isEmpty(s.accessToken) and Str_isEmpty(s.refreshToken) then return "Current · Signed out"
        return "Current"
    end if
    if Session_serverSignedIn(Str_orEmpty(srv.url)) then return ""
    return "Signed out"
end function

function isCurrent(srv as object) as boolean
    return Str_orEmpty(srv.url) <> "" and Str_orEmpty(srv.url) = Str_orEmpty(m.global.session.serverUrl)
end function

sub renderRows()
    renderRowList(m.rows, "saved")
    renderRowList(m.found, "found")
end sub

sub renderRowList(rows as object, zone as string)
    for i = 0 to rows.Count() - 1
        r = rows[i]
        focused = (m.focusZone = zone and m.focusIndex = i)
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
    if m.scheme = "http" or (m.scheme = "auto" and Left(t, 7) = "http://") then
        m.note.text = "This address uses unencrypted HTTP. Fine on a trusted home network; avoid it on public Wi-Fi."
        m.note.color = "0xF4C869FF"
    else if m.scheme = "https" or Left(t, 8) = "https://" then
        m.note.text = "Only secure HTTPS is tried."
        m.note.color = "0xEDEDED66"
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
    m.findButton.disabled = busy
    m.portField.disabled = busy
end sub

' ---------- Focus ----------

sub applyFocus()
    if m.focusZone = "field" then
        m.field.setFocus(true)
    else if m.focusZone = "chips" then
        m.chips[m.focusIndex].setFocus(true)
    else if m.focusZone = "advToggle" then
        m.advToggle.setFocus(true)
    else if m.focusZone = "adv" and m.showAdv then
        if m.focusIndex < 3 then m.schemeButtons[m.focusIndex].setFocus(true) else m.portField.setFocus(true)
    else if m.focusZone = "connect" then
        m.connectButton.setFocus(true)
    else if m.focusZone = "find" then
        m.findButton.setFocus(true)
    else if m.focusZone = "saved" and m.rows.Count() > 0 then
        m.rows[m.focusIndex].group.setFocus(true)
    else if m.focusZone = "found" and m.found.Count() > 0 then
        if m.focusIndex >= m.found.Count() then m.focusIndex = m.found.Count() - 1
        placeFoundRows()
        m.found[m.focusIndex].group.setFocus(true)
    else
        m.focusZone = "find"
        m.findButton.setFocus(true)
    end if
    renderRows()
end sub

' The card's first row (saved servers first), or false when the card has none.
function focusCard() as boolean
    if m.rows.Count() > 0 then
        focusOn("saved", 0)
        return true
    else if m.found.Count() > 0 then
        focusOn("found", 0)
        return true
    end if
    return false
end function

sub focusOn(zone as string, index = 0 as integer)
    if zone <> "saved" and zone <> "found" then m.lastFocus = zone
    m.focusZone = zone
    m.focusIndex = index
    applyFocus()
end sub

' The left column top to bottom: field, chips, Advanced options, its row (when shown), buttons.
function zoneBelow(z as string) as string
    if z = "field" then return "chips"
    if z = "chips" then return "advToggle"
    if z = "advToggle" then
        if m.showAdv then return "adv"
        return "connect"
    end if
    if z = "adv" then return "connect"
    return ""
end function

function zoneAbove(z as string) as string
    if z = "chips" then return "field"
    if z = "advToggle" then return "chips"
    if z = "adv" then return "advToggle"
    if z = "connect" or z = "find" then
        if m.showAdv then return "adv"
        return "advToggle"
    end if
    return ""
end function

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    z = m.focusZone
    if key = "back" then return false
    if key = "options" then
        if z = "saved" then askRemove(m.focusIndex)
        return true
    end if
    if z = "saved" then
        if key = "up" and m.focusIndex > 0 then
            focusOn("saved", m.focusIndex - 1)
        else if key = "down" and m.focusIndex < m.rows.Count() - 1 then
            focusOn("saved", m.focusIndex + 1)
        else if key = "down" and m.found.Count() > 0 then
            focusOn("found", 0)
        else if key = "left" then
            focusOn(m.lastFocus, 0)
        else if key = "OK" then
            pickSaved(m.focusIndex)
        end if
        return true
    else if z = "found" then
        if key = "up" and m.focusIndex > 0 then
            focusOn("found", m.focusIndex - 1)
        else if key = "up" and m.rows.Count() > 0 then
            focusOn("saved", m.rows.Count() - 1)
        else if key = "down" and m.focusIndex < m.found.Count() - 1 then
            focusOn("found", m.focusIndex + 1)
        else if key = "left" then
            focusOn(m.lastFocus, 0)
        else if key = "OK" then
            pickFound(m.focusIndex)
        end if
        return true
    end if
    if key = "down" then
        nz = zoneBelow(z)
        if nz <> "" then focusOn(nz, 0)
    else if key = "up" then
        nz = zoneAbove(z)
        if nz <> "" then focusOn(nz, 0)
    else if key = "left" then
        if (z = "chips" or z = "adv") and m.focusIndex > 0 then
            focusOn(z, m.focusIndex - 1)
        else if z = "find" then
            focusOn("connect")
        end if
    else if key = "right" then
        if z = "chips" and m.focusIndex < m.chips.Count() - 1 then
            focusOn("chips", m.focusIndex + 1)
        else if z = "adv" and m.focusIndex < 3 then
            focusOn("adv", m.focusIndex + 1)
        else if z = "connect" then
            focusOn("find")
        else
            m.lastFocus = z
            focusCard()
        end if
    end if
    return true
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

' A saved server: the current one goes back where it was; one with its own sign-in is checked
' (it must answer as a Silo v2 server, and as the same deployment) and switched to without a new
' sign-in; a signed-out one connects like a typed address and opens its sign-in screen.
sub pickSaved(i as integer)
    if m.busy or i < 0 or i >= m.rows.Count() then return
    srv = m.rows[i].server
    if isCurrent(srv) then
        print "[siku-servers] picked the current server"
        if m.manage and not Str_isEmpty(m.global.session.accessToken) then
            Nav_close()
        else
            Nav_reset("@start")
        end if
        return
    end if
    m.savedPick = srv
    m.field.text = srv.url
    startConnect(srv.url, "", [srv.url])
end sub

' Options (*) on a saved row: remove it (silo-roku's server list wording, AGPL-3.0).
sub askRemove(i as integer)
    if m.busy or i < 0 or i >= m.rows.Count() then return
    srv = m.rows[i].server
    name = serverLabel(srv)
    if isCurrent(srv) then
        nxt = invalid
        for each e in Session_savedServers()
            if nxt = invalid and Type(e) = "roAssociativeArray" and Str_orEmpty(e.url) <> Str_orEmpty(srv.url) then nxt = e
        end for
        who = name
        if Accounts_countOn(Str_orEmpty(srv.url)) > 1 then who = "every account on " + name
        if nxt <> invalid then
            body = "You'll be signed out of " + who + ", and this Roku will switch to " + serverLabel(nxt) + "."
        else
            body = "You'll be signed out of " + who + ", and you'll need to enter a server address again."
        end if
    else
        body = "Its accounts will be signed out on this Roku. You can add it again later."
    end if
    m.removeTarget = srv
    openConfirm("Remove " + name + "?", [body], ["Cancel", "Remove"], "onRemoveButton", "onRemoveClosed")
end sub

function serverLabel(srv as object) as string
    name = Str_orEmpty(srv.name).Trim()
    if name = "" then name = Url_host(Str_orEmpty(srv.url))
    return name
end function

sub onRemoveButton()
    dlg = m.confirmDialog
    if dlg = invalid then return
    choice = dlg.buttonSelected
    srv = m.removeTarget
    closeConfirm()
    m.removeTarget = invalid
    if choice <> 1 or srv = invalid then
        applyFocus()
        return
    end if
    if isCurrent(srv) then
        ' The active server: the one sign-out, then the next saved server or first-run setup.
        SignOut_run(true)
        return
    end if
    ' Another server: revoke its accounts' stored sign-ins (best effort), then forget it.
    SignOut_revokeServerAccounts(Str_orEmpty(srv.url), "")
    Session_forgetServer(Str_orEmpty(srv.url))
    print "[siku-servers] removed current=false"
    m.global.toast = serverLabel(srv) + " was removed."
    buildSavedRows(Session_savedServers())
    layout()
    if m.rows.Count() = 0 then
        focusOn("field")
    else
        if m.focusIndex >= m.rows.Count() then m.focusIndex = m.rows.Count() - 1
        focusOn("saved", m.focusIndex)
    end if
end sub

sub onRemoveClosed()
    if m.confirmDialog = invalid then return
    closeConfirm()
    m.removeTarget = invalid
    applyFocus()
end sub

' SignOutFlow.brs hook (this screen asks its own question).
sub SignOut_afterCancel()
    applyFocus()
end sub

' expectedId: a found server's advertised (and already checked) id, which the identity read in
' finishConnect must repeat; "" for a typed or saved address.
' exact: the addresses to probe as they are (a saved or found server), skipping Advanced options.
sub startConnect(raw as string, expectedId = "" as string, exact = invalid as dynamic)
    if m.busy then return
    m.expectedServerId = expectedId
    if exact = invalid then
        m.savedPick = invalid
        plan = ServerAddr_candidates(raw, m.scheme, m.portField.text)
        if plan.error <> "" then
            print "[siku-servers] address refused: " + plan.error
            showError(plan.error)
            return
        end if
        m.candidates = []
        for each c in plan.candidates
            m.candidates.Push(Url_normalize(c))
        end for
    else
        m.candidates = exact
    end if
    clearError()
    m.lastServerMessage = ""
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
        else if m.savedPick <> invalid then
            showError("Couldn't reach " + serverLabel(m.savedPick) + ". Check that it's on and connected, then try again.")
        else
            showError(ServerAddr_unreachableText(m.scheme, m.lastServerMessage))
        end if
        print "[siku-servers] connect failed update=" + Session_boolWord(m.updateNeeded) + " server_message=" + Session_boolWord(m.lastServerMessage <> "")
        m.savedPick = invalid
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
    ' The server's own reason, when it gave one (Silo Android #771); the last address tried decides.
    m.lastServerMessage = ServerAddr_serverMessage(resp.status, resp.error)
    m.candidateIndex = m.candidateIndex + 1
    probeNext()
end sub

sub onReachable(base as string)
    m.pendingBase = base
    ' A saved http:// server was approved when it was added (ServerConnect asked then).
    if LCase(Left(base, 7)) = "http://" and Session_savedServer(base) = invalid then
        askCleartext(base)
    else
        finishConnect()
    end if
end sub

' ---------- Cleartext consent ----------

sub askCleartext(base as string)
    msg = "Your password and what you watch will be sent unencrypted to " + Url_host(base) + ". Only do this on a network you trust."
    openConfirm("Connect without encryption?", [msg], ["Connect", "Cancel"], "onCleartextButton", "onCleartextClosed")
end sub

sub openConfirm(title as string, lines as object, buttons as object, onButton as string, onClosed as string)
    scene = m.top.getScene()
    dlg = CreateObject("roSGNode", "StandardMessageDialog")
    if dlg <> invalid then
        dlg.title = title
        dlg.message = lines
    else
        dlg = CreateObject("roSGNode", "Dialog")
        dlg.title = title
        dlg.message = lines.Join(Chr(10) + Chr(10))
    end if
    dlg.buttons = buttons
    dlg.observeField("buttonSelected", onButton)
    dlg.observeField("wasClosed", onClosed)
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
        id = Str_orEmpty(resp.data.server_id)
        ' Only a well-formed id is kept (it keys the phone features and server matching).
        if Lan_isServerId(id) then m.serverId = id
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
    if m.expectedServerId <> "" and m.serverId <> m.expectedServerId then
        ' A found server answered its identity check, then something else answered here.
        print "[siku-lan] found server's identity changed while connecting; not saved"
        m.expectedServerId = ""
        setBusy(false)
        setScanNote("Its identity changed while connecting. Search again, or type its address.", true)
        applyFocus()
        return
    end if
    name = m.serverName
    if name = "" then name = Url_host(base)
    cur = m.global.session
    if base = Str_orEmpty(cur.serverUrl) and not Str_isEmpty(cur.accessToken) then
        ' The address of the server already in use: nothing to switch.
        setBusy(false)
        m.savedPick = invalid
        print "[siku-servers] that is the current server"
        if m.manage then Nav_close() else Nav_reset("@start")
        return
    end if
    e = Session_savedServer(base)
    if e <> invalid and Session_serverSignedIn(base) then
        known = Str_orEmpty(e.id)
        if known = "" or m.serverId = "" or known = m.serverId then
            ' Switch to its most recently used account. Profile Selection asks again when it would at launch.
            c = AA_copy(e)
            c.name = name
            if m.serverId <> "" then c.id = m.serverId
            setBusy(false)
            m.savedPick = invalid
            Session_activateServer(c, ProfileLaunch_requiresSelectionAtLaunch())
            Nav_reset("@start")
            return
        end if
        ' Another deployment answers at that address now: its stored sign-in is not sent there.
        print "[siku-servers] saved server answered as another deployment; signing in again"
    end if
    m.savedPick = invalid
    s = AA_copy(m.global.session)
    s.serverUrl = base
    s.serverOrigin = Url_origin(base)
    s.serverId = m.serverId
    s.serverName = name
    s.accountId = ""
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

' ---------- Find servers on this network ----------

sub onFindPressed()
    if m.busy then return
    startScan()
end sub

function debugAllowSelf() as boolean
    p = m.top.params
    if Type(p) <> "roAssociativeArray" then return false
    return Lan_isTrue(p.debugLanSelf)
end function

sub startScan()
    m.scannedOnce = true
    m.scanSeq = m.scanSeq + 1
    token = "scan" + m.scanSeq.ToStr()
    m.scan = { token: token, status: "scanning", servers: [], note: "", noteIsError: false }
    t = RemoteControl_lanTask()
    if t = invalid then
        m.scan.status = "unavailable"
    else
        t.unobserveField("discovery")
        t.observeField("discovery", "onDiscovery")
        t.discover = { kind: "start", token: token, allowSelf: debugAllowSelf() }
    end if
    ' If the scan never reports (no LAN task, or it stopped), the screen stops waiting.
    m.scanTimer.control = "stop"
    m.scanTimer.control = "start"
    m.findButton.text = "Searching…"
    buildFoundRows()
end sub

sub stopScan()
    m.scanTimer.control = "stop"
    t = RemoteControl_lanTask()
    if t = invalid then return
    t.unobserveField("discovery")
    if m.scan <> invalid and m.scan.status = "scanning" then
        t.discover = { kind: "stop" }
        m.scan.status = "complete"
    end if
end sub

sub onScanTimeout()
    if m.scan = invalid or m.scan.status <> "scanning" then return
    print "[siku-lan] find servers: no word from the scan; showing what arrived"
    m.scan.status = "complete"
    m.findButton.text = "Find servers again"
    buildFoundRows()
end sub

sub onDiscovery(event as object)
    d = event.getData()
    if Type(d) <> "roAssociativeArray" or m.scan = invalid then return
    if Str_orEmpty(d.token) <> m.scan.token then return
    st = Str_orEmpty(d.status)
    if st = "cancelled" then return
    m.scan.status = st
    m.scan.servers = Arr_or(d.servers)
    if st <> "scanning" then
        m.findButton.text = "Find servers again"
        print "[siku-lan] find servers: " + st + ", " + m.scan.servers.Count().ToStr() + " listed"
    end if
    buildFoundRows()
end sub

sub setScanNote(text as string, isError as boolean)
    if m.scan = invalid then m.scan = { token: "", status: "complete", servers: [], note: "", noteIsError: false }
    m.scan.note = text
    m.scan.noteIsError = isError
    renderScanStatus()
    layout()
end sub

sub renderScanStatus()
    sc = m.scan
    if sc = invalid then return
    n = sc.servers.Count()
    text = ""
    if sc.note <> "" then
        text = sc.note
    else if sc.status = "scanning" then
        if n = 0 then text = "Looking for servers on this network…" else text = "Still looking. Pick one to check it and connect."
    else if sc.status = "unavailable" then
        text = "This Roku can't search the network now. Type the address instead."
    else if n = 0 then
        text = "No servers found. Type the address instead, or search again."
    else
        text = "Pick one to check it and connect."
    end if
    m.foundStatus.text = text
    if sc.noteIsError then m.foundStatus.color = "0xFF6961FF" else m.foundStatus.color = "0xEDEDED9E"
end sub

sub buildFoundRows()
    focusedUrl = ""
    hadFocus = false
    if m.focusZone = "found" and m.focusIndex < m.found.Count() then
        r = m.found[m.focusIndex]
        focusedUrl = r.server.url
        hadFocus = r.group.hasFocus()
    end if
    m.found = []
    m.foundRowsGroup.removeChildrenIndex(m.foundRowsGroup.getChildCount(), 0)
    nameFont = CreateObject("roSGNode", "Font")
    nameFont.uri = "pkg:/fonts/Inter-semibold.otf"
    nameFont.size = 27
    hostFont = CreateObject("roSGNode", "Font")
    hostFont.uri = "pkg:/fonts/Inter-regular.otf"
    hostFont.size = 22
    servers = []
    if m.scan <> invalid then servers = m.scan.servers
    for each srv in servers
        if Type(srv) = "roAssociativeArray" and not Str_isEmpty(srv.url) then
            g = m.foundRowsGroup.createChild("Group")
            g.focusable = true
            bg = g.createChild("Poster")
            bg.uri = "pkg:/images/ui/r20.9.png"
            bg.width = 536
            bg.height = 84
            ring = g.createChild("Poster")
            ring.uri = "pkg:/images/ui/r20_ring2.9.png"
            ring.width = 536
            ring.height = 84
            ring.blendColor = "0xFFFFFF24"
            icon = g.createChild("Poster")
            icon.uri = "pkg:/images/icons/dns.png"
            icon.width = 32
            icon.height = 32
            icon.translation = [26, 26]
            nm = g.createChild("Label")
            nm.font = nameFont
            nm.translation = [78, 10]
            nm.width = 434
            nm.height = 36
            name = Str_orEmpty(srv.name)
            if name = "" then name = "Server"
            nm.text = name
            host = g.createChild("Label")
            host.font = hostFont
            host.translation = [78, 46]
            host.width = 434
            host.height = 28
            host.text = srv.url
            if m.checking <> invalid and m.checking.url = srv.url then host.text = "Checking " + srv.url + "…"
            m.found.Push({ group: g, bg: bg, ring: ring, icon: icon, name: nm, host: host, server: srv })
        end if
    end for
    ' Keep focus on the same server when the list changes; leave the card if it emptied.
    if m.focusZone = "found" then
        idx = -1
        for i = 0 to m.found.Count() - 1
            if m.found[i].server.url = focusedUrl then idx = i
        end for
        if idx < 0 and m.found.Count() > 0 then idx = 0
        if idx >= 0 then
            m.focusIndex = idx
        else
            m.focusZone = m.lastFocus
            m.focusIndex = 0
        end if
    end if
    renderScanStatus()
    layout()
    ' A removed row took the focus with it; anything else keeps its own (dialogs, the field).
    if hadFocus then applyFocus() else renderRows()
end sub

' Positions the found rows in their window of m.foundSlots, scrolled so the focused row shows.
sub placeFoundRows()
    n = m.found.Count()
    slots = m.foundSlots
    if slots < 1 then slots = 1
    if m.focusZone = "found" then
        if m.focusIndex < m.foundTop then m.foundTop = m.focusIndex
        if m.focusIndex >= m.foundTop + slots then m.foundTop = m.focusIndex - slots + 1
    end if
    if m.foundTop > n - slots then m.foundTop = n - slots
    if m.foundTop < 0 then m.foundTop = 0
    for i = 0 to n - 1
        r = m.found[i]
        slot = i - m.foundTop
        r.group.visible = slot >= 0 and slot < slots
        r.group.translation = [0, slot * 96]
    end for
end sub

' A found server: confirm the address, check its identity, then connect as if it had been typed.
sub pickFound(i as integer)
    if m.busy or i < 0 or i >= m.found.Count() then return
    srv = m.found[i].server
    name = Str_orEmpty(srv.name)
    if name = "" then name = "This server"
    lines = [name + " at " + srv.url, "Siku first checks that this address answers as the server it advertised. You can still type an address instead."]
    m.confirmFound = srv
    openConfirm("Connect to this server?", lines, ["Continue", "Cancel"], "onFoundConfirmButton", "onFoundConfirmClosed")
end sub

sub onFoundConfirmButton()
    dlg = m.confirmDialog
    if dlg = invalid then return
    choice = dlg.buttonSelected
    srv = m.confirmFound
    closeConfirm()
    m.confirmFound = invalid
    if choice = 0 and srv <> invalid then
        checkFound(srv)
    else
        applyFocus()
    end if
end sub

sub onFoundConfirmClosed()
    if m.confirmDialog = invalid then return
    closeConfirm()
    m.confirmFound = invalid
    applyFocus()
end sub

sub checkFound(srv as object)
    m.checking = srv
    setBusy(true)
    if m.scan <> invalid then
        m.scan.note = ""
        m.scan.noteIsError = false
    end if
    buildFoundRows()
    print "[siku-lan] checking identity of found server " + srv.url
    Api_call({ method: "GET", path: "/api/v2/system/identity", baseUrl: srv.url, auth: false, profile: false, anonymous: true, timeout: 5, context: { url: srv.url } }, "onFoundIdentity")
end sub

sub onFoundIdentity(event as object)
    resp = Api_result(event)
    srv = m.checking
    if srv = invalid or resp.context = invalid or resp.context.url <> srv.url then return
    m.checking = invalid
    got = invalid
    if resp.ok and Type(resp.data) = "roAssociativeArray" then got = resp.data.server_id
    ' Exact, case-sensitive equality with the advertised id; anything that is not a well-formed
    ' id string never reaches the comparison.
    matched = false
    if Lan_isServerId(got) then matched = (got = srv.serverId)
    print "[siku-lan] found server identity " + srv.url + " matched=" + Lan_boolText(matched) + " status=" + resp.status.ToStr()
    setBusy(false)
    buildFoundRows()
    if not matched then
        if resp.status = 0 then
            setScanNote("Couldn't reach that server. Type its address instead, or search again.", true)
        else
            setScanNote("That server didn't confirm its identity. Type its address, or search again.", true)
        end if
        return
    end if
    m.field.text = srv.url
    focusOn("connect")
    m.savedPick = invalid
    startConnect(srv.url, srv.serverId, [Url_normalize(srv.url)])
end sub
