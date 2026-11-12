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
        accountId: ""        ' local id of the open account (Accounts.brs), "" with none open
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

' A copy of the published session to build a new sign-in or server on (the address screen, the
' sign-in screen, a phone's sign-in). It never carries `temporary`: Session_save would publish such
' a copy of a phone's borrowed profile without storing it, and RemoteControl would read its empty
' tokens as Sign Out on the phone's profile (signing the TV's own account out and removing it).
function Session_ownCopy() as object
    c = AA_copy(m.global.session)
    c.Delete("temporary")
    return c
end function

' Saves a session and publishes it on m.global. A temporary session (a phone's profile borrowed
' for remote playback, components/remote/RemoteControl.brs) is published only: it is never written
' to the registry, so the Roku's own sign-in is what the next launch finds.
sub Session_save(s as object)
    temporary = s.temporary <> invalid and (Type(s.temporary) = "Boolean" or Type(s.temporary) = "roBoolean")
    if temporary then temporary = s.temporary
    prev = invalid
    if not temporary then
        prev = Registry_read("session")
        ' Its account (Accounts.brs): the same one, a saved one this sign-in matches, or a new one.
        s = Accounts_assign(s)
        ' The account it replaces keeps its sign-in in its entry. Two writes around "session" when
        ' the account changes, so a stop between any two of them never loses a sign-in.
        Accounts_store(prev, s, true)
        Registry_write("session", s)
        Accounts_store(prev, s, false)
        Session_storeServers(prev, s)
    end if
    m.global.session = s
    ' Only after publishing: MainScene's purge keeps the file of m.global.session's owner, which
    ' must already be the new one (else the old owner's Home survives a profile switch).
    if not temporary then Session_homeCacheCheck(prev)
    m.global.sessionChanged = m.global.sessionChanged + 1
    ' The server-synced settings snapshot (components/common/Settings.brs) belongs to one server
    ' and profile; drop it when either changes so the next screen reloads instead of mixing them.
    st = m.global.settings
    if st <> invalid and Type(st) = "roAssociativeArray" then
        identity = Str_orEmpty(s.serverUrl) + "|" + Str_orEmpty(s.profileId)
        if Str_orEmpty(st.identity) <> identity then
            m.global.settings = { ready: false, available: false, identity: "", revision: 0, manifestRevision: 0, items: {}, error: "" }
        end if
    end if
end sub

' Why the Home cache (HomeCache.brs) must go when the saved session changes from `prev` to `s`:
' "sign-out" (tokens dropped: sign-out, an expired or removed account), "server", "account" or
' "profile" (another profile picked; clearing the profile for Who's Watching keeps it, so picking
' the same one again still starts instantly). "" when nothing that owns the cache changed.
function Session_homeCachePurgeReason(prev as dynamic, s as object) as string
    if prev = invalid or Type(prev) <> "roAssociativeArray" then return ""
    if Str_isEmpty(prev.accessToken) or Str_isEmpty(prev.serverUrl) then return ""
    if Str_orEmpty(prev.serverUrl) <> Str_orEmpty(s.serverUrl) or Str_orEmpty(prev.serverId) <> Str_orEmpty(s.serverId) then return "server"
    if Str_isEmpty(s.accessToken) then return "sign-out"
    prevUser = ""
    newUser = ""
    if prev.user <> invalid and Type(prev.user) = "roAssociativeArray" then prevUser = Str_orEmpty(prev.user.id)
    if s.user <> invalid and Type(s.user) = "roAssociativeArray" then newUser = Str_orEmpty(s.user.id)
    if prevUser <> newUser then return "account"
    if Str_orEmpty(prev.accountId) <> Str_orEmpty(s.accountId) then return "account"
    if not Str_isEmpty(prev.profileId) and not Str_isEmpty(s.profileId) and Str_orEmpty(prev.profileId) <> Str_orEmpty(s.profileId) then return "profile"
    return ""
end function

