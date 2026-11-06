' SPDX-License-Identifier: AGPL-3.0-or-later
'
' Draws each requested card overlay image once (OverlayDraw.brs): the cards on screen first, then
' the cards views asked for ahead (prefetch), and none while the viewer moves focus. Requests that
' arrive meanwhile are taken between images. A request made for a document other than the one that
' applies when its turn comes is dropped; its card asks again under the new key.
' Adapted from Silo-Server/silo-roku, AGPL-3.0 (components/tasks/OverlayArtTask.bs, commit e8244ee).

sub init()
    m.top.functionName = "serve"
end sub

' How long after the viewer last moved focus the Task waits to draw (Silo's Roku app measured the
' stall an encode causes on a TCL 55R625 and an Ultra 4850X).
function OverlayArt_quietMs() as integer
    return 1500
end function

sub serve()
    port = CreateObject("roMessagePort")
    m.top.observeField("queueSeq", port)
    m.top.observeField("image", port)
    files = CreateObject("roFileSystem")
    for each name in files.GetDirectoryListing("tmp:/")
        if Left(name, 8) = "overlay-" then files.Delete("tmp:/" + name)
    end for
    m.queues = { now: [], ahead: [] }
    m.asked = {}
    m.state = invalid
    m.clock = CreateObject("roTimespan")
    m.lastActivity = -OverlayArt_quietMs()
    m.seenActivity = m.top.activity
    m.ovStats = OverlayArt_newStats()
    m.copy = Ovl_words()
    ' Requests queued before the Task observed the queue are read now.
    m.readSeq = 0
    readQueue()
    keepImage(m.top.image)
    announce()
    done = {}
    while true
        idle = m.queues.now.Count() = 0 and m.queues.ahead.Count() = 0
        if idle then
            if done.Count() > 0 then
                publish(done)
                done = {}
            end if
            take(wait(0, port))
        else if sinceActivity() < OverlayArt_quietMs() then
            if done.Count() > 0 then
                publish(done)
                done = {}
            end if
            ' Focus moves are read, not sent: look again every 100 ms.
            take(wait(100, port))
        else
            request = m.queues.now.Shift()
            if request = invalid then request = m.queues.ahead.Shift()
            answer(request, done)
            ' Cards look for their images after every few, not after each: one rendezvous with the
            ' render thread per batch.
            if done.Count() >= 6 then
                publish(done)
                done = {}
            end if
        end if
        msg = port.GetMessage()
        while msg <> invalid
            take(msg)
            msg = port.GetMessage()
        end while
    end while
end sub

function OverlayArt_newStats() as object
    return { drawn: 0, hits: 0, failed: 0, dropped: 0, files: 0, shared: 0, spriteHits: 0, spriteMisses: 0 }
end function

' How long since the viewer last moved focus, in ms.
function sinceActivity() as integer
    seen = m.top.activity
    if seen <> m.seenActivity then
        m.seenActivity = seen
        m.lastActivity = m.clock.TotalMilliseconds()
    end if
    return m.clock.TotalMilliseconds() - m.lastActivity
end function

sub take(msg as dynamic)
    if Type(msg) <> "roSGNodeEvent" then return
    if msg.getField() = "image" then
        keepImage(msg.getData())
    else
        readQueue()
    end if
end sub

' Takes the queued requests above the last one read, then acknowledges them so senders drop them.
sub readQueue()
    q = m.top.queue
    if Type(q) <> "roArray" then return
    last = m.readSeq
    for each e in q
        if Type(e) = "roAssociativeArray" then
            seq = e.seq
            if Type(seq) = "roInt" or Type(seq) = "Integer" or Type(seq) = "roInteger" then
                if seq > m.readSeq then
                    takeRequest(e)
                    if seq > last then last = seq
                end if
            end if
        end if
    end for
    if last <> m.readSeq then
        m.readSeq = last
        m.top.ack = last
    end if
end sub

