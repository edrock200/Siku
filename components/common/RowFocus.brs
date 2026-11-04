' Which card keeps focus when a row's cards are replaced (a Home refresh), Silo Android #803.
' Pure; tested by tests/test_row_focus.py.
' SPDX-License-Identifier: AGPL-3.0-or-later

' key: { contentId, seriesId, item } of the focused card before the refresh. cards: the row's new
' cards as [{ contentId, seriesId }]. progress: the row is Continue Watching / Next Up, whose
' episode cards are keyed by their series: when Continue Watching moves a show on to its next
' episode, focus stays on that show's card wherever it now sits.
' Returns { index, how }: how is "card" (the same item), "series" (the same show's new episode),
' "position" (the same place, clamped) or "first" (an empty row).
function RowFocus_index(key as dynamic, cards as object, progress as boolean) as object
    n = cards.Count()
    if n = 0 or key = invalid then return { index: 0, how: "first" }
    cid = Str_orEmpty(key.contentId)
    if cid <> "" then
        for i = 0 to n - 1
            if Str_orEmpty(cards[i].contentId) = cid then return { index: i, how: "card" }
        end for
    end if
    sid = Str_orEmpty(key.seriesId)
    if progress and sid <> "" then
        for i = 0 to n - 1
            if Str_orEmpty(cards[i].seriesId) = sid then return { index: i, how: "series" }
        end for
    end if
    i = Int(Num_or(key.item, 0))
    if i >= n then i = n - 1
    if i < 0 then i = 0
    return { index: i, how: "position" }
end function