' Asks MainScene to purge the Home cache (it runs HomeCacheTask) when the owner changed from
' `prev` to the published m.global.session (Session_save publishes first; see there).
sub Session_homeCacheCheck(prev as dynamic)
    g = m.global
    if g = invalid or not g.hasField("homeCachePurge") then return
    reason = Session_homeCachePurgeReason(prev, g.session)
    if reason = "" then return
    g.homeCachePurgeReason = reason
    g.homeCachePurge = g.homeCachePurge + 1
end sub

' ---------- Saved servers ----------
' Registry "servers": [{url, name, id}], most recently used first. Since registry layout 2
' (Accounts.brs) the sign-ins live in the accounts, several per server: the active account's in
' "session", the others' in their "accounts" entries. Layout 1 kept one sign-in per server in its
' entry (`session`); Accounts_migrate moves those, and until it has finished an entry's stored
' sign-in is carried along untouched. Bounded: Session_maxServers() entries and
' Session_serversBudget() bytes of JSON.
' Same model as Android TV's ServerRegistry; adapted from Silo-Server/silo-roku, AGPL-3.0
' (source/storage/registry.bs, source/onboarding/servers.bs).

function Session_maxServers() as integer
    return 6
end function

function Session_serversBudget() as integer
    return 8000
end function

' The sign-in part of a session, as stored in a saved server's entry; invalid when signed out.
' Unquoted keys on purpose: they are stored lower-case, like the rest of the session, so dot reads
' match in brs-cli too (its ParseJson objects are case-sensitive).
function Session_storedSignIn(s as dynamic) as dynamic
    if s = invalid or Type(s) <> "roAssociativeArray" then return invalid
    if Str_isEmpty(s.accessToken) and Str_isEmpty(s.refreshToken) then return invalid
    user = s.user
    if user = invalid or Type(user) <> "roAssociativeArray" then user = {}
    return {
        serverOrigin: Str_orEmpty(s.serverOrigin)
        accessToken: Str_orEmpty(s.accessToken)
        refreshToken: Str_orEmpty(s.refreshToken)
        expiresAt: Int(Num_or(s.expiresAt, 0))
        user: user
        profileId: Str_orEmpty(s.profileId)
        profileToken: Str_orEmpty(s.profileToken)
        profileName: Str_orEmpty(s.profileName)
        profileAvatar: Str_orEmpty(s.profileAvatar)
    }
end function

' The saved-servers list after `s` (being saved, never temporary) replaced `prev` (the registry
' session before it). Pure (tests/test_saved_servers.py). `s`'s server moves to the front; `prev`'s
' server name and identity are kept up to date. A server missing from the list is never added back
' for `prev` (it was removed). Sign-ins are the accounts' (Accounts.brs); a layout-1 entry's stored
' sign-in is kept as it is until the migration has moved it.
function Session_serversNext(list as dynamic, prev as dynamic, s as object) as object
    url = Str_orEmpty(s.serverUrl)
    prevUrl = ""
    if prev <> invalid and Type(prev) = "roAssociativeArray" then prevUrl = Str_orEmpty(prev.serverUrl)
    out = []
    if url <> "" then out.Push({ "url": url, "name": Str_orEmpty(s.serverName), "id": Str_orEmpty(s.serverId) })
    items = Arr_or(list)
    for i = 0 to items.Count() - 1
        e = items[i]
        if e <> invalid and Type(e) = "roAssociativeArray" and not Str_isEmpty(e.url) then
            eu = Str_orEmpty(e.url)
            if eu <> url and not Session_serversHas(out, eu) then
                c = { "url": eu, "name": Str_orEmpty(e.name), "id": Str_orEmpty(e.id) }
                if prevUrl <> "" and eu = prevUrl then
                    if not Str_isEmpty(prev.serverName) then c.name = Str_orEmpty(prev.serverName)
                    if not Str_isEmpty(prev.serverId) then c.id = Str_orEmpty(prev.serverId)
                end if
                if e.session <> invalid and Type(e.session) = "roAssociativeArray" then c.session = e.session
                out.Push(c)
            end if
        end if
    end for
    while out.Count() > Session_maxServers()
        out.Pop()
    end while
    return Session_serversFit(out)
