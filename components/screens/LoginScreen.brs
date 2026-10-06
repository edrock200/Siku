' LoginScreen: device-code sign-in (QR + code, polled per api-spec §2.7) and password sign-in.
' Device status values (m.dStatus), as on Android TvSignInStatus:
'   getting, waiting, opened, newcode, unreachable, toomany, signedin,
'   couldntfinish, denied, paused, failed, update
' Every response handler checks m.gen so answers for an abandoned code are dropped.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.chrome = m.top.findNode("chrome")
    m.copy = m.top.findNode("copy")
    m.card = m.top.findNode("card")
    m.cardBg = m.top.findNode("cardBg")
    m.cardRing = m.top.findNode("cardRing")

    ' Server card
    m.serverCard = m.top.findNode("serverCard")
    m.scBg = m.top.findNode("scBg")
    m.scRing = m.top.findNode("scRing")
    m.scMarkInitial = m.top.findNode("scMarkInitial")
    m.scMarkImage = m.top.findNode("scMarkImage")
    m.scName = m.top.findNode("scName")
    m.scHost = m.top.findNode("scHost")
    m.scPill = m.top.findNode("scPill")
    m.scPillBg = m.top.findNode("scPillBg")
    m.scPillRing = m.top.findNode("scPillRing")
    m.scPillLabel = m.top.findNode("scPillLabel")

    ' Code state
    m.codeCopy = m.top.findNode("codeCopy")
    m.codeHeadline = m.top.findNode("codeHeadline")
    m.codeBody = m.top.findNode("codeBody")
    m.codeActions = m.top.findNode("codeActions")
    m.actionButton = m.top.findNode("actionButton")
    m.passwordButton = m.top.findNode("passwordButton")
    m.changeServerButton = m.top.findNode("changeServerButton")
    m.codeCard = m.top.findNode("codeCard")
    m.qr = m.top.findNode("qr")
    m.qrSpinner = m.top.findNode("qrSpinner")
    m.symbol = m.top.findNode("symbol")
    m.symbolIcon = m.top.findNode("symbolIcon")
    m.tiles = m.top.findNode("tiles")
    m.activateLabel = m.top.findNode("activateLabel")
    m.statusRow = m.top.findNode("statusRow")
    m.statusSpinner = m.top.findNode("statusSpinner")
    m.statusLabel = m.top.findNode("statusLabel")

    ' Password state
    m.passwordCopy = m.top.findNode("passwordCopy")
    m.pwHeadline = m.top.findNode("pwHeadline")
    m.pwBody = m.top.findNode("pwBody")
    m.usernameField = m.top.findNode("usernameField")
    m.passwordField = m.top.findNode("passwordField")
    m.revealButton = m.top.findNode("revealButton")
    m.pwError = m.top.findNode("pwError")
    m.pwActions = m.top.findNode("pwActions")
    m.signInButton = m.top.findNode("signInButton")
    m.usePhoneButton = m.top.findNode("usePhoneButton")
    m.pwChangeServerButton = m.top.findNode("pwChangeServerButton")
    m.phoneCard = m.top.findNode("phoneCard")
    m.phoneIcon = m.top.findNode("phoneIcon")
    m.phoneTitle = m.top.findNode("phoneTitle")
    m.phoneBody = m.top.findNode("phoneBody")

    m.pollTimer = m.top.findNode("pollTimer")
    m.pollTimer.observeField("fire", "onPollTimer")
    m.routeTimer = m.top.findNode("routeTimer")
    m.routeTimer.observeField("fire", "onRouteTimer")

    ' Buttons
    m.actionButton.observeField("buttonSelected", "onRestartPressed")
    m.passwordButton.observeField("buttonSelected", "onUsePasswordPressed")
    m.changeServerButton.observeField("buttonSelected", "onChangeServerPressed")
    m.pwChangeServerButton.observeField("buttonSelected", "onChangeServerPressed")
    m.usePhoneButton.observeField("buttonSelected", "onUsePhonePressed")
    m.signInButton.observeField("buttonSelected", "onSignInPressed")
    m.revealButton.observeField("buttonSelected", "onRevealPressed")
    m.usernameField.observeField("submitted", "onUsernameSubmitted")
    m.passwordField.observeField("submitted", "onPasswordSubmitted")
    m.usernameField.observeField("text", "onCredentialsChanged")
    m.passwordField.observeField("text", "onCredentialsChanged")
    for each b in [m.actionButton, m.passwordButton, m.changeServerButton, m.signInButton, m.usePhoneButton, m.pwChangeServerButton]
        b.observeField("width", "layoutRows")
    end for

    ' Session / server
    s = m.global.session
    m.serverUrl = Str_orEmpty(s.serverUrl)
    m.host = Url_host(m.serverUrl)
    m.serverName = Str_orEmpty(s.serverName)
    if m.serverName = "" then m.serverName = m.host
    m.secure = LCase(Left(m.serverUrl, 8)) = "https://"

    ' Device-flow state
    m.mode = "code"
    m.passwordOnly = false
    m.capability = invalid     ' invalid = not read yet; {} = read failed (unknown)
    m.gen = 0
    m.code = invalid
    m.dStatus = "getting"
    m.renewed = false
    m.opened = false
    m.budgetStart = 0
    m.failingSince = 0
    m.rateLimitedSince = 0
    m.startBackoff = 0
    m.pollBackoff = 0
    m.timerAction = ""
    m.accountName = ""
    m.routed = false
    m.signingIn = false
    m.active = false
    m.focusKey = ""

    renderServerCard()
    m.codeHeadline.text = "Sign in to " + m.serverName
    m.pwBody.text = "Use your " + m.serverName + " username and password."
    renderCode()
    renderMode()

    ' Branding: friendlier name and the server's mark (best-effort, public).
    Api_call({ method: "GET", path: "/api/v2/theme/branding", auth: false, profile: false, timeout: 6 }, "onBranding")
