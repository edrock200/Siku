' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.content = m.top.findNode("content")
    m.bar = m.top.findNode("bar")
    m.panelMain = m.top.findNode("panelMain")
    m.panelFly = m.top.findNode("panelFly")

    m.bar.observeField("tabCommitted", "onTabCommitted")
    m.bar.observeField("panelRequested", "onPanelRequested")
    m.bar.observeField("searchSelected", "onSearchSelected")
    m.bar.observeField("enterContent", "onEnterContent")
    m.panelMain.observeField("rowSelected", "onPanelMainSelected")
    m.panelMain.observeField("rowFocused", "onPanelMainFocused")
    m.panelMain.observeField("exitRight", "onPanelMainRight")
    m.panelFly.observeField("rowSelected", "onPanelFlySelected")
    m.panelFly.observeField("exitLeft", "onPanelFlyLeft")

    m.pages = {}
    m.currentKey = ""
    m.currentPage = invalid
    m.libraries = []
    m.tabs = []
    m.focusArea = "bar"      ' bar | content | panel
    m.panelKind = ""         ' libs | sections | foryou | profile
    m.panelTab = -1
    m.panelLibs = []
    m.currentLibraryId = ""
    m.profileId = Str_orEmpty(m.global.session.profileId)
    ' Fetch bookkeeping: the libraries and the requests gate load when the screen is shown
    ' (onScreenShown runs right after init) and again only when stale (see refreshData).
    m.libsLoadedAt = 0
    m.libsLoading = false
    m.gateLoadedAt = 0
    m.gateLoading = false
    m.prefsSig = prefsSignature()

    updateProfile()
    resetRequestsGate()
    buildTabs()
    showHome()
    ' Server-synced settings (components/common/Settings.brs): loaded once per profile; the pages
    ' read them through Settings_* / Theme_* with the device prefs as fallback until they land.
    m.settingsSig = Settings_uiSignature()
    Settings_load()
end sub

' The settings snapshot changed (loaded here, edited in Settings, or reset by a profile switch):
' rebuild what depends on it only when the drawn values actually differ, so the first answer with
' the default values costs nothing. Also run when the shell is shown again (after Settings).
sub onSettingsChanged()
    sig = Settings_uiSignature()
    if sig = m.settingsSig then return
    m.settingsSig = sig
    m.prefsSig = prefsSignature()
    buildTabs()
    m.global.homeDirty = true
    ' Re-show the visible page so Home rebuilds its rows now rather than on the next visit.
    if m.top.active and m.currentPage <> invalid then
        m.currentPage.active = false
        m.currentPage.active = true
    end if
end sub

' ---------- Tabs ----------

sub updateProfile()
    s = m.global.session
    m.bar.avatarUrl = Str_orEmpty(s.profileAvatar)
    m.bar.profileName = Str_orEmpty(s.profileName)
end sub

' The preferences that change the tab set.
function prefsSignature() as string
    p = m.global.prefs
    if p = invalid then return ""
    return Str_orEmpty(p.showAudiobooks) + "|" + Theme_cardPresentation().posterSize
end function

' Loads the libraries and the requests gate once per profile, then again only when the data is
' older than five minutes (or forced). In-flight requests are never duplicated. Preference changes
' (Settings → Show Audiobooks) only rebuild the tabs from the libraries we already have.
sub refreshData(force = false as boolean)
    now = Time_nowSeconds()
    maxAge = 300
    if force or (not m.libsLoading and (m.libsLoadedAt = 0 or now - m.libsLoadedAt > maxAge)) then loadLibraries()
    if force or (not m.gateLoading and (m.gateLoadedAt = 0 or now - m.gateLoadedAt > maxAge)) then loadRequestsGate()
end sub

sub loadLibraries()
    if m.libsLoading then return
    m.libsLoading = true
    Api_get("/api/v2/user/libraries", invalid, "onLibraries", { profileId: m.profileId })
end sub