end function

function Session_serversHas(list as object, url as string) as boolean
    for i = 0 to list.Count() - 1
        if Str_orEmpty(list[i].url) = url then return true
    end for
    return false
end function

' Keeps the list's JSON within Session_serversBudget(): the least recently used servers lose
' any layout-1 stored sign-in first, then whole entries go from the end (the first one always stays).
function Session_serversFit(list as object) as object
    while Len(FormatJson(list)) > Session_serversBudget()
        dropped = false
        for i = list.Count() - 1 to 1 step -1
            if list[i].session <> invalid then
                list[i].Delete("session")
                print "[siku-servers] registry budget: forgot the sign-in of a least recently used server"
                dropped = true
                exit for
            end if
        end for
        if not dropped then
            if list.Count() <= 1 then exit while
            list.Pop()
        end if
    end while
    return list
end function

' Writes the saved-servers list for a save of `s` over `prev` (only when it changed: registry
' writes wear flash).
sub Session_storeServers(prev as dynamic, s as object)
    old = Registry_read("servers", [])
    nxt = Session_serversNext(old, prev, s)
    if FormatJson(nxt) = FormatJson(Arr_or(old)) then return
    Registry_write("servers", nxt)
    ' A server pushed out by the limit or the byte budget takes its accounts with it: a sign-in
    ' nobody can see on Change Account must not stay on this Roku (or alive on the server).
    Session_dropAccountsOf(Session_serversDropped(old, nxt), "limit")
end sub

' The addresses in `old` that `nxt` no longer has (pure; tests/test_saved_servers.py).
function Session_serversDropped(old as dynamic, nxt as dynamic) as object
    kept = Arr_or(nxt)
    out = []
    items = Arr_or(old)
    for i = 0 to items.Count() - 1
        e = items[i]
        if e <> invalid and Type(e) = "roAssociativeArray" and not Str_isEmpty(e.url) then
            url = Str_orEmpty(e.url)
            if not Session_serversHas(kept, url) and not Session_listHas(out, url) then out.Push(url)
        end if
    end for
    return out
end function

function Session_listHas(list as object, v as string) as boolean
    for i = 0 to list.Count() - 1
        if list[i] = v then return true
    end for
    return false
end function

' Forgets the accounts on `urls` (servers no longer saved): each stored sign-in is ended on its
' server (Session_queueRevoke) and the accounts go. why: "limit" (Session_storeServers) or
' "orphan" (found at launch, left by an older Siku).
sub Session_dropAccountsOf(urls as object, why as string)
    if urls.Count() = 0 then return
    list = Accounts_list()
    dropped = 0
    for i = 0 to urls.Count() - 1
        accts = Accounts_onServer(list, urls[i])
        for j = 0 to accts.Count() - 1
            if Accounts_hasSignIn(accts[j]) then Session_queueRevoke(urls[i], accts[j].session)
            dropped = dropped + 1
        end for
    end for
    if dropped = 0 then return
    Registry_write("accounts", Accounts_onServersOtherThan(list, urls))
    Diag_log("[siku-accounts] forgot " + dropped.ToStr() + " account(s) on servers no longer saved (" + why + ")")
end sub

' Accounts on servers that are not saved any more (the active session's server always counts as
' saved), left by Siku builds before the limit dropped them with their accounts: forgotten at launch.
sub Session_dropOrphanAccounts()
    if Accounts_layout() < 2 then return
    urls = Accounts_unsavedServers(Accounts_list(), Session_savedServers(), Str_orEmpty(m.global.session.serverUrl))
    Session_dropAccountsOf(urls, "orphan")
end sub

