' Cursor-paged request lists (GET /api/v2/requests/mine, GET /api/v2/admin/requests).
' Follows page.next_cursor (limit 50) and hands the whole list to the component's
'   sub onRequestsListLoaded(tag as string, ok as boolean, items as object, resp as object)
' A failed page, a missing or repeated cursor, or the page bound fails the whole load instead of
' returning a partial list (docs/requests-api-v2.md). Needs Utils.brs and Api.brs.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub ReqApi_loadList(tag as string, path as string, query as dynamic, maxPages as integer)
    if m.reqLists = invalid then m.reqLists = {}
    if m.reqListSeq = invalid then m.reqListSeq = 0
    m.reqListSeq = m.reqListSeq + 1
    q = {}
    if query <> invalid then q = AA_copy(query)
    q.limit = 50
    m.reqLists[tag] = { path: path, query: q, items: [], seen: {}, pages: 0, maxPages: maxPages, seq: m.reqListSeq }
    ReqApi_fetchPage(tag, "")
end sub

sub ReqApi_fetchPage(tag as string, cursor as string)
    st = m.reqLists[tag]
    q = AA_copy(st.query)
    if cursor <> "" then q.cursor = cursor
    st.pages = st.pages + 1
    Api_get(st.path, q, "ReqApi_onPage", { tag: tag, seq: st.seq })
end sub

sub ReqApi_onPage(event as object)
    resp = Api_result(event)
    ctx = resp.context
    if ctx = invalid or m.reqLists = invalid then return
    st = m.reqLists[ctx.tag]
    if st = invalid or st.seq <> ctx.seq then return
    if not resp.ok or resp.data = invalid then
        m.reqLists.Delete(ctx.tag)
        onRequestsListLoaded(ctx.tag, false, [], resp)
        return
    end if
    st.items.Append(Arr_or(resp.data.items))
    pg = resp.data.page
    if pg = invalid or pg.has_more <> true then
        m.reqLists.Delete(ctx.tag)
        onRequestsListLoaded(ctx.tag, true, st.items, resp)
        return
    end if
    nextCursor = Str_orEmpty(pg.next_cursor)
    if nextCursor = "" or st.seen.DoesExist(nextCursor) or st.pages >= st.maxPages then
        m.reqLists.Delete(ctx.tag)
        onRequestsListLoaded(ctx.tag, false, [], { ok: false, status: 0, error: { title: "The server returned invalid request pagination." } })
        return
    end if
    st.seen[nextCursor] = true
    ReqApi_fetchPage(ctx.tag, nextCursor)
end sub
