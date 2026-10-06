' Settings screen. SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.rail = m.top.findNode("rail")
    m.pane = m.top.findNode("pane")
    m.picker = m.top.findNode("picker")
    m.pickerBg = m.top.findNode("pickerBg")
    m.pickerRing = m.top.findNode("pickerRing")
    m.pickerTitle = m.top.findNode("pickerTitle")
    m.pickerRows = m.top.findNode("pickerRows")
    m.top.findNode("version").text = "Siku " + App_version()

    s = m.global.session
    m.top.findNode("accountName").text = Str_orEmpty(s.profileName)
    username = ""
    if s.user <> invalid then username = Str_orEmpty(s.user.username)
    m.top.findNode("accountSub").text = UCase(Str_joinDots([username, s.serverName]))
    if not Str_isEmpty(s.profileAvatar) then
        m.top.findNode("avatar").uri = Url_resolve(s.profileAvatar)
    else if Len(Str_orEmpty(s.profileName)) > 0 then
        m.top.findNode("avatarInitials").text = UCase(Left(s.profileName, 1))
    end if

    m.categories = buildCategories()
    m.railRows = []
    y = 0
    for each c in m.categories
        row = m.rail.createChild("SettingsRow")
        row.rowWidth = 490
        row.rowHeight = 100
        row.label = c.title
        row.description = c.description
        row.iconUri = "pkg:/images/icons/" + c.icon + ".png"
        row.showChevron = false
        row.translation = [0, y]
        m.railRows.Push(row)
        y = y + 108
    end for

    m.catIndex = 0
    m.rowIndex = 0
    m.inPane = false
    m.pickerIndex = 0
    m.serverVersion = ""
    renderPane()
    updateFocus()
    Api_call({ path: "/api/v2/system/info", auth: false, profile: false }, "onServerInfo")
end sub

sub onScreenShown()
    m.top.setFocus(true)
end sub

' ---------- Model ----------

function onOff() as object
    return [{ value: true, label: "On" }, { value: false, label: "Off" }]
end function

function buildCategories() as object
    return [
        {
            id: "general", title: "General", description: "App and navigation", icon: "settings"
            rows: [
                { id: "posterSize", label: "Poster Size", kind: "choice", options: [{ value: "compact", label: "Compact" }, { value: "standard", label: "Standard" }, { value: "large", label: "Large" }] }
                { id: "showAudiobooks", label: "Show Audiobooks in Top Menu", kind: "choice", options: onOff() }
                { id: "switchProfile", label: "Switch Profile", kind: "action" }
            ]
        }
        {
            id: "playback", title: "Playback", description: "Quality and episodes", icon: "play_circle"
            rows: [
                { id: "quality", label: "Quality", kind: "choice", options: [{ value: "auto", label: "Auto" }, { value: "original", label: "Original" }, { value: "2160p", label: "4K" }, { value: "1080p", label: "1080p" }, { value: "720p", label: "720p" }] }
                { id: "skipIntro", label: "Skip Intros", kind: "choice", options: [{ value: "never", label: "Never" }, { value: "ask", label: "Ask to skip" }, { value: "always", label: "Skip automatically" }] }
                { id: "autoPlayNext", label: "Auto-play Next Episode", kind: "choice", options: onOff() }
                { id: "skipBack", label: "Skip Back", kind: "choice", options: [{ value: 5, label: "5 seconds" }, { value: 10, label: "10 seconds" }, { value: 15, label: "15 seconds" }, { value: 30, label: "30 seconds" }] }
                { id: "skipForward", label: "Skip Forward", kind: "choice", options: [{ value: 10, label: "10 seconds" }, { value: 15, label: "15 seconds" }, { value: 30, label: "30 seconds" }, { value: 60, label: "60 seconds" }] }
            ]
        }
        {
            id: "subtitles", title: "Subtitles", description: "Language and appearance", icon: "subtitles"
            rows: [
                { id: "captionsNote", label: "Caption style follows your Roku's Accessibility settings", kind: "info" }
            ]
        }
        {
            id: "server", title: "Server", description: "Connection and version", icon: "dns"
            rows: [
                { id: "serverName", label: "Active Server", kind: "info" }
                { id: "serverUrl", label: "Address", kind: "info" }
                { id: "serverVersion", label: "Server Version", kind: "info" }
                { id: "switchServer", label: "Switch Server", kind: "action" }
                { id: "signOut", label: "Sign Out", kind: "action", destructive: true }
            ]
        }
    ]
end function

function rowValue(row as object) as string
    s = m.global.session
    if row.kind = "choice" then
        current = m.global.prefs[row.id]
        for each o in row.options
            if o.value = current then return o.label
        end for
        return ""
    end if
    if row.id = "serverName" then return Str_orEmpty(s.serverName)
    if row.id = "serverUrl" then return Str_orEmpty(s.serverUrl)
    if row.id = "serverVersion" then return m.serverVersion
    return ""
end function

' ---------- Rendering ----------