end sub

sub onScreenShown()
    m.active = true
    if m.mode = "code" and not m.routed then
        if m.code = invalid and (m.dStatus = "getting" or m.dStatus = "newcode") then
            startDevice(false)
        else if m.code <> invalid then
            ' Back from the background: poll at once.
            schedule("poll", 0)
        end if
    end if
    applyFocus()
end sub

sub onScreenHidden()
    m.active = false
    if not m.routed then abandonCode()
    m.pollTimer.control = "stop"
end sub

' ---------- Server card ----------

sub renderServerCard()
    m.scName.text = m.serverName
    m.scHost.text = m.host
    initial = UCase(Left(m.serverName.Trim(), 1))
    m.scMarkInitial.text = initial
    if m.secure then
        m.scPillLabel.text = "SECURE"
        m.scPillLabel.color = "0xEDEDEDFF"
        m.scPillBg.blendColor = "0x00000073"
        m.scPillRing.blendColor = "0xFFFFFF24"
    else
        m.scPillLabel.text = "HTTP"
        m.scPillLabel.color = "0xF4C869FF"
        m.scPillBg.blendColor = "0xF4C86914"
        m.scPillRing.blendColor = "0xF4C86959"
    end if
    m.scPillLabel.width = 0
    pillW = Int(Label_width(m.scPillLabel)) + 32
    m.scPillLabel.width = pillW - 32 + 2
    m.scPillBg.width = pillW
    m.scPillRing.width = pillW

    m.scName.width = 0
    m.scHost.width = 0
    textW = Label_width(m.scName)
    hostW = Label_width(m.scHost)
    if hostW > textW then textW = hostW
    if textW > 560 then textW = 560
    textW = Int(textW) + 2
    m.scName.width = textW
    m.scHost.width = textW
    pillX = 126 + textW + 22
    m.scPill.translation = [pillX, 45]
    w = pillX + pillW + 24
    m.scBg.width = w
    m.scRing.width = w
end sub

sub onBranding(event as object)
    resp = Api_result(event)
    if not resp.ok or resp.data = invalid or Type(resp.data) <> "roAssociativeArray" then return
    name = Str_orEmpty(resp.data.server_name).Trim()
    if name <> "" and name <> m.serverName then
        m.serverName = name
        m.codeHeadline.text = "Sign in to " + name
        m.pwBody.text = "Use your " + name + " username and password."
    end if
    markUrl = Str_orEmpty(resp.data.mark_url)
    if markUrl <> "" then
        if Left(markUrl, 4) <> "http" then
            if Left(markUrl, 1) <> "/" then markUrl = "/" + markUrl
            markUrl = Url_origin(m.serverUrl) + markUrl
        end if
        m.scMarkImage.observeField("loadStatus", "onMarkStatus")
        m.scMarkImage.uri = markUrl
    end if
    renderServerCard()
    layout()
end sub

sub onMarkStatus()
    ok = m.scMarkImage.loadStatus = "ready"
    m.scMarkImage.visible = ok
    m.scMarkInitial.visible = not ok
end sub

' ---------- Layout ----------

sub layoutRows()
    x = 0
    for each b in [m.actionButton, m.passwordButton, m.changeServerButton]
        if b.visible then
            b.translation = [x, 0]
            x = x + b.width + 22
        end if
    end for
    x = 0
    for each b in [m.signInButton, m.usePhoneButton, m.pwChangeServerButton]
        if b.visible then
            b.translation = [x, 0]
            x = x + b.width + 22
        end if
    end for
end sub

