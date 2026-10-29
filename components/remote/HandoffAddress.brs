' Where a phone's handoff runs on this Roku (Silo Android #716, RemotePlaybackIdentityManager and
' RemotePlaybackCandidatePolicy; silo-apple's tvOS RemotePlaybackCandidatePolicy).
'
' A phone on a server's public address hands its profile to a Roku signed in over the LAN. With
' the deployment identity the phone sends (`serverIdentity`), the Roku tries, in order, its own
' saved addresses for that server, the phone's address, then the server's other addresses the
' phone offers (`serverEndpoints`), probes them all at once (GET /api/v2/system/identity) and
' judges the answers in that order: the first that reports the same identity wins. Without an
' identity (an older phone) the phone's address is used as before. Pure functions (no SceneGraph)
' so tests/test_handoff_address.py runs them in brs-cli; RemoteControl.brs does the requests.
' SPDX-License-Identifier: AGPL-3.0-or-later

' This Roku's saved addresses probed per offer.
function HandoffAddr_maxSaved() as integer
    return 6
end function

' Offered endpoints probed per offer (counting only those this Roku may probe).
function HandoffAddr_maxEndpoints() as integer
    return 6
end function

' Offered endpoints read at all, so a long list costs a bounded amount of work.
function HandoffAddr_maxEndpointsRead() as integer
    return 24
end function

' Seconds one identity probe may take.
function HandoffAddr_probeTimeout() as integer
    return 6
end function

' Seconds the whole choice may take: probes run at once, so stale addresses cost one probe
' timeout in total, inside an Android phone's 15 s wait for the challenge. When it runs out,
' every unanswered probe counts as unreachable.
function HandoffAddr_budgetSeconds() as integer
    return 8
end function

' What a handoff offer asks this Roku to probe: {offered, expected, candidates}. `own` is the
' Roku's own session (never a borrowed one), `remembered` Session_savedServers(). An offer without
' a deployment identity gets no candidates: its handoff runs at the phone's address unprobed.
function HandoffAddr_plan(offer as object, own as dynamic, remembered as dynamic) as object
    offered = Lan_trimUrl(Str_orEmpty(offer.serverURL))
    expected = Str_orEmpty(offer.serverIdentity).Trim()
    if expected = "" then return { offered: offered, expected: "", candidates: [] }
    entries = HandoffAddr_entries(own, remembered)
    activeUrl = ""
    if own <> invalid and Type(own) = "roAssociativeArray" then activeUrl = Str_orEmpty(own.serverUrl)
    saved = HandoffAddr_savedUrls(entries, activeUrl, expected)
    cands = HandoffAddr_candidates(saved, offered, HandoffAddr_endpoints(offer), HandoffAddr_approvedOrigins(entries))
    return { offered: offered, expected: expected, candidates: cands }
end function

' The form two addresses are compared in (scheme and host lower-case, default port and trailing
' slashes dropped).
function HandoffAddr_key(url as dynamic) as string
    return Lan_canonicalUrl(Str_orEmpty(url))
end function

function HandoffAddr_isHttpUrl(url as string) as boolean
    l = LCase(url)
    return (Left(l, 7) = "http://" and Len(l) > 7) or (Left(l, 8) = "https://" and Len(l) > 8)
end function

function HandoffAddr_isCleartext(url as string) as boolean
    return LCase(Left(url.Trim(), 7)) = "http://"
end function

' "https://media.example.com:8443/silo" -> "https://media.example.com:8443" (canonical).
function HandoffAddr_origin(url as dynamic) as string
    k = HandoffAddr_key(url)
    i = Instr(1, k, "://")
    if i = 0 then return k
    slash = Instr(i + 3, k, "/")
    if slash = 0 then return k
    return Left(k, slash - 1)
end function

