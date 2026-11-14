' SPDX-License-Identifier: AGPL-3.0-or-later
'
' Drawing a card's overlays into images (OverlayArtTask; Task thread only: roBitmap, roFontRegistry,
' GetPng and file writes). A card shows its badges, a band's scrims and its episodes-left disc as
' at most two Posters of these images, so it adds no Labels, 9-patches or glyph Posters per badge:
' node-built badges cost a TCL Roku TV a third of Home's frame rate (Silo's own Roku app measured
' it). The layout and looks are Overlays.brs' (the web's CardOverlays); this file measures text
' with the packaged Inter, draws anti-aliased rounded fills and borders from end caps drawn pixel by
' pixel once, scales glyphs and uploaded images, and writes only the boxes it drew in.
' Adapted from Silo-Server/silo-roku, AGPL-3.0 (components/overlays/overlayDraw.bs, commit
' e8244ee), without its 9-patch frame path: Siku rounds card corners with a MaskGroup, so every
' card shows its overlays as Posters.

function OvDraw_dir() as string
    return "tmp:/overlay-"
end function

' The pixels the badge sprites may hold, about 4 MB.
function OvDraw_maxSpritePixels() as integer
    return 1048576
end function

' Draws spec ({ key, data, w, h, shape, progress, remaining, radius, check: { size, inset } })
' under state (m.global.cardOverlays: prefs, images; invalid for the disc alone) and gives
' "x,y,w,h,uri;x,y,w,h,uri": the box drawn in the card and the image of its top half's overlays
' and of its bottom half's ("" for a half with none), or "" for nothing. Two images, not one: one
' image the card's height, mostly clear, costs frames on every card. Halves drawn alike share one
' file: encoding one costs tens of milliseconds whatever its size.
function OvDraw_draw(spec as object, state as dynamic, copy as object) as string
    width = Int(spec.w)
    height = Int(spec.h)
    if width <= 0 or height <= 0 then return ""
    bmp = CreateObject("roBitmap", { width: width, height: height, AlphaEnable: true })
    if bmp = invalid then return ""
    bmp.Clear(0)
    c = { bmp: bmp, width: width, height: height, radius: spec.radius, groups: [OvDraw_group(width, height), OvDraw_group(width, height)], look: invalid, images: {} }
    hasData = false
    if Type(spec.data) = "roAssociativeArray" then hasData = spec.data.Count() > 0
    if Type(state) = "roAssociativeArray" and hasData then
        if Type(state.prefs) = "roAssociativeArray" then
            if Type(state.images) = "roAssociativeArray" then c.images = state.images
            OvDraw_badges(c, spec, state.prefs, copy)
        end if
    end if
    if spec.remaining > 0 then OvDraw_countDisc(c, spec)
    bmp.Finish()
    topPart = OvDraw_encode(c, c.groups[0], spec, "t")
    bottomPart = OvDraw_encode(c, c.groups[1], spec, "b")
    if topPart = "" and bottomPart = "" then return ""
    return topPart + ";" + bottomPart
end function

' The box and ops (what was drawn where) of one half of a card's image.
function OvDraw_group(width as integer, height as integer) as object
    return { minX: width, minY: height, maxX: 0, maxY: 0, ops: [] }
end function

' The half's image, "x,y,w,h,uri", written once per distinct look.
function OvDraw_encode(c as object, g as object, spec as object, suffix as string) as string
    if g.maxX <= g.minX or g.maxY <= g.minY then return ""
    w = g.maxX - g.minX
    h = g.maxY - g.minY
    if m.ovFiles = invalid then m.ovFiles = {}
    g.ops.Push("area" + g.minX.ToStr() + "," + g.minY.ToStr() + "," + w.ToStr() + "," + h.ToStr() + "," + Str(spec.radius).Trim())
    signature = OvDraw_hash(g.ops.Join("|"))
    if m.ovFiles.DoesExist(signature) then
        m.ovStats.shared = m.ovStats.shared + 1
        return m.ovFiles[signature]
    end if
    ' A bitmap of just the box: a Poster does not show GetPng's output for part of a bitmap
    ' (Silo's Roku app, TCL 55R625, Roku OS 15.3.4), though roBitmap reads it.
    out = CreateObject("roBitmap", { width: w, height: h, AlphaEnable: false })
    if out = invalid then return ""
    out.Clear(0)
    out.DrawObject(-g.minX, -g.minY, c.bmp)
    out.Finish()
    png = out.GetPng(0, 0, w, h)
    path = OvDraw_dir() + spec.key + "-" + suffix + ".png"
    if png = invalid then return ""
    if not png.WriteFile(path) then return ""
    m.ovStats.files = m.ovStats.files + 1
    placed = g.minX.ToStr() + "," + g.minY.ToStr() + "," + w.ToStr() + "," + h.ToStr() + "," + path
    m.ovFiles[signature] = placed
    return placed
end function

' Records what was drawn at y, h tall, in the half it sits in, for the half's signature.
sub OvDraw_note(c as object, op as string, y as integer, h as integer)
    g = OvDraw_groupAt(c, y, h)
    g.ops.Push(op)
end sub

function OvDraw_groupAt(c as object, y as integer, h as integer) as object
    if y + h / 2 < c.height / 2 then return c.groups[0]
    return c.groups[1]
end function

' ---------- Layout (the web's CardOverlays, Android TV's insets) ----------

sub OvDraw_badges(c as object, spec as object, prefs as object, copy as object)
    look = Ovl_lookOf(prefs.preset, prefs.style)
    resolved = Ovl_resolve(prefs, spec.data, look, copy)
    shape = spec.shape
    ' The card's overlay scale (Silo Android #912, CardOverlay_scaleFor): a poster's width over 185,
    ' a wide card's Poster Size multiplier, times the text factor.
    k = 1.0
    if Ovl_isNum(spec.k) then k = spec.k
    if k <= 0 then k = 1.0
    c.look = look
    c.k = k
    c.inset = 8 * k
    ' The bottom corners sit higher on wide cards (Android TV's Wide variant 24, the episode rail
    ' 12) and lift clear of a progress bar (Silo Android #882; Siku's bar floats 18 px up).
    c.bottomInset = Ovl_bottomInset(shape, k, Ovl_isTrue(spec.progress), WatchProgress_metrics().clearance)
    ' The top row stops short of the watch-status corner (none on a landscape card).
    reserve = Ovl_topRowEnd(spec.check.inset, spec.check.size, k)
    if look.band then
        OvDraw_bandTop(c, resolved.topLeft, c.width - reserve)
        both = []
        both.Append(resolved.bottomLeft)
        both.Append(resolved.bottomRight)
        OvDraw_bandBottom(c, both)
    else
        OvDraw_stackTop(c, resolved.topLeft, c.width - reserve - c.inset)
        OvDraw_bottomRows(c, resolved.bottomLeft, resolved.bottomRight)
    end if
    railInset = c.inset
    if Ovl_flushRails(look) then railInset = 0
    OvDraw_rail(c, resolved.leftEdge, railInset, "left")
    OvDraw_rail(c, resolved.rightEdge, railInset, "right")
end sub

sub OvDraw_stackTop(c as object, list as object, maxWidth as float)
    y = c.inset
    for each b in list
        plan = OvDraw_measure(c, b, maxWidth, "")
        OvDraw_paintBadge(c, plan, c.inset, y)
        y = y + plan.h + c.look.stackGap * c.k
    end for
end sub

sub OvDraw_rail(c as object, list as object, inset as float, side as string)
    if list.Count() = 0 then return
    flush = ""
    if inset = 0 then flush = side
    gap = c.look.stackGap * c.k
    plans = []
    total = 0.0
    for each b in list
        plan = OvDraw_measure(c, b, c.width * 0.6, flush)
        plans.Push(plan)
        total = total + plan.h
    end for
    total = total + gap * (plans.Count() - 1)
    y = (c.height - total) / 2
    for each plan in plans
        x = inset
        if side = "right" then x = c.width - inset - plan.w
        OvDraw_paintBadge(c, plan, x, y)
        y = y + plan.h + gap
    end for
end sub

' The bottom corners a row per level from the bottom; a pair too wide to share its row wraps, the
' right badge onto a line under the left (Ovl_bottomLayout).
sub OvDraw_bottomRows(c as object, lt as object, rt as object)
    if lt.Count() = 0 and rt.Count() = 0 then return
    available = c.width - 2 * c.inset
    lp = []
    rp = []
    lw = []
    lh = []
    rw = []
    rh = []
    for each b in lt
        plan = OvDraw_measure(c, b, available, "")
        lp.Push(plan)
        lw.Push(plan.w)
        lh.Push(plan.h)
    end for
    for each b in rt
        plan = OvDraw_measure(c, b, available, "")
        rp.Push(plan)
        rw.Push(plan.w)
        rh.Push(plan.h)
    end for
    at = Ovl_bottomLayout(lw, lh, rw, rh, available, 8 * c.k, c.look.stackGap * c.k)
    top = c.height - c.bottomInset - at.h
    for i = 0 to lp.Count() - 1
        OvDraw_paintBadge(c, lp[i], c.inset + at.lx[i], top + at.ly[i])
    end for
    for i = 0 to rp.Count() - 1
        OvDraw_paintBadge(c, rp[i], c.inset + at.rx[i], top + at.ry[i])
    end for
end sub

sub OvDraw_bandTop(c as object, list as object, limit as float)
    if list.Count() = 0 then return
    marks = OvDraw_bandMarks(c, list, limit - c.inset)
    OvDraw_scrim(c, 0, Int(c.inset * 4 + marks.h + 0.5), true)
    OvDraw_placeMarks(c, marks, c.inset, c.inset)
end sub

sub OvDraw_bandBottom(c as object, list as object)
    if list.Count() = 0 then return
    marks = OvDraw_bandMarks(c, list, c.width - 2 * c.inset)
    below = c.bottomInset
    strip = Int(c.inset * 3 + marks.h + below + 0.5)
    OvDraw_scrim(c, c.height - strip, strip, false)
    OvDraw_placeMarks(c, marks, (c.width - marks.w) / 2, c.height - below - marks.h)
end sub

' The marks that fit whole in available, with a divider before each after the first; only a
' first mark too wide on its own truncates.
function OvDraw_bandMarks(c as object, list as object, available as float) as object
    gap = c.look.stackGap * c.k
    plans = []
    widths = []
    for each b in list
        plan = OvDraw_measure(c, b, 100000, "")
        plans.Push(plan)
        widths.Push(plan.w)
    end for
    count = Ovl_bandFit(widths, available, gap, 1)
    if count = 1 and plans[0].w > available then plans[0] = OvDraw_measure(c, list[0], available, "")
    kept = []
    total = 0.0
    tallest = 0.0
    for i = 0 to count - 1
        kept.Push(plans[i])
        total = total + plans[i].w
        if i > 0 then total = total + 2 * gap + 1
        if plans[i].h > tallest then tallest = plans[i].h
    end for
    return { plans: kept, w: total, h: tallest, gap: gap }
end function

sub OvDraw_placeMarks(c as object, marks as object, x as float, y as float)
    dividerHeight = c.look.fontSize * c.k * 0.9
    for i = 0 to marks.plans.Count() - 1
        plan = marks.plans[i]
        if i > 0 then
            x = x + marks.gap
            OvDraw_note(c, "divider" + OvDraw_whole(x).ToStr() + "," + OvDraw_whole(y).ToStr() + "," + OvDraw_whole(dividerHeight).ToStr(), OvDraw_whole(y), OvDraw_whole(marks.h))
            OvDraw_fillRect(c, OvDraw_whole(x), OvDraw_whole(y + (marks.h - dividerHeight) / 2), 1, OvDraw_whole(dividerHeight), OvDraw_rgba(255, 255, 255, 0.4))
            x = x + 1 + marks.gap
        end if
        OvDraw_paintBadge(c, plan, x, y + (marks.h - plan.h) / 2)
        x = x + plan.w
    end for
end sub

' A band's scrim from y0, rows tall: black 85% at the card's edge, 60% at 55% of the way in,
' clear at the end, inside the card's rounded corners.
sub OvDraw_scrim(c as object, y0 as integer, rows as integer, atTop as boolean)
    OvDraw_note(c, "scrim" + y0.ToStr() + "," + rows.ToStr() + "," + atTop.ToStr() + "," + c.width.ToStr(), y0, rows)
    for j = 0 to rows - 1
        t = (j + 0.5) / rows
        if not atTop then t = 1 - t
        if t <= 0.55 then
            alpha = 0.85 + (0.6 - 0.85) * t / 0.55
        else
            alpha = 0.6 * (1 - (t - 0.55) / 0.45)
        end if
        OvDraw_cardRow(c, y0 + j, alpha)
    end for
end sub

' A row of black at alpha across the card, its ends anti-aliased to the card's corners.
sub OvDraw_cardRow(c as object, y as integer, alpha as float)
    r = c.radius
    yc = y + 0.5
    dy = 0.0
    if yc < r then dy = r - yc
    if yc > c.height - r then dy = yc - (c.height - r)
    if dy <= 0 then
        OvDraw_fillRect(c, 0, y, c.width, 1, OvDraw_rgba(0, 0, 0, alpha))
        return
    end if
    zone = Int(r) + 1
    for x = 0 to zone - 1
        d = Sqr((r - (x + 0.5)) ^ 2 + dy * dy)
        amount = OvDraw_clamp(r - d + 0.5)
        if (x + 0.5) >= r then amount = OvDraw_clamp(r - dy + 0.5)
        if amount > 0 then
            OvDraw_fillRect(c, x, y, 1, 1, OvDraw_rgba(0, 0, 0, alpha * amount))
            OvDraw_fillRect(c, c.width - 1 - x, y, 1, 1, OvDraw_rgba(0, 0, 0, alpha * amount))
        end if
    end for
    middle = OvDraw_clamp(r - dy + 0.5)
    if middle > 0 then OvDraw_fillRect(c, zone, y, c.width - 2 * zone, 1, OvDraw_rgba(0, 0, 0, alpha * middle))
end sub

' ---------- A badge ----------

' What badge b draws at most maxWidth wide: its size w x h and its parts. rail is "left" or
' "right" for a tab flush with that edge, else "".
function OvDraw_measure(c as object, b as object, maxWidth as float, rail as string) as object
    look = c.look
    k = c.k
    ' An uploaded image for the badge's value replaces the whole badge.
    if b.valueImage <> "" then
        image = OvDraw_uploaded(c, b.valueImage)
        if image <> invalid then
            h = (look.fontSize + 2 * look.padY) * Ovl_valueImageScale() * k
            w = h * image.GetWidth() / image.GetHeight()
            if w > maxWidth then w = maxWidth
            return { kind: "value", badge: b, image: image, w: OvDraw_whole(w), h: OvDraw_whole(h), rail: rail }
        end if
    end if
    iconImage = invalid
    if b.image <> "" then iconImage = OvDraw_uploaded(c, b.image)
    Ovl_finish(b, look, iconImage <> invalid)
    colors = Ovl_paint(look, b.accent)
    fontSize = OvDraw_textSize(look.fontSize * k)
    plan = { kind: "badge", badge: b, colors: colors, rail: rail, font: OvDraw_font(look.weight, fontSize), fontSize: fontSize, spacing: OvDraw_spacing(look, fontSize) }
    border = 0.0
    if colors.border <> "" then
        if Ovl_parseColor(colors.border).a > 0 then border = look.borderWidth * k
    end if
    iconSize = look.iconSize * k
    ' The lead: an uploaded icon image, a source chip, a wordmark, or a glyph.
    lead = { kind: "", w: 0.0, h: 0.0, txt: "", icon: "", color: "" }
    if iconImage <> invalid then
        lead = { kind: "image", image: iconImage, h: OvDraw_whole(iconSize), w: OvDraw_whole(iconSize * iconImage.GetWidth() / iconImage.GetHeight()), txt: "", icon: "", color: "" }
    else if b.chip <> "" then
        chipColor = b.accent
        if chipColor = "" then chipColor = "#FFFFFF"
        lead = { kind: "chip", txt: b.chip, color: Ovl_opaque(chipColor), ink: Ovl_readableOn(chipColor), icon: "" }
        lead.w = OvDraw_trackedWidth(plan.font, b.chip, plan.spacing) + 0.7 * fontSize
        lead.h = fontSize * 1.3
    else if b.markText <> "" then
        units = 10
        if b.icon = "atmos" then units = 9
        markFont = OvDraw_font(800, OvDraw_textSize(iconSize * units / 12))
        lead = { kind: "mark", txt: b.markText, font: markFont, w: OvDraw_textWidth(markFont, b.markText), h: iconSize, icon: "", color: "" }
    else if b.icon <> "" then
        lead = { kind: "glyph", icon: b.icon, w: OvDraw_whole(iconSize), h: OvDraw_whole(iconSize), txt: "", color: "" }
    end if
    txt = b.txt
    width = 0.0
    if txt <> "" then width = OvDraw_trackedWidth(plan.font, txt, plan.spacing)
    contentHeight = fontSize * 1.0
    if lead.h > contentHeight then contentHeight = lead.h
    gap = 0.0
    if lead.w > 0 and width > 0 then gap = look.iconGap * k
    padL = border
    padR = border
    if rail = "left" then padL = 0
    if rail = "right" then padR = 0
    if look.accentLeft > 0 and colors.accentLeft <> "" and rail <> "left" then padL = look.accentLeft * k
    padX = look.padX * k
    padY = look.padY * k
    ' An uploaded icon image is at most the badge's content width (Silo Android #882).
    if lead.kind = "image" then
        content = OvDraw_whole(maxWidth - padL - padR - 2 * padX)
        if content < 1 then content = 1
        if lead.w > content then lead.w = content
    end if
    w = padL + padX + lead.w + gap + width + padX + padR
    ' A bare score never truncates; any other label does, with an ellipsis.
    if w > maxWidth and width > 0 and not b.scoreOnly then
        txt = OvDraw_fit(plan.font, txt, width - (w - maxWidth), plan.spacing)
        width = 0
        if txt <> "" then width = OvDraw_trackedWidth(plan.font, txt, plan.spacing)
        w = maxWidth
    end if
    plan.Append({ lead: lead, txt: txt, textWidth: width, gap: gap, border: border, padL: padL, padX: padX, padY: padY, contentHeight: contentHeight, w: w, h: border + padY + contentHeight + padY + border })
    return plan
end function

' Draws plan at x, y from a sprite of it, drawn once per look, text and size: most cards share
' their badges ("4K", "BLURAY"), so a card's image is mostly copies of sprites.
sub OvDraw_paintBadge(c as object, plan as object, x as float, y as float)
    lead = plan.lead
    if lead = invalid then lead = { kind: "", txt: "", icon: "", w: 0, h: 0, color: "" }
    ref = ""
    valueRef = ""
    if plan.badge <> invalid then
        ref = plan.badge.image
        valueRef = plan.badge.valueImage
    end if
    key = FormatJson({ kind: plan.kind, w: OvDraw_whole(plan.w), h: OvDraw_whole(plan.h), rail: plan.rail, txt: plan.txt, font: plan.fontSize, spacing: plan.spacing, border: plan.border, padL: plan.padL, padX: plan.padX, padY: plan.padY, content: plan.contentHeight, gap: plan.gap, lead: [lead.kind, lead.txt, lead.icon, lead.w, lead.h, lead.color], colors: plan.colors, look: [c.look.id, c.look.weight, c.look.radius, c.look.accentLeft, c.look.boxShadow, c.look.textShadow, c.k], images: [ref, valueRef] })
    margin = OvDraw_whole(8 * c.k) + 2
    sprite = OvDraw_sprite(c, key, plan.w, plan.h, margin, plan)
    x0 = OvDraw_whole(x)
    y0 = OvDraw_whole(y)
    if sprite.bmp = invalid or sprite.maxX <= sprite.minX then return
    OvDraw_note(c, key + "@" + x0.ToStr() + "," + y0.ToStr(), y0 - margin + sprite.minY, sprite.maxY - sprite.minY)
    ' Copied onto the card's clear canvas, only the box the sprite drew in; blended over the
    ' band's scrim or with a drop shadow, which is dark.
    if c.look.band or c.look.boxShadow <> invalid then
        c.bmp.DrawObject(x0 - margin, y0 - margin, sprite.bmp)
    else
        region = CreateObject("roRegion", sprite.bmp, sprite.minX, sprite.minY, sprite.maxX - sprite.minX, sprite.maxY - sprite.minY)
        c.bmp.SetAlphaEnable(false)
        c.bmp.DrawObject(x0 - margin + sprite.minX, y0 - margin + sprite.minY, region)
        c.bmp.SetAlphaEnable(true)
    end if
    OvDraw_touch(c, x0 - margin + sprite.minX, y0 - margin + sprite.minY, sprite.maxX - sprite.minX, sprite.maxY - sprite.minY)
end sub

' The sprite for key: plan (or the episodes-left disc, for a plan with discLabel) drawn at margin
' in a bitmap margin px larger on every side, with the box it drew in, cached for the Task's life
' within a pixel budget.
function OvDraw_sprite(c as object, key as string, w as float, h as float, margin as integer, plan as object) as object
    if m.ovSprites = invalid then m.ovSprites = { sprites: {}, pixels: 0 }
    found = m.ovSprites.sprites[key]
    if found <> invalid then
        m.ovStats.spriteHits = m.ovStats.spriteHits + 1
        return found
    end if
    m.ovStats.spriteMisses = m.ovStats.spriteMisses + 1
    width = OvDraw_whole(w) + 2 * margin
    height = OvDraw_whole(h) + 2 * margin
    ' Past the budget the cache starts again; the cards' images keep what was drawn from it.
    if m.ovSprites.pixels + width * height > OvDraw_maxSpritePixels() then m.ovSprites = { sprites: {}, pixels: 0 }
    bmp = CreateObject("roBitmap", { width: width, height: height, AlphaEnable: true })
    ' Out of graphics memory: the badge draws nothing.
    if bmp = invalid then return { bmp: invalid, minX: 0, minY: 0, maxX: 0, maxY: 0 }
    bmp.Clear(0)
    sc = { bmp: bmp, width: width, height: height, minX: width, minY: height, maxX: 0, maxY: 0, radius: 0, look: c.look, k: c.k, images: c.images }
    if plan.DoesExist("discLabel") then
        OvDraw_discAt(sc, margin, margin, OvDraw_whole(w), OvDraw_whole(h), plan.discLabel)
    else
        OvDraw_paintBadgeAt(sc, plan, margin, margin)
    end if
    bmp.Finish()
    found = { bmp: bmp, minX: sc.minX, minY: sc.minY, maxX: sc.maxX, maxY: sc.maxY }
    m.ovSprites.sprites[key] = found
    m.ovSprites.pixels = m.ovSprites.pixels + width * height
    return found
end function

sub OvDraw_paintBadgeAt(c as object, plan as object, x as float, y as float)
    x0 = OvDraw_whole(x)
    y0 = OvDraw_whole(y)
    w = OvDraw_whole(plan.w)
    h = OvDraw_whole(plan.h)
    if plan.kind = "value" then
        c.bmp.SetAlphaEnable(false)
        OvDraw_image(c, plan.image, x0, y0, w, h, OvDraw_rgba(255, 255, 255, 1))
        c.bmp.SetAlphaEnable(true)
        return
    end if
    look = c.look
    colors = plan.colors
    radius = look.radius * c.k
    if look.radius < 0 or radius > h / 2 then radius = h / 2
    if radius > w / 2 then radius = w / 2
    radii = [radius, radius, radius, radius]
    if plan.rail = "left" then radii = [0, radius, radius, 0]
    if plan.rail = "right" then radii = [radius, 0, 0, radius]
    hasFill = false
    if colors.fill <> "" then hasFill = Ovl_parseColor(colors.fill).a > 0
    shadow = look.boxShadow
    ' roBitmap's blending multiplies a colour by its alpha over a clear pixel and never divides it
    ' back, so what lands on clear canvas is copied, not blended: the fill (unless a shadow is
    ' under it), and the border when there is no fill.
    shadowed = shadow <> invalid and hasFill
    if shadowed then OvDraw_boxShadow(c, x0, y0, w, h, radii, shadow)
    if hasFill then
        c.bmp.SetAlphaEnable(shadowed)
        OvDraw_shape(c, x0, y0, w, h, radii, OvDraw_colorOf(colors.fill), 0, plan.rail)
        c.bmp.SetAlphaEnable(true)
    end if
    if plan.border > 0 then
        c.bmp.SetAlphaEnable(hasFill)
        OvDraw_shape(c, x0, y0, w, h, radii, OvDraw_colorOf(colors.border), plan.border, plan.rail)
        c.bmp.SetAlphaEnable(true)
    end if
    if colors.accentLeft <> "" and look.accentLeft > 0 and plan.rail <> "left" then
        inset = OvDraw_whole(radius * 0.3)
        OvDraw_fillRect(c, x0, y0 + inset, OvDraw_whole(plan.padL), h - 2 * inset, OvDraw_colorOf(colors.accentLeft))
    end if
    cx = x0 + plan.padL + plan.padX
    cy = y0 + plan.border + plan.padY
    lead = plan.lead
    ly = cy + (plan.contentHeight - lead.h) / 2
    if lead.kind = "image" then
        OvDraw_image(c, lead.image, OvDraw_whole(cx), OvDraw_whole(ly), lead.w, lead.h, OvDraw_rgba(255, 255, 255, 1))
    else if lead.kind = "glyph" then
        OvDraw_image(c, OvDraw_glyph(lead.icon), OvDraw_whole(cx), OvDraw_whole(ly), lead.w, lead.h, OvDraw_colorOf(colors.ink))
    else if lead.kind = "chip" then
        chipHeight = OvDraw_whole(lead.h)
        chipRadius = plan.fontSize * 0.2
        OvDraw_shape(c, OvDraw_whole(cx), OvDraw_whole(ly), OvDraw_whole(lead.w), chipHeight, [chipRadius, chipRadius, chipRadius, chipRadius], OvDraw_colorOf(lead.color), 0, "")
        OvDraw_trackedText(c, lead.txt, cx + 0.35 * plan.fontSize, ly + (lead.h - plan.fontSize) / 2, plan.fontSize, plan.font, OvDraw_colorOf(lead.ink), plan.spacing)
    else if lead.kind = "mark" then
        OvDraw_text(c, lead.txt, cx, ly, lead.h, lead.font, OvDraw_colorOf(colors.ink))
    end if
    if plan.txt <> "" then
        textX = cx + lead.w + plan.gap
        textShadow = look.textShadow
        if textShadow <> invalid then
            offset = textShadow.y * c.k
            if offset < 1 then offset = 1
            shadowColor = OvDraw_colorOf(textShadow.color)
            shadowColor.a = shadowColor.a * 0.6
            OvDraw_trackedText(c, plan.txt, textX + textShadow.x * c.k, cy + offset, plan.contentHeight, plan.font, shadowColor, plan.spacing)
        end if
        OvDraw_trackedText(c, plan.txt, textX, cy, plan.contentHeight, plan.font, OvDraw_colorOf(colors.ink), plan.spacing)
    end if
end sub

' A soft drop shadow: the badge's shape in the shadow's colour, offset, in rings that widen by a
' pixel each across the blur, so the layers build to the shadow's opacity and fade at its edge.
sub OvDraw_boxShadow(c as object, x as integer, y as integer, w as integer, h as integer, radii as object, shadow as object)
    tint = OvDraw_colorOf(shadow.color)
    steps = OvDraw_whole(shadow.blur * c.k / 2)
    if steps < 1 then steps = 1
    layer = { r: tint.r, g: tint.g, b: tint.b, a: tint.a / (steps + 1) }
    sx = OvDraw_whole(shadow.x * c.k)
    sy = OvDraw_whole(shadow.y * c.k)
    for i = steps to 0 step -1
        grown = [radii[0] + i, radii[1] + i, radii[2] + i, radii[3] + i]
        OvDraw_shape(c, x + sx - i, y + sy - i, w + 2 * i, h + 2 * i, grown, layer, 0, "")
    end for
end sub

' ---------- The watch-status corner ----------

' The episodes left on a dark capsule the check's size, in its place (the web's CardWatchStatus,
' Silo Android #882): black 65% with a 1 px white 20% ring and the number in Bold at half its height
' (11 at the reference width), 0.4 em padded and 1 px bordered each side, never narrower than tall.
sub OvDraw_countDisc(c as object, spec as object)
    size = Int(spec.check.size)
    label = Int(spec.remaining).ToStr()
    numberFont = OvDraw_font(700, Int(size / 2))
    width = OvDraw_textWidth(numberFont, label) + 0.8 * Int(size / 2) + 2
    if width < size then width = size
    w = OvDraw_whole(width)
    if c.look = invalid then c.look = Ovl_presetLook("classic")
    if c.k = invalid then c.k = 1.0
    sprite = OvDraw_sprite(c, "disc|" + label + "|" + size.ToStr(), w, size, 0, { discLabel: label })
    if sprite.bmp = invalid then return
    x = c.width - Int(spec.check.inset) - w
    y = Int(spec.check.inset)
    OvDraw_note(c, "disc" + label + "@" + x.ToStr() + "," + y.ToStr(), y, size)
    ' Copied onto clear canvas, blended over the band's top scrim.
    c.bmp.SetAlphaEnable(c.look.band = true)
    c.bmp.DrawObject(x, y, sprite.bmp)
    c.bmp.SetAlphaEnable(true)
    OvDraw_touch(c, x, y, w, size)
end sub

sub OvDraw_discAt(c as object, x as integer, y as integer, w as integer, size as integer, label as string)
    numberFont = OvDraw_font(700, Int(size / 2))
    radii = [size / 2, size / 2, size / 2, size / 2]
    c.bmp.SetAlphaEnable(false)
    OvDraw_shape(c, x, y, w, size, radii, OvDraw_rgba(0, 0, 0, 0.65), 0, "")
    c.bmp.SetAlphaEnable(true)
    OvDraw_shape(c, x, y, w, size, radii, OvDraw_rgba(255, 255, 255, 0.2), 1, "")
    OvDraw_text(c, label, x + (w - OvDraw_textWidth(numberFont, label)) / 2, y + (size - Int(size / 2)) / 2, Int(size / 2), numberFont, OvDraw_rgba(255, 255, 255, 1))
end sub

' ---------- Primitives ----------

' A rounded rectangle at x, y, w x h with corner radii [top left, top right, bottom right, bottom
' left] (each side's two the same: a tab squares one side), filled (stroke 0) or as a border
' stroke px wide; a tab's border (rail "left" or "right") is open on that side. Each end is a cap
' bitmap drawn pixel by pixel once per radius, height, stroke and colour; the middle rectangles.
sub OvDraw_shape(c as object, x as integer, y as integer, w as integer, h as integer, radii as object, tint as object, stroke as float, rail as string)
    if w <= 0 or h <= 0 then return
    leftRadius = radii[0]
    rightRadius = radii[1]
    if leftRadius > w / 2 then leftRadius = w / 2
    if rightRadius > w / 2 then rightRadius = w / 2
    capL = OvDraw_capWidth(leftRadius, stroke, rail = "left")
    capR = OvDraw_capWidth(rightRadius, stroke, rail = "right")
    if capL + capR > w then
        capL = Int(w / 2)
        capR = w - capL
    end if
    if capL > 0 then OvDraw_capDraw(c, OvDraw_cap(leftRadius, h, stroke, tint, "left", rail = "left", capL), x, y)
    if capR > 0 then OvDraw_capDraw(c, OvDraw_cap(rightRadius, h, stroke, tint, "right", rail = "right", capR), x + w - capR, y)
    middle = w - capL - capR
    if middle <= 0 then return
    if stroke = 0 then
        OvDraw_fillRect(c, x + capL, y, middle, h, tint)
        return
    end if
    ' A border's middle: its top and bottom strokes, a fractional stroke's last row at its share.
    rows = Int(stroke)
    part = stroke - rows
    if rows > 0 then
        OvDraw_fillRect(c, x + capL, y, middle, rows, tint)
        OvDraw_fillRect(c, x + capL, y + h - rows, middle, rows, tint)
    end if
    if part > 0 then
        OvDraw_fillRect(c, x + capL, y + rows, middle, 1, OvDraw_scaled(tint, part))
        OvDraw_fillRect(c, x + capL, y + h - rows - 1, middle, 1, OvDraw_scaled(tint, part))
    end if
end sub

' The width of a shape's end: its radius, at least the stroke of a border, 0 for a square side.
function OvDraw_capWidth(radius as float, stroke as float, isOpen as boolean) as integer
    width = Int(radius + 0.999)
    if stroke > 0 and not isOpen and Int(stroke + 0.999) > width then width = Int(stroke + 0.999)
    return width
end function

sub OvDraw_capDraw(c as object, cap as object, x as integer, y as integer)
    c.bmp.DrawObject(x, y, cap)
    OvDraw_touch(c, x, y, cap.GetWidth(), cap.GetHeight())
end sub

' One end of a shape, width x h: its corners' coverage of radius and, for a border, the stroke
' down that side (none when open), cached.
function OvDraw_cap(radius as float, h as integer, stroke as float, tint as object, side as string, isOpen as boolean, width as integer) as object
    if m.ovCaps = invalid then m.ovCaps = {}
    key = side + "|" + Str(radius).Trim() + "|" + h.ToStr() + "|" + Str(stroke).Trim() + "|" + isOpen.ToStr() + "|" + width.ToStr() + "|" + OvDraw_packed(tint).ToStr()
    found = m.ovCaps[key]
    if found <> invalid then return found
    ' Each pixel is set once, copied: a blend would darken the colour.
    bmp = CreateObject("roBitmap", { width: width, height: h, AlphaEnable: false })
    bmp.Clear(0)
    cap = { bmp: bmp, width: width, height: h, minX: width, minY: h, maxX: 0, maxY: 0 }
    ' The cap is the shape's end in a box twice its width: a shape that long has this end and its
    ' mirror.
    span = 2 * width
    radii = [radius, radius, radius, radius]
    flush = ""
    if isOpen then flush = side
    for j = 0 to h - 1
        for i = 0 to width - 1
            px = i + 0.5
            if side = "right" then px = width + i + 0.5
            OvDraw_plot(cap, i, j, OvDraw_cover(px, j + 0.5, span, h, radii, stroke, flush), tint)
        end for
    end for
    bmp.Finish()
    m.ovCaps[key] = bmp
    return bmp
end function

' How much of the pixel centred at px, py (in the shape's box) the shape covers, 0 to 1.
function OvDraw_cover(px as float, py as float, w as integer, h as integer, radii as object, stroke as float, rail as string) as float
    outer = OvDraw_clamp(0.5 - OvDraw_distance(px, py, 0, 0, w, h, radii))
    if stroke = 0 or outer = 0 then return outer
    x0 = stroke
    x1 = w - stroke
    if rail = "left" then x0 = -stroke
    if rail = "right" then x1 = w + stroke
    inner = [radii[0] - stroke, radii[1] - stroke, radii[2] - stroke, radii[3] - stroke]
    for i = 0 to 3
        if inner[i] < 0 then inner[i] = 0
    end for
    return OvDraw_clamp(outer - OvDraw_clamp(0.5 - OvDraw_distance(px, py, x0, stroke, x1, h - stroke, inner)))
end function

' The signed distance from px, py to the rectangle x0, y0, x1, y1 with corner radii, negative inside.
function OvDraw_distance(px as float, py as float, x0 as float, y0 as float, x1 as float, y1 as float, radii as object) as float
    cx = (x0 + x1) / 2
    cy = (y0 + y1) / 2
    if px < cx then
        r = radii[3]
        if py < cy then r = radii[0]
    else
        r = radii[2]
        if py < cy then r = radii[1]
    end if
    qx = Abs(px - cx) - ((x1 - x0) / 2 - r)
    qy = Abs(py - cy) - ((y1 - y0) / 2 - r)
    mx = qx
    if mx < 0 then mx = 0
    my = qy
    if my < 0 then my = 0
    inside = qx
    if qy > inside then inside = qy
    if inside > 0 then inside = 0
    return Sqr(mx * mx + my * my) + inside - r
end function

sub OvDraw_plot(c as object, x as integer, y as integer, amount as float, tint as object)
    if amount <= 0 then return
    OvDraw_fillRect(c, x, y, 1, 1, OvDraw_scaled(tint, amount))
end sub

sub OvDraw_fillRect(c as object, x as integer, y as integer, w as integer, h as integer, tint as object)
    if w <= 0 or h <= 0 or tint.a <= 0 then return
    if x < 0 then
        w = w + x
        x = 0
    end if
    if y < 0 then
        h = h + y
        y = 0
    end if
    if x + w > c.width then w = c.width - x
    if y + h > c.height then h = c.height - y
    if w <= 0 or h <= 0 then return
    c.bmp.DrawRect(x, y, w, h, OvDraw_packed(tint))
    OvDraw_touch(c, x, y, w, h)
end sub

' Text at x, y in a line height px tall (CSS's leading-none: ascent and descent centred on it).
sub OvDraw_text(c as object, value as string, x as float, y as float, height as float, face as object, tint as object)
    if face = invalid then return
    ascent = face.GetAscent()
    descent = face.GetDescent()
    y0 = OvDraw_whole(y + (height - ascent - descent) / 2)
    c.bmp.DrawText(value, OvDraw_whole(x), y0, OvDraw_packed(tint), face)
    OvDraw_touch(c, OvDraw_whole(x), y0, OvDraw_whole(OvDraw_textWidth(face, value)) + 1, ascent + descent)
end sub

' An image scaled to w x h; tint multiplies its colour. Scaled straight from the source: a bitmap
' that received a scaled draw drew nothing over a translucent fill (Silo's Roku app, Ultra 4850X).
sub OvDraw_image(c as object, src as dynamic, x as integer, y as integer, w as integer, h as integer, tint as object)
    if src = invalid or w <= 0 or h <= 0 then return
    c.bmp.DrawScaledObject(x, y, w / src.GetWidth(), h / src.GetHeight(), src, OvDraw_packed(tint))
    OvDraw_touch(c, x, y, w, h)
