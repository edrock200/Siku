' ChangeAccountScreen: every saved server's accounts (Silo Android #795; see the XML).
' Adapted from Silo-Server/silo-roku, AGPL-3.0 (AccountsScreen, docs/spec.md section 7.5).
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.railGroup = m.top.findNode("railRows")
    m.paneGroup = m.top.findNode("paneRows")
    m.railUp = m.top.findNode("railMoreUp")
    m.railDown = m.top.findNode("railMoreDown")
    m.paneUp = m.top.findNode("paneMoreUp")
    m.paneDown = m.top.findNode("paneMoreDown")
    m.groups = []      ' Accounts_groups(): [{server, accounts: [{account, current}]}]
    m.railRows = []    ' {group, bg, ring, icon, name}; the last one is Add server
    m.paneRows = []    ' {group, bg, ring, tile, letter, name, line, badgeBg, badge, card}; the last one is Add an account
    m.zone = "rail"
    m.railIndex = 0
    m.paneIndex = 0
    m.shown = 0        ' the server whose accounts the pane shows
    m.railTop = 0
    m.paneTop = 0
    m.active = false
    m.built = false
    m.signInDone = false
    m.busy = false
end sub

function railSlots() as integer
    return 7
end function

function paneSlots() as integer
    return 5
end function

sub onScreenShown()
    m.active = true
    p = m.top.params
    ' A switch that needs a sign-in (a "Sign in again" account, or Add an account on another
    ' server) rebuilt the stack with this screen at its root: the sign-in opens over it once.
    if p <> invalid and isTrue(p.signIn) and not m.signInDone then
        m.signInDone = true
        Nav_push("LoginScreen", { username: Str_orEmpty(p.username) })
        return
    end if
    ' The registry may have changed under this screen (a sign-in pushed from here, Back).
    rebuild()
    applyFocus()
end sub

sub onScreenHidden()
    m.active = false
end sub

' The Roku's own session: a phone's borrowed profile is never an account here.
function ownSession() as object
    s = m.global.session
    if Accounts_isTemporary(s) then
        own = Registry_read("session")
        if own <> invalid and Type(own) = "roAssociativeArray" then return own
    end if
    return s
end function

sub rebuild()
    s = ownSession()
    activeUrl = Str_orEmpty(s.serverUrl)
    activeId = Str_orEmpty(s.accountId)
    m.groups = Accounts_groups(Session_savedServers(), Accounts_list(), activeUrl, activeId)
    if not m.built then
        m.built = true
        ' Focus starts on the open account; else on the active server's first account; else the rail.
        m.shown = 0
        m.zone = "rail"
        m.railIndex = 0
        if m.groups.Count() > 0 then
            cards = m.groups[0].accounts
            for i = 0 to cards.Count() - 1
                if cards[i].current then
                    m.zone = "pane"
                    m.paneIndex = i
                end if
            end for
            if m.zone = "rail" and cards.Count() > 0 and Str_orEmpty(m.groups[0].server.url) = activeUrl then
                m.zone = "pane"
                m.paneIndex = 0
            end if
        end if
    end if
    if m.shown >= m.groups.Count() then m.shown = 0
    if m.railIndex > m.groups.Count() then m.railIndex = m.groups.Count()
    buildRail()
    buildPane()
    Diag_log("[siku-accounts] change account shown servers=" + m.groups.Count().ToStr() + " accounts=" + Accounts_list().Count().ToStr() + " root=" + Session_boolWord(isRoot()))
end sub

function isRoot() as boolean
    p = m.top.params
    return p <> invalid and isTrue(p.root)
end function

function serverLabel(srv as object) as string
    name = Str_orEmpty(srv.name).Trim()
    if name = "" then name = Url_host(Str_orEmpty(srv.url))
    return name
end function

' ---------- Rail ----------

sub buildRail()
    m.railGroup.removeChildrenIndex(m.railGroup.getChildCount(), 0)
    m.railRows = []
    for i = 0 to m.groups.Count()
        g = m.railGroup.createChild("Group")
        g.focusable = true
        bg = g.createChild("Poster")
        bg.uri = "pkg:/images/ui/r20.9.png"
        bg.width = 560
        bg.height = 88
        ring = g.createChild("Poster")
        ring.uri = "pkg:/images/ui/r20_ring2.9.png"
        ring.width = 560
        ring.height = 88
        ring.blendColor = "0xFFFFFF24"
        icon = g.createChild("Poster")
        icon.width = 36
        icon.height = 36
        icon.translation = [26, 26]
        nm = g.createChild("Label")
        Label_setFont(nm, "semibold", 28)
        nm.translation = [82, 0]
        nm.width = 450
        nm.height = 88
        nm.vertAlign = "center"
        nm.maxLines = 1
        if i < m.groups.Count() then
            icon.uri = "pkg:/images/icons/dns.png"
            nm.text = serverLabel(m.groups[i].server)
        else
            icon.uri = "pkg:/images/icons/add.png"
            nm.text = Tx("Add server")
        end if
        m.railRows.Push({ group: g, bg: bg, ring: ring, icon: icon, name: nm })
    end for
    placeRail()
end sub

sub placeRail()
    n = m.railRows.Count()
    slots = railSlots()
    if m.railIndex < m.railTop then m.railTop = m.railIndex
    if m.railIndex >= m.railTop + slots then m.railTop = m.railIndex - slots + 1
    if m.railTop < 0 then m.railTop = 0
    for i = 0 to n - 1
        r = m.railRows[i]
        shownRow = i >= m.railTop and i < m.railTop + slots
        r.group.visible = shownRow
        r.group.translation = [0, (i - m.railTop) * 98]
    end for
    m.railUp.visible = m.railTop > 0
    m.railDown.visible = m.railTop + slots < n
end sub

' ---------- Pane ----------

sub buildPane()
    m.paneGroup.removeChildrenIndex(m.paneGroup.getChildCount(), 0)
    m.paneRows = []
    if m.groups.Count() = 0 then
        m.paneUp.visible = false
        m.paneDown.visible = false
        return
    end if
    grp = m.groups[m.shown]
    cards = grp.accounts
    for i = 0 to cards.Count()
        g = m.paneGroup.createChild("Group")
        g.focusable = true
        bg = g.createChild("Poster")
        bg.uri = "pkg:/images/ui/r22.9.png"
        bg.width = 800
        bg.height = 112
        ring = g.createChild("Poster")
        ring.uri = "pkg:/images/ui/r22_ring2.9.png"
        ring.width = 800
        ring.height = 112
        ring.blendColor = "0xFFFFFF24"
        tile = g.createChild("Poster")
        tile.uri = "pkg:/images/ui/circle.png"
        tile.width = 72
        tile.height = 72
        tile.translation = [20, 20]
        letter = g.createChild("Label")
        Label_setFont(letter, "bold", 34)
        letter.translation = [20, 20]
        letter.width = 72
        letter.height = 72
        letter.horizAlign = "center"
        letter.vertAlign = "center"
        icon = g.createChild("Poster")
        icon.width = 36
        icon.height = 36
        icon.translation = [38, 38]
        nm = g.createChild("Label")
        Label_setFont(nm, "bold", 30)
        nm.translation = [112, 16]
        nm.width = 470
        nm.height = 42
        nm.maxLines = 1
        line = g.createChild("Label")
        Label_setFont(line, "regular", 22)
        line.translation = [112, 62]
        line.width = 470
        line.height = 32
        line.maxLines = 1
        badgeBg = g.createChild("Poster")
        badgeBg.uri = "pkg:/images/ui/r14.9.png"
        badgeBg.height = 36
        badge = g.createChild("Label")
        Label_setFont(badge, "semibold", 18)
        badge.height = 36
        badge.vertAlign = "center"
        badge.horizAlign = "center"
        card = invalid
        if i < cards.Count() then
            card = cards[i]
            a = card.account
            name = Str_orEmpty(a.username).Trim()
            if name = "" then name = Tx("Account")
            letter.text = UCase(Left(name, 1))
            nm.text = name
            line.text = Accounts_profileLine(a.profiles)
            if line.text = "" then nm.translation = [112, 35]
            icon.visible = false
            tile.blendColor = "0xC9783BFF"
            letter.color = "0xFFF4E0FF"
            b = Accounts_badge(a, card.current)
            badge.text = b
            ' Measured with the Font node (Label_width); an estimate when it is not ready.
            bw = Int(Label_width(badge))
            if bw <= 0 then bw = Len(b) * 12
            bw = bw + 32
            badge.width = bw
            badge.translation = [800 - 24 - bw, 38]
            badgeBg.width = bw
            badgeBg.translation = [800 - 24 - bw, 38]
            badge.visible = b <> ""
            badgeBg.visible = b <> ""
        else
            letter.visible = false
            tile.uri = "pkg:/images/ui/circle_ring.png"
            tile.blendColor = "0xEDEDED9E"
            icon.uri = "pkg:/images/icons/add.png"
            nm.text = Tx("Add an account")
            line.text = TxF("Sign in on {0}", [serverLabel(grp.server)])
            badge.visible = false
            badgeBg.visible = false
        end if
        m.paneRows.Push({ group: g, bg: bg, ring: ring, tile: tile, letter: letter, icon: icon, name: nm, line: line, badgeBg: badgeBg, badge: badge, card: card })
    end for
    if m.paneIndex >= m.paneRows.Count() then m.paneIndex = m.paneRows.Count() - 1
    if m.paneIndex < 0 then m.paneIndex = 0
    placePane()
end sub

sub placePane()
    n = m.paneRows.Count()
    slots = paneSlots()
    if m.paneIndex < m.paneTop then m.paneTop = m.paneIndex
    if m.paneIndex >= m.paneTop + slots then m.paneTop = m.paneIndex - slots + 1
    if m.paneTop > n - slots then m.paneTop = n - slots
    if m.paneTop < 0 then m.paneTop = 0
    for i = 0 to n - 1
        r = m.paneRows[i]
        r.group.visible = i >= m.paneTop and i < m.paneTop + slots
        r.group.translation = [0, (i - m.paneTop) * 126]
    end for
    m.paneUp.visible = m.paneTop > 0
    m.paneDown.visible = m.paneTop + slots < n
end sub

' ---------- Focus ----------

sub applyFocus()
    if not m.active then return
    if m.zone = "pane" and m.paneRows.Count() = 0 then m.zone = "rail"
    if m.zone = "rail" then
        if m.railRows.Count() = 0 then return
        if m.railIndex >= m.railRows.Count() then m.railIndex = m.railRows.Count() - 1
        placeRail()
        m.railRows[m.railIndex].group.setFocus(true)
    else
        placePane()
        m.paneRows[m.paneIndex].group.setFocus(true)
    end if
    render()
end sub

sub render()
    for i = 0 to m.railRows.Count() - 1
        r = m.railRows[i]
        focused = m.zone = "rail" and m.railIndex = i
        selected = i = m.shown and i < m.groups.Count()
        if focused then
            r.bg.blendColor = "0xEDEDEDFF"
            r.ring.visible = false
            r.name.color = "0x000000FF"
            r.icon.blendColor = "0x000000FF"
        else
            ' The shown server keeps a dim fill (Roku's CHROME_SELECTED_FILL).
            if selected then r.bg.blendColor = "0xFFFFFF33" else r.bg.blendColor = "0xFFFFFF14"
            r.ring.visible = true
            r.name.color = "0xEDEDEDFF"
            r.icon.blendColor = "0xEDEDED9E"
        end if
    end for
    for i = 0 to m.paneRows.Count() - 1
        r = m.paneRows[i]
        focused = m.zone = "pane" and m.paneIndex = i
        warn = r.card <> invalid and Accounts_isExpired(r.card.account)
        if focused then
            r.bg.blendColor = "0xEDEDEDFF"
            r.ring.visible = false
            r.name.color = "0x000000FF"
            r.line.color = "0x00000099"
            r.icon.blendColor = "0x000000FF"
            if r.card = invalid then r.tile.blendColor = "0x00000066"
            r.badgeBg.blendColor = "0x000000E6"
            if warn then r.badge.color = "0xFFB454FF" else r.badge.color = "0xEDEDEDFF"
        else
            r.bg.blendColor = "0xFFFFFF12"
            r.ring.visible = true
            r.name.color = "0xEDEDEDFF"
            r.line.color = "0xEDEDED9E"
            r.icon.blendColor = "0xEDEDEDFF"
            if r.card = invalid then r.tile.blendColor = "0xEDEDED9E"
            if warn then
                r.badgeBg.blendColor = "0xFFB45424"
                r.badge.color = "0xFFB454FF"
            else
                r.badgeBg.blendColor = "0x00000073"
                r.badge.color = "0xEDEDEDFF"
            end if
        end if
    end for
    speakFocus()
