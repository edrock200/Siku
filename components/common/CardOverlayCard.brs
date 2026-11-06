' SPDX-License-Identifier: AGPL-3.0-or-later
'
' A card's overlays (MediaCardItem posters and landscape cards, DetailEpisodeItem stills): the
' badges and a started series poster's episodes left, drawn by OverlayArtTask into at most two
' images, the top half's and the bottom half's, shown as two Posters over the art and progress
' bar and under the watched check and the focus outline. A card only builds the image's key
' (CardOverlayKeys.brs) and sets a uri, so its overlays cost no layout, text or node creation per
' frame; the Posters are made once, when the card first needs them. A card whose image is not
' drawn yet shows none until it is: while it waits, and only then, it observes the Task's drawn
' counter (a scoped observer on the Task node, never on m.global). Adapted from
' Silo-Server/silo-roku, AGPL-3.0 (components/views/cardOverlays.bs, commit e8244ee), where each
' request carries its card for the Task to tell; Siku queues requests instead (CardOverlay_send),
' since the simulator hands a Task only some of the values a field takes in a burst.
' The including component calls CardOverlay_init(cardGroup, nodeAbove) in init.

sub CardOverlay_init(group as object, above as object)
    m.ovGroup = group
    m.ovAbove = above
    m.ovTop = invalid
    m.ovBottom = invalid
    m.ovKey = ""
    m.ovPending = ""
    m.ovRequest = invalid
    m.ovArt = invalid
    m.ovLit = false
    m.ovWatching = false
end sub

' Shows item c's overlay image for a card of shape ("poster" | "landscape" | "episode", "" for
' none) whose art is w x h, or nothing.
sub CardOverlay_show(c as object, shape as string, w as integer, h as integer, progress as boolean)
    key = CardOverlay_keyFor(c, shape, w, h, progress)
    if key = m.ovKey then
        ' Shown again while waiting: the image may be ready now.
        if m.ovPending <> "" then CardOverlay_onArt()
        return
    end if
    m.ovKey = key
    CardOverlay_wait("", invalid)
    if key = "" then
        CardOverlay_place("")
        return
    end if
    if m.ovArt = invalid then m.ovArt = CardOverlay_artNode()
    if m.ovArt.hasField(key) then
        CardOverlay_place(m.ovArt.getField(key))
        return
    end if
    CardOverlay_place("")
    request = CardOverlay_requestFor(c, key, shape, w, h, progress, false)
    CardOverlay_wait(key, request)
    CardOverlay_send([request])
    ' Another card's request for the same image may have been answered meanwhile.
    if m.ovArt.hasField(key) then CardOverlay_onArt()
end sub

' The image this card waits for may be ready (the Task drew a batch, or the card was shown again).
' Its request stays queued until the Task reads it (CardOverlay_send), so it is not sent again.
sub CardOverlay_onArt()
    key = m.ovPending
    if key = "" or m.ovArt = invalid then return
    if not m.ovArt.hasField(key) then return
    CardOverlay_wait("", invalid)
    CardOverlay_place(m.ovArt.getField(key))
end sub

' Waits for key's image ("" to stop waiting): observes the Task's drawn counter only meanwhile.
sub CardOverlay_wait(key as string, request as dynamic)
    m.ovPending = key
    m.ovRequest = request
    waiting = key <> ""
    if waiting = m.ovWatching or m.ovArt = invalid then return
    m.ovWatching = waiting
    if waiting then
        m.ovArt.observeFieldScoped("drawn", "CardOverlay_onArt")
    else
        m.ovArt.unobserveFieldScoped("drawn")
    end if
end sub

' Shows "x,y,w,h,uri;x,y,w,h,uri" (the top half's and the bottom half's images, either "" for
' none), or nothing for "".
sub CardOverlay_place(placed as string)
    halves = placed.Split(";")
    topPart = ""
    if halves.Count() > 0 then topPart = halves[0]
    bottomPart = ""
    if halves.Count() > 1 then bottomPart = halves[1]
    if topPart <> "" and m.ovTop = invalid then m.ovTop = CardOverlay_poster("overlayTop")
    if bottomPart <> "" and m.ovBottom = invalid then m.ovBottom = CardOverlay_poster("overlayBottom")
    CardOverlay_half(m.ovTop, topPart)
    CardOverlay_half(m.ovBottom, bottomPart)
end sub

' A hidden Poster in the card group, under the node that must stay above the badges.
function CardOverlay_poster(id as string) as object
    p = CreateObject("roSGNode", "Poster")
    p.id = id
    p.visible = false
    index = 0
    for each child in m.ovGroup.getChildren(-1, 0)
        if child.isSameNode(m.ovAbove) then exit for
        index = index + 1
    end for
    m.ovGroup.insertChild(p, index)
    return p
end function

sub CardOverlay_half(p as dynamic, placed as string)
    if p = invalid then return
    if placed = "" then
        p.visible = false
        return
    end if
    parts = placed.Split(",")
    if parts.Count() < 5 then
        p.visible = false
        return
    end if
    p.setFields({ translation: [parts[0].ToInt(), parts[1].ToInt()], width: parts[2].ToInt(), height: parts[3].ToInt(), uri: parts[4], visible: true })
end sub

' The card's focus changed (p, 0..1): a newly focused card tells the Task the viewer moved, which
' covers rails that show cards outside the Home rows and library grids.
sub CardOverlay_focus(p as float)
    lit = p > 0.5
    if lit = m.ovLit then return
    m.ovLit = lit
    if lit then CardOverlay_activity()
end sub
