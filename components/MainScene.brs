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
        staleProfile: {}            ' set by ApiTask on 403 profile_verification_required (see onStaleProfile)
        sessionChanged: 0           ' bumped whenever the session is saved
        homeDirty: false            ' set after playback or state changes so Home refreshes
        settings: { ready: false, available: false, identity: "", revision: 0, manifestRevision: 0, items: {}, error: "" } ' server-synced settings snapshot (Settings.brs)
    })
    ' Screen reader (A11y.brs): the one roAudioGuide lives in A11yTask; a11yLast is the dedupe key;
    ' a11yForce (deep link debugA11y=1) speaks and logs even with the reader off, for the simulator.
    a11yTask = CreateObject("roSGNode", "A11yTask")
    m.global.addFields({ a11yTask: a11yTask, a11yLast: "", a11yForce: false })
    a11yTask.control = "RUN"
    m.top.observeField("dialog", "onDialogChanged")
    ' Launch beacons (Launch_ready in Utils.brs; onLaunchReady below) and memory warnings.
    m.global.addFields({ launchReady: "", memoryLow: false })
    m.global.observeField("launchReady", "onLaunchReady")
    ' Home cache (HomeCache.brs): Session_save bumps homeCachePurge when the account, server or
    ' profile that owns the cached Home changes; onHomeCachePurge deletes the files in a Task.
    m.global.addFields({ homeCachePurge: 0, homeCachePurgeReason: "" })
    m.global.observeField("homeCachePurge", "onHomeCachePurge")
    m.launch = { done: false, dialog: false }

    ' Single-flight token refresher used by every ApiTask.
    authTask = CreateObject("roSGNode", "AuthTask")
    m.global.addFields({ authTask: authTask })
    authTask.control = "RUN"

    ' Remote control and phone sign-in for Silo's phone app (LanTask, RemoteControl).
    m.remote = CreateObject("roSGNode", "RemoteControl")
    m.top.appendChild(m.remote)
    m.remote.observeField("launchRequest", "onRemoteLaunch")

    m.global.observeField("toast", "onToast")
    m.global.observeField("authExpired", "onAuthExpired")
    m.global.observeField("staleProfile", "onStaleProfile")
    m.profilePrompt = invalid       ' a pending "pick your profile again" prompt (onStaleProfile)

    ' Profile Selection (ProfileLaunch.brs): settle a new Roku's starting choice, then apply the
    ' launch rule before anything records this run as "in use".
    ProfileLaunch_settleFirstLaunch(not Str_isEmpty(m.global.session.profileId))
    applyLaunchProfileRule()
    m.pendingDeepLink = invalid
    routeToStart()

    ' The away clock for the timed choices: Home closes a channel without telling it, so "last in
    ' use" is refreshed every 5-10 minutes while Siku runs (and on Back out of the app).
    m.activeTimer = CreateObject("roSGNode", "Timer")
    m.activeTimer.duration = ProfileLaunch_heartbeatSeconds()
    m.activeTimer.repeat = true
    m.activeTimer.observeField("fire", "onActiveTick")
    m.activeTimer.control = "start"
end sub

' At launch, when the setting asks: forget the saved profile and its PIN proof, so Who's Watching
' shows and a protected profile needs its PIN again. The account stays signed in.
sub applyLaunchProfileRule()
    s = m.global.session
    if Str_isEmpty(s.accessToken) or Str_isEmpty(s.profileId) then return
    if not ProfileLaunch_requiresSelectionAtLaunch() then return
    c = AA_copy(s)
    c.profileId = ""
    c.profileToken = ""
    c.profileName = ""
    c.profileAvatar = ""
    Session_save(c)
    m.askedAtLaunch = true
end sub

sub onDebugRelaunch()
    print "[siku-home] debug relaunch"
    routeToStart()
end sub

