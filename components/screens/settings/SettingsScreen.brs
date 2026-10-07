' Settings screen (Android TV TvSettingsScreen / TvSettingsViewModel). Rail on the left, grouped
' rows on the right. Values come from the server's effective settings cascade (Settings.brs) and
' the device prefs; a change writes to the server, then re-reads the effective values and
' re-renders when m.global.settings changes.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.rail = m.top.findNode("rail")
    m.pane = m.top.findNode("pane")
    m.paneClip = m.top.findNode("paneClip")
    m.status = m.top.findNode("status")
    m.statusLabel = m.top.findNode("statusLabel")
    m.picker = m.top.findNode("picker")
    m.pickerBg = m.top.findNode("pickerBg")
    m.pickerRing = m.top.findNode("pickerRing")
    m.pickerTitle = m.top.findNode("pickerTitle")
    m.pickerSub = m.top.findNode("pickerSub")
    m.pickerMessage = m.top.findNode("pickerMessage")
    m.pickerHint = m.top.findNode("pickerHint")
    m.pickerDivider = m.top.findNode("pickerDivider")
    m.pickerRows = m.top.findNode("pickerRows")
    m.account = m.top.findNode("account")
    m.accountBg = m.top.findNode("accountBg")
    m.accountName = m.top.findNode("accountName")
    m.accountSub = m.top.findNode("accountSub")
    m.accountChevron = m.top.findNode("accountChevron")
    m.avatarInitials = m.top.findNode("avatarInitials")
    m.signOutRow = m.top.findNode("signOutRow")

    ' Every Label gets its own Font node (a shared Font un-fonts all but one Label on device).
    Label_setFont(m.top.findNode("title"), "black", 41)
    Label_setFont(m.avatarInitials, "bold", 26)
    Label_setFont(m.accountName, "semibold", 26)
    Label_setFont(m.accountSub, "regular", 22)
    Label_setFont(m.top.findNode("version"), "regular", 24)
    Label_setFont(m.statusLabel, "regular", 24)
    Label_setFont(m.pickerTitle, "bold", 36)
    Label_setFont(m.pickerSub, "regular", 24)
    Label_setFont(m.pickerMessage, "regular", 24)
    Label_setFont(m.pickerHint, "regular", 22)
    m.top.findNode("version").text = "Siku " + App_version()

    m.signOutRow.rowWidth = 490
    m.signOutRow.rowHeight = 64
    m.signOutRow.label = "Sign Out"
    m.signOutRow.iconUri = "pkg:/images/icons/logout.png"
    m.signOutRow.showChevron = false
    m.signOutRow.destructive = true

    fillAccount()
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
    m.railFocus = 0          ' -1 account row, 0..n-1 categories, n Sign Out
    m.inPane = false
    m.focusIdx = -1          ' index into m.entries
    m.entries = []
    m.scrollY = 0
    m.pickerIndex = 0
    m.pickerFirst = 0
    m.pickerMode = ""        ' "options" | "confirm"
    m.pendingWrites = 0
    m.writeFailed = false
    m.serverVersion = ""
    m.supportsDolbyVision = displaySupportsDolbyVision()
    Hs_init()

    renderPane()
    updateFocus()
    Api_call({ path: "/api/v2/system/info", auth: false, profile: false }, "onServerInfo")
    ' Opening Settings is a refresh edge (the TV re-reads the device settings and title art).
    Settings_load()
end sub

sub onScreenShown()
    m.top.setFocus(true)
    fillAccount()
    ' Back from Switch Profile: the snapshot may belong to another profile now.
    if not Settings_available() then Settings_load()
    renderPane()
end sub

sub fillAccount()
    s = m.global.session
    name = Str_orEmpty(s.profileName)
    if name = "" and s.user <> invalid then name = Str_orEmpty(s.user.username)
    if name = "" then name = "Siku"
    m.accountName.text = name
    m.accountSub.text = accountSubtitle(s)
    avatar = m.top.findNode("avatar")
    if not Str_isEmpty(s.profileAvatar) then
        avatar.uri = Url_resolve(s.profileAvatar)
        m.avatarInitials.text = ""
    else
        avatar.uri = ""
        m.avatarInitials.text = UCase(Left(name, 1))
    end if
end sub

' tvOS accountSubtitle: "Administrator" for admins, else the username, else a generic line.
function accountSubtitle(s as object) as string
    if s.user <> invalid then
        if LCase(Str_orEmpty(s.user.role)) = "admin" then return "Administrator"
        if not Str_isEmpty(s.user.username) then return s.user.username
    end if
    return "Signed in"
end function

function displaySupportsDolbyVision() as boolean
    di = CreateObject("roDeviceInfo")
    if di = invalid then return false
    props = di.GetDisplayProperties()
    return props <> invalid and props.DolbyVision = true
end function

' ---------- Model ----------

function buildCategories() as object
    return [
        { id: "general", title: "General", description: "App and navigation", blurb: "App-level options for this Roku.", icon: "settings" }
        { id: "playback", title: "Playback", description: "Quality and episodes", blurb: "Streaming quality and episode behavior for this Roku.", icon: "play_circle" }
        { id: "subtitles", title: "Subtitles", description: "Language and appearance", blurb: "Language, behavior, and on-screen appearance.", icon: "subtitles" }
        { id: "server", title: "Server", description: "Connection and version", blurb: "The Silo server this Roku is connected to.", icon: "dns" }
    ]
end function

function onOff(v as boolean) as string
    if v then return "On"
    return "Off"
end function

function rowDef(id as string, kind as string, label as string) as object
    return { id: id, kind: kind, label: label }
end function

