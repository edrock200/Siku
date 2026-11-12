' ProfileScreen: pick who's watching on the open account, unlock PIN profiles, or sign out / change
' account (Silo Android #795: the open account's profiles only; other accounts are on Change Account).
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.content = m.top.findNode("content")
    m.subtitle = m.top.findNode("subtitle")
    m.gridClip = m.top.findNode("gridClip")
    m.gridGroup = m.top.findNode("grid")
    m.errorLabel = m.top.findNode("error")
    m.buttonsGroup = m.top.findNode("buttons")
    m.retryButton = m.top.findNode("retryButton")
    m.changeAccountButton = m.top.findNode("changeAccountButton")
    m.manageButton = m.top.findNode("manageButton")
    m.signOutButton = m.top.findNode("signOutButton")
    m.spinner = m.top.findNode("spinner")

    m.retryButton.observeField("buttonSelected", "onRetry")
    m.manageButton.observeField("buttonSelected", "onManage")
    m.changeAccountButton.observeField("buttonSelected", "onChangeAccount")
    m.signOutButton.observeField("buttonSelected", "onSignOut")
    for each b in buttonList()
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
    m.offerVisible = false
    m.accountsOpened = false
    m.loaded = false
    m.active = false
    m.cols = 6
    m.rowH = 220 + 44 + 40 + 60
    m.maxRows = 2 ' rows that fit above the buttons; more scroll (scrollToFocus)
    m.scrollRow = 0
    ' Manage mode (Silo Android TV): acting as the household's primary profile.
    m.canManage = false
    m.manageMode = false
    m.manager = invalid      ' { id, token } of the primary profile, in memory only
    m.pinForManage = false   ' the open PIN pad unlocks manage mode instead of choosing a profile
    m.manageAsked = false    ' params.manage (debug) started it once
    m.maxProfiles = -1
    m.keepFocusId = ""       ' the tile to focus after a reload (the profile just edited)

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
    ' A phone signed several accounts in (PhonePairing.brs): this is the first one's picker, and
    ' Change Account opens over it once, focused on its card; Back from it lands here.
    p = m.top.params
    if p <> invalid and isTrue(p.openAccounts) and not m.accountsOpened then
        m.accountsOpened = true
        Nav_push("ChangeAccountScreen", {})
        return
    end if
    applyFocus()
end sub

sub onScreenHidden()
    m.active = false
end sub

sub renderSubtitle()
    if m.accountName <> "" then m.subtitle.text = TxF("Signed in as {0}", [m.accountName]) else m.subtitle.text = " "
end sub