sub onLibraries(event as object)
    resp = Api_result(event)
    if resp.context = invalid or resp.context.profileId <> m.profileId then return
    m.libsLoading = false
    if not resp.ok or resp.data = invalid then return
    m.libsLoadedAt = Time_nowSeconds()
    m.libraries = Arr_or(resp.data.items)
    buildTabs()
end sub

' Requests feature gate (RequestsFeatureStore): the tab and the search row appear only when the
' server enables requests for this profile; admins who can moderate also get the approval rows.
' A transient failure keeps the previous answer.
sub loadRequestsGate()
    if m.gateLoading then return
    m.gateLoading = true
    Api_get("/api/v2/requests/status", invalid, "onRequestsStatus", { profileId: m.profileId })
end sub

sub resetRequestsGate()
    Req_setGate({ enabled: false, canModerate: false, resolved: false })
end sub

sub onRequestsStatus(event as object)
    resp = Api_result(event)
    if resp.context = invalid or resp.context.profileId <> m.profileId then return
    prev = Req_gate()
    enabled = prev.enabled = true
    if resp.ok then enabled = Req_statusAvailable(resp.data)
    if not enabled then
        m.gateLoading = false
        if resp.ok then m.gateLoadedAt = Time_nowSeconds()
        applyRequestsGate({ enabled: false, canModerate: false, resolved: true })
        return
    end if
    Api_get("/api/v2/admin/requests/capabilities", invalid, "onRequestsCapabilities", { profileId: m.profileId })
end sub

sub onRequestsCapabilities(event as object)
    resp = Api_result(event)
    if resp.context = invalid or resp.context.profileId <> m.profileId then return
    m.gateLoading = false
    m.gateLoadedAt = Time_nowSeconds()
    moderates = false
    if resp.ok and resp.data <> invalid then
        moderates = resp.data.available = true
    else if resp.status = 0 then
        moderates = Req_gate().canModerate = true
    end if
    applyRequestsGate({ enabled: true, canModerate: moderates, resolved: true })
end sub

sub applyRequestsGate(g as object)
    Req_setGate(g)
    if (tabIndex("requests") >= 0) <> (g.enabled = true) then buildTabs()
    if not g.enabled and m.currentKey = "requests" then
        showHome()
        m.bar.selectedIndex = 0
    end if
end sub

sub buildTabs()
    groups = { movies: [], series: [], music: [], audiobooks: [] }
    for each lib in m.libraries
        mode = Library_mode(lib.type)
        if mode = "mixed" then
            groups.movies.Push(lib)
            groups.series.Push(lib)
        else if groups.DoesExist(mode) then
            groups[mode].Push(lib)
        end if
    end for
    tabs = [{ id: "home", label: "Home", kind: "home", hasPanel: false }]
    defs = [
        { id: "movies", label: "Movies", mode: "movies", mediaType: "movie", header: "MOVIE LIBRARIES" },
        { id: "series", label: "Series", mode: "series", mediaType: "series", header: "SERIES LIBRARIES" },
        { id: "music", label: "Music", mode: "music", mediaType: "", header: "MUSIC LIBRARIES" },
        { id: "audiobooks", label: "Audiobooks", mode: "audiobooks", mediaType: "", header: "AUDIOBOOK LIBRARIES" }
    ]
    prefs = m.global.prefs
    showAudiobooks = prefs <> invalid and prefs.showAudiobooks = true
    for each d in defs
        libs = groups[d.mode]
        if libs.Count() > 0 and (d.id <> "audiobooks" or showAudiobooks) then
            tabs.Push({ id: d.id, label: d.label, kind: "library", mode: d.mode, mediaType: d.mediaType, header: d.header, libraries: libs, hasPanel: true })
        end if
    end for
    tabs.Push({ id: "foryou", label: "For You", kind: "foryou", hasPanel: true })
    tabs.Push({ id: "calendar", label: "Calendar", kind: "calendar", hasPanel: false })
    if Req_gate().enabled = true then tabs.Push({ id: "requests", label: "Requests", kind: "requests", hasPanel: false })
    ' Keep the selected tabDef by id across rebuilds.
    selectedId = "home"
    if m.tabs.Count() > 0 and m.bar.selectedIndex < m.tabs.Count() then selectedId = m.tabs[m.bar.selectedIndex].id
    m.tabs = tabs
    m.bar.tabs = tabs
    si = tabIndex(selectedId)
    if si < 0 then si = 0
    m.bar.selectedIndex = si
    if m.bar.focusIndex >= tabs.Count() then m.bar.focusIndex = si