' The pane content for the selected category: a flat list of
' { kind: "header"|"row"|"footer"|"preview", text?, row? }.
function buildPane(catId as string) as object
    out = []
    if catId = "general" then
        out.Push({ kind: "header", text: "Home Sections" })
        out.Push({ kind: "row", row: rowDef("homeSections", "action", "Home Sections") })
        out.Push({ kind: "footer", text: "Choose which Home rows are visible and edit the order in which they appear on this Roku." })

        out.Push({ kind: "header", text: "Cards & Posters" })
        if Settings_available() and Settings_manifestRevision() < 5 then
            out.Push({ kind: "footer", text: "Update your Silo server to customize media cards." })
        else
            out.Push({ kind: "row", row: rowDef("cardPreset", "choice", "Preset") })
            out.Push({ kind: "row", row: rowDef("cardPosterSize", "choice", "Poster Size") })
            out.Push({ kind: "row", row: rowDef("cardCaptions", "choice", "Captions") })
            out.Push({ kind: "row", row: rowDef("cardDeviceOnly", "toggle", "Only This Device") })
            if Settings_source("ui.card_presentation") = "profile_client" then
                out.Push({ kind: "row", row: rowDef("cardUseProfileDefault", "action", "Use Profile Default") })
            end if
            out.Push({ kind: "footer", text: "Start with Balanced, Compact, Cinema, or Artwork Only, then fine-tune size and captions. These choices sync with other TVs on this profile unless Only This Device is on." })
        end if

        ' Title Pages (ui.title_art, revision 16): hidden until the server confirms the key.
        if Settings_available() and Settings_manifestRevision() >= 16 then
            out.Push({ kind: "header", text: "Title Pages" })
            out.Push({ kind: "row", row: rowDef("titleArt", "toggle", "Show title art") })
            out.Push({ kind: "footer", text: "Use logo artwork as the title when available." })
            out.Push({ kind: "row", row: rowDef("titleArtAll", "toggle", "Apply to all devices") })
            if Settings_source("ui.title_art") = "profile" then
                out.Push({ kind: "footer", text: "On: every device on this profile uses this choice. Title art is " + LCase(onOff(Settings_showTitleArt())) + " on every device signed into this profile. Changing it here changes it everywhere. Turn off “Apply to all devices” to choose for this Roku only." })
            else
                out.Push({ kind: "footer", text: "Off: only affects this Roku. Your other devices keep their own setting." })
            end if
        end if

        out.Push({ kind: "header", text: "Top Menu" })
        out.Push({ kind: "row", row: rowDef("showAudiobooks", "toggle", "Show Audiobooks") })
        out.Push({ kind: "footer", text: "Adds an Audiobooks tab to the top menu when your server has an audiobook library. Hidden by default." })

        out.Push({ kind: "header", text: "Profile" })
        out.Push({ kind: "row", row: rowDef("switchProfile", "action", "Switch Profile") })

        out.Push({ kind: "header", text: "Metadata" })
        out.Push({ kind: "row", row: rowDef("metadataLanguage", "choice", "Metadata Language") })
        out.Push({ kind: "footer", text: "Fallback language Silo prefers for titles, descriptions, and artwork." })
    else if catId = "playback" then
        out.Push({ kind: "header", text: "Streaming" })
        out.Push({ kind: "row", row: rowDef("quality", "choice", "Quality") })
        out.Push({ kind: "row", row: rowDef("audioLanguage", "choice", "Audio Language") })
        ' TvSettingsScreen STREAMING parity: Dolby Vision (default on; off plays the HDR10 base
        ' layer) with the narrower Profile 7 fallback nested under it while Dolby Vision is on,
        ' then Force HDR Passthrough. Match Content Frame Rate and True Black Bars are Android-only
        ' (Roku switches refresh rate system-wide and never draws its own bars).
        if m.supportsDolbyVision then out.Push({ kind: "row", row: rowDef("dolbyVision", "toggle", "Dolby Vision") })
        if m.supportsDolbyVision and Settings_dolbyVision() then out.Push({ kind: "row", row: rowDef("dvProfile7Fallback", "toggle", "Profile 7 HDR10 Fallback") })
        out.Push({ kind: "row", row: rowDef("forceHdr", "toggle", "Force HDR Passthrough") })
        out.Push({ kind: "row", row: rowDef("forceDolby", "toggle", "Force Dolby Audio Passthrough") })
        out.Push({ kind: "row", row: rowDef("progressiveRemux", "toggle", "Experimental: Progressive Remux") })
        q = Settings_qualityPresetFor(Settings_quality(), Settings_maxBitrateKbps())
        if q <> invalid then qText = q.description else qText = Settings_describeQuality(Settings_quality(), Settings_maxBitrateKbps()) + "."
        if m.supportsDolbyVision then qText = qText + " Dolby Vision off asks the server for the HDR10 layer of Dolby Vision files instead. Profile 7 HDR10 Fallback plays dual-layer Dolby Vision files as their HDR10 base layer; off, they are sent as they are and this Roku's HEVC decoder shows the base layer itself."
        qText = qText + " Force HDR Passthrough allows HDR playback when this TV doesn't report support. It does not force the HDMI output into HDR; the Roku may still convert the picture to SDR. Enable it only if you've confirmed your TV supports the source format."
        qText = qText + " Force Dolby Audio Passthrough tells the server this Roku can play Dolby Digital and Dolby Digital Plus even when the TV or receiver does not report it, so the original audio is sent instead of being converted to AAC. If you then get no sound, turn it off; a Roku app cannot switch the HDMI audio output itself."
        qText = qText + " Experimental: Progressive Remux offers the server a second way to keep the original video while converting only the audio: one MP4 stream over plain HTTP instead of HLS. Roku may not play it; if videos fail to start, turn it off."
        out.Push({ kind: "footer", text: qText })

        out.Push({ kind: "header", text: "Episodes" })
        out.Push({ kind: "row", row: rowDef("autoPlayNext", "toggle", "Auto-Play Next Episode") })
        out.Push({ kind: "row", row: rowDef("showNextUp", "choice", "Show Next Up") })
        out.Push({ kind: "row", row: rowDef("skipIntros", "choice", "Skip Intros") })
        out.Push({ kind: "row", row: rowDef("skipCredits", "toggle", "Skip Credits") })
        out.Push({ kind: "row", row: rowDef("rewindOnResume", "choice", "Rewind on Resume") })
        out.Push({ kind: "row", row: rowDef("stillWatching", "choice", "Still Watching Prompt") })
        out.Push({ kind: "footer", text: "Rewind on Resume skips back when you return to a partly watched title. Still Watching Prompt sets how many episodes play in a row before Silo asks whether you're still watching." })

        out.Push({ kind: "header", text: "Video" })
        out.Push({ kind: "row", row: rowDef("skipBack", "choice", "Skip Back") })
        out.Push({ kind: "row", row: rowDef("skipForward", "choice", "Skip Forward") })
        if seekIntervalsSynced() then
            out.Push({ kind: "footer", text: "Used by left and right presses on the remote and the on-screen skip buttons. Applies to every device signed in to this profile." })
        else
            out.Push({ kind: "footer", text: "Used by left and right presses on the remote and the on-screen skip buttons. This server does not sync skip intervals, so they stay on this Roku." })
        end if

        out.Push({ kind: "header", text: "Reset" })
        out.Push({ kind: "row", row: { id: "resetOverrides", kind: "action", label: "Reset Playback Overrides", destructive: true } })
        out.Push({ kind: "footer", text: "Resets playback choices for this Roku and profile back to the server fallback." })
    else if catId = "subtitles" then
        out.Push({ kind: "header", text: "Profile" })
        out.Push({ kind: "row", row: rowDef("subtitleLanguage", "choice", "Language") })
        out.Push({ kind: "row", row: rowDef("subtitleMode", "choice", "Behavior") })
        out.Push({ kind: "row", row: rowDef("showForced", "toggle", "Show Forced Subtitles") })
        out.Push({ kind: "footer", text: "Used to pick a matching track when one is available. Forced subtitles cover foreign-language dialogue even when subtitles are off or set to auto." })

        out.Push({ kind: "header", text: "Appearance" })
        out.Push({ kind: "preview" })
        out.Push({ kind: "row", row: rowDef("useDeviceSettings", "info", "Use Device Settings") })
        out.Push({ kind: "row", row: rowDef("customAppearance", "toggle", "Custom Subtitle Appearance") })
        disabled = not customAppearanceOn()
        for each f in [["fontSize", "Font Size"], ["fontFamily", "Font Family"], ["fontColor", "Font Color"], ["textOpacity", "Text Opacity"], ["textOutline", "Text Outline"], ["textOutlineColor", "Outline Color"], ["backgroundStyle", "Background Style"], ["backgroundOpacity", "Background Opacity"], ["backgroundColor", "Background Color"], ["position", "Position"]]
            fid = f[0]
            if fid <> "textOpacity" or textOpacitySupported() then
                kind = "choice"
                if fid = "textOutline" then kind = "toggle"
                r = rowDef(fid, kind, f[1])
                r.appearance = true
                r.disabled = disabled
                out.Push({ kind: "row", row: r })
            end if
        end for
        out.Push({ kind: "row", row: { id: "resetAppearance", kind: "action", label: "Reset Custom Appearance", destructive: true, disabled: disabled } })
        if customAppearanceOn() then
            out.Push({ kind: "footer", text: "Appearance is saved on the server for this profile on this device." })
        else
            out.Push({ kind: "footer", text: "Appearance is using the server fallback for this profile on this device." })
        end if
        out.Push({ kind: "footer", text: "Roku draws captions with your Roku's own caption style (Settings › Accessibility › Captions style), so these choices are saved for your other Silo devices and do not change captions here." })
    else if catId = "server" then
        s = m.global.session
        out.Push({ kind: "header", text: "Active Server" })
        out.Push({ kind: "row", row: rowDef("server", "info", "Server") })
        if not Str_isEmpty(s.serverUrl) and Str_orEmpty(s.serverName) <> Str_orEmpty(s.serverUrl) then
            out.Push({ kind: "row", row: rowDef("address", "info", "Address") })
        end if
        out.Push({ kind: "row", row: rowDef("serverVersion", "info", "Server Version") })
        out.Push({ kind: "row", row: rowDef("manageServers", "action", "Manage Servers") })
        out.Push({ kind: "header", text: "About" })
        out.Push({ kind: "row", row: rowDef("appVersion", "info", "App Version") })
    end if
    return out