sub layout()
    layoutRows()
    y = 128 + 44
    if m.mode = "code" then
        m.codeCopy.translation = [0, y]
        cy = 0
        m.codeHeadline.translation = [0, cy]
        cy = cy + Int(m.codeHeadline.boundingRect().height) + 26
        m.codeBody.translation = [0, cy]
        cy = cy + Int(m.codeBody.boundingRect().height) + 48
        m.codeActions.translation = [0, cy]
        total = y + cy + 76
    else
        m.passwordCopy.translation = [0, y]
        cy = 0
        m.pwHeadline.translation = [0, cy]
        cy = cy + Int(m.pwHeadline.boundingRect().height) + 22
        m.pwBody.translation = [0, cy]
        cy = cy + Int(m.pwBody.boundingRect().height) + 40
        m.usernameField.translation = [0, cy]
        cy = cy + 84 + 20
        m.passwordField.translation = [0, cy]
        m.revealButton.translation = [668 + 16, cy]
        cy = cy + 84
        if m.pwError.visible then
            cy = cy + 16
            m.pwError.translation = [0, cy]
            cy = cy + Int(m.pwError.boundingRect().height)
        end if
        cy = cy + 40
        m.pwActions.translation = [0, cy]
        total = y + cy + 76
    end if
    ' The password form is top-anchored (as on Android); the code copy is centered.
    if m.mode = "code" then
        top = 124 + (896 - total) \ 2
    else
        top = 160
    end if
    if top < 124 then top = 124
    m.copy.translation = [90, top]
    layoutCard()
end sub

sub layoutCard()
    if m.mode = "code" then
        y = 52
        if m.qr.visible or m.qrSpinner.visible then
            y = y + 380
        else
            y = y + 112
        end if
        if m.tiles.visible then
            y = y + 34
            m.tiles.translation = [0, y]
            y = y + m.tileH
        end if
        if m.activateLabel.visible and m.activateLabel.text <> "" then
            y = y + 18
            m.activateLabel.translation = [52, y]
            y = y + Int(m.activateLabel.boundingRect().height)
        end if
        y = y + 24
        layoutStatusRow()
        m.statusRow.translation = [m.statusRow.translation[0], y]
        y = y + 34 + 52
        h = y
    else
        m.phoneBody.translation = [52, 256]
        h = 256 + Int(m.phoneBody.boundingRect().height) + 52
    end if
    m.cardBg.height = h
    m.cardRing.height = h
    m.card.translation = [1190, 124 + (896 - h) \ 2]
end sub

sub layoutStatusRow()
    m.statusLabel.width = 0
    tw = Label_width(m.statusLabel)
    if tw > 536 then tw = 536
    m.statusLabel.width = tw + 2
    w = tw
    x = 0
    if m.statusSpinner.visible then
        m.statusSpinner.translation = [0, 4]
        x = 26 + 14
        w = w + x
    end if
    m.statusLabel.translation = [x, 0]
    m.statusRow.translation = [(640 - w) / 2, m.statusRow.translation[1]]
end sub

' ---------- Code card rendering ----------

' Splits the user code into tile characters: "4821-7730" -> 4821 – 7730; 8 bare chars -> 4 + 4.
function codeChars(code as string) as object
    out = []
    clean = ""
    for i = 1 to Len(code)
        ch = UCase(Mid(code, i, 1))
        if ch = "-" or ch = " " then
            out.Push("-")
        else
            out.Push(ch)
            clean = clean + ch
        end if
    end for
    if Len(clean) = Len(code) and Len(clean) = 8 then
        out = []
        for i = 1 to 8
            out.Push(Mid(clean, i, 1))
            if i = 4 then out.Push("-")
        end for
    end if
    return out
end function

sub buildTiles(code as string)
    m.tiles.removeChildrenIndex(m.tiles.getChildCount(), 0)
    chars = codeChars(code)
    n = chars.Count()
    m.tileH = 0
    if n = 0 then return
    gap = 14
    maxW = 536
    ' Android: min(42dp, (maxWidth - gaps) / count) per tile; separators are 45% wide.
    tileW = (maxW - gap * (n - 1)) \ n
    if tileW > 84 then tileW = 84
    tileH = Int(tileW * 1.24)
    m.tileH = tileH
    font = CreateObject("roSGNode", "Font")
    font.uri = "pkg:/fonts/Inter-bold.otf"
    font.size = Int(tileW * 0.66 * 0.86 * 1.6)
    if font.size > Int(tileH * 0.62) then font.size = Int(tileH * 0.62)
    total = 0
    for each ch in chars
        if ch = "-" then total = total + Int(tileW * 0.45) else total = total + tileW
    end for
    total = total + gap * (n - 1)
    x = (640 - total) \ 2
    for each ch in chars
        sep = (ch = "-")
        w = tileW
        if sep then w = Int(tileW * 0.45)
        g = m.tiles.createChild("Group")
        g.translation = [x, 0]
        if not sep then
            bg = g.createChild("Poster")
            bg.uri = "pkg:/images/ui/r16.9.png"
            bg.width = w
            bg.height = tileH
            bg.blendColor = "0xFFFFFF14"
            ring = g.createChild("Poster")
            ring.uri = "pkg:/images/ui/r16_ring2.9.png"
            ring.width = w
            ring.height = tileH
            ring.blendColor = "0xFFFFFF1F"
        end if
        lbl = g.createChild("Label")
        lbl.font = font
        lbl.width = w
        lbl.height = tileH
        lbl.horizAlign = "center"
        lbl.vertAlign = "center"
        if sep then
            lbl.text = "–"
            lbl.color = "0xEDEDED66"
        else
            lbl.text = ch
            lbl.color = "0xEDEDEDFF"
        end if
        x = x + w + gap
    end for