sub onAccount(event as object)
    resp = Api_result(event)
    if resp.ok and resp.data <> invalid and Type(resp.data) = "roAssociativeArray" then
        m.accountName = Str_orEmpty(resp.data.username)
        renderSubtitle()
        if isTrue(resp.data.password_change_required) then Diag_log("[siku-auth] account says password_change_required=true")
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
    if PasswordChange_isRequired(resp) then
        ' Silo Android #790: the account holds a temporary password. The TV has no form for it;
        ' say where to change it. The message follows each load's answer: Retry after the change
        ' shows the profiles (or sign-in, since the change ends this session).
        Diag_log("[siku-auth] password change required: profiles refused (403); showing where to change it")
        showPasswordChange()
        return
    end if
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
    ' Change Account's card shows how many profiles each account has; the profile menu's row reads
    ' the count and the account's limit (max_profiles, Silo Android #881).
    s = m.global.session
    if not Session_isTemporary(s) then Accounts_setProfiles(Str_orEmpty(s.accountId), items.Count(), Accounts_maxProfilesOf(resp.data))
    m.maxProfiles = Accounts_maxProfilesOf(resp.data)
    m.canManage = ProfileManage_canManage(items, Session_isTemporary(s))
    m.manageButton.visible = m.canManage
    if not m.canManage and m.manageMode then setManageMode(false, false)

    ' One profile and no PIN: nothing to pick (unless the person asked to switch).
    params = m.top.params
    switching = params <> invalid and (isTrue(params.switching) or isTrue(params.atLaunch))
    if items.Count() = 1 and not isTrue(items[0].has_pin) and not switching and not m.manageMode then
        chooseProfile(items[0], "")
        return
    end if
    if params <> invalid and isTrue(params.deepLink) and not m.manageMode then
        p = DeepLink_profileFor(items, "")
        if p <> invalid then
            print "[siku-deeplink] content link opens a profile without the picker"
            chooseProfile(p, "")
            return
        end if
    end if

    m.errorLabel.visible = false
    m.retryButton.visible = false
    buildGrid()
    m.content.visible = true
    m.buttonsGroup.visible = true
    layout()
    ' Keep focus on the current profile when there is one.
    current = Str_orEmpty(m.global.session.profileId)
    if m.keepFocusId <> "" then current = m.keepFocusId
    m.keepFocusId = ""
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
    ' debugManage=1 (DEBUG builds): manage mode once the list is shown.
    if params <> invalid and isTrue(params.manage) and not m.manageAsked and m.canManage then
        m.manageAsked = true
        enterManage()
    end if
end sub

' A temporary password: no profiles, the message, and Retry | Change account | Sign out with
' Sign out focused (the way forward on this TV; Retry lands on sign-in once it was changed).
sub showPasswordChange()
    m.profiles = []
    m.loaded = false
    buildGrid()
    showLoadError(PasswordChange_pickerMessage())
    m.errorLabel.color = "0xEDEDEDFF" ' a way forward, not a failure
    bs = visibleButtons()
    for i = 0 to bs.Count() - 1
        if bs[i].isSameNode(m.signOutButton) then m.buttonIndex = i
    end for
    applyFocus()
end sub

sub showLoadError(msg as string)
    m.manageButton.visible = false
    if m.manageMode then setManageMode(false, false)
    m.content.visible = true
    m.errorLabel.color = "0xFF6961FF"
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
    ' Manage mode ends the grid with Add profile while the account has room (max_profiles).
    withAdd = m.manageMode and ProfileManage_canAdd(n, m.maxProfiles)
    total = n
    if withAdd then total = n + 1
    colW = 256
    gap = 28
    rowH = m.rowH
    for i = 0 to total - 1
        row = i \ m.cols
        col = i mod m.cols
        inRow = total - row * m.cols
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

        nm = g.createChild("Label")
        Label_setFont(nm, "semibold", 26)
        nm.width = colW
        nm.height = 36
        nm.horizAlign = "center"
        nm.maxLines = 1
        nm.translation = [0, 246]

        if i < n then
            p = m.profiles[i]
            av = g.createChild("AuthAvatar")
            av.size = 220
            av.translation = [18, 0]
            av.profile = p
            ' Manage mode: the avatar dims under a pencil (the tile edits instead of selects).
            pencil = g.createChild("Poster")
            pencil.uri = "pkg:/images/icons/edit.png"
            pencil.width = 60
            pencil.height = 60
            pencil.translation = [98, 80]
            pencil.visible = m.manageMode
            if m.manageMode then av.opacity = 0.6
            nm.text = Str_orEmpty(p.name)
            m.tiles.Push({ kind: "profile", group: g, ring: ring, avatar: av, name: nm, pencil: pencil, circle: invalid, icon: invalid })
        else
            ' The round Add tile after the profiles (Android TV's TvAddTile).
            circle = g.createChild("Poster")
            circle.uri = "pkg:/images/ui/circle_ring.png"
            circle.width = 220
            circle.height = 220
            circle.translation = [18, 0]
            icon = g.createChild("Poster")
            icon.uri = "pkg:/images/icons/add.png"
            icon.width = 66
            icon.height = 66
            icon.translation = [95, 77]
            nm.text = Tx("Add profile")
            m.tiles.Push({ kind: "add", group: g, ring: ring, avatar: invalid, name: nm, pencil: invalid, circle: circle, icon: icon })
        end if
    end for
    renderTiles()
end sub