end function

' Whether the server stores the revision-9 skip intervals for this profile.
function seekIntervalsSynced() as boolean
    return Settings_available() and Settings_manifestRevision() >= 9
end function

function textOpacitySupported() as boolean
    return (not Settings_available()) or Settings_manifestRevision() >= 14
end function

' "Custom Subtitle Appearance" is on while the appearance resolves from this device's own row.
function customAppearanceOn() as boolean
    return Settings_source("playback.subtitle_appearance") = "profile_device"
end function

function rowValue(row as object) as string
    id = row.id
    s = m.global.session
    p = m.global.prefs
    if p = invalid then p = {}
    if id = "cardPreset" then
        cp = Settings_cardPresentation()
        for each pr in cardPresets()
            if pr.posterSize = cp.posterSize and pr.caption = cp.caption then return pr.label
        end for
        return "Custom"
    else if id = "cardPosterSize" then
        return Settings_optionLabel(rowOptions(row), Settings_cardPresentation().posterSize)
    else if id = "cardCaptions" then
        return Settings_optionLabel(rowOptions(row), Settings_cardPresentation().caption)
    else if id = "cardDeviceOnly" then
        return onOff(Settings_source("ui.card_presentation") = "profile_device")
    else if id = "titleArt" then
        return onOff(Settings_showTitleArt())
    else if id = "titleArtAll" then
        return onOff(Settings_source("ui.title_art") = "profile")
    else if id = "showAudiobooks" then
        return onOff(p.showAudiobooks = true)
    else if id = "metadataLanguage" then
        return Settings_languageLabel(Settings_value("catalog.metadata_language", ""), "catalog.metadata_language")
    else if id = "quality" then
        return Settings_describeQuality(Settings_quality(), Settings_maxBitrateKbps())
    else if id = "audioLanguage" then
        return Settings_languageLabel(Settings_value("playback.audio_language", ""), "playback.audio_language")
    else if id = "dolbyVision" then
        return onOff(Settings_dolbyVision())
    else if id = "dvProfile7Fallback" then
        return onOff(Settings_dvProfile7Fallback())
    else if id = "forceHdr" then
        return onOff(Settings_forceHdrPassthrough())
    else if id = "forceDolby" then
        return onOff(Settings_forceDolbyPassthrough())
    else if id = "progressiveRemux" then
        return onOff(Settings_progressiveRemux())
    else if id = "autoPlayNext" then
        return onOff(Settings_autoPlayNext())
    else if id = "showNextUp" then
        return nextUpPromptLabel(Settings_nextUpPromptSeconds())
    else if id = "skipIntros" then
        return Settings_optionLabel(rowOptions(row), Settings_introSkipMode())
    else if id = "skipCredits" then
        return onOff(Settings_autoSkipCredits())
    else if id = "rewindOnResume" then
        v = Settings_resumeRewindSeconds()
        if v <= 0 then return "Off"
        return v.ToStr() + "s"
    else if id = "stillWatching" then
        v = Settings_passoutThreshold()
        if v <= 0 then return "Off"
        return v.ToStr()
    else if id = "skipBack" then
        return Settings_skipBackSeconds().ToStr() + " seconds"
    else if id = "skipForward" then
        return Settings_skipForwardSeconds().ToStr() + " seconds"
    else if id = "subtitleLanguage" then
        return Settings_languageLabel(Settings_value("playback.subtitle_language", ""), "playback.subtitle_language")
    else if id = "subtitleMode" then
        return Settings_optionLabel(rowOptions(row), subtitleMode())
    else if id = "showForced" then
        return onOff(Settings_value("playback.show_forced_subtitles", true) <> false)
    else if id = "useDeviceSettings" then
        return "Always on"
    else if id = "customAppearance" then
        return onOff(customAppearanceOn())
    else if row.appearance = true then
        a = Settings_appearance()
        if id = "textOpacity" or id = "backgroundOpacity" then return Int(Content_numOr(a[id], 100)).ToStr() + "%"
        if id = "textOutline" then return onOff(a.textOutline = true)
        return Settings_optionLabel(Settings_appearanceOptions(id), a[id])
    else if id = "server" then
        if Str_isEmpty(s.serverName) then return "Not configured"
        return s.serverName
    else if id = "address" then
        return Str_orEmpty(s.serverUrl)
    else if id = "serverVersion" then
        if m.serverVersion = "" then return "…"
        return m.serverVersion
    else if id = "appVersion" then
        return App_version()
    end if
    return ""