end sub

function isTrue(v as dynamic) as boolean
    t = Type(v)
    if t = "Boolean" or t = "roBoolean" then return v
    return false
end function

function isProblem(st as string) as boolean
    return st = "couldntfinish" or st = "denied" or st = "unreachable" or st = "toomany" or st = "failed" or st = "update"
end function

function statusText(st as string) as string
    if st = "getting" then return "Getting a sign-in code…"
    if st = "waiting" then return "Waiting for approval"
    if st = "opened" then return "Continue on your phone"
    if st = "newcode" then return "New code. Waiting for approval."
    if st = "unreachable" then return "Can't reach " + m.host + ". Check this TV's connection."
    if st = "toomany" then return "Too many sign-in attempts. Trying again shortly."
    if st = "signedin" then
        if m.accountName <> "" then return "Signed in as " + m.accountName
        return "Signed in"
    end if
    if st = "couldntfinish" then return "Couldn't finish signing in on this TV."
    if st = "denied" then return "Sign-in was declined on your phone."
    if st = "paused" then return "Sign-in paused."
    if st = "failed" then return "Couldn't get a sign-in code."
    if st = "update" then return "This server needs an update before this TV can sign in."
    return ""
end function

' "Try again" / "Show a new code" for states that need the person (or keep retrying).
function actionLabel(st as string) as string
    if st = "couldntfinish" or st = "failed" or st = "unreachable" or st = "toomany" then return "Try again"
    if st = "denied" or st = "paused" then return "Show a new code"
    return ""
end function

sub renderCode()
    st = m.dStatus
    code = m.code
    showCode = code <> invalid and (st = "waiting" or st = "opened" or st = "newcode" or st = "unreachable" or st = "toomany")
    if showCode then
        m.qr.visible = true
        m.qr.text = Str_orEmpty(code.verification_uri_complete)
        if m.qr.text = "" then m.qr.text = Str_orEmpty(code.verification_uri)
        m.qrSpinner.visible = false
        m.symbol.visible = false
        if m.shownCode <> Str_orEmpty(code.user_code) then
            m.shownCode = Str_orEmpty(code.user_code)
            buildTiles(m.shownCode)
        end if
        m.tiles.visible = true
        m.activateLabel.text = activateText()
        m.activateLabel.visible = true
    else
        m.tiles.visible = false
        m.activateLabel.visible = false
        if st = "signedin" then
            m.qr.visible = false
            m.qrSpinner.visible = false
            m.symbol.visible = true
            m.symbolIcon.uri = "pkg:/images/icons/check.png"
            m.symbolIcon.blendColor = "0x30D158FF"
        else if isProblem(st) or st = "paused" then
            m.qr.visible = false
            m.qrSpinner.visible = false
            m.symbol.visible = true
            m.symbolIcon.uri = "pkg:/images/icons/error.png"
            m.symbolIcon.blendColor = "0xF4C869FF"
        else
            ' Getting a code: an empty white tile with a spinner.
            m.qr.visible = true
            m.qr.text = ""
            m.qrSpinner.visible = (st = "getting")
            m.symbol.visible = false
        end if
    end if

    m.statusLabel.text = statusText(st)
    if isProblem(st) then m.statusLabel.color = "0xFF6961FF" else m.statusLabel.color = "0xEDEDED9E"
    m.statusSpinner.visible = (st = "waiting" or st = "opened" or st = "getting" or st = "newcode")

    ' Body copy names the activate page.
    act = activateText()
    if act = "" then act = "your server's /activate page"
    m.codeBody.text = "Scan the code with your phone's camera, or go to " + act + " and enter it. Approve on your phone and this TV signs in by itself."

    ' Action row: the state's action; no password button when an update is required.
    label = actionLabel(st)
    m.actionButton.visible = label <> ""
    if label <> "" then m.actionButton.text = label
    m.passwordButton.visible = (st <> "update")
    layout()
end sub

function activateText() as string
    if m.code <> invalid then
        u = Str_orEmpty(m.code.verification_uri)
        if u <> "" then
            i = Instr(1, u, "://")
            if i > 0 then u = Mid(u, i + 3)
            return u
        end if
    end if
    if m.host <> "" then return m.host + "/activate"
    return ""
end function