end sub

' Screen reader: "Mock Silo, button, 1 of 3"; "laura, 3 profiles, current, button, 1 of 2".
sub speakFocus()
    if m.zone = "rail" then
        if m.railIndex >= m.railRows.Count() then return
        A11y_say("rail:" + m.railIndex.ToStr(), m.railRows[m.railIndex].name.text, "button", m.railIndex, m.railRows.Count())
        return
    end if
    if m.paneIndex >= m.paneRows.Count() then return
    r = m.paneRows[m.paneIndex]
    parts = [r.name.text, r.line.text]
    if r.badge.visible then parts.Push(LCase(r.badge.text))
    label = A11y_join(parts)
    A11y_say("pane:" + m.shown.ToStr() + ":" + m.paneIndex.ToStr(), label, "button", m.paneIndex, m.paneRows.Count())
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.busy then return true
    if key = "back" then
        ' On the start screen Back steps from the accounts to the rail first, then leaves Siku.
        if isRoot() and m.zone = "pane" then
            m.zone = "rail"
            m.railIndex = m.shown
            applyFocus()
            return true
        end if
        return false
    end if
    if m.zone = "rail" then
        last = m.railRows.Count() - 1
        if key = "up" and m.railIndex > 0 then
            m.railIndex = m.railIndex - 1
            showFocusedServer()
        else if key = "down" and m.railIndex < last then
            m.railIndex = m.railIndex + 1
            showFocusedServer()
        else if key = "right" or key = "OK" then
            if m.railIndex < m.groups.Count() then
                enterPane()
            else if key = "OK" then
                addServer()
                return true
            end if
        end if
    else
        if key = "up" and m.paneIndex > 0 then
            m.paneIndex = m.paneIndex - 1
        else if key = "down" and m.paneIndex < m.paneRows.Count() - 1 then
            m.paneIndex = m.paneIndex + 1
        else if key = "left" then
            m.zone = "rail"
            m.railIndex = m.shown
        else if key = "OK" then
            r = m.paneRows[m.paneIndex]
            if r.card <> invalid then chooseAccount(r.card) else addAccount()
            return true
        end if
    end if
    applyFocus()
    return true