' Copies an uploaded image ApiTask downloaded ({ ref, path }) to where OverlayDraw reads it, before
' ApiTask's file is reused.
sub keepImage(image as dynamic)
    if Type(image) <> "roAssociativeArray" then return
    if not Ovl_isImageRef(image.ref) or not Ovl_isStr(image.path) then return
    files = CreateObject("roFileSystem")
    target = OvDraw_imagePath(image.ref)
    if files.Exists(target) then files.Delete(target)
    ok = false
    if files.Exists(image.path) then ok = files.CopyFile(image.path, target)
    if ok then
        Diag_log("[siku-overlays] image kept")
    else
        Diag_log("[siku-overlays] image could not be kept; its badge draws without it")
    end if
    ' A failed earlier load is forgotten (OvDraw_uploaded).
    if m.ovImages <> invalid then m.ovImages.Delete(image.ref)
end sub

sub takeRequest(request as dynamic)
    if Type(request) <> "roAssociativeArray" then return
    if not Ovl_isStr(request.key) then return
    if request.key = "" then return
    status = OverlayArt_status(request.key)
    if status <> "" then
        m.ovStats.hits = m.ovStats.hits + 1
        ' A card on screen now wants what was asked for ahead: it goes first.
        if not Ovl_isTrue(request.prefetch) and status = "ahead" then
            m.asked[request.key] = "now"
            m.queues.now.Push(request)
        end if
        return
    end if
    if Ovl_isTrue(request.prefetch) then
        m.asked[request.key] = "ahead"
        m.queues.ahead.Push(request)
    else
        m.asked[request.key] = "now"
        m.queues.now.Push(request)
    end if
end sub

' Where key stands: "" (never asked), "ahead", "now", "done" or "published". Never compared as
' invalid with a string (a Type Mismatch on a Roku).
function OverlayArt_status(key as string) as string
    v = m.asked[key]
    if v = invalid then return ""
    return v
end function

' Draws request's image into done under its key, unless it is drawn already or its document no
' longer applies.
sub answer(request as object, done as object)
    status = OverlayArt_status(request.key)
    if status = "done" or status = "published" then return
    state = invalid
    if request.doc <> "none" then
        state = currentState(request.doc)
        if state = invalid then
            ' Its cards ask again under the document that applies now.
            m.asked.Delete(request.key)
            m.ovStats.dropped = m.ovStats.dropped + 1
            m.top.drawn = m.top.drawn + 1
            return
        end if
    end if
    m.asked[request.key] = "done"
    ' A failure while drawing (graphics memory, say) costs this card its overlays, not every card
    ' after it.
    try
        done[request.key] = OvDraw_draw(request, state, m.copy)
        m.ovStats.drawn = m.ovStats.drawn + 1
    catch failure
        Diag_log("[siku-overlays] drawing failed: " + failure.message)
        m.ovStats.failed = m.ovStats.failed + 1
        done[request.key] = ""
    end try
end sub

' Adds done's keys as fields, then bumps drawn, which the cards waiting for an image observe.
sub publish(done as object)
    m.top.addFields(done)
    for each key in done
        m.asked[key] = "published"
    end for
    m.top.drawn = m.top.drawn + 1
    s = m.ovStats
    Diag_log(Diag_join(["[siku-overlays] art drawn=", s.drawn, " hits=", s.hits, " files=", s.files, " shared=", s.shared, " sprites=", s.spriteHits, "/", s.spriteMisses, " dropped=", s.dropped, " failed=", s.failed, " queued=", m.queues.now.Count() + m.queues.ahead.Count()]))
    m.ovStats = OverlayArt_newStats()
end sub

' Tells the views showing cards that the Task listens now: requests made before were lost, and
' their cards ask again.
sub announce()
    if not m.global.hasField("overlayArtRevision") then m.global.addFields({ overlayArtRevision: 0 })
    m.global.overlayArtRevision = m.global.overlayArtRevision + 1
end sub

' The overlays that apply when they are doc's, read from m.global once per document; invalid when
' another document applies now.
function currentState(doc as string) as dynamic
    if m.state <> invalid then
        if m.state.prefsKey = doc then return m.state
    end if
    if not m.global.hasField("cardOverlays") then return invalid
    state = m.global.cardOverlays
    if Type(state) <> "roAssociativeArray" then return invalid
    if Ovl_text(state.prefsKey) <> doc then return invalid
    m.state = state
    return state
end function