sub setStatus(st as string)
    m.dStatus = st
    renderCode()
    if m.mode = "code" then
        ' A state that waits for the person takes focus on its action.
        if st = "couldntfinish" or st = "denied" or st = "paused" or st = "failed" then
            focusOn("action")
        else if not isFocusable(m.focusKey) then
            focusOn(defaultCodeFocus())
        end if
    end if
end sub

' ---------- Device flow ----------

function nowSec() as integer
    return Time_nowSeconds()
end function

sub schedule(action as string, seconds as float)
    m.timerAction = action
    m.pollTimer.control = "stop"
    if seconds < 0.05 then seconds = 0.05
    m.pollTimer.duration = seconds
    m.pollTimer.control = "start"
end sub

sub onPollTimer()
    if not m.active or m.mode <> "code" or m.routed then return
    a = m.timerAction
    m.timerAction = ""
    if a = "poll" then
        doPoll()
    else if a = "start" then
        requestCode()
    end if
end sub

' (Re)starts device sign-in from "Getting a sign-in code".
sub startDevice(resetBudget as boolean)
    m.gen = m.gen + 1
    m.pollTimer.control = "stop"
    m.code = invalid
    m.shownCode = ""
    m.renewed = false
    m.opened = false
    m.failingSince = 0
    m.rateLimitedSince = 0
    m.startBackoff = 0
    m.pollBackoff = 0
    if resetBudget or m.budgetStart = 0 then m.budgetStart = nowSec()
    setStatus("getting")
    if m.capability = invalid then
        Api_call({ method: "GET", path: "/api/v2/auth/device/capability", auth: false, profile: false, timeout: 8, context: { gen: m.gen } }, "onCapability")
    else
        requestCode()
    end if
end sub

sub onCapability(event as object)
    resp = Api_result(event)
    if resp.context.gen <> m.gen then return
    if resp.ok and resp.data <> invalid and Type(resp.data) = "roAssociativeArray" then
        m.capability = resp.data
        if Str_orEmpty(resp.data.state) <> "available" then
            goPasswordOnly()
            return
        end if
    else
        m.capability = {} ' unknown: try the flow anyway
    end if
    requestCode()
end sub

function mayWithdraw() as boolean
    if m.capability = invalid then return true
    c = m.capability.cancel
    if c = invalid then return true
    if Type(c) = "Boolean" or Type(c) = "roBoolean" then return c
    return true
end function

sub requestCode()
    if nowSec() - m.budgetStart >= 3600 then
        setStatus("paused")
        return
    end if
    if m.dStatus <> "unreachable" and m.dStatus <> "toomany" and m.code = invalid and m.dStatus <> "getting" then
        setStatus("getting")
    end if
    di = CreateObject("roDeviceInfo")
    name = di.GetFriendlyName()
    if name = invalid or name = "" then name = "Roku " + di.GetModelDisplayName()
    body = { device_name: name, device_platform: "roku" }
    Api_call({ method: "POST", path: "/api/v2/auth/device/start", body: body, auth: false, profile: false, timeout: 15, context: { gen: m.gen } }, "onStart")
end sub

' Failure kinds as on Android DeviceLoginErrorKind.
function errorKind(resp as object) as string
    st = resp.status
    if st = 429 then return "ratelimited"
    if st = 404 or st = 501 then return "notfound"
    if st = 410 or st = 426 then return "update"
    if st = 0 or st = 408 or st >= 500 then return "transient"
    return "rejected"
end function

sub onStart(event as object)
    resp = Api_result(event)
    if resp.context.gen <> m.gen then
        ' Nobody will show this code: withdraw it.
        if resp.ok and resp.data <> invalid and mayWithdraw() then cancelCode(Str_orEmpty(resp.data.device_code))
        return
    end if
    if resp.ok and resp.data <> invalid and Type(resp.data) = "roAssociativeArray" and not Str_isEmpty(resp.data.device_code) then
        d = resp.data
        recovered()
        now = nowSec()
        expiresIn = d.expires_in
        if expiresIn = invalid then expiresIn = 900
        expiresIn = Int(expiresIn)
        if expiresIn < 1 then expiresIn = 1
        m.deadline = now + expiresIn
        m.serverToLocal = invalid
        dt = Time_parseIso(d.expires_at)
        if dt <> invalid then m.serverToLocal = now + expiresIn - dt.AsSeconds()
        interval = d.interval
        if interval = invalid then interval = 5
        interval = Int(interval)
        if interval < 1 then interval = 1
        m.interval = interval
        m.pollBackoff = 0
        m.opened = false
        m.code = d
        if m.renewed then setStatus("newcode") else setStatus("waiting")
        doPoll() ' poll at once
        return
    end if
    kind = errorKind(resp)
    if kind = "notfound" then
        goPasswordOnly()
    else if kind = "update" then
        setStatus("update")
    else if kind = "rejected" then
        setStatus("failed")
    else
        noteFailure(kind, true)
        if m.startBackoff <= 0 then m.startBackoff = 1 else m.startBackoff = m.startBackoff * 2
        if m.startBackoff > 30 then m.startBackoff = 30
        schedule("start", m.startBackoff)
    end if