sub renderTiles()
    scrollToFocus()
    for i = 0 to m.tiles.Count() - 1
        t = m.tiles[i]
        focused = m.active and m.focusZone = "grid" and m.focusIndex = i
        if focused then
            ' Focused: 1.12x (220 -> 246) about the center, ring 12 px outside, name lower.
            if t.avatar <> invalid then
                t.avatar.size = 246
                t.avatar.translation = [18 - 13, -13]
            end if
            t.ring.visible = true
            t.name.translation = [0, 264]
            t.name.color = "0xEDEDEDFF"
        else
            if t.avatar <> invalid then
                t.avatar.size = 220
                t.avatar.translation = [18, 0]
            end if
            t.ring.visible = false
            t.name.translation = [0, 246]
            t.name.color = "0xEDEDED9E"
        end if
        if t.circle <> invalid then
            if focused then t.circle.blendColor = "0xFFFFFFB3" else t.circle.blendColor = "0xFFFFFF40"
            if focused then t.icon.blendColor = "0xEDEDEDFF" else t.icon.blendColor = "0xEDEDED66"
        end if
        if focused and m.pinDialog = invalid then
            ' Screen reader: "Kids, PIN protected, Kids profile, Edit, button, 3 of 4".
            parts = [t.name.text]
            if t.kind = "profile" and i < m.profiles.Count() then
                p = m.profiles[i]
                if isTrue(p.has_pin) then parts.Push(Tx("PIN protected"))
                if isTrue(p.is_child) then parts.Push(Tx("Kids profile"))
                if m.manageMode then parts.Push(Tx("Edit"))
            end if
            A11y_say("profile:" + i.ToStr() + ":" + Session_boolWord(m.manageMode), A11y_join(parts), "button", i, m.tiles.Count())
        end if
    end for
end sub

function buttonList() as object
    return [m.retryButton, m.manageButton, m.changeAccountButton, m.signOutButton]
end function

sub layoutButtons()
    x = 0
    for each b in buttonList()
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
    n = m.tiles.Count()
    rows = (n + m.cols - 1) \ m.cols
    if rows > m.maxRows then
        ' Clip to the rows that fit; scrollToFocus moves the grid. 30 px above the first row and
        ' 10 px below the last name leave room for the focused avatar's ring and lowered name.
        m.gridClip.clippingRect = [0, -30, 1920, m.maxRows * m.rowH - 60 + 40]
        rows = m.maxRows
    else
        m.gridClip.clippingRect = [0, 0, 0, 0]
    end if
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

' Keeps the focused row inside the rows shown (more than 12 profiles).
sub scrollToFocus()
    if m.focusZone = "grid" and m.tiles.Count() > 0 then
        row = m.focusIndex \ m.cols
        if row < m.scrollRow then m.scrollRow = row
        if row > m.scrollRow + m.maxRows - 1 then m.scrollRow = row - m.maxRows + 1
    end if
    rows = (m.tiles.Count() + m.cols - 1) \ m.cols
    if m.scrollRow > rows - m.maxRows then m.scrollRow = rows - m.maxRows
    if m.scrollRow < 0 then m.scrollRow = 0
    m.gridGroup.translation = [0, -m.scrollRow * m.rowH]
end sub

' The buttons count only once the page is drawn: while the profiles load the group is hidden,
' and a hidden focused button still takes OK (Change account, Sign out).
function visibleButtons() as object
    out = []
    if not m.buttonsGroup.visible then return out
    for each b in buttonList()
        if b.visible then out.Push(b)
    end for
    return out
end function

sub applyFocus()
    if not m.active then return
    if m.offerVisible = true then
        renderOffer()
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
        if bs.Count() = 0 then
            ' Nothing to focus yet (still loading): hold focus on the screen itself (pitfall 7).
            m.top.setFocus(true)
            return
        end if
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
    if key = "back" then
        ' Back leaves manage mode first (as Done does).
        if m.manageMode then
            setManageMode(false, true)
            return true
        end if
        return false
    end if
    if m.busy then return true
    if not m.content.visible then return true ' still loading: only Back does anything
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
            if m.manageMode then
                manageTile(i)
            else if i < m.profiles.Count() then
                selectProfile(m.profiles[i])
            end if
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
    m.offerBodyLabel = m.top.findNode("offerBody")
    ' Left to right: Ask Every Time | Remember (index 1, focused first).
    m.offerButtons = [m.top.findNode("offerAsk"), m.top.findNode("offerRemember")]
    Label_setFont(m.offerTitleLabel, "bold", 36)
    w = 900
    m.offerTitleLabel.width = w - 96
    m.offerTitleLabel.text = TxF("Open {0} automatically?", [name])
    m.offerBodyLabel.width = w - 96
    ' Wording adapted from Silo-Server/silo-roku, AGPL-3.0 (locale/en_US/strings.json).
    m.offerBodyLabel.text = Tx("Siku can skip Who's watching and open this profile when it starts on this Roku. You can change this later in Settings > General > Profile Selection.")
    titleH = Int(Label_height(m.offerTitleLabel))
    if titleH <= 0 then titleH = 44
    bodyH = Int(Label_height(m.offerBodyLabel))
    if bodyH <= 0 then bodyH = 96
    btnH = 68
    h = 48 + titleH + 20 + bodyH + 40 + btnH + 48
    x = (1920 - w) \ 2
    top = (1080 - h) \ 2
    bg = m.top.findNode("offerBg")
    ring = m.top.findNode("offerRing")
    for each node in [bg, ring]
        node.width = w
        node.height = h
        node.translation = [x, top]
    end for
    m.offerTitleLabel.translation = [x + 48, top + 48]
    m.offerBodyLabel.translation = [x + 48, top + 48 + titleH + 20]
    m.offerButtonsY = top + 48 + titleH + 20 + bodyH + 40
    m.offerX = x
    m.offerW = w
    for each b in m.offerButtons
        b.observeField("width", "layoutOfferButtons")
        b.observeField("buttonSelected", "onOfferButton")
    end for
    layoutOfferButtons()
    m.offerIndex = 1
    m.offerVisible = true
    m.content.visible = false
    m.buttonsGroup.visible = false
    m.top.findNode("offer").visible = true
    renderOffer()