end function

function subtitleMode() as string
    v = LCase(Str_orEmpty(Settings_value("playback.subtitle_mode", "auto")))
    if v <> "off" and v <> "always" then v = "auto"
    return v
end function

' CardPresentationPreset: friendly recipes over the two contract axes.
function cardPresets() as object
    return [
        { id: "balanced", label: "Balanced", posterSize: "standard", caption: "title_metadata" }
        { id: "compact", label: "Compact", posterSize: "compact", caption: "title" }
        { id: "cinema", label: "Cinema", posterSize: "large", caption: "title" }
        { id: "artwork", label: "Artwork Only", posterSize: "large", caption: "artwork" }
    ]
end function

function nextUpPromptLabel(seconds as integer) as string
    if seconds <= 0 then return "At end"
    if seconds < 60 then return seconds.ToStr() + " seconds before end"
    if seconds = 60 then return "1 minute before end"
    return (seconds \ 60).ToStr() + " minutes before end"
end function

' Picker options for a choice row: [{value, label}].
function rowOptions(row as object) as object
    id = row.id
    if id = "cardPreset" then
        out = []
        for each pr in cardPresets()
            out.Push({ value: pr.id, label: pr.label })
        end for
        if rowValue(row) = "Custom" then out.Push({ value: "custom", label: "Custom" })
        return out
    else if id = "cardPosterSize" then
        return [{ value: "compact", label: "Compact" }, { value: "standard", label: "Standard" }, { value: "large", label: "Large" }]
    else if id = "cardCaptions" then
        return [{ value: "title_metadata", label: "Title & Metadata" }, { value: "title", label: "Title Only" }, { value: "artwork", label: "Artwork Only" }]
    else if id = "metadataLanguage" then
        return Settings_languageOptions("catalog.metadata_language")
    else if id = "quality" then
        out = []
        for each pr in Settings_qualityPresets()
            out.Push({ value: pr.id, label: pr.label })
        end for
        return out
    else if id = "audioLanguage" then
        return Settings_languageOptions("playback.audio_language")
    else if id = "showNextUp" then
        out = []
        for each v in [0, 10, 30, 60, 120]
            out.Push({ value: v, label: nextUpPromptLabel(v) })
        end for
        return out
    else if id = "skipIntros" then
        return [{ value: "never", label: "Never" }, { value: "ask", label: "Ask to skip" }, { value: "always", label: "Skip automatically" }]
    else if id = "rewindOnResume" then
        out = []
        for each v in [0, 3, 5, 7, 10, 15, 20, 30]
            if v = 0 then out.Push({ value: 0, label: "Off" }) else out.Push({ value: v, label: v.ToStr() + "s" })
        end for
        return out
    else if id = "stillWatching" then
        out = []
        for each v in [0, 2, 3, 4, 5]
            if v = 0 then out.Push({ value: 0, label: "Off" }) else out.Push({ value: v, label: v.ToStr() })
        end for
        return out
    else if id = "skipBack" or id = "skipForward" then
        out = []
        for each v in [5, 10, 15, 30, 45, 60, 90]
            out.Push({ value: v, label: v.ToStr() + " seconds" })
        end for
        return out
    else if id = "subtitleLanguage" then
        return Settings_languageOptions("playback.subtitle_language")
    else if id = "subtitleMode" then
        return [{ value: "off", label: "Off" }, { value: "auto", label: "Auto" }, { value: "always", label: "Always" }]
    else if id = "textOpacity" then
        return Settings_percentOptions(5, Int(Content_numOr(Settings_appearance().textOpacity, 100)))
    else if id = "backgroundOpacity" then
        return Settings_percentOptions(0, Int(Content_numOr(Settings_appearance().backgroundOpacity, 75)))
    else if row.appearance = true then
        return Settings_appearanceOptions(id)
    end if
    return []
end function

' The value a choice row currently holds, for the picker's check mark.
function rowCurrent(row as object) as dynamic
    id = row.id
    if id = "cardPreset" then
        cp = Settings_cardPresentation()
        for each pr in cardPresets()
            if pr.posterSize = cp.posterSize and pr.caption = cp.caption then return pr.id
        end for
        return "custom"
    else if id = "cardPosterSize" then
        return Settings_cardPresentation().posterSize
    else if id = "cardCaptions" then
        return Settings_cardPresentation().caption
    else if id = "metadataLanguage" then
        return Str_orEmpty(Settings_value("catalog.metadata_language", ""))
    else if id = "quality" then
        q = Settings_qualityPresetFor(Settings_quality(), Settings_maxBitrateKbps())
        if q = invalid then return ""
        return q.id
    else if id = "audioLanguage" then
        return Str_orEmpty(Settings_value("playback.audio_language", ""))
    else if id = "showNextUp" then
        return Settings_nextUpPromptSeconds()
    else if id = "skipIntros" then
        return Settings_introSkipMode()
    else if id = "rewindOnResume" then
        return Settings_resumeRewindSeconds()
    else if id = "stillWatching" then
        return Settings_passoutThreshold()
    else if id = "skipBack" then
        return Settings_skipBackSeconds()
    else if id = "skipForward" then
        return Settings_skipForwardSeconds()
    else if id = "subtitleLanguage" then
        return Str_orEmpty(Settings_value("playback.subtitle_language", ""))
    else if id = "subtitleMode" then
        return subtitleMode()
    else if row.appearance = true then
        a = Settings_appearance()
        if id = "textOpacity" or id = "backgroundOpacity" then return Int(Content_numOr(a[id], 0))
        return a[id]
    end if
    return invalid
end function

function sameValue(a as dynamic, b as dynamic) as boolean
    return LCase(Str_orEmpty(a)) = LCase(Str_orEmpty(b))
end function

' ---------- Rendering ----------

