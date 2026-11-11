' SPDX-License-Identifier: AGPL-3.0-or-later
' Several accounts per saved server (Silo Android #795, Android TV's Change Account; Silo's own Roku
' app did it first). Adapted from Silo-Server/silo-roku, AGPL-3.0 (docs/spec.md section 7.5,
' source/storage/registry.bs): accounts keyed by a local account id made on this Roku, an offline
' migration that deletes the old slots only after the new ones read back, and a registry budget.
'
' Registry layout 2 (section "siku"):
'   "layout"   2 once the migration below has finished (absent or 1: one sign-in per server).
'   "session"  the active session, as before, plus `accountId` (the local id of its account, "" with
'              no account open). The active account's tokens live only here, so a token refresh
'              writes one key, as before.
'   "servers"  saved servers [{url, name, id}], most recently used first (Session.brs).
'   "accounts" one entry per saved account, every key lower case (pitfall 15):
'              {id, url, userid, username, profiles, maxprofiles?, added, used, expired, session?}
'              `session` is a stored sign-in (Session_storedSignIn) for an account that is not the
'              active one; `expired` marks one the server refused ("Sign in again"): it stays saved
'              with no tokens until someone signs in again or signs out of it. `profiles` is the
'              profile count the picker last read (-1 unknown); `maxprofiles` the limit that list
'              sent as `max_profiles` (-1 or absent: not said; Silo Android #881).
' The server's user id only finds a saved account again: a sign-in whose user id matches a saved
' account on that server refreshes it; an unknown identity (no user id either side) is a new
' account, as Android's commitAccountReplacement decides.
' Include with Session.brs and Utils.brs.

function Accounts_max() as integer
    return 12
end function

' Bytes of JSON the "accounts" key may take (each stored sign-in is roughly 0.4-1.5 KB of tokens).
' Layout 1 kept up to 8000 bytes of stored sign-ins in "servers"; the extra 1000 covers the
' accounts' own fields, so a migrated registry fits without dropping a sign-in. With "session",
' "servers" and the preferences it stays well inside a channel's 16 KB registry.
function Accounts_budget() as integer
    return 9000
end function

function Accounts_list() as object
    return Accounts_clean(Registry_read("accounts", []))
end function

' Only well-formed entries (an id and a server address).
function Accounts_clean(list as dynamic) as object
    out = []
    items = Arr_or(list)
    for i = 0 to items.Count() - 1
        e = items[i]
        if e <> invalid and Type(e) = "roAssociativeArray" and not Str_isEmpty(e.id) and not Str_isEmpty(e.url) then out.Push(e)
    end for
    return out
end function

function Accounts_find(list as object, id as string) as dynamic
    if id = "" then return invalid
    for i = 0 to list.Count() - 1
        if Str_orEmpty(list[i].id) = id then return list[i]
    end for
    return invalid
end function

' True when an entry holds a stored sign-in to switch to without signing in.
function Accounts_hasSignIn(e as dynamic) as boolean
    if e = invalid or Type(e) <> "roAssociativeArray" then return false
    st = e.session
    if st = invalid or Type(st) <> "roAssociativeArray" then return false
    return not Str_isEmpty(st.accessToken) or not Str_isEmpty(st.refreshToken)
end function

function Accounts_isExpired(e as dynamic) as boolean
    if e = invalid or Type(e) <> "roAssociativeArray" then return false
    v = e.expired
    if Type(v) = "Boolean" or Type(v) = "roBoolean" then return v
    return false
end function

function Accounts_signedIn(s as dynamic) as boolean
    if s = invalid or Type(s) <> "roAssociativeArray" then return false
    return not Str_isEmpty(s.accessToken) or not Str_isEmpty(s.refreshToken)
end function

function Accounts_userId(s as dynamic) as string
    if s = invalid or Type(s) <> "roAssociativeArray" then return ""
    u = s.user
    if u = invalid or Type(u) <> "roAssociativeArray" then return ""
    return Str_orEmpty(u.id).Trim()
end function

function Accounts_username(s as dynamic) as string
    if s = invalid or Type(s) <> "roAssociativeArray" then return ""
    u = s.user
    if u = invalid or Type(u) <> "roAssociativeArray" then return ""
    return Str_orEmpty(u.username).Trim()
end function

