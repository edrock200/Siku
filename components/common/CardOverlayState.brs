' SPDX-License-Identifier: AGPL-3.0-or-later
'
' Reading the open profile's card overlays for the shell (ShellScreen), as Silo Android's
' OverlayPrefsStore reads them: the server's overlay config (GET /api/v2/settings/overlay-config:
' its default document, whether badges are on, the uploaded images) and the profile's own
' ui.card_overlays and ui.card_overlays_enabled, which come with Siku's settings snapshot
' (Settings.brs, the effective values endpoint). The profile's choice wins either way, then the
' server's default (Ovl_settle). Until both answer, the profile's last answer this session applies,
' and a profile without one draws no badges, so the built-in look never flashes before the
' profile's own. A failed read keeps what applies; a server without the overlay config (404) draws
' the built-in document. The uploaded images the document draws download through ApiTask first,
' each once a session, so no card is drawn without them; a failed download leaves its badge to draw
' without the image. Adapted from Silo-Server/silo-roku, AGPL-3.0 (components/views/overlayRead.bs
' and overlayState.bs, commit e8244ee). Needs Overlays.brs, CardOverlayKeys.brs, Settings.brs, Api.brs.

' The open session's "<server>|<profile>", or "" without a profile.
function CardOverlays_key() as string
    s = m.global.session
    if s = invalid then return ""
    profileId = Str_orEmpty(s.profileId)
    if profileId = "" then return ""
    return Str_orEmpty(s.serverUrl) + "|" + profileId
end function

' Starts a read for the open profile: ShellScreen calls it when it starts, after a profile switch,
' and whenever it re-reads the settings, so a change made on the web shows here.
sub CardOverlays_read()
    key = CardOverlays_key()
    known = invalid
    if key <> "" and m.global.hasField("cardOverlaysKnown") then known = m.global.cardOverlaysKnown[key]
    CardOverlays_apply(key, known)
    m.ovReading = { key: key, config: invalid, answered: false, failed: false, source: "" }
    if key = "" then return
    ' Started now, the Task listens before any uploaded image is handed to it.
    CardOverlay_artNode()
    Api_call({ method: "GET", path: "/api/v2/settings/overlay-config", timeout: 10, context: { overlayKey: key } }, "CardOverlays_onConfig")
end sub

sub CardOverlays_onConfig(event as object)
    resp = Api_result(event)
    r = m.ovReading
    if r = invalid or resp.context = invalid then return
    if Str_orEmpty(resp.context.overlayKey) <> r.key or r.key <> CardOverlays_key() then return
    r.answered = true
    if resp.ok and Type(resp.data) = "roAssociativeArray" then
        r.config = resp.data
        r.source = "server"
    else if resp.status = 404 then
        ' A server without the endpoint draws the built-in document.
        r.source = "builtin"
    else
        ' Any other failure keeps what applies.
        r.failed = true
        Diag_log(Diag_join(["[siku-overlays] config read failed status=", resp.status, "; keeping what applies"]))
        return
    end if
    CardOverlays_settle()
end sub

' The settings snapshot changed (ShellScreen.onSettingsChanged): settle again with it.
sub CardOverlays_onSettings()
    r = m.ovReading
    if r = invalid then return
    if r.answered and not r.failed then CardOverlays_settle()
end sub

' Settles what cards draw once the config answered and the profile's settings are in.
sub CardOverlays_settle()
    r = m.ovReading
    if r = invalid then return
    if r.key <> CardOverlays_key() then return
    if not Settings_available() then
        ' Not in yet, or the read failed (what applies stays): the next snapshot settles.
        return
    end if
    values = Ovl_profileValues(Settings_state().items)
    settled = Ovl_settle(values, r.config)
    profileDoc = "no"
    if values.document <> invalid then profileDoc = "yes"
    profileOn = "unset"
    if values.enabled <> invalid then
        if values.enabled then profileOn = "on" else profileOn = "off"
    end if
    Diag_log(Diag_join(["[siku-overlays] config source=", r.source, " enabled=", settled.enabled, " preset=", settled.prefs.preset, " badges=", Ovl_enabledCount(settled.prefs), " images=", settled.images.Count(), " profile_doc=", profileDoc, " profile_enabled=", profileOn]))
    ' The uploaded images the document draws go to OverlayArtTask before it applies, each once.
    sent = {}
    if m.global.hasField("overlayImagesSent") then sent = m.global.overlayImagesSent
    refs = []
    if settled.enabled then
        for each ref in Ovl_usedImages(settled.prefs)
            if not sent.DoesExist(ref) and settled.images.DoesExist(ref) then refs.Push(ref)
        end for
    end if
    m.ovImages = { key: r.key, settled: settled, refs: refs, delivered: false }
    CardOverlays_nextImage()
end sub

' Downloads the next image the settled document draws, through ApiTask, or publishes the document
' when none is left.
sub CardOverlays_nextImage()
    loading = m.ovImages
    if loading = invalid then return
    if loading.key <> CardOverlays_key() then
        m.ovImages = invalid
        return
    end if
    if loading.refs.Count() = 0 then
        m.ovImages = invalid
        CardOverlays_publish(loading.settled, loading.key, loading.delivered)
        return
    end if
    loading.ref = loading.refs.Shift()
    ' A public, immutable read: no credentials. Bounded, so a stalled server cannot hold every
    ' card's overlay image behind it.
    Api_call({ method: "GET", path: Ovl_imagePath() + loading.ref, auth: false, profile: false, saveTo: "tmp:/ovdl-" + loading.ref, timeout: 8, context: { overlayKey: loading.key } }, "CardOverlays_onImage")
end sub

' Hands the downloaded file to OverlayArtTask at once, which keeps its own copy.
sub CardOverlays_onImage(event as object)
    resp = Api_result(event)
    loading = m.ovImages
    if loading = invalid then return
    if resp.ok and Type(resp.data) = "roAssociativeArray" then
        path = Str_orEmpty(resp.data.path)
        if path <> "" then
            CardOverlay_artNode().image = { ref: loading.ref, path: path }
            loading.delivered = true
            sent = {}
            if m.global.hasField("overlayImagesSent") then sent = m.global.overlayImagesSent
            sent[loading.ref] = true
            if m.global.hasField("overlayImagesSent") then
                m.global.overlayImagesSent = sent
            else
                m.global.addFields({ overlayImagesSent: sent })
            end if
        end if
    else
        Diag_log(Diag_join(["[siku-overlays] image download failed status=", resp.status, "; its badge draws without it"]))
    end if
    CardOverlays_nextImage()
end sub

' Records what cards draw (Ovl_settle) for key and makes it what applies. The same document again
' keeps its name (compared, not serialized); a new one, or one that brought new images (fresh),
' takes the next name this session, as OverlayArtTask's files last a session.
sub CardOverlays_publish(settled as object, key as string, fresh as boolean)
    known = {}
    if m.global.hasField("cardOverlaysKnown") then known = m.global.cardOverlaysKnown
    previous = known[key]
    same = false
    if not fresh and Type(previous) = "roAssociativeArray" then
        same = Ovl_same(previous.prefs, settled.prefs) and Ovl_same(previous.images, settled.images)
    end if
    if same then
        settled.prefsKey = previous.prefsKey
    else
        if not m.global.hasField("overlayDocuments") then m.global.addFields({ overlayDocuments: 0 })
        m.global.overlayDocuments = m.global.overlayDocuments + 1
        settled.prefsKey = "d" + m.global.overlayDocuments.ToStr()
    end if
    known[key] = settled
    if m.global.hasField("cardOverlaysKnown") then
        m.global.cardOverlaysKnown = known
    else
        m.global.addFields({ cardOverlaysKnown: known })
    end if
    CardOverlays_apply(key, settled)
end sub

' Makes value (a settled state, or invalid for none yet) what applies for key. Unchanged (the
' name covers the document and images), the views need not draw their cards again.
sub CardOverlays_apply(key as string, value as dynamic)
    st = { key: key, shown: false, enabled: false, prefs: invalid, images: {}, prefsKey: "" }
    if Type(value) = "roAssociativeArray" then
        st.shown = true
        st.enabled = Ovl_isTrue(value.enabled)
        st.prefs = value.prefs
        st.images = value.images
        st.prefsKey = Str_orEmpty(value.prefsKey)
    end if
    docKey = ""
    if st.shown and st.enabled and Type(st.prefs) = "roAssociativeArray" then docKey = st.prefsKey
    if not m.global.hasField("cardOverlaysRevision") then m.global.addFields({ cardOverlaysRevision: 0, cardOverlaysKey: "" })
    if not m.global.hasField("cardOverlays") then m.global.addFields({ cardOverlays: {} })
    applied = m.global.cardOverlays
    if Type(applied) = "roAssociativeArray" and applied.DoesExist("prefsKey") then
        if applied.key = key and applied.shown = st.shown and applied.enabled = st.enabled and applied.prefsKey = st.prefsKey then return
    end if
    m.global.cardOverlays = st
    m.global.cardOverlaysKey = docKey
    m.global.cardOverlaysRevision = m.global.cardOverlaysRevision + 1
end sub
