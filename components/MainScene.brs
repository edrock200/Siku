' Root scene: screen stack, Back handling, startup routing.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.top.backgroundColor = "0x000000FF"
    m.top.backgroundUri = ""
    m.screens = m.top.findNode("screens")
    m.toast = m.top.findNode("toast")
    m.stack = []

    ' Registry layout 2 (several accounts per server, Accounts.brs): an older Roku's sign-ins move
    ' into accounts offline, before anything reads the session.
    migration = Accounts_migrate()

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
        exiting: false              ' Back left the app: requests started now hold the exit (beginExit)
        exitHolds: []               ' those requests' ApiTasks
    })
    ' Screen reader (A11y.brs): the one roAudioGuide lives in A11yTask; a11yLast is the dedupe key;
    ' a11yForce (deep link debugA11y=1) speaks and logs even with the reader off, for the simulator.
    a11yTask = CreateObject("roSGNode", "A11yTask")
    m.global.addFields({ a11yTask: a11yTask, a11yLast: "", a11yForce: false })
    a11yTask.control = "RUN"
    m.top.observeField("dialog", "onDialogChanged")
    ' Launch beacons (Launch_ready in Utils.brs; onLaunchReady below) and memory warnings.
    ' memoryLevel / lowEnd: MemoryPolicy.brs (0 normal .. 3 critical; a low-memory Roku, onDeviceTier).
    m.global.addFields({ launchReady: "", memoryLow: false, memoryLevel: 0, lowEnd: false })
    m.global.observeField("launchReady", "onLaunchReady")
    ' Home cache (HomeCache.brs): Session_save bumps homeCachePurge when the account, server or
    ' profile that owns the cached Home changes; onHomeCachePurge deletes the files in a Task.
    m.global.addFields({ homeCachePurge: 0, homeCachePurgeReason: "" })
    m.global.observeField("homeCachePurge", "onHomeCachePurge")
    m.launch = { done: false, dialog: false }
    ' Diagnostics log and last-exit notice (DiagScene.brs).
    Diag_init()
    if migration <> "" then Diag_log(migration)

    ' Single-flight token refresher used by every ApiTask.
    authTask = CreateObject("roSGNode", "AuthTask")
    m.global.addFields({ authTask: authTask })
    authTask.control = "RUN"

    ' Remote control and phone sign-in for Silo's phone app (LanTask, RemoteControl).
    m.remote = CreateObject("roSGNode", "RemoteControl")
    m.top.appendChild(m.remote)
    m.remote.observeField("launchRequest", "onRemoteLaunch")

    ' Playback stops outlive the player (PlaybackJobs.brs: retried after a failed delivery).
    PlaybackJobs_init()

    m.global.observeField("toast", "onToast")
    ' Interface language (I18n in Utils.brs): the last profile language applied, else the Roku's.
    m.global.addFields({ appLocale: "en", strings: {} })
    m.languageRebuild = false
    I18n_apply(I18n_resolve(m.global.prefs.appLanguage, CreateObject("roDeviceInfo").GetCurrentLocale()), "launch")
    m.global.observeField("settings", "onLanguageSettings")
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
    ' Kept for a content deep link that launched the app: it skips Who's Watching (onLaunchArgs).
    m.launchRuleProfile = { profileId: s.profileId, profileToken: s.profileToken, profileName: s.profileName, profileAvatar: s.profileAvatar, accessToken: s.accessToken }
    c = AA_copy(s)
    c.profileId = ""
    c.profileToken = ""
    c.profileName = ""
    c.profileAvatar = ""
    Session_save(c)
    m.askedAtLaunch = true
end sub