function Accounts_isTemporary(s as dynamic) as boolean
    if s = invalid or Type(s) <> "roAssociativeArray" then return false
    t = s.temporary
    if Type(t) = "Boolean" or Type(t) = "roBoolean" then return t
    return false
end function

' ---------- Which account a session belongs to (pure) ----------

' The saved account a session being saved belongs to, or "" for a new one. A session that keeps its
' account id (a refresh, a profile pick) stays in it while that account is on the same server. A
' new sign-in (Session_withTokens clears the id) finds the saved account on that server whose server
' user id matches; an unknown user id never adopts one.
function Accounts_resolveId(list as object, s as object) as string
    url = Str_orEmpty(s.serverUrl)
    if url = "" then return ""
    id = Str_orEmpty(s.accountId)
    if id <> "" then
        e = Accounts_find(list, id)
        if e <> invalid and Str_orEmpty(e.url) = url then return id
        if not Accounts_signedIn(s) then return ""
    end if
    if not Accounts_signedIn(s) then return ""
    uid = Accounts_userId(s)
    if uid = "" then return ""
    for i = 0 to list.Count() - 1
        e = list[i]
        if Str_orEmpty(e.url) = url and Str_orEmpty(e.userid) = uid then return Str_orEmpty(e.id)
    end for
    return ""
end function

' The list after saving `s` over `prev` (the registry session before it), at `now`. Pure
' (tests/test_accounts.py). `prev`'s account, when another one is now active, keeps its sign-in in
' its entry (only an entry still in the list: a signed-out account never comes back). `s`'s
' account is created or updated; keepStash leaves its stored copy in place (the first of the two
' writes of a switch, so a stop between them never loses a sign-in). quiet: a what-if (phone
' sign-in's room check, PairSession.brs) logs nothing.
function Accounts_next(list as dynamic, prev as dynamic, s as object, now as integer, keepStash as boolean, quiet = false as boolean) as object
    out = []
    items = Accounts_clean(list)
    for i = 0 to items.Count() - 1
        out.Push(AA_copy(items[i]))
    end for
    id = Str_orEmpty(s.accountId)
    if prev <> invalid and Type(prev) = "roAssociativeArray" and not Accounts_isTemporary(prev) then
        prevId = Str_orEmpty(prev.accountId)
        if prevId <> "" and prevId <> id then
            pe = Accounts_find(out, prevId)
            if pe <> invalid and Str_orEmpty(pe.url) = Str_orEmpty(prev.serverUrl) then
                st = Session_storedSignIn(prev)
                if st <> invalid then
                    pe.session = st
                    pe.expired = false
                else
                    pe.Delete("session")
                end if
            end if
        end if
    end if
    if id <> "" then
        e = Accounts_find(out, id)
        signedIn = Accounts_signedIn(s)
        if e = invalid and signedIn then
            e = { "id": id, "url": Str_orEmpty(s.serverUrl), "userid": "", "username": "", "profiles": -1, "added": now, "used": now, "expired": false }
            out.Push(e)
        end if
        if e <> invalid then
            uid = Accounts_userId(s)
            if uid <> "" then e.userid = uid
            nm = Accounts_username(s)
            if nm <> "" then e.username = nm
            e.used = now
            e.expired = not signedIn
            if not keepStash or not signedIn then e.Delete("session")
        end if
    end if
    return Accounts_fit(out, id, quiet)
end function

' Keeps at most Accounts_max() entries and Accounts_budget() bytes of JSON. The active account
' (`keepId`) always stays; past the budget the least recently used accounts lose their stored
' sign-in first (they stay, needing to sign in again), then go.
function Accounts_fit(list as object, keepId as string, quiet = false as boolean) as object
    while list.Count() > Accounts_max()
        i = Accounts_oldest(list, keepId, false)
        if i < 0 then exit while
        list.Delete(i)
    end while
    while Len(FormatJson(list)) > Accounts_budget()
        i = Accounts_oldest(list, keepId, true)
        if i >= 0 then
            list[i].Delete("session")
            list[i].expired = true
            if not quiet then Diag_log("[siku-accounts] registry budget: an account not used lately needs to sign in again")
        else
            i = Accounts_oldest(list, keepId, false)
            if i < 0 then exit while
            list.Delete(i)
            if not quiet then Diag_log("[siku-accounts] registry budget: forgot an account not used lately")
        end if
    end while
    return list