end sub

function tabIndex(id as string) as integer
    for i = 0 to m.tabs.Count() - 1
        if m.tabs[i].id = id then return i
    end for
    return -1
end function

' ---------- Pages ----------

sub showPage(key as string, componentName as string, params as object)
    if key = m.currentKey and m.currentPage <> invalid then return
    page = m.pages[key]
    if page = invalid then
        page = CreateObject("roSGNode", componentName)
        page.params = params
        page.observeField("navigateTo", "onPageNavigate")
        m.content.appendChild(page)
        m.pages[key] = page
    end if
    if m.currentPage <> invalid then
        m.currentPage.active = false
        m.currentPage.visible = false
    end if
    m.currentPage = page
    m.currentKey = key
    page.visible = true
    page.active = m.top.active
    ' Keep Home cached; drop other pages we are no longer showing.
    stale = []
    for each k in m.pages
        if k <> "home" and k <> key then stale.Push(k)
    end for
    for each k in stale
        old = m.pages[k]
        old.unobserveField("navigateTo")
        m.content.removeChild(old)
        m.pages.Delete(k)
    end for
end sub

sub showHome()
    showPage("home", "HomePage", {})
end sub

sub onPageNavigate(event as object)
    req = event.getData()
    if req <> invalid then m.top.navigateTo = req
end sub

' Commits a tabDef chosen with OK (tabs without a panel, or the landing page of a library tabDef).
sub commitTab(index as integer)
    if index < 0 or index >= m.tabs.Count() then return
    tabDef = m.tabs[index]
    m.bar.selectedIndex = index
    if tabDef.kind = "home" then
        showHome()
    else if tabDef.kind = "calendar" then
        showPage("calendar", "CalendarPage", {})
    else if tabDef.kind = "requests" then
        showPage("requests", "RequestsPage", {})
    else if tabDef.kind = "foryou" then
        showPage("foryou", "ForYouPage", {})
    else if tabDef.kind = "library" then
        libs = tabDef.libraries
        if libs.Count() > 0 then commitLibrary(tabDef, libs[0], "recommended")
    end if
end sub

sub commitLibrary(tabDef as object, lib as object, section as string)
    libId = Str_orEmpty(lib.id)
    libName = Str_orEmpty(lib.name)
    m.currentLibraryId = libId
    m.bar.selectedIndex = tabIndex(tabDef.id)
    mediaType = ""
    if Library_mode(lib.type) = "mixed" then mediaType = Str_orEmpty(tabDef.mediaType)
    key = "lib:" + libId + ":" + section + ":" + mediaType
    if section = "recommended" then
        showPage(key, "HomePage", { libraryId: libId, libraryName: libName, mode: Library_mode(lib.type) })
    else
        showPage(key, "LibraryPage", { section: section, libraryId: libId, libraryName: libName, mode: Library_mode(lib.type), mediaType: mediaType })
    end if
end sub

sub showPersonal(section as string)
    showPage("personal:" + section, "LibraryPage", { section: section })
end sub

' ---------- Focus ----------

sub focusBar(index as integer)
    m.focusArea = "bar"
    m.bar.focusIndex = index
    m.bar.dimmed = false
    m.bar.setFocus(true)
end sub