sub renderPane()
    m.pane.removeChildrenIndex(m.pane.getChildCount(), 0)
    m.paneRows = []
    cat = m.categories[m.catIndex]
    header = m.pane.createChild("Label")
    header.text = UCase(cat.title)
    header.color = "0xEDEDED80"
    header.font = ThemeFont("semibold", 24)
    y = 56
    for each r in cat.rows
        row = m.pane.createChild("SettingsRow")
        row.rowWidth = 1080
        row.rowHeight = 76
        row.label = r.label
        row.value = rowValue(r)
        row.showChevron = r.kind <> "info"
        row.destructive = r.destructive = true
        row.translation = [0, y]
        m.paneRows.Push(row)
        y = y + 84
    end for
end sub

sub updateFocus()
    for i = 0 to m.railRows.Count() - 1
        r = m.railRows[i]
        r.focusedState = (not m.inPane) and i = m.catIndex
        r.highlighted = m.inPane and i = m.catIndex
    end for
    for i = 0 to m.paneRows.Count() - 1
        m.paneRows[i].focusedState = m.inPane and i = m.rowIndex
    end for
end sub

sub refreshValues()
    cat = m.categories[m.catIndex]
    for i = 0 to cat.rows.Count() - 1
        m.paneRows[i].value = rowValue(cat.rows[i])
    end for
end sub

sub onServerInfo(event as object)
    resp = Api_result(event)
    if resp.ok and resp.data <> invalid then
        m.serverVersion = Str_orEmpty(resp.data.server_version)
        refreshValues()
    end if
end sub

' ---------- Picker ----------

sub openPicker(row as object)
    m.pickerRow = row
    m.pickerRows.removeChildrenIndex(m.pickerRows.getChildCount(), 0)
    m.pickerItems = []
    current = m.global.prefs[row.id]
    w = 640
    y = 0
    m.pickerIndex = 0
    for i = 0 to row.options.Count() - 1
        o = row.options[i]
        item = m.pickerRows.createChild("SettingsRow")
        item.rowWidth = w - 48
        item.rowHeight = 72
        item.label = o.label
        item.showChevron = false
        if o.value = current then
            item.value = "✓"
            m.pickerIndex = i
        end if
        item.translation = [0, y]
        m.pickerItems.Push(item)
        y = y + 78
    end for
    h = y + 120
    x = (1920 - w) / 2
    top = (1080 - h) / 2
    m.pickerBg.width = w
    m.pickerBg.height = h
    m.pickerBg.translation = [x, top]
    m.pickerRing.width = w
    m.pickerRing.height = h
    m.pickerRing.translation = [x, top]
    m.pickerTitle.text = UCase(row.label)
    m.pickerTitle.translation = [x + 36, top + 30]
    m.pickerRows.translation = [x + 24, top + 90]
    m.picker.visible = true
    updatePicker()
end sub

sub updatePicker()
    for i = 0 to m.pickerItems.Count() - 1
        m.pickerItems[i].focusedState = i = m.pickerIndex
    end for
end sub

sub choosePicker()
    o = m.pickerRow.options[m.pickerIndex]
    p = AA_copy(m.global.prefs)
    p[m.pickerRow.id] = o.value
    Prefs_save(p)
    ' Home rebuilds its rows (card size) and the shell its tabs on the next show.
    if m.pickerRow.id = "showAudiobooks" or m.pickerRow.id = "posterSize" then m.global.homeDirty = true
    m.picker.visible = false
    refreshValues()
end sub

' ---------- Actions ----------

sub activateRow(row as object)
    if row.kind = "choice" then
        openPicker(row)
    else if row.id = "switchProfile" then
        Nav_push("ProfileScreen", { switching: true })
    else if row.id = "switchServer" then
        Session_clearServer()
        Nav_reset("ServerConnectScreen")
    else if row.id = "signOut" then
        Api_signOut()
        Nav_reset("@start")
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.picker.visible then
        if key = "up" and m.pickerIndex > 0 then
            m.pickerIndex = m.pickerIndex - 1
            updatePicker()
        else if key = "down" and m.pickerIndex < m.pickerItems.Count() - 1 then
            m.pickerIndex = m.pickerIndex + 1
            updatePicker()
        else if key = "OK" then
            choosePicker()
        else if key = "back" then
            m.picker.visible = false
        end if
        return true
    end if

    if m.inPane then
        rows = m.categories[m.catIndex].rows
        if key = "up" then
            if m.rowIndex > 0 then m.rowIndex = m.rowIndex - 1
        else if key = "down" then
            if m.rowIndex < rows.Count() - 1 then m.rowIndex = m.rowIndex + 1
        else if key = "left" or key = "back" then
            m.inPane = false
        else if key = "OK" then
            activateRow(rows[m.rowIndex])
        else
            return true
        end if
        updateFocus()
        return true
    end if

    if key = "up" then
        if m.catIndex > 0 then
            m.catIndex = m.catIndex - 1
            renderPane()
        end if
    else if key = "down" then
        if m.catIndex < m.categories.Count() - 1 then
            m.catIndex = m.catIndex + 1
            renderPane()
        end if
    else if key = "right" or key = "OK" then
        m.inPane = true
        m.rowIndex = 0
    else if key = "back" then
        return false
    else
        return true
    end if
    updateFocus()
    return true
end function