end function

' Index of the least recently used entry other than keepId (withSignIn: only those that hold a
' stored sign-in), or -1.
function Accounts_oldest(list as object, keepId as string, withSignIn as boolean) as integer
    best = -1
    bestUsed = 0
    for i = 0 to list.Count() - 1
        e = list[i]
        if Str_orEmpty(e.id) <> keepId and (not withSignIn or e.session <> invalid) then
            used = Accounts_int(e.used)
            if best < 0 or used < bestUsed then
                best = i
                bestUsed = used
            end if
        end if
    end for
    return best
end function

' Integer seconds from a stored number (never Num_or: single precision rounds epoch seconds).
function Accounts_int(v as dynamic) as integer
    t = Type(v)
    if t = "Integer" or t = "roInt" or t = "roInteger" then return v
    if t = "LongInteger" or t = "roLongInteger" or t = "Double" or t = "roDouble" or t = "Float" or t = "roFloat" then return Int(v)
    if t = "String" or t = "roString" then return Int(Val(v))
    return 0
end function

function Accounts_without(list as dynamic, id as string) as object
    out = []
    items = Accounts_clean(list)
    for i = 0 to items.Count() - 1
        if Str_orEmpty(items[i].id) <> id then out.Push(items[i])
    end for
    return out
end function

function Accounts_withoutServer(list as dynamic, url as string) as object
    out = []
    items = Accounts_clean(list)
    for i = 0 to items.Count() - 1
        if Str_orEmpty(items[i].url) <> url then out.Push(items[i])
    end for
    return out
end function

' A server's accounts in the order they were added (Android's buildAccountGroups).
function Accounts_onServer(list as object, url as string) as object
    out = []
    for i = 0 to list.Count() - 1
        if Str_orEmpty(list[i].url) = url then out.Push(list[i])
    end for
    ' Insertion sort by `added` (a handful of entries).
    for i = 1 to out.Count() - 1
        cur = out[i]
        j = i - 1
        while j >= 0 and Accounts_int(out[j].added) > Accounts_int(cur.added)
            out[j + 1] = out[j]
            j = j - 1
        end while
        out[j + 1] = cur
    end for
    return out
end function

' The account a saved server opens with: its most recently used one that holds a sign-in, else its
' most recently used one (expired: "Sign in again"), else invalid.
function Accounts_latestOn(list as object, url as string, exceptId as string) as dynamic
    best = invalid
    for pass = 0 to 1
        for i = 0 to list.Count() - 1
            e = list[i]
            if Str_orEmpty(e.url) = url and Str_orEmpty(e.id) <> exceptId and (pass = 1 or Accounts_hasSignIn(e)) then
                if best = invalid or Accounts_int(e.used) > Accounts_int(best.used) then best = e
            end if
        end for
        if best <> invalid then return best
    end for
    return invalid
end function

' Whether another account than the open one holds a sign-in (with no account open, Change Account
' is then the start screen instead of sign-in, as Android TV's noAccountOpenButAnotherSignedIn).
function Accounts_anotherSignedIn(list as object, s as object) as boolean
    id = Str_orEmpty(s.accountId)
    for i = 0 to list.Count() - 1
        if Str_orEmpty(list[i].id) <> id and Accounts_hasSignIn(list[i]) then return true
    end for
    return false
end function

