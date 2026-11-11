' SPDX-License-Identifier: AGPL-3.0-or-later
'
' Card overlay images by key (render thread): what a card of a shape and size asks OverlayArtTask
' to draw for an item, used by the cards themselves (CardOverlayCard.brs) and by the long-lived
' views that ask ahead for the cards they will show (Home rows, library grids), so scrolling
' finds the images drawn. Self-contained: MediaCardItem has no Utils.brs in scope.
' Adapted from Silo-Server/silo-roku, AGPL-3.0 (components/views/overlayKeys.bs, commit e8244ee).
'
' m.global, written by ShellScreen (CardOverlayState.brs):
'   cardOverlaysKey       the applying document's name ("" while no badges draw), all a card reads
'   cardOverlays          { key, shown, enabled, prefs, images, prefsKey } for OverlayArtTask
'   cardOverlaysRevision  bumped when what applies changes (views draw their cards again)
'   overlayArt            the app's one OverlayArtTask
'   overlayArtRevision    bumped when the Task starts listening (requests made before are lost)

' The applying document's name, or "" when no badges draw (overlays off, or no answer yet).
function CardOverlay_docKey() as string
    if not m.global.hasField("cardOverlaysKey") then return ""
    return m.global.cardOverlaysKey
end function

' The art shapes that carry overlays: posters, landscape cards and episode stills.
function CardOverlay_shapeOf(style as string) as string
    if style = "poster" or style = "landscape" or style = "episode" then return style
    return ""
end function

' Whether a card shows its progress bar (MediaCardItem.layout: some progress, not finished; a box
' set's bar may be full).
function CardOverlay_hasProgress(c as object) as boolean
    p = 0.0
    if c.hasField("progress") then
        v = c.progress
        if Type(v) = "roFloat" or Type(v) = "Float" or Type(v) = "roInt" or Type(v) = "Integer" or Type(v) = "roDouble" or Type(v) = "Double" then p = v
    end if
    return p > 0.01 and p < 0.995
end function

' The watch-status corner on a card of shape, w px wide (Silo Android #882, the web's
' CardWatchStatus): { size, inset }. Poster-shaped art (posters, square cards) draws it at the web's
' 22 and 8 at the 185 px reference poster width; landscape cards never draw it (size 0); the episode
' rail keeps its own 44 px check 12 px in (DetailEpisodeItem). The top badge row stops short of it
' and the episodes-left count takes its place.
function CardOverlay_check(shape as string, w as integer) as object
    if shape = "episode" then return { size: 44, inset: 12 }
    if shape = "landscape" or w <= 0 then return { size: 0, inset: 0 }
    unit = w / 185.0
    return { size: Int(22 * unit + 0.5), inset: Int(8 * unit + 0.5) }
end function