end sub

sub recovered()
    m.failingSince = 0
    m.rateLimitedSince = 0
    m.startBackoff = 0
end sub

sub noteFailure(kind as string, starting as boolean)
    now = nowSec()
    if kind = "ratelimited" then
        if m.rateLimitedSince = 0 then m.rateLimitedSince = now
        if now - m.rateLimitedSince >= 60 then setStatus("toomany")
    else
        if m.failingSince = 0 then m.failingSince = now
        threshold = 30
        if starting then threshold = 10
        if now - m.failingSince >= threshold then setStatus("unreachable")
    end if
end sub

sub doPoll()
    if m.code = invalid then
        requestCode()
        return
    end if
    body = { device_code: Str_orEmpty(m.code.device_code) }
    Api_call({ method: "POST", path: "/api/v2/auth/device/poll", body: body, auth: false, profile: false, timeout: 15, context: { gen: m.gen } }, "onPoll")
end sub

function clampToDeadline(seconds as float) as float
    remaining = m.deadline - nowSec()
    if remaining < 0 then remaining = 0
    if seconds > remaining then return remaining
    return seconds
end function

sub onPoll(event as object)
    resp = Api_result(event)
    if resp.context.gen <> m.gen or m.code = invalid then return
    if resp.ok and resp.data <> invalid and Type(resp.data) = "roAssociativeArray" then
        d = resp.data
        m.pollBackoff = 0
        st = LCase(Str_orEmpty(d.status))
        if st = "pending" then
            recovered()
            if isTrue(d.opened) then m.opened = true
            dt = Time_parseIso(d.expires_at)
            if dt <> invalid and m.serverToLocal <> invalid then
                localExpiry = dt.AsSeconds() + m.serverToLocal
                if localExpiry > m.deadline then m.deadline = localExpiry
            end if
            if d.poll_after <> invalid then
                pa = Int(d.poll_after)
                if pa < 1 then pa = 1
                m.interval = pa
            end if
            if m.opened then
                newStatus = "opened"
            else if m.renewed then
                newStatus = "newcode"
            else
                newStatus = "waiting"
            end if
            if newStatus <> m.dStatus then setStatus(newStatus)
            if nowSec() >= m.deadline then
                replaceCode(true)
            else
                schedule("poll", clampToDeadline(m.interval))
            end if
        else if st = "approved" then
            tokens = d.tokens
            if tokens = invalid or Type(tokens) <> "roAssociativeArray" or Str_isEmpty(tokens.access_token) or Str_isEmpty(tokens.refresh_token) then
                m.code = invalid
                setStatus("failed")
            else
                onApproved(d)
            end if
        else if st = "denied" then
            m.code = invalid
            setStatus("denied")
        else if st = "expired" or st = "consumed" or st = "canceled" or st = "cancelled" then
            replaceCode(false)
        else
            m.code = invalid
            setStatus("failed")
        end if
        return
    end if
    kind = errorKind(resp)
    if kind = "notfound" or kind = "rejected" then
        replaceCode(false)
    else if kind = "update" then
        m.code = invalid
        setStatus("update")
    else
        noteFailure(kind, false)
        if m.pollBackoff <= 0 then
            m.pollBackoff = m.interval
            if m.pollBackoff < 1 then m.pollBackoff = 1
        else
            m.pollBackoff = m.pollBackoff * 2
        end if
        if m.pollBackoff > 30 then m.pollBackoff = 30
        if nowSec() >= m.deadline then
            replaceCode(true)
        else
            schedule("poll", clampToDeadline(m.pollBackoff))
        end if
    end if
end sub

' Drops the current code for a new one; withdraws it first when the server may still hold it.
sub replaceCode(stillLive as boolean)
    if stillLive and m.code <> invalid and mayWithdraw() then cancelCode(Str_orEmpty(m.code.device_code))
    m.code = invalid
    m.renewed = true
    requestCode()
end sub

sub cancelCode(deviceCode as string)
    if deviceCode = "" then return
    Api_call({ method: "POST", path: "/api/v2/auth/device/cancel", body: { device_code: deviceCode }, auth: false, profile: false, timeout: 5 }, "onCancelDone")
end sub

sub onCancelDone(event as object)
    Api_result(event) ' 404 is harmless
end sub

' Leaving the code: withdraw it on the server and stop polling.
sub abandonCode()
    m.gen = m.gen + 1
    m.pollTimer.control = "stop"
    if m.code <> invalid and mayWithdraw() then cancelCode(Str_orEmpty(m.code.device_code))
    m.code = invalid
end sub