' Change Account's servers (Android TV's buildAccountGroups): the active server first, then the
' saved-servers order (most recently used first); each with its accounts in the order added and
' which one is open. Servers with no address are skipped.
function Accounts_groups(servers as dynamic, list as object, activeUrl as string, activeId as string) as object
    ordered = []
    items = Arr_or(servers)
    for i = 0 to items.Count() - 1
        e = items[i]
        if e <> invalid and Type(e) = "roAssociativeArray" and Str_orEmpty(e.url) = activeUrl and activeUrl <> "" then ordered.Push(e)
    end for
    for i = 0 to items.Count() - 1
        e = items[i]
        if e <> invalid and Type(e) = "roAssociativeArray" and not Str_isEmpty(e.url) and Str_orEmpty(e.url) <> activeUrl then ordered.Push(e)
    end for
    out = []
    for i = 0 to ordered.Count() - 1
        srv = ordered[i]
        cards = []
        accts = Accounts_onServer(list, Str_orEmpty(srv.url))
        for j = 0 to accts.Count() - 1
            a = accts[j]
            cards.Push({ "account": a, "current": Str_orEmpty(a.id) = activeId and activeId <> "" })
        end for
        out.Push({ "server": srv, "accounts": cards })
    end for
    return out
end function

' "1 profile", "3 profiles", "" (not read yet).
function Accounts_profileLine(n as dynamic) as string
    c = Accounts_int(n)
    if n = invalid or c < 0 then return ""
    return TxP("1 profile", "{0} profiles", c)
end function

' The badge an account card shows: "SIGN IN AGAIN", "CURRENT" or "".
function Accounts_badge(e as object, current as boolean) as string
    if Accounts_isExpired(e) then return Tx("SIGN IN AGAIN")
    if current then return Tx("CURRENT")
    return ""
end function

' ---------- Migration from layout 1 (pure part) ----------

' Layout 1 -> 2 (silo-roku's migrateLayout1): the active session and every saved server's stored
' sign-in become accounts with the given new ids, keeping tokens, user and profile; the servers
' lose their stored sign-ins. Pure (tests/test_accounts.py); `ids` holds at least one id per server
' plus one. Returns {accounts, servers, session, count}.
function Accounts_migrateLayout(servers as dynamic, session as dynamic, ids as object, now as integer) as object
    accounts = []
    n = 0
    s = invalid
    activeUrl = ""
    if session <> invalid and Type(session) = "roAssociativeArray" then
        s = AA_copy(session)
        activeUrl = Str_orEmpty(s.serverUrl)
        s.accountId = ""
        if activeUrl <> "" and Accounts_signedIn(s) and n < ids.Count() then
            id = Str_orEmpty(ids[n])
            n = n + 1
            accounts.Push({ "id": id, "url": activeUrl, "userid": Accounts_userId(s), "username": Accounts_username(s), "profiles": -1, "added": now, "used": now, "expired": false })
            s.accountId = id
        end if
    end if
    stripped = []
    items = Arr_or(servers)
    for i = 0 to items.Count() - 1
        e = items[i]
        if e <> invalid and Type(e) = "roAssociativeArray" and not Str_isEmpty(e.url) then
            url = Str_orEmpty(e.url)
            stripped.Push({ "url": url, "name": Str_orEmpty(e.name), "id": Str_orEmpty(e.id) })
            if url <> activeUrl and Session_entrySignedIn(e) and n < ids.Count() then
                id = Str_orEmpty(ids[n])
                n = n + 1
                st = AA_copy(e.session)
                ' Older entries are less recently used: keep the list's order in `used`.
                used = now - 1 - i
                accounts.Push({ "id": id, "url": url, "userid": Accounts_userId(st), "username": Accounts_username(st), "profiles": -1, "added": used, "used": used, "expired": false, "session": st })
            end if
        end if
    end for
    return { "accounts": accounts, "servers": stripped, "session": s, "count": accounts.Count() }
end function

' ---------- Registry ----------

function Accounts_layout() as integer
    return Accounts_int(Registry_read("layout", 1))
end function

' Moves a layout-1 registry to layout 2 at launch, offline (MainScene.init, before anything reads
' the session). The new keys are written and read back before the old slots (the saved servers'
' stored sign-ins) are deleted; until "layout" says 2, the next launch migrates again from the
' untouched layout-1 data. Returns the console line to log ("" when there was nothing to do).
function Accounts_migrate() as string
    if Accounts_layout() >= 2 then return ""
    servers = Arr_or(Registry_read("servers", []))
    session = Registry_read("session")
    if session = invalid and servers.Count() = 0 then
        Registry_write("layout", 2)
        return ""
    end if
    di = CreateObject("roDeviceInfo")
    ids = []
    for i = 0 to servers.Count()
        ids.Push(di.GetRandomUUID())
    end for
    r = Accounts_migrateLayout(servers, session, ids, Time_nowSeconds())
    Registry_write("accounts", r.accounts)
    back = Registry_read("accounts")
    if back = invalid or FormatJson(back) <> FormatJson(r.accounts) then
        return "[siku-accounts] migration failed: the accounts did not read back; layout 1 kept"
    end if
    if r.session <> invalid then
        Registry_write("session", r.session)
        sb = Registry_read("session")
        if sb = invalid or Type(sb) <> "roAssociativeArray" or Str_orEmpty(sb.accountId) <> Str_orEmpty(r.session.accountId) or Str_orEmpty(sb.accessToken) <> Str_orEmpty(r.session.accessToken) then
            return "[siku-accounts] migration failed: the session did not read back; layout 1 kept"
        end if
    end if
    ' Only now: the old slots go.
    Registry_write("servers", r.servers)
    Registry_write("layout", 2)
    active = "false"
    if r.session <> invalid and Str_orEmpty(r.session.accountId) <> "" then active = "true"
    return "[siku-accounts] migration layout=1->2 accounts=" + r.count.ToStr() + " active=" + active + " servers=" + r.servers.Count().ToStr()