end sub

sub layoutOfferButtons()
    if m.offerButtons = invalid then return
    gap = 24
    total = m.offerButtons[0].width + gap + m.offerButtons[1].width
    bx = m.offerX + (m.offerW - total) \ 2
    m.offerButtons[0].translation = [bx, m.offerButtonsY]
    m.offerButtons[1].translation = [bx + m.offerButtons[0].width + gap, m.offerButtonsY]
end sub

sub renderOffer()
    m.offerButtons[m.offerIndex].setFocus(true)
end sub

sub onOfferButton(event as object)
    if m.offerVisible <> true then return
    b = event.getRoSGNode()
    answerOffer(b.isSameNode(m.offerButtons[1]))
end sub

sub answerOffer(remember as boolean)
    if m.offerVisible <> true then return
    m.offerVisible = false
    m.top.findNode("offer").visible = false
    print "[siku-profiles] open automatically answered remember=" + Session_boolWord(remember)
    ProfileLaunch_answerOffer(remember)
    Nav_reset("ShellScreen")
end sub

function onOfferKey(key as string) as boolean
    if key = "left" and m.offerIndex > 0 then
        m.offerIndex = m.offerIndex - 1
    else if key = "right" and m.offerIndex < m.offerButtons.Count() - 1 then
        m.offerIndex = m.offerIndex + 1
    else if key = "back" then
        ' Back answers Ask Every Time, as upstream's dismiss does.
        answerOffer(false)
        return true
    end if
    renderOffer()
    return true
end function

sub openPin(p as object, forManage = false as boolean)
    m.pinProfile = p
    m.pinForManage = forManage
    dlg = CreateObject("roSGNode", "AuthPinDialog")
    if forManage then dlg.prompt = Tx("Enter this PIN to manage profiles")
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
    dlg.unobserveField("pinEntered")
    dlg.unobserveField("dismissed")
    m.top.removeChild(dlg)
    m.content.visible = true
    m.buttonsGroup.visible = true
    applyFocus()
end sub

sub onPinDismissed()
    if m.pinForManage then Diag_log("[siku-profiles] manage: PIN cancelled")
    m.pinForManage = false
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
        forManage = m.pinForManage
        m.pinForManage = false
        if forManage then
            ' Kept for manage mode only; the Roku's open profile is untouched. The grid is redrawn
            ' for manage mode before the pad closes, so its first spoken tile is already "Edit".
            m.manager = { id: Str_orEmpty(p.id), token: token }
            setManageMode(true, false)
            closePin()
            return
        end if
        closePin()
        chooseProfile(p, token)
        return
    end if
    if resp.status = 0 then
        dlg.error = Tx("Network error. Please try again.")
    else if resp.status = 429 then
        dlg.error = Tx("Too many attempts. Wait a moment, then try again.")
    else if resp.ok or (resp.status >= 400 and resp.status < 500) then
        dlg.error = Tx("That PIN didn't work. Try again.")
    else
        dlg.error = Api_errorText(resp)
    end if
end sub