' This Roku's saved servers as [{url, id}]: the active server (the Roku's own session, never a
' borrowed one) first, then the remembered list (Session_rememberServer).
function HandoffAddr_entries(own as dynamic, remembered as dynamic) as object
    out = []
    if own <> invalid and Type(own) = "roAssociativeArray" and not Str_isEmpty(own.serverUrl) then
        out.Push({ url: Str_orEmpty(own.serverUrl), id: Str_orEmpty(own.serverId) })
    end if
    list = Arr_or(remembered)
    for i = 0 to list.Count() - 1
        e = list[i]
        if Type(e) = "roAssociativeArray" and not Str_isEmpty(e.url) then out.Push({ url: Str_orEmpty(e.url), id: Str_orEmpty(e.id) })
    end for
    return out
end function

' The saved addresses that may serve `identity`, at most HandoffAddr_maxSaved(): those recorded
' under it, then those with no recorded identity, the active server first within each. A server
' recorded as another deployment is never tried. Every one is probed and an unverified one that
' answers for another deployment is skipped, so trying them is safe.
function HandoffAddr_savedUrls(entries as object, activeUrl as dynamic, identity as string) as object
    activeKey = HandoffAddr_key(activeUrl)
    recordedActive = []
    recorded = []
    unverifiedActive = []
    unverified = []
    seen = {}
    list = Arr_or(entries)
    for i = 0 to list.Count() - 1
        e = list[i]
        if Type(e) = "roAssociativeArray" then
            url = Lan_trimUrl(Str_orEmpty(e.url))
            k = HandoffAddr_key(url)
            if HandoffAddr_isHttpUrl(url) and not seen.DoesExist(k) then
                seen[k] = true
                rec = Str_orEmpty(e.id).Trim()
                active = activeKey <> "" and k = activeKey
                if rec = identity and identity <> "" then
                    if active then recordedActive.Push(url) else recorded.Push(url)
                else if rec = "" then
                    if active then unverifiedActive.Push(url) else unverified.Push(url)
                end if
            end if
        end if
    end for
    out = []
    for each group in [recordedActive, recorded, unverifiedActive, unverified]
        for each url in group
            if out.Count() < HandoffAddr_maxSaved() then out.Push(url)
        end for
    end for
    return out
end function

' Plain-HTTP origins this Roku approved earlier: every http:// server it saved. Siku saves a
' plain-HTTP server only after ServerConnect's "Connect without encryption?" (or a phone sign-in
' at that address), so a saved one is the approval; no other plain-HTTP address gets credentials.
function HandoffAddr_approvedOrigins(entries as object) as object
    out = {}
    list = Arr_or(entries)
    for i = 0 to list.Count() - 1
        e = list[i]
        if Type(e) = "roAssociativeArray" then
            url = Str_orEmpty(e.url)
            if HandoffAddr_isCleartext(url) then out[HandoffAddr_origin(url)] = true
        end if
    end for
    return out
end function

' The other addresses the phone offers (SiloCastHandoffOffer.serverEndpoints: [{url, kind,
' provider?, displayName?}], public first, then providers), as URLs. At most
' HandoffAddr_maxEndpointsRead() entries are read; malformed entries are skipped.
function HandoffAddr_endpoints(offer as dynamic) as object
    out = []
    if offer = invalid or Type(offer) <> "roAssociativeArray" then return out
    list = Arr_or(offer.serverEndpoints)
    n = list.Count()
    if n > HandoffAddr_maxEndpointsRead() then n = HandoffAddr_maxEndpointsRead()
    for i = 0 to n - 1
        e = list[i]
        if Type(e) = "roAssociativeArray" then
            t = Type(e.url)
            if t = "String" or t = "roString" then out.Push(e.url) else out.Push("")
        else
            out.Push("")
        end if
    end for
    return out
end function

' The addresses to probe, in order, de-duplicated, as [{url, kind}] with kind "own" (saved by this
' Roku), "phone" (the phone's address) or "endpoint". The phone's address keeps its old treatment;
' any other plain-HTTP address needs this Roku's earlier approval (`approved`, from
' HandoffAddr_approvedOrigins). Of the endpoints, at most HandoffAddr_maxEndpointsRead() are read
' and the first HandoffAddr_maxEndpoints() allowed new ones kept.
function HandoffAddr_candidates(saved as object, offered as string, endpoints as object, approved as object) as object
    out = []
    seen = {}
    offeredKey = HandoffAddr_key(offered)
    first = []
    for each url in Arr_or(saved)
        first.Push({ url: Str_orEmpty(url), kind: "own" })
    end for
    first.Push({ url: offered, kind: "phone" })
    for each c in first
        url = Lan_trimUrl(c.url)
        k = HandoffAddr_key(url)
        if HandoffAddr_isHttpUrl(url) and not seen.DoesExist(k) then
            seen[k] = true
            if HandoffAddr_mayProbe(url, offeredKey, approved) then out.Push({ url: url, kind: c.kind })
        end if
    end for
    kept = 0
    list = Arr_or(endpoints)
    n = list.Count()
    if n > HandoffAddr_maxEndpointsRead() then n = HandoffAddr_maxEndpointsRead()
    for i = 0 to n - 1
        if kept >= HandoffAddr_maxEndpoints() then exit for
        url = Lan_trimUrl(Str_orEmpty(list[i]))
        k = HandoffAddr_key(url)
        if HandoffAddr_isHttpUrl(url) and not seen.DoesExist(k) then
            seen[k] = true
            if HandoffAddr_mayProbe(url, offeredKey, approved) then
                out.Push({ url: url, kind: "endpoint" })
                kept = kept + 1
            end if
        end if
    end for
    return out
end function

function HandoffAddr_mayProbe(url as string, offeredKey as string, approved as dynamic) as boolean
    if HandoffAddr_key(url) = offeredKey then return true
    if not HandoffAddr_isCleartext(url) then return true
    if approved = invalid or Type(approved) <> "roAssociativeArray" then return false
    return approved.DoesExist(HandoffAddr_origin(url))
end function

' One identity probe's answer ({ok, status, data} as Api_result gives it) as
' {state: "identity", id} | {state: "unsupported"} (it answers but cannot say who it is) |
' {state: "unreachable"} (no answer, or a gateway error with nothing behind it).
function HandoffAddr_classify(resp as dynamic) as object
    if resp = invalid or Type(resp) <> "roAssociativeArray" then return { state: "unreachable" }
    status = Int(Num_or(resp.status, 0))
    if status = 0 or status >= 500 then return { state: "unreachable" }
    d = resp.data
    if Lan_isTrue(resp.ok) and d <> invalid and Type(d) = "roAssociativeArray" then
        id = Str_orEmpty(d.server_id).Trim()
        if Lan_isServerId(id) then return { state: "identity", id: id }
    end if
    return { state: "unsupported" }
end function

' Judges the answers in candidate order. answers[i] is HandoffAddr_classify's result or invalid
' while that probe is out; `final` counts those as unreachable (the budget ran out). Returns
' {done, url, kind, index, failure: "" | "mismatch" | "unreachable"}; not done while an earlier
' candidate could still win.
function HandoffAddr_judge(candidates as object, answers as object, offered as string, expected as string, final as boolean) as object
    offeredKey = HandoffAddr_key(offered)
    list = Arr_or(candidates)
    got = Arr_or(answers)
    for i = 0 to list.Count() - 1
        c = list[i]
        a = invalid
        if i < got.Count() then a = got[i]
        if a = invalid or Type(a) <> "roAssociativeArray" then
            if not final then return { done: false, url: "", kind: "", index: -1, failure: "" }
            a = { state: "unreachable" }
        end if
        st = Str_orEmpty(a.state)
        atPhone = HandoffAddr_key(c.url) = offeredKey
        if st = "identity" then
            if Str_orEmpty(a.id) = expected then return { done: true, url: c.url, kind: c.kind, index: i, failure: "" }
            ' The phone vouches for its addresses, so another server answering at one ends the
            ' handoff (even when this Roku saved that address too). A saved address of this
            ' Roku's alone may since point elsewhere; it is skipped.
            if atPhone or c.kind <> "own" then return { done: true, url: "", kind: c.kind, index: i, failure: "mismatch" }
        else if st = "unsupported" then
            ' Reachable but cannot prove who it is: only the phone's own address is trusted that way.
            if atPhone then return { done: true, url: c.url, kind: c.kind, index: i, failure: "" }
        end if
    end for
    return { done: true, url: "", kind: "", index: -1, failure: "unreachable" }
end function
