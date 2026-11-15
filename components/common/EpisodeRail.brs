' SPDX-License-Identifier: AGPL-3.0-or-later
'
' The series page's episode rail at the profile's Poster Size (Silo Android TV TvDetailEpisodeRail:
' tvEpisodeCardWidth().cardScaled(), the still 16:9 of that width). Android TV scales the card's width
' and so its still; the caption's text, its gaps and the 20 dp between cards stay as they are. In px:
' a Standard card is 360 wide (Android's 180 dp), Compact ×0.86 (310), Large ×1.2 (432). Pure, so
' DetailScreen, DetailEpisodeItem and the host tests share the numbers.

' A Standard card's width in px (RowDimens.BackdropWidth 180 dp).
function EpisodeRail_baseWidth() as integer
    return 360
end function

' The card's still height for a card w px wide: 16:9, whole px.
function EpisodeRail_stillHeight(w as dynamic) as integer
    return Int(w * 9 / 16)
end function

' The rail at Poster Size multiplier scale (CardOverlay_posterScale; anything not a number is 1):
' { cardW, stillH, insetY, cellH, spacing, rowY, sectionH }.
'   insetY   headroom above the still inside its cell (a real Roku clips items to their cell, pitfall 12):
'            the focused still's lift and its shadow (CardFocus, 14 px above the art) stay inside it.
'   cellH    the cell's height: the headroom, the still and the caption (the gap, "S01E02 · Title", the
'            meta line and three lines of description: 218 px, the same at every size).
'   spacing  between cards: 40 px (Android's 20 dp, not scaled).
'   rowY     the RowList's y in the section (under the header and the season chips), less the headroom.
'   sectionH the episodes section's height, header to the caption's last line.
function EpisodeRail_geometry(scale as dynamic) as object
    s = 1.0
    t = Type(scale)
    if t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double" or t = "roInt" or t = "Integer" or t = "roInteger" then s = scale * 1.0
    if not (s > 0) then s = 1.0
    w = Int(EpisodeRail_baseWidth() * s + 0.5)
    h = EpisodeRail_stillHeight(w)
    lift = Int(h * 0.025 + 0.5)
    insetY = 15 + lift
    if insetY < 20 then insetY = 20
    caption = 218
    top = 130
    return { cardW: w, stillH: h, insetY: insetY, cellH: insetY + h + caption, spacing: 40, rowY: top - insetY, sectionH: top + h + caption }
end function