sub onDebugRelaunch()
    Diag_log("[siku-home] debug relaunch")
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
    else if Str_isEmpty(s.accessToken) and Accounts_anotherSignedIn(Accounts_list(), s) then
        ' No account open (signed out, or the server refused it) while another account has a
        ' session: Change Account is the start screen (Android TV, silo-roku).
        params = AA_copy(params)
        params.root = true
        resetTo("ChangeAccountScreen", params)
    else if Str_isEmpty(s.accessToken) then
        resetTo("LoginScreen", params)
    else if Str_isEmpty(s.profileId) then
        ' Asked by the launch rule: show the picker even for a one-profile household.
        if m.askedAtLaunch = true then
            m.askedAtLaunch = false
            params = AA_copy(params)
            params.atLaunch = true
        end if
        ' A content link waiting for a profile opens one by itself (DeepLink_profileFor), as
        ' silo-roku does for Roku certification 5.1: no picker between the link and playback.
        if m.pendingDeepLink <> invalid then
            params = AA_copy(params)
            params.deepLink = true
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
        m.global.toast = Tx("Something went wrong")
        return
    end if
    ' The layout's English text in the applied language (I18n in Utils.brs), before params load data.
    I18n_translateTree(screen)
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
    ' Screens deeper than the budget give back their artwork and lists (all covered ones under pressure).
    trimStack()
    if m.debugMemoryAt <> invalid and m.stack.Count() >= 2 then
        m.top.memoryPressure = m.debugMemoryAt
        m.debugMemoryAt = invalid
    end if
    checkProfilePrompt()
end sub

sub popScreen()
    if m.stack.Count() <= 1 then
        ProfileLaunch_markActive(0)
        beginExit()
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

' ---------- Leaving the app ----------
' Back from the first screen. Before Main returns (which ends every Task at once), the top screen
' is hidden so it withdraws a sign-in code it shows (LoginScreen, or a phone's setup attempt:
' POST /api/v2/auth/device/cancel) and the LanTask says goodbye to phones and withdraws its mDNS
' records (TTL 0). Requests started meanwhile are held in m.global.exitHolds (Api_call); the app
' exits once they and the LanTask are done, or after 2 s whatever happened. Adapted from
' Silo-Server/silo-roku, AGPL-3.0 (docs/spec.md "Leaving sign-in": exit once /device/cancel
' answers or after 2 s).
sub beginExit()
    if m.leaving <> invalid then return
    m.leaving = { clock: CreateObject("roTimespan"), lan: invalid }
    m.global.exitHolds = []
    m.global.exiting = true
    top = topScreen()
    if top <> invalid then top.active = false
    lan = invalid
    if m.global.hasField("lanTask") then lan = m.global.lanTask
    if lan <> invalid then
        m.leaving.lan = lan
        lan.command = { kind: "shutdown" }
    end if
    Diag_log("[siku-launch] leaving: requests=" + m.global.exitHolds.Count().ToStr() + " lan=" + exitBool(lan <> invalid))
    m.exitTimer = CreateObject("roSGNode", "Timer")
    m.exitTimer.duration = 0.1
    m.exitTimer.repeat = true
    m.exitTimer.observeField("fire", "onExitTick")
    m.exitTimer.control = "start"
end sub

sub onExitTick()
    e = m.leaving
    pending = 0
    for each t in m.global.exitHolds
        if t <> invalid then
            r = t.response
            answered = Type(r) = "roAssociativeArray" and r.Count() > 0
            st = Str_orEmpty(t.state)
            if not answered and st <> "stop" and st <> "done" then pending = pending + 1
        end if
    end for
    lanDone = e.lan = invalid or e.lan.stopped = true
    ms = e.clock.TotalMilliseconds()
    if (pending = 0 and lanDone) or ms >= 2000 then
        m.exitTimer.control = "stop"
        Diag_log("[siku-launch] exit after " + ms.ToStr() + " ms (requests pending=" + pending.ToStr() + " lan done=" + exitBool(lanDone) + ")")
        m.top.exitApp = true
    end if
end sub

function exitBool(v as boolean) as string
    if v then return "true"
    return "false"
end function

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
        print "[siku-deeplink] opening the held link"
        openDeepLink(link)
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
    Diag_log("[siku-launch] ready: " + what)
    m.global.unobserveField("launchReady")
    Diag_tryNotice()
end sub

sub Launch_beacon(name as string)
    Diag_log(Diag_join(["[siku-launch] beacon ", name]))
    m.top.signalBeacon(name)
end sub

' ---------- Memory and focus ----------