' Asks MainScene to end a stored sign-in on its server (Api_revoke; best effort, also from a Task
' thread, and outliving the screen that asked). signIn: {accessToken, refreshToken, expiresAt}.
sub Session_queueRevoke(url as string, signIn as dynamic)
    if url = "" or signIn = invalid or Type(signIn) <> "roAssociativeArray" then return
    if Str_isEmpty(signIn.accessToken) and Str_isEmpty(signIn.refreshToken) then return
    g = m.global
    if g = invalid or not g.hasField("revokeQueue") then return
    q = Arr_or(g.revokeQueue)
    q.Push({ url: url, accessToken: Str_orEmpty(signIn.accessToken), refreshToken: Str_orEmpty(signIn.refreshToken), expiresAt: Accounts_int(signIn.expiresAt) })
    g.revokeQueue = q
    g.revokeSeq = g.revokeSeq + 1
end sub

' Records the server in the saved-servers list without touching another server's sign-in.
sub Session_rememberServer(s as object)
    if Str_isEmpty(s.serverUrl) then return
    Session_storeServers(invalid, s)
end sub

function Session_savedServers() as object
    return Arr_or(Registry_read("servers", []))
end function

' The saved entry for `url`, or invalid.
function Session_savedServer(url as string) as dynamic
    list = Session_savedServers()
    for i = 0 to list.Count() - 1
        e = list[i]
        if Type(e) = "roAssociativeArray" and Str_orEmpty(e.url) = url then return e
    end for
    return invalid
end function

' True when a layout-1 entry holds a stored sign-in (the migration reads it; Accounts.brs).
function Session_entrySignedIn(e as dynamic) as boolean
    if e = invalid or Type(e) <> "roAssociativeArray" then return false
    st = e.session
    if st = invalid or Type(st) <> "roAssociativeArray" then return false
    return not Str_isEmpty(st.accessToken) or not Str_isEmpty(st.refreshToken)
end function

' Drops `url` from the saved-servers list, with every account on it, and returns its entry
' (invalid when it was not saved). Pure list form: Session_serversWithout.
function Session_forgetServer(url as string) as dynamic
    list = Session_savedServers()
    removed = invalid
    for i = 0 to list.Count() - 1
        if Type(list[i]) = "roAssociativeArray" and Str_orEmpty(list[i].url) = url then removed = list[i]
    end for
    Registry_write("servers", Session_serversWithout(list, url))
    Accounts_removeServer(url)
    return removed
end function

' True when any saved account on `url` holds a sign-in, or it is the active server and signed in.
function Session_serverSignedIn(url as string) as boolean
    if url = "" then return false
    s = m.global.session
    if Str_orEmpty(s.serverUrl) = url and Accounts_signedIn(s) and not Accounts_isTemporary(s) then return true
    return Accounts_hasSignIn(Accounts_latestOn(Accounts_list(), url, ""))
end function

function Session_serversWithout(list as dynamic, url as string) as object
    out = []
    items = Arr_or(list)
    for i = 0 to items.Count() - 1
        e = items[i]
        if Type(e) = "roAssociativeArray" and Str_orEmpty(e.url) <> url then out.Push(e)
    end for
    return out
end function