sub renderPane()
    keepId = focusedRowId()
    m.pane.removeChildrenIndex(m.pane.getChildCount(), 0)
    m.entries = []
    cat = m.categories[m.catIndex]
    w = 1080

    ' Pane header: glyph on a graphite tile, the category title and its blurb.
    tile = m.pane.createChild("Poster")
    tile.uri = "pkg:/images/ui/r14.9.png"
    tile.blendColor = "0x3A3A3CFF"
    tile.width = 72
    tile.height = 72
    tile.translation = [0, 0]
    glyph = m.pane.createChild("Poster")
    glyph.uri = "pkg:/images/icons/" + cat.icon + ".png"
    glyph.width = 36
    glyph.height = 36
    glyph.blendColor = "0xEDEDEDFF"
    glyph.translation = [18, 18]
    h1 = m.pane.createChild("Label")
    h1.text = cat.title
    h1.color = "0xEDEDEDFF"
    Label_setFont(h1, "bold", 36)
    h1.translation = [96, -2]
    h2 = m.pane.createChild("Label")
    h2.text = cat.blurb
    h2.color = "0xEDEDED9E"
    Label_setFont(h2, "regular", 24)
    h2.translation = [96, 42]
    y = 84

    st = Settings_state()
    if st.ready <> true then
        y = addFooter("Loading settings from the server…", y, w)
    else if st.available <> true or st.identity <> Settings_identity() then
        y = addFooter("Couldn't load settings from the server (" + Str_orEmpty(st.error) + "). Showing this Roku's saved values.", y, w)
        y = addRow(rowDef("retry", "action", "Try Again"), y, w)
    else if not Str_isEmpty(st.error) then
        y = addFooter("Couldn't refresh settings (" + Str_orEmpty(st.error) + "). Showing the last values the server sent.", y, w)
    end if

    for each e in buildPane(cat.id)
        if e.kind = "header" then
            y = addHeader(e.text, y, w)
        else if e.kind = "row" then
            y = addRow(e.row, y, w)
        else if e.kind = "footer" then
            y = addFooter(e.text, y, w)
        else if e.kind = "preview" then
            y = addPreview(y, w)
        end if
    end for
    m.paneHeight = y

    ' Keep the focused row across a re-render; otherwise start at the first row.
    m.focusIdx = -1
    if keepId <> "" then m.focusIdx = entryIndexFor(keepId)
    if m.focusIdx < 0 then m.focusIdx = nextFocusable(-1, 1)
    updateFocus()
end sub

function addHeader(text as string, y as integer, w as integer) as integer
    lbl = m.pane.createChild("Label")
    lbl.text = UCase(text)
    lbl.color = "0xEDEDED80"
    lbl.width = w - 48
    Label_setFont(lbl, "semibold", 24)
    lbl.translation = [24, y + 22]
    m.entries.Push({ kind: "header", node: lbl, y: y, h: 60 })
    return y + 60
end function

function addRow(row as object, y as integer, w as integer) as integer
    node = m.pane.createChild("SettingsRow")
    node.rowWidth = w
    node.rowHeight = 76
    node.label = row.label
    node.value = rowValue(row)
    node.showChevron = row.kind = "choice" or (row.kind = "action" and row.destructive <> true)
    node.destructive = row.destructive = true
    node.highlighted = row.kind = "info"
    if row.disabled = true then node.opacity = 0.42
    node.translation = [0, y]
    focusable = row.kind <> "info" and row.disabled <> true
    m.entries.Push({ kind: "row", node: node, row: row, y: y, h: 76, focusable: focusable })
    return y + 84
end function

function addFooter(text as string, y as integer, w as integer) as integer
    lbl = m.pane.createChild("Label")
    lbl.text = text
    lbl.color = "0xEDEDED99"
    lbl.wrap = true
    lbl.width = w - 48
    Label_setFont(lbl, "regular", 24)
    lbl.translation = [24, y + 2]
    h = Int(Label_height(lbl))
    if h <= 0 then h = 32
    m.entries.Push({ kind: "footer", node: lbl, y: y, h: h + 16 })
    return y + h + 16
end function

' TvSettingsSubtitlePreview: a rough picture of the stored appearance (what other clients draw).
function addPreview(y as integer, w as integer) as integer
    a = Settings_appearance()
    g = m.pane.createChild("Group")
    g.translation = [0, y]
    bg = g.createChild("Poster")
    bg.uri = "pkg:/images/ui/r14.9.png"
    bg.blendColor = "0x33353AFF"
    bg.width = w
    bg.height = 150
    sizes = { small: 26, medium: 32, large: 40, xlarge: 48, xxlarge: 58 }
    fs = sizes[LCase(Str_orEmpty(a.fontSize))]
    if fs = invalid then fs = 40
    weight = "semibold"
    if LCase(Str_orEmpty(a.fontFamily)) = "monospace" then weight = "medium"
    lbl = g.createChild("Label")
    lbl.text = "Subtitles will look like this"
    Label_setFont(lbl, weight, fs)
    lbl.color = Settings_hexToColor(a.fontColor, Int(Content_numOr(a.textOpacity, 100)))
    lbl.horizAlign = "center"
    lbl.vertAlign = "center"
    textW = Int(Label_width(lbl))
    if textW <= 0 then textW = Int(fs * 14)
    boxW = textW + 36
    boxH = fs + 20
    placement = LCase(Str_orEmpty(a.position))
    if placement = "top" then
        boxY = 14
    else if placement = "lower-third" then
        boxY = 150 - boxH - 36
    else
        boxY = 150 - boxH - 14
    end if
    style = LCase(Str_orEmpty(a.backgroundStyle))
    if style = "box" then
        bgBox = g.createChild("Poster")
        bgBox.uri = "pkg:/images/ui/r6.9.png"
        bgBox.blendColor = Settings_hexToColor(a.backgroundColor, Int(Content_numOr(a.backgroundOpacity, 75)))
        bgBox.width = boxW
        bgBox.height = boxH
        bgBox.translation = [(w - boxW) / 2, boxY]
    end if
    if a.textOutline = true or style = "outline" then
        for each d in [[-2, 0], [2, 0], [0, -2], [0, 2]]
            shadow = g.createChild("Label")
            shadow.text = lbl.text
            Label_setFont(shadow, weight, fs)
            shadow.color = Settings_hexToColor(a.textOutlineColor, 100)
            shadow.horizAlign = "center"
            shadow.vertAlign = "center"
            shadow.width = w
            shadow.height = boxH
            shadow.translation = [d[0], boxY + d[1]]
        end for
    else if style = "shadow" then
        shadow = g.createChild("Label")
        shadow.text = lbl.text
        Label_setFont(shadow, weight, fs)
        shadow.color = "0x000000B3"
        shadow.horizAlign = "center"
        shadow.vertAlign = "center"
        shadow.width = w
        shadow.height = boxH
        shadow.translation = [3, boxY + 3]
    end if
    ' The text itself goes on top of its box and decorations.
    g.removeChild(lbl)
    g.appendChild(lbl)
    lbl.width = w
    lbl.height = boxH
    lbl.translation = [0, boxY]
    m.entries.Push({ kind: "preview", node: g, y: y, h: 150 })
    return y + 162