sub onHomeCachePurge()
    ' Keep the active owner's file (a new profile's Home may already have written it); a sign-out
    ' has no owner, so everything goes. The reference keeps the Task alive while it runs.
    task = CreateObject("roSGNode", "HomeCacheTask")
    task.job = { action: "purge", reason: Str_orEmpty(m.global.homeCachePurgeReason), keepOwnerSource: HomeCache_ownerSource(m.global.session) }
    task.control = "RUN"
    m.homeCachePurgeTask = task
end sub

sub onActiveTick()
    ProfileLaunch_heartbeat()
end sub

' Decides the first screen from what we have stored.
sub routeToStart(params = {} as object)
    s = m.global.session
    if Str_isEmpty(s.serverUrl) then
        resetTo("ServerConnectScreen", params)
    else if Str_isEmpty(s.accessToken) then
        resetTo("LoginScreen", params)
    else if Str_isEmpty(s.profileId) then
        ' Asked by the launch rule: show the picker even for a one-profile household.
        if m.askedAtLaunch = true then
            m.askedAtLaunch = false
            params = AA_copy(params)
            params.atLaunch = true
        end if
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
    A11y_reset()
    Launch_onScreen(name)
    screen.active = true
    ' Under memory pressure a screen gives back its artwork as soon as it is covered.
    if prev <> invalid and m.global.memoryLow = true then prev.memoryRelease = true
    if m.debugMemoryAt <> invalid and m.stack.Count() >= 2 then
        m.top.memoryPressure = m.debugMemoryAt
        m.debugMemoryAt = invalid
    end if
    checkProfilePrompt()
end sub

sub popScreen()
    if m.stack.Count() <= 1 then
        ProfileLaunch_markActive(0)
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
    A11y_reset()
    if result <> invalid then prev.screenResult = result
    prev.active = true
    checkProfilePrompt()
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
    ' A content link that arrived while Who's Watching was up opens once a profile is chosen.
    if name = "ShellScreen" and m.pendingDeepLink <> invalid and not Str_isEmpty(m.global.session.profileId) then
        link = m.pendingDeepLink
        m.pendingDeepLink = invalid
        handleDeepLink(link)
    end if
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

' ---------- Launch beacons ----------
' Roku measures launch time up to AppLaunchComplete, which is signalled once the first real screen
' is up: Home drawn (HomePage), a deep-linked title's details shown (DetailScreen) or video playing
' (PlayerScreen), each through Launch_ready. Time spent signing in or picking a profile at launch
' is the viewer's, so the server, sign-in and profile screens are bracketed by AppDialogInitiate /
' AppDialogComplete (before AppLaunchComplete only, as Roku asks). The PIN pad is part of the
' profile screen's bracket. Adapted from ManavA/silo-roku, AGPL-3.0 (components/SiloUILaunch.brs).

sub Launch_onScreen(name as string)
    if m.launch.done then return
    gate = name = "ServerConnectScreen" or name = "LoginScreen" or name = "ProfileScreen"
    if gate and not m.launch.dialog then
        m.launch.dialog = true
        Launch_beacon("AppDialogInitiate")
    else if not gate and m.launch.dialog then
        m.launch.dialog = false
        Launch_beacon("AppDialogComplete")
    end if
end sub

sub onLaunchReady()
    what = m.global.launchReady
    if m.launch.done or Str_isEmpty(what) then return
    if m.launch.dialog then
        m.launch.dialog = false
        Launch_beacon("AppDialogComplete")
    end if
    m.launch.done = true
    Launch_beacon("AppLaunchComplete")
    print "[siku-launch] ready: "; what
    m.global.unobserveField("launchReady")
end sub

sub Launch_beacon(name as string)
    print "[siku-launch] beacon "; name
    m.top.signalBeacon(name)
end sub

' ---------- Memory and focus ----------

' A memory warning (70 % of the channel's limit or more): every screen under the top one drops its
' artwork and list content, and keeps doing so when covered until the pressure eases (50 % or
' less); the top screen drops its own caches (onMemoryPressure).
sub onMemoryPressure()
    level = m.top.memoryPressure
    print "[siku-memory] pressure "; level
    if level <= 50 then
        m.global.memoryLow = false
        return
    end if
    if level < 70 then return
    m.global.memoryLow = true
    top = topScreen()
    for each s in m.stack
        if top <> invalid and s.isSameNode(top) then
            s.memoryPressure = level
        else
            s.memoryRelease = true
        end if
    end for
end sub