sub focusContent()
    m.focusArea = "content"
    m.bar.dimmed = true
    if m.currentPage <> invalid then
        m.currentPage.focusRequested = true
    else
        m.top.setFocus(true)
    end if
end sub

sub onTabCommitted()
    commitTab(m.bar.tabCommitted)
    focusContent()
end sub

sub onEnterContent()
    focusContent()
end sub

sub onSearchSelected()
    Nav_push("SearchScreen", {})
end sub

' ---------- Panels ----------

' Level-2 sections per library type (TvLibraryPill.set): Movies / Series: Recommended · Browse ·
' Collections. Music: Recommended · Browse · Genres. Audiobooks: Recommended · Browse · Authors ·
' Series · Collections · A-Z. The ids are LibraryPage sections.
function sectionRows(tabDef as object) as object
    rows = [{ id: "recommended", label: "Recommended", icon: "sparkle" }]
    rows.Push({ id: "browse", label: "Browse", icon: "list" })
    if tabDef.mode = "music" then
        rows.Push({ id: "genres", label: "Genres", icon: "sparkle" })
    else if tabDef.mode = "audiobooks" then
        rows.Push({ id: "authors", label: "Authors", icon: "person" })
        rows.Push({ id: "series", label: "Series", icon: "collections" })
        rows.Push({ id: "collections", label: "Collections", icon: "collections" })
        rows.Push({ id: "alphabet", label: "A-Z", icon: "list" })
    else
        rows.Push({ id: "collections", label: "Collections", icon: "collections" })
    end if
    return rows
end function

function libIcon(lib as object) as string
    mode = Library_mode(lib.type)
    if mode = "movies" then return "movie"
    if mode = "series" then return "tv"
    if mode = "music" then return "music"
    if mode = "audiobooks" then return "audiobook"
    return "video"
end function

sub onPanelRequested()
    idx = m.bar.panelRequested
    if idx = 1000 then
        openProfilePanel()
    else
        openTabPanel(idx)
    end if
end sub

sub openTabPanel(ti as integer)
    if ti < 0 or ti >= m.tabs.Count() then return
    tabDef = m.tabs[ti]
    m.panelTab = ti
    frames = m.bar.tabFrames
    x = 88
    if frames <> invalid and ti < frames.Count() then x = frames[ti][0] + 22
    m.panelMain.profile = {}
    m.panelMain.width = 460
    m.panelMain.focusIndex = 0
    m.panelFly.visible = false
    totalW = 460
    if tabDef.kind = "library" then
        libs = tabDef.libraries
        m.panelLibs = libs
        if libs.Count() > 1 then
            m.panelKind = "libs"
            rows = []
            focusIdx = 0
            for i = 0 to libs.Count() - 1
                lib = libs[i]
                tr = "chevron"
                if Str_orEmpty(lib.id) = m.currentLibraryId then
                    tr = "check"
                    focusIdx = i
                end if
                rows.Push({ id: Str_orEmpty(lib.id), label: Str_orEmpty(lib.name), icon: libIcon(lib), trailing: tr })
            end for
            m.panelMain.header = tabDef.header
            m.panelMain.footer = "Press opens the library · → jumps to a section · Menu closes"
            m.panelMain.rows = rows
            m.panelMain.focusIndex = focusIdx
            totalW = 460 + 12 + 300
        else
            m.panelKind = "sections"
            m.panelMain.header = UCase(tabDef.label)
            m.panelMain.footer = "Press opens the section · Menu closes"
            m.panelMain.rows = sectionRows(tabDef)
        end if
    else if tabDef.kind = "foryou" then
        m.panelKind = "foryou"
        m.panelMain.header = "FOR YOU"
        m.panelMain.footer = "Press opens the section · Menu closes"
        m.panelMain.rows = [
            { id: "recommendations", label: "Recommendations", icon: "sparkle" },
            { id: "favorites", label: "Favorites", icon: "heart" },
            { id: "watchlist", label: "Watchlist", icon: "bookmark" }
        ]
    else
        return
    end if
    if x + totalW > 1832 then x = 1832 - totalW
    m.panelMain.translation = [x, 132]
    m.panelMain.visible = true
    if m.panelKind = "libs" then updateFly(m.panelMain.focusIndex)
    m.focusArea = "panel"
    m.bar.dimmed = false
    m.bar.activeTab = ti
    m.panelMain.setFocus(true)
