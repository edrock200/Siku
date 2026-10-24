' ProfileScreen: pick who's watching, unlock PIN profiles, or sign out / change server.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.content = m.top.findNode("content")
    m.subtitle = m.top.findNode("subtitle")
    m.gridGroup = m.top.findNode("grid")
    m.errorLabel = m.top.findNode("error")
    m.buttonsGroup = m.top.findNode("buttons")
    m.retryButton = m.top.findNode("retryButton")
    m.changeServerButton = m.top.findNode("changeServerButton")
    m.signOutButton = m.top.findNode("signOutButton")
    m.spinner = m.top.findNode("spinner")

    m.retryButton.observeField("buttonSelected", "onRetry")
    m.changeServerButton.observeField("buttonSelected", "onChangeServer")
    m.signOutButton.observeField("buttonSelected", "onSignOut")
    for each b in [m.retryButton, m.changeServerButton, m.signOutButton]
        b.observeField("width", "layoutButtons")
    end for

    m.profiles = []
    m.tiles = []
    m.focusZone = "grid"   ' grid | buttons
    m.focusIndex = 0
    m.buttonIndex = 0
    m.pinDialog = invalid
    m.pinProfile = invalid
    m.busy = false
    m.loaded = false
    m.active = false
    m.cols = 6

    m.nameFont = CreateObject("roSGNode", "Font")
    m.nameFont.uri = "pkg:/fonts/Inter-semibold.otf"
    m.nameFont.size = 26

    m.accountName = ""
    u = m.global.session.user
    if u <> invalid and Type(u) = "roAssociativeArray" then m.accountName = Str_orEmpty(u.username)
    renderSubtitle()
    if m.accountName = "" then
        Api_call({ method: "GET", path: "/api/v2/account/me", profile: false, timeout: 10 }, "onAccount")
    end if
    loadProfiles()
end sub

sub onScreenShown()
    m.active = true
    applyFocus()
end sub

sub onScreenHidden()
    m.active = false
end sub

sub renderSubtitle()
    if m.accountName <> "" then m.subtitle.text = "Signed in as " + m.accountName else m.subtitle.text = " "
end sub

sub onAccount(event as object)
    resp = Api_result(event)
    if resp.ok and resp.data <> invalid and Type(resp.data) = "roAssociativeArray" then
        m.accountName = Str_orEmpty(resp.data.username)
        renderSubtitle()
    end if
end sub

' ---------- Loading ----------

sub loadProfiles()
    m.spinner.visible = not m.loaded
    Api_call({ method: "GET", path: "/api/v2/profiles", profile: false, timeout: 15 }, "onProfiles")
end sub

sub onProfiles(event as object)
    resp = Api_result(event)
    m.spinner.visible = false
    if not resp.ok or resp.data = invalid or Type(resp.data) <> "roAssociativeArray" then
        if m.profiles.Count() = 0 then
            showLoadError(Api_errorText(resp))
        end if
        return
    end if
    m.loaded = true
    items = []
    for each p in Arr_or(resp.data.items)
        if p <> invalid and Type(p) = "roAssociativeArray" then items.Push(p)
    end for
    m.profiles = items

    ' One profile and no PIN: nothing to pick (unless the person asked to switch).
    params = m.top.params
    switching = params <> invalid and (isTrue(params.switching) or isTrue(params.atLaunch))
    if items.Count() = 1 and not isTrue(items[0].has_pin) and not switching then
        chooseProfile(items[0], "")
        return
    end if

    m.errorLabel.visible = false
    m.retryButton.visible = false
    buildGrid()
    m.content.visible = true
    m.buttonsGroup.visible = true
    layout()
    ' Keep focus on the current profile when there is one.
    current = Str_orEmpty(m.global.session.profileId)
    m.focusIndex = 0
    for i = 0 to items.Count() - 1
        if Str_orEmpty(items[i].id) = current then m.focusIndex = i
    end for
    if items.Count() = 0 then
        m.focusZone = "buttons"
        m.buttonIndex = 0
    else
        m.focusZone = "grid"
    end if
    applyFocus()
end sub

