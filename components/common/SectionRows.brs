' Home and library rows: the 20-card cap, the "Explore all" rule and the `item_limit` the section
' lists may carry (Silo Android #688: SectionRowLimits.kt, SectionRowItemLimit.kt).
'
' A row shows at most SectionRows_max() cards; the rest live on the row's full page (LibraryPage
' section "section", paged through GET /api/v2/catalog?source=section). Servers that list
' `section_item_limit_max` in GET /api/v2/home/capabilities take `item_limit` on
' GET /api/v2/home/sections and GET /api/v2/library/{id}/sections, so they send no more cards than
' a row shows. Older servers answer an unknown query parameter with 422 `unknown_parameter`, so the
' parameter goes only to the server that advertised it. A failed or slow capability read (3 s)
' counts as "not supported"; a server that still refuses the parameter is read again without it
' and treated as unsupported for the rest of the session.
'
' The capability is kept on m.global.sectionLimit as { serverUrl, limit } (limit 0: send nothing).
' The pure functions are host-tested (tests/test_section_rows.py). Needs Utils.brs and Api.brs.
' SPDX-License-Identifier: AGPL-3.0-or-later

' The most cards a Home or library row shows (SECTION_ROW_MAX_ITEMS).
function SectionRows_max() as integer
    return 20
end function

' The item_limit to send for an advertised `section_item_limit_max`: min(20, max), or 0 to send
' nothing (absent, not a number, or below 1). Numbers sent as strings are read too (pitfall 6).
function SectionRows_itemLimitParam(advertised as dynamic) as integer
    if advertised = invalid then return 0
    t = Type(advertised)
    if t = "roString" or t = "String" then
        s = advertised.Trim()
        if s = "" then return 0
        re = CreateObject("roRegex", "^[0-9]+$", "")
        if not re.IsMatch(s) then return 0
    else if t <> "Integer" and t <> "roInt" and t <> "roInteger" and t <> "LongInteger" and t <> "roLongInteger" and t <> "Float" and t <> "roFloat" and t <> "Double" and t <> "roDouble" then
        return 0
    end if
    n = Num_or(advertised, 0)
    if n < 1 then return 0
    if n >= SectionRows_max() then return SectionRows_max()
    return Int(n)
end function

' Whether a row ends with an "Explore all" card: every non-featured row with cards, not only rows
' whose total exceeds what they show (Home drops titles another row already shows, so a row can
' look complete while its full page holds more).
function SectionRows_offersExploreAll(section as dynamic, cardCount as integer) as boolean
    if section = invalid or Type(section) <> "roAssociativeArray" then return false
    if cardCount <= 0 then return false
    if Str_orEmpty(section.id) = "" then return false
    f = section.featured
    if (Type(f) = "Boolean" or Type(f) = "roBoolean") and f then return false
    return true
end function

' The first SectionRows_max() cards of a row.
function SectionRows_capped(items as object) as object
    n = SectionRows_max()
    if items.Count() <= n then return items
    out = []
    for i = 0 to n - 1
        out.Push(items[i])
    end for
    return out
end function

' True for v2's 422 `validation_failed` naming `query.item_limit` as an `unknown_parameter`: the
' server refused the parameter itself. Any other failure is an ordinary error.
function SectionRows_rejectsItemLimit(status as dynamic, data as dynamic) as boolean
    if Int(Num_or(status, 0)) <> 422 then return false
    if data = invalid or Type(data) <> "roAssociativeArray" then return false
    code = Str_orEmpty(data.code)
    if code = "" then
        t = Str_orEmpty(data.type)
        if t <> "" then
            parts = t.Split("/")
            code = parts[parts.Count() - 1]
        end if
    end if
    if code <> "validation_failed" then return false
    errs = data.errors
    if errs = invalid or Type(errs) <> "roArray" then return false
    for each e in errs
        if e <> invalid and Type(e) = "roAssociativeArray" then
            if Str_orEmpty(e.location) = "query.item_limit" and Str_orEmpty(e.code) = "unknown_parameter" then return true
        end if
    end for
    return false
end function

' ---------- The server's capability (m.global.sectionLimit) ----------

' True once the capability read answered (or failed) for the active server.
function SectionRows_capsSettled() as boolean
    if not m.global.hasField("sectionLimit") then return false
    c = m.global.sectionLimit
    if c = invalid or Type(c) <> "roAssociativeArray" then return false
    server = Str_orEmpty(m.global.session.serverUrl)
    return server <> "" and Str_orEmpty(c.serverUrl) = server
end function

' Reads GET /api/v2/home/capabilities once per server; `callback` (in the calling component) gets
' the response event and must call SectionRows_storeCaps(event). At most 3 seconds.
sub SectionRows_fetchCaps(callback as string)
    Api_call({ method: "GET", path: "/api/v2/home/capabilities", timeout: 3, context: { serverUrl: Str_orEmpty(m.global.session.serverUrl) } }, callback)
end sub

sub SectionRows_storeCaps(event as object)
    resp = Api_result(event)
    serverUrl = ""
    if resp.context <> invalid then serverUrl = Str_orEmpty(resp.context.serverUrl)
    ' A read of another server (a switch while it ran) is dropped; the next page asks again.
    if serverUrl = "" or serverUrl <> Str_orEmpty(m.global.session.serverUrl) then return
    limit = 0
    advertised = "none"
    if resp.ok and Type(resp.data) = "roAssociativeArray" then
        limit = SectionRows_itemLimitParam(resp.data.section_item_limit_max)
        if resp.data.section_item_limit_max <> invalid then advertised = Str_orEmpty(resp.data.section_item_limit_max)
    else
        advertised = "failed status=" + Int(Num_or(resp.status, 0)).ToStr()
    end if
    sending = "none"
    if limit > 0 then sending = limit.ToStr()
    print "[siku-home] section item limit max="; advertised; " sending="; sending
    SectionRows_setLimit(serverUrl, limit)
end sub

sub SectionRows_setLimit(serverUrl as string, limit as integer)
    if not m.global.hasField("sectionLimit") then m.global.addFields({ sectionLimit: {} })
    m.global.sectionLimit = { serverUrl: serverUrl, limit: limit }
end sub

' The item_limit for the active server's section lists, or 0 to send none.
function SectionRows_activeLimit() as integer
    if not SectionRows_capsSettled() then return 0
    return Int(Num_or(m.global.sectionLimit.limit, 0))
end function

' The server refused item_limit: send none to it for the rest of the session.
sub SectionRows_markUnsupported()
    SectionRows_setLimit(Str_orEmpty(m.global.session.serverUrl), 0)
end sub