end sub

sub updateFly(libIndex as integer)
    if m.panelKind <> "libs" then return
    if libIndex < 0 or libIndex >= m.panelLibs.Count() then return
    tabDef = m.tabs[m.panelTab]
    m.flyLib = m.panelLibs[libIndex]
    m.panelFly.header = UCase(Str_orEmpty(m.flyLib.name))
    m.panelFly.footer = ""
    m.panelFly.rows = sectionRows(tabDef)
    m.panelFly.focusIndex = 0
    m.panelFly.translation = [m.panelMain.translation[0] + 460 + 12, 132]
    m.panelFly.visible = true
end sub

sub openProfilePanel()
    s = m.global.session
    role = ""
    if s.user <> invalid then role = Str_orEmpty(s.user.role)
    if role = "" then role = "member"
    server = Str_orEmpty(s.serverName)
    if server = "" then server = Url_host(Str_orEmpty(s.serverUrl))
    m.panelKind = "profile"
    m.panelTab = m.tabs.Count()
    m.panelFly.visible = false
    m.panelMain.width = 480
    m.panelMain.header = ""
    m.panelMain.footer = ""
    m.panelMain.profile = { name: Str_orEmpty(s.profileName), "sub": role + " · " + server, avatar: Str_orEmpty(s.profileAvatar) }
    m.panelMain.rows = [
        { id: "switch_profile", label: "Switch Profile", icon: "people" },
        { id: "watchlist", label: "Watchlist", icon: "bookmark" },
        { id: "favorites", label: "Favorites", icon: "heart" },
        { id: "history", label: "History", icon: "history" },
        { id: "notifications", label: "Notifications", icon: "notifications" },
        { id: "-" },
        { id: "settings", label: "Settings", icon: "settings" },
        { id: "switch_server", label: "Switch Server", icon: "dns" },
        { id: "sign_out", label: "Sign Out", icon: "logout" }
    ]
    m.panelMain.focusIndex = 0
    m.panelMain.translation = [1920 - 88 - 480, 132]
    m.panelMain.visible = true
    m.focusArea = "panel"
    m.bar.dimmed = false
    m.bar.activeTab = m.tabs.Count()
    m.panelMain.setFocus(true)
end sub

function panelOpen() as boolean
    return m.panelMain.visible
end function

sub closePanel()
    m.bar.activeTab = -2
    m.panelMain.visible = false
    m.panelFly.visible = false
    m.panelKind = ""
end sub

sub onPanelMainFocused()
    if m.panelKind = "libs" then updateFly(m.panelMain.rowFocused)
end sub

sub onPanelMainRight()
    if m.panelKind = "libs" and m.panelFly.visible then m.panelFly.setFocus(true)
end sub

sub onPanelFlyLeft()
    m.panelMain.setFocus(true)
end sub

sub onPanelMainSelected()
    id = m.panelMain.rowSelected
    kind = m.panelKind
    if kind = "libs" then
        lib = findLib(id)
        tabDef = m.tabs[m.panelTab]
        closePanel()
        if lib <> invalid then commitLibrary(tabDef, lib, "recommended")
        focusContent()
    else if kind = "sections" then
        tabDef = m.tabs[m.panelTab]
        closePanel()
        if tabDef.libraries.Count() > 0 then commitLibrary(tabDef, tabDef.libraries[0], id)
        focusContent()
    else if kind = "foryou" then
        ti = m.panelTab
        closePanel()
        m.bar.selectedIndex = ti
        if id = "recommendations" then
            showPage("foryou", "ForYouPage", {})
        else
            showPersonal(id)
        end if
        focusContent()
    else if kind = "profile" then
        onProfileAction(id)
    end if