sub showLoadError(msg as string)
    m.content.visible = true
    m.buttonsGroup.visible = true
    m.errorLabel.text = msg
    m.errorLabel.visible = true
    m.retryButton.visible = true
    layout()
    m.focusZone = "buttons"
    m.buttonIndex = 0
    applyFocus()
end sub

sub onRetry()
    m.retryButton.visible = false
    m.errorLabel.visible = false
    layout()
    loadProfiles()
end sub

' ---------- Grid ----------

sub buildGrid()
    m.gridGroup.removeChildrenIndex(m.gridGroup.getChildCount(), 0)
    m.tiles = []
    n = m.profiles.Count()
    colW = 256
    gap = 28
    rowH = 220 + 44 + 40 + 60
    for i = 0 to n - 1
        p = m.profiles[i]
        row = i \ m.cols
        col = i mod m.cols
        inRow = n - row * m.cols
        if inRow > m.cols then inRow = m.cols
        rowW = inRow * colW + (inRow - 1) * gap
        x = (1920 - rowW) \ 2 + col * (colW + gap)
        g = m.gridGroup.createChild("Group")
        g.focusable = true
        g.translation = [x, row * rowH]

        ring = g.createChild("Poster")
        ring.uri = "pkg:/images/ui/circle_ring.png"
        ring.width = 270
        ring.height = 270
        ring.translation = [18 - 25, -25]
        ring.blendColor = "0xEDEDEDFF"
        ring.visible = false

        av = g.createChild("AuthAvatar")
        av.size = 220
        av.translation = [18, 0]
        av.profile = p

        nm = g.createChild("Label")
        Label_setFont(nm, "semibold", 26)
        nm.width = colW
        nm.height = 36
        nm.horizAlign = "center"
        nm.maxLines = 1
        nm.text = Str_orEmpty(p.name)
        nm.translation = [0, 246]

        m.tiles.Push({ group: g, ring: ring, avatar: av, name: nm })
    end for
    renderTiles()
end sub

sub renderTiles()
    for i = 0 to m.tiles.Count() - 1
        t = m.tiles[i]
        focused = m.active and m.focusZone = "grid" and m.focusIndex = i
        if focused then
            ' Focused: 1.12x (220 -> 246) about the center, ring 12 px outside, name lower.
            t.avatar.size = 246
            t.avatar.translation = [18 - 13, -13]
            t.ring.visible = true
            t.name.translation = [0, 264]
            t.name.color = "0xEDEDEDFF"
        else
            t.avatar.size = 220
            t.avatar.translation = [18, 0]
            t.ring.visible = false
            t.name.translation = [0, 246]
            t.name.color = "0xEDEDED9E"
        end if
    end for
end sub

sub layoutButtons()
    x = 0
    for each b in [m.retryButton, m.changeServerButton, m.signOutButton]
        if b.visible then
            b.translation = [x, 0]
            x = x + b.width + 20
        end if
    end for
    w = x - 20
    if w < 0 then w = 0
    m.buttonsGroup.translation = [(1920 - w) \ 2, 1080 - 60 - 61]
end sub

sub layout()
    layoutButtons()
    n = m.profiles.Count()
    rows = (n + m.cols - 1) \ m.cols
    gridH = 0
    if rows > 0 then gridH = rows * (220 + 44 + 40) + (rows - 1) * 60
    h = 194 + gridH
    if m.errorLabel.visible then
        m.errorLabel.translation = [0, h + 36]
        h = h + 36 + 40
    end if
    avail = 1080 - 60 - 61 - 40 - 60
    top = 60 + (avail - h) \ 2
    if top < 60 then top = 60
    m.content.translation = [0, top]
end sub

' ---------- Focus and keys ----------

function visibleButtons() as object
    out = []
    for each b in [m.retryButton, m.changeServerButton, m.signOutButton]
        if b.visible then out.Push(b)
    end for
    return out
end function