' A memory warning or a sample from source/main.brs (percent of the channel's limit) moves the
' level (MemoryPolicy.brs): trim, pressure, critical. A rising level asks the top screen to drop its
' own caches (onMemoryPressure) and releases the covered screens past the level's budget.
sub onMemoryPressure()
    pct = m.top.memoryPressure
    prev = Memory_currentLevel()
    level = Memory_nextLevel(prev, pct)
    if level = prev then return
    Diag_log("[siku-memory] pressure " + pct.ToStr() + " level=" + Memory_levelName(level) + " was=" + Memory_levelName(prev))
    m.global.memoryLevel = level
    m.global.memoryLow = level >= 2
    if level < prev then return
    top = topScreen()
    if top <> invalid then top.memoryPressure = pct
    trimStack()
end sub

' Keeps the top screen and Memory_aliveBelow() screens under it whole; deeper ones give back their
' artwork and lists (Memory.brs) and get them back, state intact, when they are on top again.
sub trimStack()
    keep = Memory_aliveBelow(Memory_currentLevel(), Memory_isLowEnd())
    for i = 0 to m.stack.Count() - 2 - keep
        m.stack[i].memoryRelease = true
    end for
end sub

' From source/main.brs at launch: a low-memory Roku gets smaller budgets (MemoryPolicy.brs).
sub onDeviceTier()
    t = m.top.deviceTier
    if Type(t) <> "roAssociativeArray" then return
    low = false
    if Type(t.low) = "Boolean" or Type(t.low) = "roBoolean" then low = t.low
    m.global.lowEnd = low
    tier = "standard"
    if low then tier = "low"
    Diag_log("[siku-memory] device tier=" + tier + " reasons=" + Str_orEmpty(t.reasons) + " limit_mb=" + Str_orEmpty(t.foregroundMb))
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
    if m.languageRebuild = true and not languagePlayerOnTop() then languageRebuild()
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
        m.global.toast = Tx("The phone profile session expired.")
        return
    end if
    ' Not a sign-out (Silo Android #795): the account stays saved, needing to sign in again.
    ' A second refusal for the same expiry (requests that were in flight) changes nothing.
    if Str_isEmpty(s.accessToken) and Str_isEmpty(s.refreshToken) then return
    Session_expireLocal(s)
    m.global.toast = Tx("Your session expired. Please sign in again.")
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
    args = m.top.launchArgs
    Diag_launchArgs(args)
    ' A content link at launch never shows Who's Watching for a profile this Roku already had open:
    ' the launch rule (Profile Selection) asked for the picker, so the profile it put aside opens
    ' again and the link plays over Home (Roku certification 5.1; silo-roku does the same).
    link = DeepLink_parse(args)
    keep = m.launchRuleProfile
    m.launchRuleProfile = invalid
    if link <> invalid and link.valid and keep <> invalid then
        s = m.global.session
        if Str_isEmpty(s.profileId) and not Str_isEmpty(s.accessToken) and s.accessToken = keep.accessToken then
            c = AA_copy(s)
            c.profileId = keep.profileId
            c.profileToken = keep.profileToken
            c.profileName = keep.profileName
            c.profileAvatar = keep.profileAvatar
            Session_save(c)
            m.askedAtLaunch = false
            m.pendingDeepLink = link
            print "[siku-deeplink] launch link skips Who's Watching; reopening the last profile"
            routeToStart()
            return
        end if
    end if
    handleDeepLink(args)
end sub

sub onInputArgs()
    handleDeepLink(m.top.inputArgs)
end sub

sub handleDeepLink(args as dynamic)
    if args = invalid then return