end sub

sub OvDraw_touch(c as object, x as integer, y as integer, w as integer, h as integer)
    ' A card's image keeps a box per half; a sprite's or cap's bitmap one.
    area = c
    if c.groups <> invalid then area = OvDraw_groupAt(c, y, h)
    if x < area.minX then area.minX = x
    if y < area.minY then area.minY = y
    if x + w > area.maxX then area.maxX = x + w
    if y + h > area.maxY then area.maxY = y + h
    if area.minX < 0 then area.minX = 0
    if area.minY < 0 then area.minY = 0
    if area.maxX > c.width then area.maxX = c.width
    if area.maxY > c.height then area.maxY = c.height
end sub

' ---------- Text ----------

' The packaged Inter at weight (400 to 800; 800 draws in Bold, as Silo's Roku app does) and size
' px. Each weight's file is registered in a registry of its own, and its family is the one the
' file added, so the name the file carries does not matter.
function OvDraw_font(weight as integer, size as integer) as dynamic
    if m.ovFonts = invalid then
        m.ovFonts = {}
        m.ovFaces = {}
    end if
    file = "regular"
    if weight >= 500 then file = "medium"
    if weight >= 600 then file = "semibold"
    if weight >= 700 then file = "bold"
    key = file + size.ToStr()
    found = m.ovFonts[key]
    if found <> invalid then return found
    face = m.ovFaces[file]
    if face = invalid then
        reg = CreateObject("roFontRegistry")
        before = {}
        for each f in reg.GetFamilies()
            before[f] = true
        end for
        reg.Register("pkg:/fonts/Inter-" + file + ".otf")
        family = ""
        for each f in reg.GetFamilies()
            if not before.DoesExist(f) then family = f
        end for
        face = { reg: reg, family: family }
        m.ovFaces[file] = face
    end if
    if face.family <> "" then
        found = face.reg.GetFont(face.family, size, file = "bold", false)
    else
        found = face.reg.GetDefaultFont(size, file = "bold", false)
    end if
    m.ovFonts[key] = found
    return found