sub applyFocus()
    if not m.active then return
    if m.offerVisible = true then
        m.top.setFocus(true)
        return
    end if
    if m.pinDialog <> invalid then
        m.pinDialog.setFocus(true)
        return
    end if
    if m.focusZone = "grid" and m.tiles.Count() > 0 then
        if m.focusIndex >= m.tiles.Count() then m.focusIndex = m.tiles.Count() - 1
        m.tiles[m.focusIndex].group.setFocus(true)
    else
        bs = visibleButtons()
        if bs.Count() = 0 then return
        if m.buttonIndex >= bs.Count() then m.buttonIndex = bs.Count() - 1
        m.focusZone = "buttons"
        bs[m.buttonIndex].setFocus(true)
    end if
    renderTiles()
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.offerVisible = true then return onOfferKey(key)
    if m.pinDialog <> invalid then return true ' the dialog handles its own keys
    if key = "back" then return false
    if m.busy then return true
    if m.focusZone = "grid" then
        n = m.tiles.Count()
        i = m.focusIndex
        col = i mod m.cols
        if key = "left" and col > 0 then
            m.focusIndex = i - 1
        else if key = "right" and col < m.cols - 1 and i + 1 < n then
            m.focusIndex = i + 1
        else if key = "up" and i - m.cols >= 0 then
            m.focusIndex = i - m.cols
        else if key = "down" then
            if i + m.cols < n then
                m.focusIndex = i + m.cols
            else if (i \ m.cols) < ((n - 1) \ m.cols) then
                m.focusIndex = n - 1
            else
                m.focusZone = "buttons"
                m.buttonIndex = 0
            end if
        else if key = "OK" then
            selectProfile(m.profiles[i])
        end if
        applyFocus()
        return true
    end if
    ' Buttons row
    bs = visibleButtons()
    if key = "left" and m.buttonIndex > 0 then
        m.buttonIndex = m.buttonIndex - 1
    else if key = "right" and m.buttonIndex < bs.Count() - 1 then
        m.buttonIndex = m.buttonIndex + 1
    else if key = "up" and m.tiles.Count() > 0 then
        m.focusZone = "grid"
    end if
    applyFocus()
    return true
end function

' ---------- Selection and PIN ----------

sub selectProfile(p as object)
    if isTrue(p.has_pin) then
        openPin(p)
    else
        chooseProfile(p, "")
    end if
end sub

sub chooseProfile(p as object, token as string)
    Session_save(Session_withProfile(m.global.session, p, token))
    m.global.homeDirty = true
    ' A chosen profile ends any away interval (Profile Selection's timed choices).
    ProfileLaunch_markActive(0)
    if ProfileLaunch_offerPending() then
        showOffer(p)
        return
    end if
    Nav_reset("ShellScreen")
end sub

' ---------- Remember offer (a new Roku, TvProfileSelectionScreen #542) ----------

sub showOffer(p as object)
    name = Str_orEmpty(p.name)
    m.offerTitleLabel = m.top.findNode("offerTitle")
    m.offerRows = [m.top.findNode("offerRemember"), m.top.findNode("offerAsk")]
    Label_setFont(m.offerTitleLabel, "bold", 36)
    w = 980
    m.offerTitleLabel.width = w - 72
    m.offerTitleLabel.text = "Open " + name + " automatically?"
    titleH = Int(Label_height(m.offerTitleLabel))
    if titleH <= 0 then titleH = 44
    rowH = 140
    labels = [["Remember", "Open " + name + " when Siku starts on this Roku."], ["Ask every time", "Show Who's watching when Siku starts. Change this in Settings > General > Profile Selection."]]
    h = 40 + titleH + 28 + 2 * (rowH + 8) + 28
    x = (1920 - w) \ 2
    top = (1080 - h) \ 2
    bg = m.top.findNode("offerBg")
    ring = m.top.findNode("offerRing")
    for each node in [bg, ring]
        node.width = w
        node.height = h
        node.translation = [x, top]
    end for
    m.offerTitleLabel.translation = [x + 36, top + 40]
    y = top + 40 + titleH + 28
    for i = 0 to 1
        r = m.offerRows[i]
        r.rowWidth = w - 48
        r.rowHeight = rowH
        r.label = labels[i][0]
        r.description = labels[i][1]
        r.showChevron = false
        r.translation = [x + 24, y]
        y = y + rowH + 8
    end for
    m.offerIndex = 0
    m.offerVisible = true
    m.content.visible = false
    m.buttonsGroup.visible = false
    m.top.findNode("offer").visible = true
    renderOffer()
    m.top.setFocus(true)