#if DEBUG
    ' Developer aids for the simulator (tools/simulate.py, tools/mock_server.py). Compiled only when
    ' the manifest says bs_const=DEBUG=true, which tools/simulate.py sets in its own copy of the
    ' package: the release package (npm run package, manifest DEBUG=false) has none of them, so no
    ' device on the network can sign the viewer out, forget servers or play an arbitrary URL with
    ' an ECP launch link.
    ' debugA11y=1: speak (and log "[siku-a11y] say:") as if Roku's screen reader were on.
    if not Str_isEmpty(args.debugA11y) then m.global.a11yForce = args.debugA11y = "1"
    ' debugLang=<de|fr|es|pt-BR|en>: apply that interface language now (screens built from here on).
    if not Str_isEmpty(args.debugLang) then
        m.debugLang = I18n_resolve(args.debugLang, "en_US")
        I18n_apply(m.debugLang, "debug")
    end if
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
        if args.debugServers = "reset" or args.debugServers = "two" then Registry_write("servers", [])
        ' debugAccounts=reset|two|legacy: start with no saved accounts (the registry is shared by every
        ' worktree's runs); two also saves a second account on this server (user "sam", id 2; mock
        ' tokens acc-debug-sam); legacy writes this session as an older Siku stored it (registry layout
        ' 1, a second server's sign-in in its entry) and runs the migration (Accounts.brs) again.
        if args.debugAccounts = "reset" or args.debugAccounts = "two" or args.debugAccounts = "legacy" then
            Registry_write("accounts", [])
            s.accountId = ""
        end if
        s.accessToken = "acc-debug"
        s.refreshToken = "ref-debug"
        s.expiresAt = Time_nowSeconds() + 3600
        s.user = { id: "1", username: "laura", role: "admin" }
        s.profileId = "p-owner"
        s.profileName = "Laura"
        s.profileAvatar = "/mock-img/avatar/laura.jpg"
        Session_save(s)
        ' debugServers=two: also save a second, distinct server signed in on its own (Manage Servers;
        ' tools/mock_server.py --port <debugPort2, default debugPort+1> --server-id mock-server-2
        ' --server-name "Den Silo").
        if args.debugServers = "two" then
            port2 = Int(Val(port)) + 1
            if not Str_isEmpty(args.debugPort2) then port2 = Int(Val(Str_orEmpty(args.debugPort2)))
            url2 = Left(s.serverUrl, Len(s.serverUrl) - Len(port)) + port2.ToStr() ' the same loopback host, another port
            list = Session_serversWithout(Session_savedServers(), url2)
            list.Push({ url: url2, name: "Den Silo", id: "mock-server-2" })
            Registry_write("servers", list)
            ' Its sign-in is an account of its own (registry layout 2, Accounts.brs).
            accts = Accounts_without(Accounts_withoutServer(Accounts_list(), url2), "debug-account-den")
            den = { "id": "debug-account-den", "url": url2, "userid": "7", "username": "sam", "profiles": -1, "added": Time_nowSeconds(), "used": Time_nowSeconds() - 120, "expired": false }
            den.session = { serverOrigin: url2, accessToken: "acc-debug2", refreshToken: "ref-debug2", expiresAt: Time_nowSeconds() + 3600, user: { id: "7", username: "sam", role: "user" }, profileId: "p-sam", profileName: "Sam", profileToken: "", profileAvatar: "" }
            accts.Push(den)
            Registry_write("accounts", accts)
        end if
        if args.debugAccounts = "two" then
            list = Accounts_list()
            other = { "id": "debug-account-sam", "url": s.serverUrl, "userid": "2", "username": "sam", "profiles": -1, "added": Time_nowSeconds() + 1, "used": Time_nowSeconds() - 60, "expired": false }
            other.session = { serverOrigin: s.serverUrl, accessToken: "acc-debug-sam", refreshToken: "ref-debug-sam", expiresAt: Time_nowSeconds() + 3600, user: { id: "2", username: "sam", role: "user" }, profileId: "", profileName: "", profileToken: "", profileAvatar: "" }
            list = Accounts_without(list, "debug-account-sam")
            list.Push(other)
            Registry_write("accounts", list)
        else if args.debugAccounts = "legacy" then
            legacy = AA_copy(m.global.session)
            legacy.Delete("accountId")
            port2 = (Int(Val(port)) + 1).ToStr()
            url2 = Left(s.serverUrl, Len(s.serverUrl) - Len(port)) + port2 ' the same loopback host, another port
            Registry_write("session", legacy)
            Registry_write("servers", [{ url: s.serverUrl, name: "Mock Silo", id: "mock-server-1" }, { url: url2, name: "Den Silo", id: "mock-server-2", session: { serverOrigin: url2, accessToken: "acc-debug2", refreshToken: "ref-debug2", expiresAt: Time_nowSeconds() + 3600, user: { id: "7", username: "sam", role: "user" }, profileId: "p-sam", profileName: "Sam", profileToken: "", profileAvatar: "" } }])
            Registry_delete("accounts")
            Registry_write("layout", 1)
            line = Accounts_migrate()
            if line <> "" then Diag_log(line)
            m.global.session = Session_load()
        end if
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
        if not Str_isEmpty(args.debugQuery) then params.query = Str_orEmpty(args.debugQuery) ' SearchScreen: search for this
        if not Str_isEmpty(args.debugLibrary) then params.libraryId = Str_orEmpty(args.debugLibrary) ' LibraryScreen: browse this library (mock: 1 = Movies)
        if not Str_isEmpty(args.debugManage) then params.manage = true ' ServerConnectScreen: open as Manage Servers (pushed over the shell in the app)
        if not Str_isEmpty(args.debugLanSelf) then params.debugLanSelf = true ' ServerConnectScreen: Find servers also accepts this machine's own address (tools/silo_responder.py)
        resetTo(args.debugScreen, params)
        return
    end if