end function

function OvDraw_textWidth(face as dynamic, value as string) as float
    if value = "" or face = invalid then return 0
    return face.GetOneLineWidth(value, 100000)
end function

' The letter spacing look's text takes at size px (the web's tracking-wide / tracking-widest), or 0
' when it would round away: under a third of a pixel each letter is drawn as one string.
function OvDraw_spacing(look as object, size as integer) as float
    t = look.tracking
    if t = invalid then return 0.0
    spacing = t * size
    if spacing < 0.34 then return 0.0
    return spacing
end function

' value's width with spacing after every letter, as CSS letter-spacing measures it.
function OvDraw_trackedWidth(face as dynamic, value as string, spacing as float) as float
    if value = "" then return 0
    return OvDraw_textWidth(face, value) + spacing * Len(value)
end function

' Text as OvDraw_text, spacing px after each letter: each letter at the width of the text before it
' (keeping the face's own advances) plus the spacing so far.
sub OvDraw_trackedText(c as object, value as string, x as float, y as float, height as float, face as object, tint as object, spacing as float)
    if spacing <= 0 or Len(value) < 2 then
        OvDraw_text(c, value, x, y, height, face, tint)
        return
    end if
    for i = 1 to Len(value)
        ch = Mid(value, i, 1)
        if ch <> " " then OvDraw_text(c, ch, x + OvDraw_textWidth(face, Left(value, i - 1)) + (i - 1) * spacing, y, height, face, tint)
    end for