end sub

sub renderOffer()
    for i = 0 to m.offerRows.Count() - 1
        m.offerRows[i].focusedState = i = m.offerIndex
    end for
end sub

sub answerOffer(remember as boolean)
    m.offerVisible = false
    m.top.findNode("offer").visible = false
    ProfileLaunch_answerOffer(remember)
    Nav_reset("ShellScreen")
end sub

function onOfferKey(key as string) as boolean
    if key = "up" and m.offerIndex > 0 then
        m.offerIndex = m.offerIndex - 1
    else if key = "down" and m.offerIndex < m.offerRows.Count() - 1 then
        m.offerIndex = m.offerIndex + 1
    else if key = "OK" then
        answerOffer(m.offerIndex = 0)
        return true
    else if key = "back" then
        ' Closing the question keeps asking, as upstream's dismiss does.
        answerOffer(false)
        return true
    end if
    renderOffer()
    return true
end function

sub openPin(p as object)
    m.pinProfile = p
    dlg = CreateObject("roSGNode", "AuthPinDialog")
    dlg.profile = p
    dlg.observeField("pinEntered", "onPinEntered")
    dlg.observeField("dismissed", "onPinDismissed")
    m.top.appendChild(dlg)
    m.pinDialog = dlg
    m.content.visible = false
    m.buttonsGroup.visible = false
    dlg.setFocus(true)
end sub

sub closePin()
    dlg = m.pinDialog
    if dlg = invalid then return
    m.pinDialog = invalid
    m.pinProfile = invalid
    m.pinGen = invalid
    dlg.unobserveField("pinEntered")
    dlg.unobserveField("dismissed")
    m.top.removeChild(dlg)
    m.content.visible = true
    m.buttonsGroup.visible = true
    applyFocus()
end sub

sub onPinDismissed()
    closePin()
end sub

sub onPinEntered()
    dlg = m.pinDialog
    if dlg = invalid or m.pinProfile = invalid then return
    dlg.error = ""
    dlg.verifying = true
    id = Str_orEmpty(m.pinProfile.id)
    Api_call({ method: "POST", path: "/api/v2/profiles/" + Str_urlEncode(id) + "/verify-pin", body: { pin: dlg.pinEntered }, profile: false, timeout: 15, context: { id: id } }, "onPinVerified")
end sub

sub onPinVerified(event as object)
    resp = Api_result(event)
    dlg = m.pinDialog
    ' A late answer after Cancel, or for another profile, is dropped.
    if dlg = invalid or m.pinProfile = invalid or Str_orEmpty(m.pinProfile.id) <> resp.context.id then return
    dlg.verifying = false
    if resp.ok and resp.data <> invalid and Type(resp.data) = "roAssociativeArray" and not Str_isEmpty(resp.data.profile_token) then
        p = m.pinProfile
        token = Str_orEmpty(resp.data.profile_token)
        closePin()
        chooseProfile(p, token)
        return
    end if
    if resp.status = 0 then
        dlg.error = "Network error. Please try again."
    else if resp.status = 429 then
        dlg.error = "Too many attempts. Wait a moment, then try again."
    else if resp.ok or (resp.status >= 400 and resp.status < 500) then
        dlg.error = "That PIN didn't work. Try again."
    else
        dlg.error = Api_errorText(resp)
    end if
end sub

' ---------- Account actions ----------

sub onChangeServer()
    if m.busy then return
    Session_clearServer()
    Nav_reset("ServerConnectScreen")
end sub

sub onSignOut()
    if m.busy then return
    m.busy = true
    m.signOutButton.text = "Signing out…"
    Api_call({ method: "POST", path: "/api/v2/auth/logout", profile: false, timeout: 8 }, "onLoggedOut")
end sub

sub onLoggedOut(event as object)
    Api_result(event) ' sign out locally whatever the server said
    Session_signOutLocal(m.global.session)
    Nav_reset("@start")
end sub

function isTrue(v as dynamic) as boolean
    t = Type(v)
    if t = "Boolean" or t = "roBoolean" then return v
    return false
end function