end function

function focusedRowId() as string
    if m.focusIdx < 0 or m.focusIdx >= m.entries.Count() then return ""
    e = m.entries[m.focusIdx]
    if e.kind <> "row" then return ""
    return e.row.id
end function

function entryIndexFor(rowId as string) as integer
    for i = 0 to m.entries.Count() - 1
        e = m.entries[i]
        if e.kind = "row" and e.focusable = true and e.row.id = rowId then return i
    end for
    return -1
end function

' The next focusable entry from `start` in direction `dir` (1 or -1), or -1.
function nextFocusable(start as integer, dir as integer) as integer
    i = start + dir
    while i >= 0 and i < m.entries.Count()
        e = m.entries[i]
        if e.kind = "row" and e.focusable = true then return i
        i = i + dir
    end while
    return -1
end function

sub updateFocus()
    railHasFocus = not m.inPane
    m.accountBg.visible = railHasFocus and m.railFocus = -1
    if m.accountBg.visible then
        ink = "0x000000FF"
        sub2 = "0x000000B3"
    else
        ink = "0xEDEDEDFF"
        sub2 = "0xEDEDED9E"
    end if
    m.accountName.color = ink
    m.accountSub.color = sub2
    m.avatarInitials.color = ink
    m.accountChevron.blendColor = sub2
    for i = 0 to m.railRows.Count() - 1
        r = m.railRows[i]
        r.focusedState = railHasFocus and i = m.railFocus
        r.highlighted = i = m.catIndex and not r.focusedState
    end for
    m.signOutRow.focusedState = railHasFocus and m.railFocus = m.railRows.Count()
    for i = 0 to m.entries.Count() - 1
        e = m.entries[i]
        if e.kind = "row" then e.node.focusedState = m.inPane and i = m.focusIdx
    end for
    scrollToFocus()
end sub

' Keeps the focused row inside the pane's viewport (the header stays while at the top).
sub scrollToFocus()
    viewport = 940
    target = m.scrollY
    if m.inPane and m.focusIdx >= 0 and m.focusIdx < m.entries.Count() then
        e = m.entries[m.focusIdx]
        ' Pull the group header (and footer) along with the first row of a group.
        top = e.y
        if m.focusIdx > 0 and m.entries[m.focusIdx - 1].kind = "header" then top = m.entries[m.focusIdx - 1].y
        if m.focusIdx > 1 and m.entries[m.focusIdx - 1].kind = "preview" then top = m.entries[m.focusIdx - 2].y
        bottom = e.y + e.h
        if m.focusIdx + 1 < m.entries.Count() and m.entries[m.focusIdx + 1].kind = "footer" then bottom = bottom + m.entries[m.focusIdx + 1].h
        if top - target < 0 then target = top
        if bottom - target > viewport then target = bottom - viewport
        if target < 0 then target = 0
    else
        target = 0
    end if
    m.scrollY = target
    m.pane.translation = [0, -target]
end sub

sub refreshValues()
    for each e in m.entries
        if e.kind = "row" then e.node.value = rowValue(e.row)
    end for
end sub

sub onServerInfo(event as object)
    resp = Api_result(event)
    if resp.ok and Type(resp.data) = "roAssociativeArray" then
        m.serverVersion = Str_orEmpty(resp.data.server_version)
    else
        m.serverVersion = "Unknown"
    end if
    refreshValues()
end sub

' A load this screen started landed (settingsLoaded), or the screen is shown again.
sub onSettingsChanged()
    showStatus("")
    renderPane()
end sub

sub showStatus(text as string)
    m.status.visible = text <> ""
    m.statusLabel.text = text
    ' The status line sits over the pane header's right side.
    m.status.translation = [1250, 96]
end sub

' ---------- Picker / confirm ----------

sub openPicker(row as object)
    m.pickerMode = "options"
    m.pickerRow = row
    m.pickerOptions = rowOptions(row)
    current = rowCurrent(row)
    m.pickerIndex = 0
    for i = 0 to m.pickerOptions.Count() - 1
        if sameValue(m.pickerOptions[i].value, current) then m.pickerIndex = i
    end for
    layoutPicker(row.label, "Choose an option", "")
end sub

sub openConfirm(actionId as string, title as string, message as string, confirmLabel as string)
    m.pickerMode = "confirm"
    m.confirmAction = actionId
    m.pickerRow = invalid
    m.pickerOptions = [{ value: "cancel", label: "Cancel" }, { value: "ok", label: confirmLabel, destructive: true }]
    m.pickerIndex = 0
    layoutPicker(title, "", message)
end sub

sub layoutPicker(title as string, subtitle as string, message as string)
    m.pickerRows.removeChildrenIndex(m.pickerRows.getChildCount(), 0)
    m.pickerItems = []
    w = 760
    rowH = 72
    maxVisible = 8
    count = m.pickerOptions.Count()
    shownCount = count
    if shownCount > maxVisible then shownCount = maxVisible
    for i = 0 to count - 1
        o = m.pickerOptions[i]
        item = m.pickerRows.createChild("SettingsRow")
        item.rowWidth = w - 48
        item.rowHeight = rowH
        item.label = o.label
        item.showChevron = false
        item.destructive = o.destructive = true
        m.pickerItems.Push(item)
    end for
    headH = 110
    if message <> "" then
        m.pickerMessage.visible = true
        m.pickerMessage.width = w - 72
        m.pickerMessage.text = message
        msgH = Int(Label_height(m.pickerMessage))
        if msgH <= 0 then msgH = 32
        headH = 90 + msgH + 24
    else
        m.pickerMessage.visible = false
    end if
    h = headH + shownCount * (rowH + 6) + 24
    x = (1920 - w) / 2
    top = (1080 - h) / 2
    m.pickerBg.width = w
    m.pickerBg.height = h
    m.pickerBg.translation = [x, top]
    m.pickerRing.width = w
    m.pickerRing.height = h
    m.pickerRing.translation = [x, top]
    m.pickerTitle.text = title
    m.pickerTitle.translation = [x + 36, top + 28]
    m.pickerSub.text = subtitle
    m.pickerSub.visible = subtitle <> ""
    m.pickerSub.translation = [x + 36, top + 72]
    m.pickerMessage.translation = [x + 36, top + 80]
    m.pickerHint.width = 240
    m.pickerHint.translation = [x + w - 36 - 240, top + 34]
    m.pickerDivider.width = w
    m.pickerDivider.translation = [x, top + headH - 12]
    m.pickerRows.translation = [x + 24, top + headH]
    m.pickerVisible = shownCount
    m.pickerFirst = 0
    m.picker.visible = true
    updatePicker()
end sub