' The session a saved account restores on its server (pure): the server entry's address, name and
' identity, and the account's id, user and stored sign-in (none for an expired one, or with
' `acct` invalid: the server with no account open). askProfile: see Session_fromEntry.
function Session_fromAccount(srv as object, acct as dynamic, deviceId as string, askProfile as boolean) as object
    e = { "url": Str_orEmpty(srv.url), "name": Str_orEmpty(srv.name), "id": Str_orEmpty(srv.id) }
    if acct <> invalid and Type(acct) = "roAssociativeArray" and Accounts_hasSignIn(acct) then e.session = acct.session
    s = Session_fromEntry(e, deviceId, askProfile)
    if acct <> invalid and Type(acct) = "roAssociativeArray" then
        s.accountId = Str_orEmpty(acct.id)
        if Str_isEmpty(s.accessToken) and Str_isEmpty(s.refreshToken) then
            ' An expired account: no tokens, but who it was (LoginScreen fills the username in).
            s.user = { "id": Str_orEmpty(acct.userid), "username": Str_orEmpty(acct.username) }
        end if
    end if
    return s
end function

' The session a saved entry restores: its address, name, identity and stored sign-in (pure).
' askProfile (Profile Selection would ask at launch, or the caller wants the picker) drops the
' stored profile so Who's watching shows; it never reopens a PIN profile without its PIN then.
function Session_fromEntry(e as object, deviceId as string, askProfile as boolean) as object
    s = Session_empty()
    s.deviceId = deviceId
    s.serverUrl = Str_orEmpty(e.url)
    s.serverOrigin = Url_origin(s.serverUrl)
    s.serverName = Str_orEmpty(e.name)
    s.serverId = Str_orEmpty(e.id)
    st = e.session
    if st <> invalid and Type(st) = "roAssociativeArray" then
        s.accessToken = Str_orEmpty(st.accessToken)
        s.refreshToken = Str_orEmpty(st.refreshToken)
        s.expiresAt = Int(Num_or(st.expiresAt, 0))
        if st.user <> invalid and Type(st.user) = "roAssociativeArray" then s.user = st.user
        if not askProfile then
            s.profileId = Str_orEmpty(st.profileId)
            s.profileToken = Str_orEmpty(st.profileToken)
            s.profileName = Str_orEmpty(st.profileName)
            s.profileAvatar = Str_orEmpty(st.profileAvatar)
        end if
    end if
    return s
end function

' Makes a saved server the active one with its most recently used account (Manage Servers, Sign
' Out & Remove Server). The account it replaces keeps its sign-in (Session_save). Callers then
' route with Nav_reset("@start"): Home, Who's watching or the sign-in screen, whatever the sign-in
' reaches.
sub Session_activateServer(e as object, askProfile as boolean)
    Session_activateAccount(e, Accounts_latestOn(Accounts_list(), Str_orEmpty(e.url), ""), askProfile)
end sub

' Makes `acct` (an "accounts" entry; invalid: none, for a sign-in of a new account) on the saved
' server `srv` the active one (Change Account).
sub Session_activateAccount(srv as object, acct as dynamic, askProfile as boolean)
    Session_forgetPlaybackCaps()
    Session_forgetServerState()
    s = Session_fromAccount(srv, acct, Str_orEmpty(m.global.session.deviceId), askProfile)
    signedIn = not Str_isEmpty(s.accessToken) or not Str_isEmpty(s.refreshToken)
    profile = "none"
    if not Str_isEmpty(s.profileId) then profile = "kept"
    if signedIn and askProfile then profile = "ask"
    state = "none"
    if acct <> invalid then
        state = "signed_in"
        if not signedIn then state = "sign_in_again"
    end if
    Diag_log("[siku-accounts] switched account=" + state + " profile=" + profile + " accounts_on_server=" + Accounts_countOn(Str_orEmpty(srv.url)).ToStr())
    Session_save(s)
end sub

function Session_boolWord(b as boolean) as string
    if b then return "true"
    return "false"
end function

' Per-server answers kept on m.global for the session (Requests gate, Shuffle capability).
sub Session_forgetServerState()
    g = m.global
    if g = invalid then return
    if g.hasField("requests") then g.requests = { enabled: false, resolved: false }
    if g.hasField("shuffleCaps") then g.shuffleCaps = {}
end sub

' Signs out of the open account on this Roku: the account goes (its server stays), tokens and
' profile are cleared. A phone's borrowed (temporary) session has no saved account of its own.
sub Session_signOutLocal(s as object)
    Session_forgetPlaybackCaps()
    c = AA_copy(s)
    id = Str_orEmpty(s.accountId)
    if id <> "" and not Accounts_isTemporary(s) then
        ' First, so Session_save cannot stash it back.
        Accounts_remove(id)
        Diag_log("[siku-accounts] signed out of an account; accounts left on this server=" + Accounts_countOn(Str_orEmpty(s.serverUrl)).ToStr())
    end if
    c.accountId = ""
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

' The server refused the open account's refresh token (expired or revoked): not a sign-out. The
' account stays saved, needing to sign in again ("Sign in again" on Change Account), and its tokens
' and profile are cleared.
sub Session_expireLocal(s as object)
    Session_forgetPlaybackCaps()
    c = AA_copy(s)
    c.accessToken = ""
    c.refreshToken = ""
    c.expiresAt = 0
    c.profileId = ""
    c.profileToken = ""
    c.profileName = ""
    c.profileAvatar = ""
    if Str_orEmpty(c.accountId) <> "" then Diag_log("[siku-accounts] session expired; the account stays, needing to sign in again")
    Session_save(c)
end sub

' Forgets the server entirely (Change server).
sub Session_clearServer()
    Session_forgetPlaybackCaps()
    s = Session_empty()
    s.deviceId = m.global.session.deviceId
    Session_save(s)
end sub

' The playback installation (GET /api/v2/playback/capabilities, cached on m.global.playbackCaps by
' the players) belongs to one server and login; forget it so the next start probes again instead of
' sending another server's installation_id.
sub Session_forgetPlaybackCaps()
    if m.global.hasField("playbackCaps") then m.global.playbackCaps = {}
end sub

' Applies a token response {access_token, refresh_token, expires_in, user?}.
function Session_withTokens(s as object, tokens as object) as object
    c = AA_copy(s)
    c.accessToken = Str_orEmpty(tokens.access_token)
    if not Str_isEmpty(tokens.refresh_token) then c.refreshToken = tokens.refresh_token
    expiresIn = Int(Num_or(tokens.expires_in, 3600))
    if expiresIn <= 0 then expiresIn = 3600
    c.expiresAt = Time_nowSeconds() + expiresIn
    ' A response with a user is a new sign-in (refresh responses carry none):
    ' drop any profile selected under the previous login. Its account is found again by the
    ' server's user id (Accounts_resolveId), never assumed to be the open one.
    if tokens.user <> invalid then
        c.accountId = ""
        c.user = tokens.user
        c.profileId = ""
        c.profileToken = ""
        c.profileName = ""
        c.profileAvatar = ""
    end if
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

' Whether url is on origin (scheme://host[:port]): scheme and host compared case-insensitively,
' a default port (80 for http, 443 for https) the same as none. The account token is sent only to
' the user's own server origin (PlayerScreen, AudioPlayerScreen, subtitle sidecars).
function Url_sameOrigin(url as dynamic, origin as dynamic) as boolean
    a = Url_originKey(Str_orEmpty(url))
    return a <> "" and a = Url_originKey(Str_orEmpty(origin))
end function

' "scheme://host:port" in lower case with the default port filled in, "" for a relative URL.
function Url_originKey(u as string) as string
    o = LCase(Url_origin(u.Trim()))
    i = Instr(1, o, "://")
    if i = 0 then return ""
    scheme = Left(o, i - 1)
    hostPort = Mid(o, i + 3)
    q = Instr(1, hostPort, "?")
    if q > 0 then hostPort = Left(hostPort, q - 1)
    q = Instr(1, hostPort, "#")
    if q > 0 then hostPort = Left(hostPort, q - 1)
    at = Instr(1, hostPort, "@")
    if at > 0 then hostPort = Mid(hostPort, at + 1)
    if hostPort = "" then return ""
    ' The port follows the last ':' after any IPv6 literal's closing bracket.
    colon = 0
    bracket = Instr(1, hostPort, "]")
    for k = Len(hostPort) to bracket + 1 step -1
        if Mid(hostPort, k, 1) = ":" then
            colon = k
            exit for
        end if
    end for
    if colon = 0 then
        if scheme = "https" then hostPort = hostPort + ":443"
        if scheme = "http" then hostPort = hostPort + ":80"
    end if
    return scheme + "://" + hostPort
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
        hiddenSections: []         ' Home Sections editor: hidden row ids (per device, like Android TV)
        sectionOrder: []           ' Home Sections editor: row ids in display order
        resumeRewind: 7            ' Rewind on Resume, seconds (contract client_local, 0 = off)
        passoutThreshold: 3        ' Still Watching Prompt: auto-advances before Up Next waits (0 = off)
        appLanguage: ""            ' the last profile ui.app_language applied ("" = the Roku's language)
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