end sub

' value cut to fit width with an ellipsis, "" when not even that fits.
function OvDraw_fit(face as object, value as string, width as float, spacing as float) as string
    if OvDraw_trackedWidth(face, value, spacing) <= width then return value
    for count = Len(value) - 1 to 1 step -1
        cut = Left(value, count).Trim() + "…"
        if OvDraw_trackedWidth(face, cut, spacing) <= width then return cut
    end for
    return ""
end function

' A text size in whole px, at least 6.
function OvDraw_textSize(value as float) as integer
    size = Int(value + 0.5)
    if size < 6 then size = 6
    return size
end function

' ---------- Images ----------

' A badge glyph (images/badges/<icon>.png, 48 px white, scripts/badge-art.py), loaded once.
function OvDraw_glyph(icon as string) as dynamic
    if m.ovGlyphs = invalid then m.ovGlyphs = {}
    name = icon.Replace("-", "_")
    found = m.ovGlyphs[name]
    if found = invalid then
        found = CreateObject("roBitmap", "pkg:/images/badges/" + name + ".png")
        if found = invalid then found = false
        m.ovGlyphs[name] = found
    end if
    if Type(found) = "roBitmap" then return found
    return invalid
end function

' An administrator's uploaded image, which ShellScreen downloaded before the document applied and
' the Task copied to OvDraw_imagePath, or invalid when it did not load: the badge then draws what
' it would without it.
function OvDraw_uploaded(c as object, ref as string) as dynamic
    if m.ovImages = invalid then m.ovImages = {}
    if m.ovImages.DoesExist(ref) then
        found = m.ovImages[ref]
        if Type(found) = "roBitmap" then return found
        return invalid
    end if
    m.ovImages[ref] = false
    if not c.images.DoesExist(ref) then return invalid
    bitmap = CreateObject("roBitmap", OvDraw_imagePath(ref))
    if bitmap = invalid then
        Diag_log("[siku-overlays] image unreadable; its badge draws without it")
        return invalid
    end if
    if bitmap.GetWidth() <= 0 or bitmap.GetHeight() <= 0 then return invalid
    m.ovImages[ref] = bitmap
    return bitmap