' Lays out the window of options around the focused one (long lists scroll).
sub updatePicker()
    count = m.pickerItems.Count()
    shownCount = m.pickerVisible
    if m.pickerIndex < m.pickerFirst then m.pickerFirst = m.pickerIndex
    if m.pickerIndex >= m.pickerFirst + shownCount then m.pickerFirst = m.pickerIndex - shownCount + 1
    if m.pickerFirst < 0 then m.pickerFirst = 0
    current = invalid
    if m.pickerMode = "options" and m.pickerRow <> invalid then current = rowCurrent(m.pickerRow)
    y = 0
    for i = 0 to count - 1
        item = m.pickerItems[i]
        shown = i >= m.pickerFirst and i < m.pickerFirst + shownCount
        item.visible = shown
        if shown then
            item.translation = [0, y]
            y = y + 78
        end if
        item.focusedState = i = m.pickerIndex
        if m.pickerMode = "options" and sameValue(m.pickerOptions[i].value, current) then
            item.value = "✓"
            item.highlighted = not item.focusedState
        else
            item.value = ""
            item.highlighted = false
        end if
    end for
end sub

sub closePicker()
    m.picker.visible = false
    m.pickerMode = ""
end sub

sub choosePicker()
    o = m.pickerOptions[m.pickerIndex]
    if m.pickerMode = "confirm" then
        closePicker()
        if o.value = "ok" then performConfirmed(m.confirmAction)
        return
    end if
    row = m.pickerRow
    closePicker()
    applyChoice(row, o.value)
end sub

' ---------- Writes ----------

sub beginWrites(count as integer)
    m.pendingWrites = count
    m.writeFailed = false
    showStatus("Saving…")
end sub

' One write finished. A 404 on a DELETE means nothing was stored there, which is what was asked.
' Chained follow-ups (context.thenOp) run before the re-read.
sub onWriteDone(event as object)
    resp = Api_result(event)
    ctx = resp.context
    ok = resp.ok
    if not ok and resp.status = 404 and ctx <> invalid and ctx.isDelete = true then ok = true
    if not ok then
        m.writeFailed = true
        m.global.toast = "Couldn't save the setting: " + Api_errorText(resp)
    else if ctx <> invalid and ctx.thenOp <> invalid then
        op = ctx.thenOp
        if op.method = "DELETE" then
            Settings_delete(op.key, op.scope, "onWriteDone", { isDelete: true })
        else
            Settings_put(op.key, op.scope, op.value, "onWriteDone")
        end if
        return
    end if
    m.pendingWrites = m.pendingWrites - 1
    if m.pendingWrites <= 0 then
        m.pendingWrites = 0
        showStatus("")
        Settings_load()
    end if
end sub

sub putValue(key as string, scope as string, value as dynamic)
    Settings_put(key, scope, value, "onWriteDone")
end sub

sub deleteValue(key as string, scope as string)
    Settings_delete(key, scope, "onWriteDone", { isDelete: true })
end sub

' Writes a language-tag key: "" clears the row (the contract refuses an empty tag).
sub putLanguage(key as string, scope as string, tag as string)
    beginWrites(1)
    if tag.Trim() = "" then deleteValue(key, scope) else putValue(key, scope, tag)
end sub

' ui.card_presentation: the whole two-field object, at profile_device while "Only This Device"
' is on, else at profile_client (roams between this profile's TVs).
sub writeCardPresentation(posterSize as string, caption as string, deviceOnly as boolean)
    scope = "profile_client"
    if deviceOnly then scope = "profile_device"
    beginWrites(1)
    putValue("ui.card_presentation", scope, { poster_size: posterSize, caption: caption })
end sub

' playback.subtitle_appearance at profile_device (the full object; textOpacity only when the
' server's manifest knows it).
sub writeAppearance(a as object)
    body = {}
    for each k in Settings_defaultAppearance()
        if a[k] <> invalid then body[k] = a[k]
    end for
    if not textOpacitySupported() then body.Delete("textOpacity")
    beginWrites(1)
    putValue("playback.subtitle_appearance", "profile_device", body)
end sub

sub savePref(key as string, value as dynamic)
    p = AA_copy(m.global.prefs)
    p[key] = value
    Prefs_save(p)
end sub