' What a card's top-right corner shows (Silo Android #882 CardWatchStatus.of): "check" on a watched
' title, "count" for the episodes a started, unfinished series or season has left (remaining, from
' Content_episodesLeft), "" for nothing. Only poster-shaped art (portrait or square) shows it, whether
' or not badges are on.
function CardOverlay_status(watched as dynamic, remaining as dynamic, portrait as boolean) as string
    if not portrait then return ""
    if (Type(watched) = "Boolean" or Type(watched) = "roBoolean") and watched then return "check"
    n = 0
    t = Type(remaining)
    if t = "roInt" or t = "Integer" or t = "roInteger" or t = "LongInteger" or t = "roFloat" or t = "Float" then n = remaining
    if n > 0 then return "count"
    return ""
end function

' The key of item c's overlay image on a card of shape, w x h, "" for nothing to draw: the
' document's name ("none" for the episodes-left disc alone), size and shape, whether a progress
' bar lifts the bottom row, the data's key and the episodes left.
function CardOverlay_keyFor(c as object, shape as string, w as integer, h as integer, progress as boolean) as string
    if shape = "" or w <= 0 or h <= 0 then return ""
    if not c.hasField("overlayKey") then return ""
    if c.hasField("exploreAll") then
        if c.exploreAll = true then return ""
    end if
    if c.hasField("markedBadge") then
        if c.markedBadge <> "" then return ""
    end if
    count = 0
    if CardOverlay_status(c.watched, c.remaining, shape = "poster") = "count" then count = c.remaining
    doc = "none"
    if c.overlayKey <> "" then
        d = CardOverlay_docKey()
        if d <> "" then doc = d
    end if
    if doc = "none" and count <= 0 then return ""
    dataKey = ""
    if doc <> "none" then dataKey = c.overlayKey
    flags = Left(shape, 1)
    if progress then flags = flags + "p"
    return "ov" + doc + "_" + w.ToStr() + "x" + h.ToStr() + flags + "_" + dataKey + "_" + count.ToStr()
end function

' What OverlayArtTask needs to draw key; prefetch for a card not on screen yet (it waits behind
' those that are).
function CardOverlay_requestFor(c as object, key as string, shape as string, w as integer, h as integer, progress as boolean, prefetch as boolean) as object
    count = 0
    if CardOverlay_status(c.watched, c.remaining, shape = "poster") = "count" then count = c.remaining
    doc = Mid(key, 3, Instr(1, key, "_") - 3)
    return { key: key, doc: doc, data: c.overlayData, w: w, h: h, shape: shape, progress: progress, remaining: count, radius: 16, check: CardOverlay_check(shape, w), prefetch: prefetch }
end function

' The app's OverlayArtTask, started by the first view that needs it.
function CardOverlay_artNode() as object
    if not m.global.hasField("overlayArt") then
        task = CreateObject("roSGNode", "OverlayArtTask")
        task.control = "run"
        m.global.addFields({ overlayArt: task })
    end if
    return m.global.overlayArt
end function

' Hands requests to OverlayArtTask through its queue: each gets the next number, and entries the Task
' has read (ack) are dropped first. A queue, not one field set per request: the simulator hands a
' Task only some of the values a field takes in a burst, and lost requests left cards waiting.
sub CardOverlay_send(requests as object)
    if requests.Count() = 0 then return
    art = CardOverlay_artNode()
    ack = art.ack
    q = []
    for each e in art.queue
        if Type(e) = "roAssociativeArray" then
            if e.seq > ack then q.Push(e)
        end if
    end for
    seq = art.queueSeq
    for each r in requests
        seq = seq + 1
        r.seq = seq
        q.Push(r)
    end for
    art.queue = q
    art.queueSeq = seq
end sub

' Asks ahead for the images of content's cards (ContentNode children of one row or grid) on cards
' of style w x h that are not drawn yet.
sub CardOverlay_prefetch(content as dynamic, style as string, w as integer, h as integer)
    if content = invalid or w <= 0 or h <= 0 then return
    shape = CardOverlay_shapeOf(style)
    if shape = "" then return
    art = invalid
    batch = []
    asked = {}
    for each c in content.getChildren(-1, 0)
        progress = CardOverlay_hasProgress(c)
        key = CardOverlay_keyFor(c, shape, w, h, progress)
        if key <> "" and not asked.DoesExist(key) then
            if art = invalid then art = CardOverlay_artNode()
            asked[key] = true
            if not art.hasField(key) then batch.Push(CardOverlay_requestFor(c, key, shape, w, h, progress, true))
        end if
    end for
    CardOverlay_send(batch)
end sub

' Calls callback when the cards' overlays should draw again: a new document, or OverlayArtTask
' started listening (requests made before then are lost). Only long-lived views observe these: an
' observer on m.global keeps its component alive.
sub CardOverlay_observe(callback as string)
    if not m.global.hasField("cardOverlaysRevision") then m.global.addFields({ cardOverlaysRevision: 0, cardOverlaysKey: "" })
    if not m.global.hasField("overlayArtRevision") then m.global.addFields({ overlayArtRevision: 0 })
    m.global.observeField("cardOverlaysRevision", callback)
    m.global.observeField("overlayArtRevision", callback)
end sub

' For screens that come and go (a detail page): watch for a new document, or the Task starting to
' listen (requests made before are lost), only while on top, with scoped observers the screen
' removes again when it is covered, so nothing on m.global holds it. Returns true when either
' changed since since (CardOverlay_revision as this screen saw it last).
function CardOverlay_watch(callback as string, since as string) as boolean
    if not m.global.hasField("cardOverlaysRevision") then m.global.addFields({ cardOverlaysRevision: 0, cardOverlaysKey: "" })
    if not m.global.hasField("overlayArtRevision") then m.global.addFields({ overlayArtRevision: 0 })
    m.global.observeFieldScoped("cardOverlaysRevision", callback)
    m.global.observeFieldScoped("overlayArtRevision", callback)
    return CardOverlay_revision() <> since
end function

sub CardOverlay_unwatch()
    if m.global.hasField("cardOverlaysRevision") then m.global.unobserveFieldScoped("cardOverlaysRevision")
    if m.global.hasField("overlayArtRevision") then m.global.unobserveFieldScoped("overlayArtRevision")
end sub

' What applies now and whether the Task listens, as text that changes with either.
function CardOverlay_revision() as string
    rev = 0
    art = 0
    if m.global.hasField("cardOverlaysRevision") then rev = m.global.cardOverlaysRevision
    if m.global.hasField("overlayArtRevision") then art = m.global.overlayArtRevision
    return rev.ToStr() + "|" + art.ToStr()
end function

' Draws again the cards of content (ContentNode children, or rows of them) that carry overlays.
' Setting overlayRev on a card's node makes the list hand it to its item component again.
sub CardOverlay_refresh(content as dynamic)
    if content = invalid then return
    for each child in content.getChildren(-1, 0)
        if child.hasField("overlayKey") then
            if child.overlayKey <> "" or child.remaining > 0 then
                if not child.hasField("overlayRev") then child.addFields({ overlayRev: 0 })
                child.overlayRev = child.overlayRev + 1
            end if
        else if child.getChildCount() > 0 then
            CardOverlay_refresh(child)
        end if
    end for
end sub

' Tells OverlayArtTask the viewer is moving focus, so it waits to draw: encoding an image stalls
' the frames drawn meanwhile.
sub CardOverlay_activity()
    if not m.global.hasField("overlayArt") then return
    art = m.global.overlayArt
    art.activity = art.activity + 1
end sub