'' ---------- Manage mode (Silo Android TV's TvProfileSelectionViewModel) ----------

sub onManage()
    if m.busy or not m.canManage then return
    if m.manageMode then
        setManageMode(false, true)
    else
        enterManage()
    end if
end sub

' Acting as the household's primary profile, the only one the server lets manage the others. A
' PIN-locked primary is verified first; Cancel there leaves manage mode off. The primary is never
' selected, so watching still needs a pick.
sub enterManage()
    primary = Accounts_householdPrimary(m.profiles)
    if primary = invalid then
        m.global.toast = Tx("Couldn't find the primary profile needed to manage profiles.")
        return
    end if
    if isTrue(primary.has_pin) then
        Diag_log("[siku-profiles] manage: asking the primary profile's PIN")
        openPin(primary, true)
        return
    end if
    m.manager = { id: Str_orEmpty(primary.id), token: "" }
    setManageMode(true, true)
end sub

sub setManageMode(onOff as boolean, keepFocus as boolean)
    m.manageMode = onOff
    if not onOff then m.manager = invalid
    if onOff then
        m.manageButton.text = Tx("Done")
        m.manageButton.iconUri = ""
    else
        m.manageButton.text = Tx("Manage")
        m.manageButton.iconUri = "pkg:/images/icons/edit.png"
    end if
    hasToken = false
    if m.manager <> invalid then hasToken = m.manager.token <> ""
    word = "off"
    if onOff then word = "on"
    Diag_log("[siku-profiles] manage mode " + word + " primary_token=" + Session_boolWord(hasToken))
    A11y_reset()
    buildGrid()
    layout()
    if m.focusIndex >= m.tiles.Count() then m.focusIndex = m.tiles.Count() - 1
    if m.focusIndex < 0 then m.focusIndex = 0
    if keepFocus then applyFocus()
end sub

' OK on a tile in manage mode: a profile opens Edit Profile, the last tile Add profile.
sub manageTile(i as integer)
    if i >= m.tiles.Count() then return
    t = m.tiles[i]
    if t.kind = "add" then
        Diag_log("[siku-profiles] manage: add profile opened")
        Nav_push("NewProfileScreen", { manager: m.manager })
        return
    end if
    p = m.profiles[i]
    m.keepFocusId = Str_orEmpty(p.id)
    Diag_log("[siku-profiles] manage: edit opened primary=" + Session_boolWord(isTrue(p.is_primary)) + " can_delete=" + Session_boolWord(ProfileManage_canDelete(p)))
    params = { profileId: Str_orEmpty(p.id), manager: m.manager }
    tp = m.top.params
    if tp <> invalid and not Str_isEmpty(tp.debugName) then params.debugName = Str_orEmpty(tp.debugName)
    Nav_push("EditProfileScreen", params)
end sub

' Edit Profile / New Profile closed: { changed, deletedId, token, manageEnded }.
sub onChildResult(result as object)
    if result = invalid or Type(result) <> "roAssociativeArray" then return
    token = Str_orEmpty(result.token)
    if token <> "" and m.manager <> invalid then m.manager.token = token
    if isTrue(result.manageEnded) and m.manageMode then setManageMode(false, false)
    if not isTrue(result.changed) then return
    deleted = Str_orEmpty(result.deletedId)
    s = m.global.session
    deletedActive = deleted <> "" and deleted = Str_orEmpty(s.profileId)
    if deletedActive and not Session_isTemporary(s) then
        ' Its profile token died with it: drop the selection before the list reloads.
        c = AA_copy(s)
        c.profileId = ""
        c.profileToken = ""
        c.profileName = ""
        c.profileAvatar = ""
        Session_save(c)
    end if
    m.global.homeDirty = true
    Diag_log("[siku-profiles] manage: list reloaded after a change deleted=" + Session_boolWord(deleted <> "") + " deleted_open=" + Session_boolWord(deletedActive))
    loadProfiles()
end sub

' ---------- Account actions ----------

' Change Account (Silo Android #795, where Change server was): every saved server's accounts;
' this account keeps its sign-in, Back returns here.
sub onChangeAccount()
    if m.busy then return
    Nav_push("ChangeAccountScreen", {})
end sub

sub onSignOut()
    if m.busy then return
    SignOut_ask()
end sub

' SignOutFlow.brs: Cancel (or Back) leaves focus on Sign out.
sub SignOut_afterCancel()
    applyFocus()
end sub

function isTrue(v as dynamic) as boolean
    t = Type(v)
    if t = "Boolean" or t = "roBoolean" then return v
    return false
end function