sub onApproved(d as object)
    m.gen = m.gen + 1
    m.pollTimer.control = "stop"
    m.code = invalid
    m.routed = true
    tokens = d.tokens
    s = withoutProfile(Session_withTokens(m.global.session, tokens))
    profileId = Str_orEmpty(d.profile_id)
    profileToken = Str_orEmpty(d.profile_token)
    if profileId <> "" then
        s.profileId = profileId
        s.profileToken = profileToken
    end if
    Session_save(s)
    user = tokens.user
    if user <> invalid and Type(user) = "roAssociativeArray" then m.accountName = Str_orEmpty(user.username)
    setStatus("signedin")
    if profileId <> "" then
        ' The session is already bound to a profile: fetch its name for the shell.
        m.boundProfileId = profileId
        Api_call({ method: "GET", path: "/api/v2/profiles", auth: true, profile: false, timeout: 10 }, "onBoundProfiles")
    else
        m.routeTimer.control = "start"
    end if
end sub

sub onBoundProfiles(event as object)
    resp = Api_result(event)
    if resp.ok and resp.data <> invalid and Type(resp.data) = "roAssociativeArray" then
        for each p in Arr_or(resp.data.items)
            if Str_orEmpty(p.id) = m.boundProfileId then
                s = AA_copy(m.global.session)
                s.profileName = Str_orEmpty(p.name)
                s.profileAvatar = Str_orEmpty(p.avatar_url)
                Session_save(s)
                exit for
            end if
        end for
    end if
    m.routeTimer.control = "start"
end sub

' A new login session: any earlier profile selection (and its PIN token) no longer applies.
function withoutProfile(s as object) as object
    s.profileId = ""
    s.profileToken = ""
    s.profileName = ""
    s.profileAvatar = ""
    return s
end function

sub onRouteTimer()
    Nav_reset("@start")
end sub

' ---------- Modes ----------

sub goPasswordOnly()
    m.passwordOnly = true
    m.gen = m.gen + 1
    m.pollTimer.control = "stop"
    m.code = invalid
    showPassword()
end sub

sub showPassword()
    m.mode = "password"
    clearPwError()
    renderMode()
    focusOn("username")
end sub

sub renderMode()
    isCode = (m.mode = "code")
    m.codeCopy.visible = isCode
    m.codeCard.visible = isCode
    m.passwordCopy.visible = not isCode
    m.phoneCard.visible = not isCode
    m.usePhoneButton.visible = not m.passwordOnly
    if m.passwordOnly then
        m.pwBody.text = "This server only supports password sign-in."
        m.phoneIcon.uri = "pkg:/images/icons/lock.png"
        m.phoneTitle.text = "Sign in to " + m.serverName
        m.phoneBody.text = "Siku sends your username and password only to " + m.host + "."
    else
        m.pwBody.text = "Use your " + m.serverName + " username and password."
        m.phoneIcon.uri = "pkg:/images/icons/phone.png"
        m.phoneTitle.text = "Easier with a phone"
        m.phoneBody.text = "Choose " + Chr(8220) + "Use your phone instead" + Chr(8221) + " to scan a code and approve on your phone. Nothing to type with the remote."
    end if
    layout()
end sub

sub onUsePasswordPressed()
    abandonCode()
    showPassword()
end sub

sub onUsePhonePressed()
    if m.signingIn then return
    m.mode = "code"
    renderMode()
    startDevice(true)
    focusOn(defaultCodeFocus())
end sub

sub onRestartPressed()
    abandonCode()
    startDevice(true)
    focusOn(defaultCodeFocus())
end sub

sub onChangeServerPressed()
    abandonCode()
    m.routed = true
    Session_clearServer()
    Nav_reset("ServerConnectScreen")
end sub

' ---------- Password sign-in ----------

sub onRevealPressed()
    r = not m.passwordField.revealed
    m.passwordField.revealed = r
    if r then
        m.revealButton.iconUri = "pkg:/images/icons/visibility_off.png"
    else
        m.revealButton.iconUri = "pkg:/images/icons/visibility.png"
    end if
end sub

sub onUsernameSubmitted()
    focusOn("password")
end sub

sub onPasswordSubmitted()
    focusOn("signin")
    onSignInPressed()
end sub

sub onCredentialsChanged()
    if m.pwError.visible then clearPwError()
end sub

sub showPwError(msg as string, onUsername = false as boolean)
    m.pwError.text = msg
    m.pwError.visible = true
    m.usernameField.error = onUsername
    m.passwordField.error = not onUsername
    layout()
end sub

sub clearPwError()
    if not m.pwError.visible then return
    m.pwError.visible = false
    m.usernameField.error = false
    m.passwordField.error = false
    layout()
end sub

sub onSignInPressed()
    if m.signingIn then return
    username = m.usernameField.text.Trim()
    password = m.passwordField.text
    if username = "" then
        showPwError("Username is required", true)
        focusOn("username")
        return
    end if
    if password = "" then
        showPwError("Password is required")
        focusOn("password")
        return
    end if
    clearPwError()
    m.signingIn = true
    m.signInButton.text = "Signing in…"
    m.usernameField.disabled = true
    m.passwordField.disabled = true
    Api_call({ method: "POST", path: "/api/v2/auth/login", body: { username: username, password: password }, auth: false, profile: false, timeout: 20 }, "onLogin")