#end if
    link = DeepLink_parse(args)
    if link = invalid then return
    if not link.valid then
        print "[siku-deeplink] refused reason=" + link.reason
        return
    end if
    openDeepLink(link)
end sub

' A valid content link (DeepLink.brs). Signed out, or signed in with no profile open: it waits and
' opens once a profile is chosen (resetTo ShellScreen). Otherwise a video item is read under the
' open profile and played at once (a series or season: its next episode), resuming where the
' profile left off; music opens its page. The player replaces a player on top. Nothing that does
' not resolve changes the screen.
sub openDeepLink(link as object)
    s = m.global.session
    if Str_isEmpty(s.accessToken) or Str_isEmpty(s.profileId) then
        m.pendingDeepLink = link
        print "[siku-deeplink] held until " + deepLinkWaitsFor(s) + " type=" + deepLinkType(link)
        return
    end if
    if link.kind = "audio" then
        showDeepLinkScreen("AudioDetailScreen", { itemId: link.contentId, itemType: link.mediaType })
        return
    end if
    if m.deepLinkGen = invalid then m.deepLinkGen = 0
    m.deepLinkGen = m.deepLinkGen + 1
    print "[siku-deeplink] resolving type=" + deepLinkType(link)
    Api_call({ method: "GET", path: "/api/v2/catalog/items/" + Str_urlEncode(link.contentId), query: { image_size: "small" }, timeout: 15, context: { gen: m.deepLinkGen, stage: "item" } }, "onDeepLinkItem")
end sub

function deepLinkWaitsFor(s as object) as string
    if Str_isEmpty(s.serverUrl) then return "server setup"
    if Str_isEmpty(s.accessToken) then return "sign-in"
    return "profile"
end function

function deepLinkType(link as object) as string
    if link.mediaType = "" then return "none"
    return link.mediaType
end function

sub onDeepLinkItem(event as object)
    resp = Api_result(event)
    if resp.context = invalid or resp.context.gen <> m.deepLinkGen then
        print "[siku-deeplink] answer dropped: a newer link arrived"
        return
    end if
    if not resp.ok or Type(resp.data) <> "roAssociativeArray" then
        print "[siku-deeplink] dropped reason=unavailable status=" + Str_orEmpty(resp.status)
        m.global.toast = Tx("That title isn't available.")
        return
    end if
    if resp.context.stage = "next" then
        deepLinkPlay(resp.data)
        return
    end if
    r = DeepLink_route(resp.data)
    print "[siku-deeplink] item type=" + LCase(Str_orEmpty(resp.data["type"])) + " action=" + r.action
    if r.action = "play" then
        deepLinkPlay(resp.data)
    else if r.action = "next" then
        ' A series or season: read the episode it plays next, for its resume point.
        Api_call({ method: "GET", path: "/api/v2/catalog/items/" + Str_urlEncode(r.itemId), query: { image_size: "small" }, timeout: 15, context: { gen: m.deepLinkGen, stage: "next" } }, "onDeepLinkItem")
    else if r.action = "detail" then
        showDeepLinkScreen("DetailScreen", { itemId: r.itemId })
    else if r.action = "audio" then
        showDeepLinkScreen("AudioDetailScreen", { itemId: r.itemId, itemType: r.itemType })
    else
        m.global.toast = Tx("That title isn't available.")
    end if