sub onAppFocused()
    ' Back from a system overlay: the reader should say the focused control again.
    if m.top.appFocused then A11y_reset()
end sub

sub onDialogChanged()
    A11y_reset()
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
    ' A longer message (a full sentence to read on a TV) sets m.global.toastSeconds first.
    secs = 3.5
    if m.global.hasField("toastSeconds") then
        asked = Num_or(m.global.toastSeconds, 0)
        if asked > 0 then secs = asked
        m.global.toastSeconds = 0
    end if
    m.toast.duration = secs
    m.toast.message = msg
end sub

sub onAuthExpired()
    if m.global.authExpired <> true then return
    m.global.authExpired = false
    s = m.global.session
    if isTemporarySession(s) then
        ' A phone's borrowed profile expired: hand it back, keep the Roku's own sign-in.
        m.remote.endBorrowed = "refresh refused"
        m.global.toast = "The phone profile session expired."
        return
    end if
    Session_signOutLocal(s)
    m.global.toast = "Your session expired. Please sign in again."
    routeToStart()
end sub

' ---------- Profile access recovery (Android TV ProfileVerificationRecovery, upstream #440) ----------
' An administrator changed the account's access, so the server stopped accepting the active PIN
' profile's token and answers 403 profile_verification_required. Instead of letting every screen
' fail, clear the profile selection (never the sign-in) and send the viewer to the profile picker.
' Only a refusal for the identity that is active right now counts, so a late or repeated report
' (or one for a profile already switched away from) does nothing and cannot loop.

sub onStaleProfile()
    r = m.global.staleProfile
    if r = invalid or Type(r) <> "roAssociativeArray" or Str_isEmpty(r.profileId) then return
    s = m.global.session
    if Str_isEmpty(s.accessToken) or Str_isEmpty(s.profileId) then return
    if isTemporarySession(s) then return
    if Str_orEmpty(r.profileId) <> Str_orEmpty(s.profileId) then return
    if Str_orEmpty(r.profileToken) <> Str_orEmpty(s.profileToken) then return
    if Url_origin(Str_orEmpty(r.serverUrl)) <> Url_origin(Str_orEmpty(s.serverUrl)) then return
    print "[MainScene] the server no longer accepts this profile's proof; clearing the profile selection"
    c = AA_copy(s)
    c.profileId = ""
    c.profileToken = ""
    c.profileName = ""
    c.profileAvatar = ""
    Session_save(c)
    if m.global.hasField("requests") then m.global.requests = { enabled: false, resolved: false }
    if m.global.hasField("shuffleCaps") then m.global.shuffleCaps = {}
    m.profilePrompt = { serverUrl: Str_orEmpty(s.serverUrl) }
    checkProfilePrompt()
end sub

' Acts on a pending prompt for the screen now on top: playback and the sign-in/server screens are
' not interrupted (the prompt waits until the viewer leaves them), the picker itself needs nothing,
' and a prompt that no longer applies (signed out, another server, a profile picked) is dropped.
sub checkProfilePrompt()
    prompt = m.profilePrompt
    if prompt = invalid then return
    s = m.global.session
    if Str_isEmpty(s.accessToken) or not Str_isEmpty(s.profileId) or Str_orEmpty(s.serverUrl) <> prompt.serverUrl then
        m.profilePrompt = invalid
        return
    end if
    top = topScreen()
    if top = invalid then return
    name = top.subtype()
    if name = "PlayerScreen" or name = "AudioPlayerScreen" or name = "LoginScreen" or name = "ServerConnectScreen" then return
    m.profilePrompt = invalid
    if name = "ProfileScreen" then return
    resetTo("ProfileScreen", { switching: true })
end sub

function isTemporarySession(s as object) as boolean
    t = s.temporary
    if Type(t) = "Boolean" or Type(t) = "roBoolean" then return t
    return false
end function

' ---------- Remote control launches ----------