end sub

sub onLogin(event as object)
    resp = Api_result(event)
    m.signingIn = false
    m.signInButton.text = "Sign in"
    m.usernameField.disabled = false
    m.passwordField.disabled = false
    if resp.ok and resp.data <> invalid and Type(resp.data) = "roAssociativeArray" and not Str_isEmpty(resp.data.access_token) then
        m.routed = true
        Session_save(withoutProfile(Session_withTokens(m.global.session, resp.data)))
        Nav_reset("@start")
        return
    end if
    showPwError(loginErrorText(resp))
    focusOn("password")
end sub

function loginErrorText(resp as object) as string
    code = ""
    if resp.error <> invalid then code = Str_orEmpty(resp.error.code)
    st = resp.status
    if st = 0 then return "Network error. Check your connection."
    if st = 401 then return "Invalid username or password"
    if code = "local_login_disabled" then return "Password sign-in is turned off on this server. Use your phone instead."
    if code = "not_permitted" then return "Your account isn't allowed to use this server."
    if code = "password_expired" then return "Your password has expired. Change it, then sign in again."
    if code = "account_disabled" then return "Account is disabled"
    if st = 429 then return "Too many attempts. Wait a moment, then try again."
    if code = "provider_unavailable" or st = 503 then return "The sign-in service can't be reached right now. Try again later."
    return Api_errorText(resp)
end function

' ---------- Focus ----------

function defaultCodeFocus() as string
    st = m.dStatus
    if st = "couldntfinish" or st = "denied" or st = "paused" or st = "failed" then return "action"
    if st = "update" then return "changeServer"
    return "usePassword"
end function

function nodeFor(key as string) as dynamic
    if key = "action" then return m.actionButton
    if key = "usePassword" then return m.passwordButton
    if key = "changeServer" then return m.changeServerButton
    if key = "username" then return m.usernameField
    if key = "password" then return m.passwordField
    if key = "reveal" then return m.revealButton
    if key = "signin" then return m.signInButton
    if key = "usePhone" then return m.usePhoneButton
    if key = "pwChangeServer" then return m.pwChangeServerButton
    return invalid
end function

function isFocusable(key as string) as boolean
    n = nodeFor(key)
    if n = invalid or not n.visible then return false
    if m.mode = "code" then return key = "action" or key = "usePassword" or key = "changeServer"
    return not (key = "action" or key = "usePassword" or key = "changeServer")
end function

sub focusOn(key as string)
    if not isFocusable(key) then
        if m.mode = "code" then
            key = defaultCodeFocus()
            if not isFocusable(key) then key = "changeServer"
        else
            key = "username"
        end if
    end if
    m.focusKey = key
    if m.active then nodeFor(key).setFocus(true)
end sub

sub applyFocus()
    if m.focusKey = "" or not isFocusable(m.focusKey) then
        if m.mode = "code" then focusOn(defaultCodeFocus()) else focusOn("username")
    else
        focusOn(m.focusKey)
    end if
end sub

' Visible keys of a row, left to right.
function rowKeys(keys as object) as object
    out = []
    for each k in keys
        if isFocusable(k) then out.Push(k)
    end for
    return out
end function

sub moveInRow(keys as object, delta as integer)
    row = rowKeys(keys)
    for i = 0 to row.Count() - 1
        if row[i] = m.focusKey then
            j = i + delta
            if j >= 0 and j < row.Count() then focusOn(row[j])
            return
        end if
    end for
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "back" then
        if m.mode = "password" and not m.passwordOnly then
            onUsePhonePressed()
            return true
        end if
        return false
    end if
    f = m.focusKey
    if m.mode = "code" then
        if key = "left" then
            moveInRow(["action", "usePassword", "changeServer"], -1)
        else if key = "right" then
            moveInRow(["action", "usePassword", "changeServer"], 1)
        end if
        return true
    end if
    ' Password form
    buttons = ["signin", "usePhone", "pwChangeServer"]
    if f = "username" then
        if key = "down" then focusOn("password")
    else if f = "password" then
        if key = "up" then
            focusOn("username")
        else if key = "down" then
            focusOn("signin")
        else if key = "right" then
            focusOn("reveal")
        end if
    else if f = "reveal" then
        if key = "left" then
            focusOn("password")
        else if key = "up" then
            focusOn("username")
        else if key = "down" then
            focusOn("signin")
        end if
    else
        if key = "up" then
            focusOn("password")
        else if key = "left" then
            moveInRow(buttons, -1)
        else if key = "right" then
            moveInRow(buttons, 1)
        end if
    end if
    return true
end function
