' SPDX-License-Identifier: AGPL-3.0-or-later
' Phone sign-in of several accounts in one phone session (Silo Android #810, the Roku side of
' its contract; adapted from Silo-Server/silo-roku, AGPL-3.0 (source/storage/registry.bs
' sessionSignIns / roomForSignIn, source/auth/companion.bs companionCapable)). Pure decisions,
' host-tested in tests/test_pair_session.py; PhonePairing.brs acts on them.
'   - On the server screen Siku advertises TXT acct=1 (any number of pushServer in one session,
'     any servers, each sign-in its own account) and lim=<PairSession_limit()>.
'   - A push past lim, or one that would make the registry budget (Accounts_fit: 12 accounts,
'     9000 bytes, least recently used first) take the stored sign-in of an account this phone
'     session already signed in, answers limit_reached; the session keeps waiting.
'   - The session binding goes only to an https server whose device capability says
'     session_binding: true; a failed read or a missing key means no binding.
' Include with Accounts.brs, Session.brs and Utils.brs.

' The bytes budgeted for each account a phone session signs in and Siku stores while another one
' is open (Session_storedSignIn with both tokens and the user; a Silo sign-in is about 1 KB).
function PairSession_signInBytes() as integer
    return 1800
end function

' The most sign-ins one phone session keeps (TXT lim): each becomes the most recently used
' account, so it stays while the session's accounts fit Accounts_max(), their servers fit
' Session_maxServers() and all but the open one (its tokens live in "session") fit the accounts
' budget at PairSession_signInBytes() each. 6 today.
function PairSession_limit() as integer
    lim = Accounts_max()
    if Session_maxServers() < lim then lim = Session_maxServers()
    byBudget = Accounts_budget() \ PairSession_signInBytes() + 1
    if byBudget < lim then lim = byBudget
    return lim
end function

' Why a push is refused before anything is checked, or "": "auth_failed" while the session is
' ending (You're all set is up), "limit_reached" after the sign-in screen's one account or once
' `signedIn` accounts reached `limit`.
function PairSession_refusal(mode as string, signedIn as integer, limit as integer, ending as boolean) as string
    if ending then return "auth_failed"
    if signedIn <= 0 then return ""
    if mode = "login" or signedIn >= limit then return "limit_reached"
    return ""
end function

' The worst case of the next sign-in on `url`: a new account, open, with long user fields. Its
' tokens live in "session", outside the accounts budget, but are filled all the same.
function PairSession_incoming(url as string, name as string, identity as string) as object
    s = Session_empty()
    s.serverUrl = url
    s.serverOrigin = Url_origin(url)
    s.serverName = name
    s.serverId = identity
    s.accessToken = String(2048, "a")
    s.refreshToken = String(512, "r")
    s.expiresAt = 2000000000
    s.user = { "id": String(128, "u"), "username": String(128, "n") }
    s.accountId = String(36, "i")
    return s
end function

' Whether one more sign-in on `url` keeps the stored sign-in of every account in `ids` (the
' accounts this phone session signed in) and the server each one is on, given the accounts list,
' the saved servers and `prev` (the registry session now, the session's last sign-in open). The
' save runs as Session_save would run it (Accounts_next, Session_serversNext), quietly.
function PairSession_room(list as dynamic, servers as dynamic, prev as dynamic, ids as object, url as string, name as string, identity as string, now as integer) as boolean
    if ids.Count() = 0 then return true
    s = PairSession_incoming(url, name, identity)
    nxt = Accounts_next(list, prev, s, now, false, true)
    srvs = Session_serversNext(servers, prev, s)
    for i = 0 to ids.Count() - 1
        e = Accounts_find(nxt, Str_orEmpty(ids[i]))
        if not Accounts_hasSignIn(e) then return false
        if not Session_serversHas(srvs, Str_orEmpty(e.url)) then return false
    end for
    return true
end function

' The binding a device login at `base` carries: `binding` ({secret, binding}, the phone
' session's) when `base` is https and `capability` (GET /api/v2/auth/device/capability's answer,
' invalid when it failed) says session_binding: true; invalid otherwise. Over plain HTTP the
' secret would reach the on-path attacker the binding defends against.
function PairSession_bindingFor(base as string, capability as dynamic, binding as dynamic) as dynamic
    if LCase(Left(base, 8)) <> "https://" then return invalid
    if binding = invalid or Type(binding) <> "roAssociativeArray" then return invalid
    if Str_isEmpty(binding.secret) or Str_isEmpty(binding.binding) then return invalid
    if capability = invalid or Type(capability) <> "roAssociativeArray" then return invalid
    v = capability.session_binding
    if Type(v) <> "Boolean" and Type(v) <> "roBoolean" then return invalid
    if not v then return invalid
    return binding
end function

' Why no binding went with a device login ("" when one did), for the console.
function PairSession_noBindingReason(base as string, capability as dynamic, binding as dynamic) as string
    if PairSession_bindingFor(base, capability, binding) <> invalid then return ""
    if LCase(Left(base, 8)) <> "https://" then return "http"
    if binding = invalid or Type(binding) <> "roAssociativeArray" or Str_isEmpty(binding.secret) then return "no_secret"
    if capability = invalid or Type(capability) <> "roAssociativeArray" then return "capability_unread"
    return "no_session_binding"
end function

' `ids` with `id` added once, keeping the order accounts first signed in.
function PairSession_note(ids as object, id as string) as object
    out = []
    found = false
    for i = 0 to ids.Count() - 1
        out.Push(ids[i])
        if ids[i] = id then found = true
    end for
    if not found and id <> "" then out.Push(id)
    return out
end function

' "You're all set"'s detail: the last sign-in's server, or how many accounts signed in.
function PairSession_completedText(count as integer, server as string) as string
    if count > 1 then return count.ToStr() + " accounts are signed in. Next, choose which one to open."
    return "Signed in to " + server + ". Taking you to your profiles" + Chr(8230)
end function
