' Root scene: screen stack, Back handling, startup routing.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.top.backgroundColor = "0x000000FF"
    m.top.backgroundUri = ""
    m.screens = m.top.findNode("screens")
    m.toast = m.top.findNode("toast")
    m.stack = []

    ' App-wide state shared with every component and Task.
    m.global.addFields({
        session: Session_load()     ' active server, tokens, user and profile
        prefs: Prefs_load()         ' device-local preferences
        toast: ""                   ' set to show a toast message
        authExpired: false          ' set by ApiTask when the refresh token is rejected
        sessionChanged: 0           ' bumped whenever the session is saved
        homeDirty: false            ' set after playback or state changes so Home refreshes
        settings: { ready: false, available: false, identity: "", revision: 0, manifestRevision: 0, items: {}, error: "" } ' server-synced settings snapshot (Settings.brs)
    })
    ' Single-flight token refresher used by every ApiTask.
    authTask = CreateObject("roSGNode", "AuthTask")
    m.global.addFields({ authTask: authTask })
    authTask.control = "RUN"

    m.global.observeField("toast", "onToast")
    m.global.observeField("authExpired", "onAuthExpired")

    routeToStart()
end sub

' Decides the first screen from what we have stored.
sub routeToStart(params = {} as object)
    s = m.global.session
    if Str_isEmpty(s.serverUrl) then
        resetTo("ServerConnectScreen", params)
    else if Str_isEmpty(s.accessToken) then
        resetTo("LoginScreen", params)
    else if Str_isEmpty(s.profileId) then
        resetTo("ProfileScreen", params)
    else
        resetTo("ShellScreen", params)
    end if
end sub

' ---------- Stack ----------

function topScreen() as dynamic
    if m.stack.Count() = 0 then return invalid
    return m.stack[m.stack.Count() - 1]
end function

sub pushScreen(name as string, params = {} as object)
    screen = CreateObject("roSGNode", name)
    if screen = invalid then
        print "[MainScene] unknown screen "; name
        m.global.toast = "Something went wrong"
        return
    end if
    if params = invalid then params = {}
    screen.params = params
    screen.observeField("navigateTo", "onNavigate")
    screen.observeField("close", "onCloseScreen")

    prev = topScreen()
    if prev <> invalid then
        prev.active = false
        prev.visible = false
    end if
    m.screens.appendChild(screen)
    m.stack.Push(screen)
    screen.visible = true
    screen.active = true
end sub

sub popScreen()
    if m.stack.Count() <= 1 then
        m.top.exitApp = true
        return
    end if
    closing = m.stack.Pop()
    result = closing.result
    closing.active = false
    closing.unobserveField("navigateTo")
    closing.unobserveField("close")
    m.screens.removeChild(closing)

    prev = topScreen()
    prev.visible = true
    if result <> invalid then prev.screenResult = result
    prev.active = true
end sub

sub resetTo(name as string, params = {} as object)
    for each s in m.stack
        s.active = false
        s.unobserveField("navigateTo")
        s.unobserveField("close")
    end for
    m.screens.removeChildrenIndex(m.screens.getChildCount(), 0)
    m.stack = []
    pushScreen(name, params)
end sub

sub replaceTop(name as string, params = {} as object)
    if m.stack.Count() > 0 then
        closing = m.stack.Pop()
        closing.active = false
        closing.unobserveField("navigateTo")
        closing.unobserveField("close")
        m.screens.removeChild(closing)
    end if
    pushScreen(name, params)
end sub

' ---------- Events from screens ----------

sub onNavigate(event as object)
    req = event.getData()
    if req = invalid or req.screen = invalid then return
    params = req.params
    if params = invalid then params = {}
    if req.screen = "@start" then
        routeToStart(params)
    else if req.reset = true then
        resetTo(req.screen, params)
    else if req.replace = true then
        replaceTop(req.screen, params)
    else
        pushScreen(req.screen, params)
    end if
end sub

sub onCloseScreen(event as object)
    if event.getData() <> true then return
    screen = event.getRoSGNode()
    top = topScreen()
    if top <> invalid and top.isSameNode(screen) then popScreen()
end sub

sub onToast()
    msg = m.global.toast
    if Str_isEmpty(msg) then return
    m.toast.message = msg
end sub

sub onAuthExpired()
    if m.global.authExpired <> true then return
    m.global.authExpired = false
    s = m.global.session
    Session_signOutLocal(s)
    m.global.toast = "Your session expired. Please sign in again."
    routeToStart()
end sub

' ---------- Deep links ----------

sub onLaunchArgs()
    handleDeepLink(m.top.launchArgs)
end sub

sub onInputArgs()
    handleDeepLink(m.top.inputArgs)
end sub

sub handleDeepLink(args as dynamic)
    if args = invalid then return
    ' Developer aids for the simulator (tools/simulate.py, tools/mock_server.py).
    if args.debugSession = "mock" then
        s = AA_copy(m.global.session)
        s.serverUrl = "http://127.0.0.1:8097"
        s.serverOrigin = s.serverUrl
        s.serverName = "Mock Silo"
        s.serverId = "mock-server-1"
        s.accessToken = "acc-debug"
        s.refreshToken = "ref-debug"
        s.expiresAt = Time_nowSeconds() + 3600
        s.user = { id: "1", username: "laura", role: "admin" }
        s.profileId = "p-owner"
        s.profileName = "Laura"
        s.profileAvatar = "/mock-img/avatar/laura.jpg"
        Session_save(s)
        if Str_isEmpty(args.debugScreen) then routeToStart()
    end if
    if not Str_isEmpty(args.debugScreen) then
        params = {}
        if not Str_isEmpty(args.debugItem) then params.itemId = args.debugItem
        if not Str_isEmpty(args.debugFile) then params.fileId = args.debugFile ' PlayerScreen: play this version (mock 4K files: 52, 56)
        if not Str_isEmpty(args.debugUrl) then params.url = args.debugUrl ' StreamTestScreen: an extra stream to try
        resetTo(args.debugScreen, params)
        return
    end if
    if Str_isEmpty(args.contentId) then return
    if Str_isEmpty(m.global.session.profileId) then return
    mediaType = LCase(Str_orEmpty(args.mediaType))
    if mediaType = "album" or mediaType = "artist" or mediaType = "audiobook" or mediaType = "track" then
        pushScreen("AudioDetailScreen", { itemId: args.contentId, itemType: mediaType })
    else if mediaType = "movie" or mediaType = "episode" or mediaType = "series" or mediaType = "season" or mediaType = "" then
        pushScreen("DetailScreen", { itemId: args.contentId })
    end if
end sub

' ---------- Keys ----------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "back" then
        popScreen()
        return true
    end if
    return false
end function