end sub

sub onPanelFlySelected()
    id = m.panelFly.rowSelected
    tabDef = m.tabs[m.panelTab]
    lib = m.flyLib
    closePanel()
    if lib <> invalid then commitLibrary(tabDef, lib, id)
    focusContent()
end sub

function findLib(id as string) as dynamic
    for each lib in m.panelLibs
        if Str_orEmpty(lib.id) = id then return lib
    end for
    return invalid
end function

sub onProfileAction(id as string)
    avatarIndex = m.tabs.Count()
    if id = "switch_profile" then
        closePanel()
        focusBar(avatarIndex)
        Nav_push("ProfileScreen", { switching: true })
    else if id = "notifications" then
        ' Siku addition: Android TV ships the inbox screen but has no entry point for it.
        closePanel()
        focusBar(avatarIndex)
        Nav_push("NotificationsScreen")
    else if id = "watchlist" or id = "favorites" or id = "history" then
        closePanel()
        showPersonal(id)
        focusContent()
    else if id = "settings" then
        closePanel()
        focusBar(avatarIndex)
        Nav_push("SettingsScreen", {})
    else if id = "switch_server" then
        closePanel()
        Session_clearServer()
        Nav_reset("ServerConnectScreen", {})
    else if id = "sign_out" then
        closePanel()
        Api_signOut()
        Nav_reset("@start", {})
    else
        closePanel()
        focusBar(avatarIndex)
    end if
end sub

' ---------- Lifecycle ----------

sub onScreenShown()
    newProfile = Str_orEmpty(m.global.session.profileId)
    if newProfile <> m.profileId then
        ' Profile switched: rebuild everything for the new profile.
        m.profileId = newProfile
        updateProfile()
        for each k in m.pages
            old = m.pages[k]
            old.unobserveField("navigateTo")
            m.content.removeChild(old)
        end for
        m.pages = {}
        m.currentPage = invalid
        m.currentKey = ""
        m.currentLibraryId = ""
        m.libraries = []
        m.bar.selectedIndex = 0
        m.libsLoading = false
        m.gateLoading = false
        resetRequestsGate()
        buildTabs()
        showHome()
        refreshData(true)
        m.global.homeDirty = false
        m.settingsSig = Settings_uiSignature()
        Settings_load()
        focusBar(0)
        return
    end if
    updateProfile()
    onSettingsChanged()
    ' Settings may have toggled the Audiobooks tab (or the poster size): rebuild the tabs from the
    ' libraries we have, immediately and without a network round trip.
    sig = prefsSignature()
    if sig <> m.prefsSig then
        m.prefsSig = sig
        buildTabs()
    end if
    ' First show, or data older than five minutes: fetch again.
    refreshData(false)
    if m.currentPage <> invalid then m.currentPage.active = true
    if m.focusArea = "content" then
        focusContent()
    else if m.focusArea = "panel" and panelOpen() then
        m.panelMain.setFocus(true)
    else
        focusBar(m.bar.focusIndex)
    end if
end sub

sub onScreenHidden()
    if m.currentPage <> invalid then m.currentPage.active = false
end sub

' ---------- Keys ----------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if panelOpen() then
        if key = "back" then
            closePanel()
            focusBar(m.panelTab)
            return true
        end if
        ' Focus is trapped in the panel.
        return true
    end if
    barFocused = m.bar.hasFocus()
    if key = "back" then
        if barFocused then
            if m.bar.selectedIndex <> 0 then
                commitTab(0)
                focusBar(0)
                return true
            end if
            return false
        end if
        focusBar(m.bar.selectedIndex)
        return true
    else if key = "up" and not barFocused then
        focusBar(m.bar.selectedIndex)
        return true
    end if
    return false
end function