end sub

sub deepLinkPlay(item as object)
    params = DeepLink_playerParams(item)
    if params.itemId = "" then return
    resumeAt = 0
    if params.startPosition <> invalid then resumeAt = Int(params.startPosition)
    print "[siku-deeplink] play resume=" + resumeAt.ToStr()
    showDeepLinkScreen("PlayerScreen", params)
end sub

' A link that arrives while a player is on top replaces the player (as a phone launch does): a
' player covered by another screen has stopped and closed its session, so it is never kept.
sub showDeepLinkScreen(screenName as string, params as object)
    s = m.global.session
    if Str_isEmpty(s.accessToken) or Str_isEmpty(s.profileId) then return
    top = topScreen()
    replacePlayer = false
    if top <> invalid then replacePlayer = top.subtype() = "PlayerScreen" or top.subtype() = "AudioPlayerScreen"
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

' ---------- Interface language ----------
' Loads a language's strings (pkg:/locale/<folder>/strings.json) for screens built from now on.
sub I18n_apply(folder as string, reason as string)
    table = {}
    if folder <> "en" then
        raw = ReadAsciiFile("pkg:/locale/" + folder + "/strings.json")
        parsed = invalid
        if raw <> "" then parsed = ParseJson(raw)
        if Type(parsed) = "roAssociativeArray" then
            table = parsed
        else
            Diag_log("[siku-i18n] strings for " + folder + " unreadable; showing English")
            folder = "en"
        end if
    end if
    m.global.strings = table
    m.global.appLocale = folder
    Diag_log("[siku-i18n] language " + folder + " (" + reason + ", " + table.Count().ToStr() + " strings)")
end sub

' The profile's settings arrived or changed: apply its ui.app_language (Match device when unset or
' on a server without the key) and rebuild the screens in it. A playing video is never torn down:
' the rebuild waits until the player closes.
sub onLanguageSettings()
    st = m.global.settings
    if st = invalid or st.ready <> true then return
    if Str_isEmpty(m.global.session.profileId) then return
    if m.debugLang <> invalid then return ' simulator: debugLang holds
    value = invalid
    if st.items <> invalid and st.items["ui.app_language"] <> invalid then value = st.items["ui.app_language"].value
    tag = ""
    if Type(value) = "roString" or Type(value) = "String" then tag = value
    p = m.global.prefs
    if p.appLanguage <> tag then
        p.appLanguage = tag
        Prefs_save(p)
    end if
    folder = I18n_resolve(tag, CreateObject("roDeviceInfo").GetCurrentLocale())
    if folder = I18n_locale() then return
    I18n_apply(folder, "profile")
    languageRebuild()
end sub

function languagePlayerOnTop() as boolean
    top = topScreen()
    if top = invalid then return false
    t = top.subtype()
    return t = "PlayerScreen" or t = "AudioPlayerScreen"
end function

' Rebuilds the stack in the new language: Home, with Settings on top again when the change came
' from there. Waits for a playing video to close.
sub languageRebuild()
    if languagePlayerOnTop() then
        m.languageRebuild = true
        Diag_log("[siku-i18n] rebuild waits for the player")
        return
    end if
    m.languageRebuild = false
    top = topScreen()
    if top = invalid or Str_isEmpty(m.global.session.profileId) then return
    reopenSettings = top.subtype() = "SettingsScreen"
    Diag_log("[siku-i18n] rebuilding screens in " + I18n_locale())
    resetTo("ShellScreen")
    if reopenSettings then pushScreen("SettingsScreen")
end sub