end function

' Session_save's bookkeeping for a non-temporary `s` over `prev`: gives `s` its account id (a new
' one for a new account) and returns the session to store.
function Accounts_assign(s as object) as object
    c = AA_copy(s)
    list = Accounts_list()
    id = Accounts_resolveId(list, c)
    if id = "" and Accounts_signedIn(c) and not Str_isEmpty(c.serverUrl) then
        id = CreateObject("roDeviceInfo").GetRandomUUID()
        Diag_log("[siku-accounts] added an account on this server (accounts=" + (Accounts_onServer(list, Str_orEmpty(c.serverUrl)).Count() + 1).ToStr() + ")")
    end if
    c.accountId = id
    return c
end function

' Writes the accounts for a save of `s` over `prev` (only when it changed: registry writes wear
' flash). firstHalf: the write before "session" changes (keeps `s`'s stored copy).
sub Accounts_store(prev as dynamic, s as object, firstHalf as boolean)
    old = Accounts_list()
    nxt = Accounts_next(old, prev, s, Time_nowSeconds(), firstHalf)
    if FormatJson(nxt) = FormatJson(old) then return
    Registry_write("accounts", nxt)
end sub

' Records how many profiles an account has (Change Account's cards) and its profile limit, the
' profile list's `max_profiles` (-1: the server did not say; Silo Android #881). Both feed the
' profile menu's row (Accounts_profileMenuRow). Writes only when something changed.
sub Accounts_setProfiles(id as string, count as integer, maxProfiles = -1 as integer)
    if id = "" then return
    list = Accounts_list()
    e = Accounts_find(list, id)
    if e = invalid then return
    if Accounts_int(e.profiles) = count and e.maxprofiles <> invalid and Accounts_int(e.maxprofiles) = maxProfiles then return
    e.profiles = count
    e.maxprofiles = maxProfiles
    Registry_write("accounts", list)
end sub

' ---------- The profile menu's profile row (Silo Android #881, pure) ----------

' The account's profile limit from a profile list answer: its `max_profiles`, or -1 when the
' server did not send one (an older server, a handoff session) or sent something unreadable.
function Accounts_maxProfilesOf(data as dynamic) as integer
    if data = invalid or Type(data) <> "roAssociativeArray" then return -1
    v = data["max_profiles"]
    if v = invalid then return -1
    t = Type(v)
    if t = "String" or t = "roString" then
        ' Digits only: Num_or reads "lots" as 0, which would hide the profile row.
        txt = v.Trim()
        if txt = "" then return -1
        for i = 1 to Len(txt)
            c = Asc(Mid(txt, i, 1))
            if c < 48 or c > 57 then return -1
        end for
        return Int(Val(txt))
    end if
    n = Num_or(v, -1)
    if n < 0 then return -1
    return Int(n)
end function

' Which profile row the menu shows (Android's profileMenuRow, ProfileMenuRow.kt): "switch_profile"
' while the account has several profiles or none were read yet (count -1 / invalid); "add_profile"
' with one profile and room for another, or an unknown limit (the server's create stays the
' check); "none" with one profile and a limit of one, and for a phone's borrowed (handoff) profile,
' which can neither switch nor add.
function Accounts_profileMenuRow(profileCount as dynamic, maxProfiles as dynamic, handoff as boolean) as string
    if handoff then return "none"
    if profileCount = invalid or Accounts_int(profileCount) <> 1 then return "switch_profile"
    if maxProfiles = invalid then return "add_profile"
    mx = Accounts_int(maxProfiles)
    if mx < 0 or mx > 1 then return "add_profile"
    return "none"
end function

' The household's primary profile, the one the server lets create profiles: the one marked
' is_primary, else an only profile (silo-roku householdPrimary); invalid without one.
function Accounts_householdPrimary(profiles as dynamic) as dynamic
    items = Arr_or(profiles)
    for i = 0 to items.Count() - 1
        p = items[i]
        if p <> invalid and Type(p) = "roAssociativeArray" then
            v = p.is_primary
            if (Type(v) = "Boolean" or Type(v) = "roBoolean") and v then return p
        end if
    end for
    if items.Count() = 1 and items[0] <> invalid and Type(items[0]) = "roAssociativeArray" then return items[0]
    return invalid
end function

' ---------- New Profile (the menu's Add Profile, NewProfileScreen; pure) ----------