end function

' Where an uploaded image is kept once downloaded (CardOverlayState.brs, OverlayArtTask).
function OvDraw_imagePath(ref as string) as string
    return OvDraw_dir() + "image-" + ref
end function

' ---------- Colours ----------

function OvDraw_colorOf(hex as string) as object
    p = Ovl_parseColor(hex)
    return { r: Int(p.r * 255 + 0.5), g: Int(p.g * 255 + 0.5), b: Int(p.b * 255 + 0.5), a: p.a }
end function

function OvDraw_rgba(r as integer, g as integer, b as integer, a as float) as object
    return { r: r, g: g, b: b, a: a }
end function

function OvDraw_scaled(tint as object, amount as float) as object
    return { r: tint.r, g: tint.g, b: tint.b, a: tint.a * amount }
end function

' A colour as roBitmap's &hRRGGBBAA integer.
function OvDraw_packed(tint as object) as integer
    alpha = Int(tint.a * 255 + 0.5)
    if alpha > 255 then alpha = 255
    if alpha < 0 then alpha = 0
    return (tint.r << 24) or (tint.g << 16) or (tint.b << 8) or alpha
end function

function OvDraw_clamp(v as float) as float
    if v < 0 then return 0
    if v > 1 then return 1
    return v
end function

function OvDraw_whole(v as float) as integer
    return Int(v + 0.5)
end function

' Two polynomial hashes of text, each modulo a 31-bit prime (Content_hash, which this Task does
' not include).
function OvDraw_hash(text as string) as string
    a = 0&
    b = 0&
    for i = 1 to Len(text)
        ch = Asc(Mid(text, i, 1))
        a = (a * 131& + ch) mod 2147483647&
        b = (b * 257& + ch) mod 2147483629&
    end for
    return a.ToStr() + "z" + b.ToStr()
end function