' A phone launched a title (RemoteControl.onLaunch): it replaces a player on top, or opens over
' whatever screen is up. A signed-out Roku has no shell under it; the player then closes back to
' the sign-in screen.
sub onRemoteLaunch()
    params = m.remote.launchRequest
    if params = invalid then return
    top = topScreen()
    if top <> invalid then
        name = top.subtype()
        if name = "PlayerScreen" or name = "AudioPlayerScreen" then
            replaceTop("PlayerScreen", params)
            return
        end if
    end if
    pushScreen("PlayerScreen", params)
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
    ' debugA11y=1: speak (and log "[siku-a11y] say:") as if Roku's screen reader were on.
    if not Str_isEmpty(args.debugA11y) then m.global.a11yForce = args.debugA11y = "1"
    ' debugMemory=<percent>: replay a memory warning once a second screen is open (the simulator
    ' never sends one), so the covered screen's release and restore can be watched.
    if not Str_isEmpty(args.debugMemory) then m.debugMemoryAt = Int(Val(Str_orEmpty(args.debugMemory)))
    ' debugRelaunch=<seconds>: rebuild the start screen once after that long, as a second launch
    ' would. brs-cli keeps cachefs in memory only, so this is how the simulator shows the Home cache
    ' drawing before the server answers (with tools/mock_server.py --home-delay).
    if not Str_isEmpty(args.debugRelaunch) then
        m.relaunchTimer = CreateObject("roSGNode", "Timer")
        m.relaunchTimer.duration = Val(Str_orEmpty(args.debugRelaunch))
        m.relaunchTimer.observeField("fire", "onDebugRelaunch")
        m.relaunchTimer.control = "start"
    end if
    if args.debugSession = "mock" then
        s = AA_copy(m.global.session)
        ' debugPort lets several simulator runs use separate mock servers.
        port = "8097"
        if not Str_isEmpty(args.debugPort) then port = args.debugPort
        s.serverUrl = "http://127.0.0.1:" + port
        s.serverOrigin = s.serverUrl
        s.serverName = "Mock Silo"
        s.serverId = "mock-server-1"
        ' debugNoServerId=1: a session saved by an older Siku, with no deployment identity recorded
        ' (RemoteControl reads and records it, Silo Android #717).
        if args.debugNoServerId = "1" then s.serverId = ""
        ' debugServers=reset: forget the remembered servers first (the simulator's registry is shared
        ' by every worktree's runs), so a handoff's saved addresses are only this mock's.
        if args.debugServers = "reset" then Registry_write("servers", [])
        s.accessToken = "acc-debug"
        s.refreshToken = "ref-debug"
        s.expiresAt = Time_nowSeconds() + 3600
        s.user = { id: "1", username: "laura", role: "admin" }
        s.profileId = "p-owner"
        s.profileName = "Laura"
        s.profileAvatar = "/mock-img/avatar/laura.jpg"
        Session_save(s)
        ' debugProfileLaunch=<automatic|askEveryLaunch|afterOneHour|afterTwelveHours|new>[&debugAwaySeconds=N]
        ' replays the launch rule against the seeded profile ("new" = a Roku with no saved choice).
        if not Str_isEmpty(args.debugProfileLaunch) then
            p = AA_copy(m.global.prefs)
            p.profileLaunch = ""
            p.profileLaunchOffer = false
            Prefs_save(p)
            if args.debugProfileLaunch = "new" then
                ProfileLaunch_settleFirstLaunch(false)
            else
                ProfileLaunch_setBehavior(args.debugProfileLaunch)
            end if
            if not Str_isEmpty(args.debugAwaySeconds) then Registry_write("profileLastActive", Time_nowSeconds() - Int(Val(args.debugAwaySeconds)))
            applyLaunchProfileRule()
        end if
        if Str_isEmpty(args.debugScreen) then routeToStart()
    end if
    if not Str_isEmpty(args.debugScreen) then
        params = {}
        if not Str_isEmpty(args.debugItem) then params.itemId = args.debugItem
        if not Str_isEmpty(args.debugFile) then params.fileId = args.debugFile ' PlayerScreen: play this version (mock 4K files: 52, 56)
        if not Str_isEmpty(args.debugBufq) then params.debugBufq = true ' PlayerScreen: fake a play-then-stall for the buffering-quality controller (the simulator never plays)
        if not Str_isEmpty(args.debugHoldSeek) then params.debugHoldSeek = true ' PlayerScreen: start hold-to-seek as a held Right would (the simulator cannot hold a key)
        if not Str_isEmpty(args.debugVideoError) then params.debugVideoError = Str_orEmpty(args.debugVideoError) ' PlayerScreen: fake this Roku Video error code 4 s after every plan (native recovery; PlaybackRecovery.brs)
        if not Str_isEmpty(args.debugStallSeconds) then params.debugStallSeconds = Str_orEmpty(args.debugStallSeconds) ' PlayerScreen: no-progress limit for the buffering_timeout recovery (default 60 s / 120 s)
        if not Str_isEmpty(args.debugSubtitle) then params.subtitleTrackIndex = Int(Val(Str_orEmpty(args.debugSubtitle))) ' PlayerScreen: start with this subtitle (combined index), as a details-page pick
        if not Str_isEmpty(args.debugUrl) then params.url = args.debugUrl ' StreamTestScreen: an extra stream to try
        if not Str_isEmpty(args.debugDeepLink) then params.debugDeepLink = Str_orEmpty(args.debugDeepLink) ' PlayerScreen: a content deep link for the playing item arrives after this many seconds (replaces the player)
        if not Str_isEmpty(args.debugVoice) then params.debugVoice = Str_orEmpty(args.debugVoice) ' PlayerScreen / AudioPlayerScreen: inject this voice transport command (<command>[:<seconds>]) once playback has started (the simulator sends none)
        if not Str_isEmpty(args.debugLanSelf) then params.debugLanSelf = true ' ServerConnectScreen: Find servers also accepts this machine's own address (tools/silo_responder.py)
        resetTo(args.debugScreen, params)
        return
    end if
    if Str_isEmpty(args.contentId) then return
    if Str_isEmpty(m.global.session.profileId) then
        ' Signed in but no profile yet (Who's Watching): hold the link until one is chosen.
        if not Str_isEmpty(m.global.session.accessToken) then m.pendingDeepLink = args
        return
    end if
    mediaType = LCase(Str_orEmpty(args.mediaType))
    ' A link that arrives while a player is on top replaces the player (as a phone launch does): a
    ' player covered by another screen has stopped and closed its session, so it is never kept.
    replacePlayer = false
    top = topScreen()
    if top <> invalid then replacePlayer = top.subtype() = "PlayerScreen" or top.subtype() = "AudioPlayerScreen"
    screenName = ""
    params = invalid
    if mediaType = "album" or mediaType = "artist" or mediaType = "audiobook" or mediaType = "track" then
        screenName = "AudioDetailScreen"
        params = { itemId: args.contentId, itemType: mediaType }
    else if mediaType = "movie" or mediaType = "episode" or mediaType = "series" or mediaType = "season" or mediaType = "" then
        screenName = "DetailScreen"
        params = { itemId: args.contentId }
    end if
    if screenName = "" then return
    if replacePlayer then
        print "[MainScene] deep link replaces the player on top"
        replaceTop(screenName, params)
    else
        pushScreen(screenName, params)
    end if
end sub

' ---------- Voice transport ----------

' A Roku voice transport event from source/main.brs (called synchronously; the answer goes back to
' Roku). Only a player on top of the stack acts on it; everything else is refused.
function handleTransport(info as dynamic) as object
    result = { "status": "error.generic" }
    top = topScreen()
    name = "none"
    if top <> invalid then name = top.subtype()
    if m.top.dialog <> invalid then
        name = name + "+dialog"
    else if name = "PlayerScreen" or name = "AudioPlayerScreen" then
        r = top.callFunc("voiceTransport", info)
        if Type(r) = "roAssociativeArray" and r.status <> invalid then result = r
    end if
    line = "[siku-voice] " + Voice_describe(info) + " screen=" + name + " result=" + Str_orEmpty(result.status)
    if result.target <> invalid then line = line + " target=" + Int(Num_or(result.target, 0)).ToStr()
    if not Str_isEmpty(result.reason) then line = line + " reason=" + Str_orEmpty(result.reason)
    print line
    return result
end function

' ---------- Keys ----------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "back" then
        popScreen()
        return true
    end if
    return false
end function