' A choice was made in the picker (or a toggle flipped with OK).
sub applyChoice(row as object, value as dynamic)
    id = row.id
    cp = Settings_cardPresentation()
    deviceOnly = Settings_source("ui.card_presentation") = "profile_device"
    if id = "cardPreset" then
        for each pr in cardPresets()
            if pr.id = value then writeCardPresentation(pr.posterSize, pr.caption, deviceOnly)
        end for
    else if id = "cardPosterSize" then
        writeCardPresentation(Str_orEmpty(value), cp.caption, deviceOnly)
    else if id = "cardCaptions" then
        writeCardPresentation(cp.posterSize, Str_orEmpty(value), deviceOnly)
    else if id = "cardDeviceOnly" then
        if value = true then
            writeCardPresentation(cp.posterSize, cp.caption, true)
        else
            beginWrites(1)
            deleteValue("ui.card_presentation", "profile_device")
        end if
    else if id = "titleArt" then
        scope = "profile_device"
        if Settings_source("ui.title_art") = "profile" then scope = "profile"
        beginWrites(1)
        putValue("ui.title_art", scope, value = true)
    else if id = "titleArtAll" then
        show = Settings_showTitleArt()
        beginWrites(1)
        if value = true then
            putValue("ui.title_art", "profile", show)
        else
            ' Pin this device's value first, then clear the profile value so other devices return to their own.
            Settings_put("ui.title_art", "profile_device", show, "onWriteDone", { thenOp: { method: "DELETE", key: "ui.title_art", scope: "profile" } })
        end if
    else if id = "showAudiobooks" then
        savePref("showAudiobooks", value = true)
        m.global.homeDirty = true
        refreshValues()
    else if id = "metadataLanguage" then
        putLanguage("catalog.metadata_language", "profile", Str_orEmpty(value))
    else if id = "quality" then
        preset = Settings_qualityPresetById(Str_orEmpty(value))
        if preset <> invalid then
            beginWrites(2)
            putValue("playback.preferred_quality", "profile_device", preset.resolution)
            if preset.kbps > 0 then
                putValue("playback.max_bitrate_kbps", "profile_device", preset.kbps)
            else
                ' Uncapped: store JSON null at this scope ("no cap of my own", contracts/settings
                ' conformance), as Android's flusher does. Deleting the row instead let a cap
                ' stored at the profile scope show through, so "Original" read "Original at 6 Mbps"
                ' and the server honoured that cap with a 720p transcode.
                putValue("playback.max_bitrate_kbps", "profile_device", invalid)
            end if
        end if
    else if id = "audioLanguage" then
        putLanguage("playback.audio_language", "profile_device", Str_orEmpty(value))
    else if id = "dolbyVision" then
        beginWrites(1)
        putValue("player.dolby_vision_enabled", "profile_device", value = true)
    else if id = "dvProfile7Fallback" then
        beginWrites(1)
        putValue("player.dv_profile7_hdr10_fallback", "profile_device", value = true)
    else if id = "forceHdr" then
        savePref("forceHdrPassthrough", value = true)
    else if id = "forceDolby" then
        savePref("forceDolbyPassthrough", value = true)
    else if id = "progressiveRemux" then
        savePref("progressiveRemux", value = true)
        refreshValues()
    else if id = "autoPlayNext" then
        beginWrites(1)
        putValue("playback.auto_play_next", "profile_device", value = true)
    else if id = "showNextUp" then
        beginWrites(1)
        putValue("playback.next_up_prompt_seconds", "profile_device", Int(Content_numOr(value, 30)))
    else if id = "skipIntros" then
        beginWrites(1)
        putValue("playback.intro_skip_mode", "profile_device", Str_orEmpty(value))
    else if id = "skipCredits" then
        beginWrites(1)
        putValue("playback.auto_skip_credits", "profile_device", value = true)
    else if id = "rewindOnResume" then
        savePref("resumeRewind", Int(Content_numOr(value, 7)))
        refreshValues()
    else if id = "stillWatching" then
        savePref("passoutThreshold", Int(Content_numOr(value, 3)))
        refreshValues()
    else if id = "skipBack" or id = "skipForward" then
        seconds = Int(Content_numOr(value, 10))
        if seekIntervalsSynced() then
            beginWrites(1)
            if id = "skipBack" then putValue("player.video_skip_back_seconds", "profile", seconds) else putValue("player.video_skip_forward_seconds", "profile", seconds)
        else
            savePref(id, seconds)
            refreshValues()
        end if
    else if id = "subtitleLanguage" then
        putLanguage("playback.subtitle_language", "profile", Str_orEmpty(value))
    else if id = "subtitleMode" then
        beginWrites(1)
        putValue("playback.subtitle_mode", "profile", Str_orEmpty(value))
    else if id = "showForced" then
        beginWrites(1)
        putValue("playback.show_forced_subtitles", "profile", value = true)
    else if id = "customAppearance" then
        if value = true then
            writeAppearance(Settings_appearance())
        else
            beginWrites(1)
            deleteValue("playback.subtitle_appearance", "profile_device")
        end if
    else if row.appearance = true then
        a = Settings_appearance()
        if id = "textOpacity" or id = "backgroundOpacity" then
            a[id] = Int(Content_numOr(value, 100))
        else if id = "textOutline" then
            a[id] = value = true
        else
            a[id] = Str_orEmpty(value)
        end if
        writeAppearance(a)
    end if
end sub

' A confirmed destructive action.
sub performConfirmed(actionId as string)
    if actionId = "signOut" then
        Api_signOut()
        Settings_clear()
        Nav_reset("@start")
    else if actionId = "resetOverrides" then
        ' Clear every server-side device override for this profile on this Roku, and the
        ' device-local playback keys that have no server row.
        p = AA_copy(m.global.prefs)
        p.resumeRewind = 7
        p.passoutThreshold = 3
        p.forceHdrPassthrough = false
        p.forceDolbyPassthrough = false
        p.progressiveRemux = false
        Prefs_save(p)
        keys = Settings_deviceKeys()
        beginWrites(keys.Count())
        for each k in keys
            deleteValue(k, "profile_device")
        end for
    else if actionId = "resetAppearance" then
        writeAppearance(Settings_defaultAppearance())
    end if
end sub

' ---------- Actions ----------

sub activateRow(row as object)
    id = row.id
    if row.kind = "choice" then
        openPicker(row)
    else if row.kind = "toggle" then
        current = rowValue(row) = "On"
        applyChoice(row, not current)
    else if id = "homeSections" then
        Hs_open()
    else if id = "cardUseProfileDefault" then
        beginWrites(1)
        deleteValue("ui.card_presentation", "profile_client")
    else if id = "switchProfile" then
        Nav_push("ProfileScreen", { switching: true })
    else if id = "resetOverrides" then
        openConfirm("resetOverrides", "Reset Playback Overrides?", "Playback choices for this Roku and profile go back to the server fallback.", "Reset")
    else if id = "resetAppearance" then
        openConfirm("resetAppearance", "Reset Custom Appearance?", "This restores all custom subtitle appearance options to their defaults.", "Reset")
    else if id = "manageServers" then
        Session_clearServer()
        Nav_reset("ServerConnectScreen")
    else if id = "retry" then
        showStatus("Loading…")
        Settings_load()
    end if
end sub

sub enterPane()
    first = nextFocusable(-1, 1)
    if first < 0 then return
    m.inPane = true
    m.focusIdx = first
    updateFocus()
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.hsVisible = true then return Hs_onKey(key)
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
            closePicker()
        end if
        return true
    end if

    if m.inPane then
        if key = "up" then
            nxt = nextFocusable(m.focusIdx, -1)
            if nxt >= 0 then m.focusIdx = nxt
        else if key = "down" then
            nxt = nextFocusable(m.focusIdx, 1)
            if nxt >= 0 then m.focusIdx = nxt
        else if key = "left" or key = "back" then
            m.inPane = false
            m.railFocus = m.catIndex
        else if key = "OK" then
            if m.focusIdx >= 0 and m.focusIdx < m.entries.Count() then activateRow(m.entries[m.focusIdx].row)
            return true
        else
            return true
        end if
        updateFocus()
        return true
    end if

    ' Rail: -1 account, 0..n-1 categories, n Sign Out. Focusing a category swaps the pane.
    last = m.railRows.Count()
    if key = "up" then
        if m.railFocus > -1 then m.railFocus = m.railFocus - 1
    else if key = "down" then
        if m.railFocus < last then m.railFocus = m.railFocus + 1
    else if key = "right" then
        if m.railFocus >= 0 and m.railFocus < last then enterPane()
        return true
    else if key = "OK" then
        if m.railFocus = -1 then
            Nav_push("ProfileScreen", { switching: true })
        else if m.railFocus = last then
            openConfirm("signOut", "Sign Out", "You will be returned to the login screen.", "Sign Out")
        else
            enterPane()
        end if
        return true
    else if key = "back" then
        return false
    else
        return true
    end if
    if m.railFocus >= 0 and m.railFocus < last and m.railFocus <> m.catIndex then
        m.catIndex = m.railFocus
        m.scrollY = 0
        m.focusIdx = -1
        renderPane()
    end if
    updateFocus()
    return true
end function
