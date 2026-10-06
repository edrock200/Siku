' Session persistence: the active server, tokens, signed-in user and selected profile.
' Lives on m.global.session (an associative array). Always replace the whole AA
' (m.global.session = s) after editing a copy, so observers fire.
' SPDX-License-Identifier: AGPL-3.0-or-later

function Session_empty() as object
    return {
        serverUrl: ""        ' normalized base, may include a path prefix
        serverOrigin: ""     ' scheme://host[:port] — used to resolve root-relative URLs
        serverId: ""
        serverName: ""
        accessToken: ""
        refreshToken: ""
        expiresAt: 0         ' epoch seconds
        user: {}
        profileId: ""
        profileToken: ""
        profileName: ""
        profileAvatar: ""
        deviceId: ""
    }
end function

function Session_load() as object
    s = Session_empty()
    saved = Registry_read("session")
    if saved <> invalid then
        for each k in saved
            s[k] = saved[k]
        end for
    end if
    if Str_isEmpty(s.deviceId) then
        s.deviceId = Registry_read("deviceId", "")
        if Str_isEmpty(s.deviceId) then
            s.deviceId = CreateObject("roDeviceInfo").GetRandomUUID()
            Registry_write("deviceId", s.deviceId)
        end if
    end if
    return s
end function

' Saves a session and publishes it on m.global.
sub Session_save(s as object)
    Registry_write("session", s)
    Session_rememberServer(s)
    m.global.session = s
    m.global.sessionChanged = m.global.sessionChanged + 1
end sub

' Records the server in the saved-servers list (for Switch Server).
sub Session_rememberServer(s as object)
    if Str_isEmpty(s.serverUrl) then return
    servers = Registry_read("servers", [])
    out = [{ url: s.serverUrl, name: s.serverName, id: s.serverId }]
    for each e in servers
        if e.url <> s.serverUrl then out.Push(e)
    end for
    Registry_write("servers", out)
end sub

function Session_savedServers() as object
    return Registry_read("servers", [])
end function

' Clears tokens and profile but keeps the server.
sub Session_signOutLocal(s as object)
    c = AA_copy(s)
    c.accessToken = ""
    c.refreshToken = ""
    c.expiresAt = 0
    c.user = {}
    c.profileId = ""
    c.profileToken = ""
    c.profileName = ""
    c.profileAvatar = ""
    Session_save(c)
end sub

' Forgets the server entirely (Change server).
sub Session_clearServer()
    s = Session_empty()
    s.deviceId = m.global.session.deviceId
    Session_save(s)
end sub

' Applies a token response {access_token, refresh_token, expires_in, user?}.
function Session_withTokens(s as object, tokens as object) as object
    c = AA_copy(s)
    c.accessToken = Str_orEmpty(tokens.access_token)
    if not Str_isEmpty(tokens.refresh_token) then c.refreshToken = tokens.refresh_token
    expiresIn = tokens.expires_in
    if expiresIn = invalid then expiresIn = 3600
    c.expiresAt = Time_nowSeconds() + Int(expiresIn)
    if tokens.user <> invalid then c.user = tokens.user
    return c
end function

function Session_withProfile(s as object, profile as object, profileToken = "" as string) as object
    c = AA_copy(s)
    c.profileId = Str_orEmpty(profile.id)
    c.profileName = Str_orEmpty(profile.name)
    c.profileAvatar = Str_orEmpty(profile.avatar_url)
    c.profileToken = profileToken
    return c
end function

' ---------- Server URLs ----------

' Trims, strips trailing "/", lowercases scheme and host. Returns "" if unusable.
function Url_normalize(input as string) as string
    s = input.Trim()
    while Len(s) > 0 and Right(s, 1) = "/"
        s = Left(s, Len(s) - 1)
    end while
    if s = "" then return ""
    schemeEnd = Instr(1, s, "://")
    if schemeEnd = 0 then return s
    scheme = LCase(Left(s, schemeEnd - 1))
    rest = Mid(s, schemeEnd + 3)
    slash = Instr(1, rest, "/")
    if slash = 0 then
        host = LCase(rest)
        path = ""
    else
        host = LCase(Left(rest, slash - 1))
        path = Mid(rest, slash)
    end if
    return scheme + "://" + host + path
end function

' "https://media.example.com/silo" -> "https://media.example.com"
function Url_origin(base as string) as string
    schemeEnd = Instr(1, base, "://")
    if schemeEnd = 0 then return base
    rest = Mid(base, schemeEnd + 3)
    slash = Instr(1, rest, "/")
    if slash = 0 then return base
    return Left(base, schemeEnd + 2) + Left(rest, slash - 1)
end function

function Url_host(base as string) as string
    o = Url_origin(base)
    i = Instr(1, o, "://")
    if i = 0 then return o
    return Mid(o, i + 3)
end function

' Resolves an artwork/stream URL from the API: absolute stays, root-relative gets the origin.
function Url_resolve(u as dynamic) as string
    if Str_isEmpty(u) then return ""
    if Left(u, 7) = "http://" or Left(u, 8) = "https://" then return u
    origin = m.global.session.serverOrigin
    if Left(u, 1) = "/" then return origin + u
    return origin + "/" + u
end function

' ---------- Preferences (device-local) ----------

function Prefs_default() as object
    return {
        posterSize: "standard"     ' compact | standard | large
        showAudiobooks: false      ' top-menu Audiobooks tab
        skipIntro: "ask"           ' never | ask | always
        autoPlayNext: true
        quality: "auto"
        skipBack: 10
        skipForward: 30
        subtitleSize: "medium"
        hiddenSections: []
    }
end function

function Prefs_load() as object
    p = Prefs_default()
    saved = Registry_read("prefs")
    if saved <> invalid then
        for each k in saved
            p[k] = saved[k]
        end for
    end if
    return p
end function

sub Prefs_save(p as object)
    Registry_write("prefs", p)
    m.global.prefs = p
end sub