end function

' Moving on the rail shows that server's accounts (Add server keeps the last one).
sub showFocusedServer()
    if m.railIndex >= m.groups.Count() or m.railIndex = m.shown then return
    m.shown = m.railIndex
    m.paneIndex = 0
    m.paneTop = 0
    buildPane()
end sub

' Right (or OK) from the rail: the open account when it is on this server, else the first card.
sub enterPane()
    if m.paneRows.Count() = 0 then return
    m.zone = "pane"
    m.paneIndex = 0
    for i = 0 to m.paneRows.Count() - 1
        c = m.paneRows[i].card
        if c <> invalid and c.current then m.paneIndex = i
    end for
end sub

' ---------- Actions ----------

sub chooseAccount(card as object)
    a = card.account
    srv = m.groups[m.shown].server
    expired = Accounts_isExpired(a) or not Accounts_hasSignIn(a)
    if card.current then
        s = ownSession()
        if Accounts_signedIn(s) then
            ' The open account: its picker, as Android TV's Picker(switched = false).
            Diag_log("[siku-accounts] change account picked the open account")
            Nav_reset("ProfileScreen", { switching: true })
            return
        end if
        ' Already the active one, waiting to sign in again: no switch needed.
        Diag_log("[siku-accounts] sign in again on the open account")
        Nav_push("LoginScreen", { username: Str_orEmpty(a.username) })
        return
    end if
    m.busy = true
    ' The arriving account's remembered profile is put aside so its picker asks (only a lone
    ' profile without a PIN opens at once); the one it replaces keeps its sign-in.
    Session_activateAccount(srv, a, true)
    m.global.homeDirty = true
    if expired then
        Nav_reset("ChangeAccountScreen", { root: true, signIn: true, username: Str_orEmpty(a.username) })
    else
        Nav_reset("@start")
    end if
end sub

' "Add an account" on the shown server: on the open server, sign-in opens over this screen and the
' open account stays until another signs in; elsewhere that server becomes active first, with no
' account open, and the stack starts again here.
sub addAccount()
    srv = m.groups[m.shown].server
    url = Str_orEmpty(srv.url)
    s = m.global.session
    if Str_orEmpty(s.serverUrl) = url and not Accounts_isTemporary(s) then
        Diag_log("[siku-accounts] add an account on the open server")
        Nav_push("LoginScreen", { addAccount: true })
        return
    end if
    Diag_log("[siku-accounts] add an account on another server")
    m.busy = true
    Session_activateAccount(srv, invalid, true)
    Nav_reset("ChangeAccountScreen", { root: true, signIn: true })
end sub

sub addServer()
    ' Server setup over this screen; the open account keeps its sign-in, Back comes here.
    Nav_push("ServerConnectScreen", { manage: true })
end sub

function isTrue(v as dynamic) as boolean
    t = Type(v)
    if t = "Boolean" or t = "roBoolean" then return v
    return false
end function