' What stops the form being sent: "" when nothing does, "name" (empty after trimming) or "pin"
' (neither empty nor exactly four digits).
function Accounts_newProfileProblem(name as string, pin as string) as string
    if name.Trim() = "" then return "name"
    if pin = "" then return ""
    if Len(pin) <> 4 then return "pin"
    for i = 1 to 4
        c = Asc(Mid(pin, i, 1))
        if c < 48 or c > 57 then return "pin"
    end for
    return ""
end function

' The POST /api/v2/profiles body (silo-roku's createProfile.body without the library allowlist):
' the trimmed name, the PIN when there is one, and for a child profile is_child with the PG
' ceiling Android TV and tvOS fill in. Members not set are left out (the server rejects null).
function Accounts_newProfileBody(name as string, pin as string, child as boolean) as object
    out = { "name": name.Trim() }
    if pin <> "" then out["pin"] = pin
    if child then
        out["is_child"] = true
        out["max_content_rating"] = "PG"
    end if
    return out
end function

' What a create answer means (silo-roku's createProfile.outcome; POST /profiles is never retried):
' "created" (2xx), "unconfirmed" (no answer: it may exist, the picker shows), "verify" (403
' profile_verification_required: the primary profile's PIN is needed again), "refused" (403, 409
' or 422 with the server's reason) or "failed".
function Accounts_createOutcome(status as integer, code as string) as string
    if status >= 200 and status < 300 then return "created"
    if status = 0 then return "unconfirmed"
    if status = 403 and code = "profile_verification_required" then return "verify"
    if status = 403 or status = 409 or status = 422 then return "refused"
    return "failed"
end function

sub Accounts_remove(id as string)
    if id = "" then return
    Registry_write("accounts", Accounts_without(Accounts_list(), id))
end sub

sub Accounts_removeServer(url as string)
    if url = "" then return
    old = Accounts_list()
    nxt = Accounts_withoutServer(old, url)
    if nxt.Count() <> old.Count() then Registry_write("accounts", nxt)
end sub

' How many saved accounts a server has.
function Accounts_countOn(url as string) as integer
    return Accounts_onServer(Accounts_list(), url).Count()
end function

' A stored access token that a new sign-in on `s`'s server replaces (the same server user signing
' in again), so the caller can end that session on the server (best effort, as Android ends the
' session it replaces). "" when nothing is replaced. Pure given the list and the active session.
function Accounts_replacedToken(list as object, active as dynamic, s as object) as string
    uid = Accounts_userId(s)
    url = Str_orEmpty(s.serverUrl)
    if uid = "" or url = "" then return ""
    if active <> invalid and Type(active) = "roAssociativeArray" and not Accounts_isTemporary(active) then
        if Str_orEmpty(active.serverUrl) = url and Accounts_userId(active) = uid and Str_orEmpty(active.accessToken) <> Str_orEmpty(s.accessToken) then return Str_orEmpty(active.accessToken)
    end if
    for i = 0 to list.Count() - 1
        e = list[i]
        if Str_orEmpty(e.url) = url and Str_orEmpty(e.userid) = uid and Accounts_hasSignIn(e) then
            if Str_orEmpty(e.session.accessToken) <> Str_orEmpty(s.accessToken) then return Str_orEmpty(e.session.accessToken)
        end if
    end for
    return ""
end function
