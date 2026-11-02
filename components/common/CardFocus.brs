' SPDX-License-Identifier: AGPL-3.0-or-later
'
' The focused-card look shared by every card (Silo Android TV #781, tvOS TVCardOutlineButtonStyle):
' a 5% lift, a 4 px white outline at 70% inside the card's edge (Android's 2 dp) that scales with
' the card, and a black drop shadow. The lift, by whole px on each side about the card's top-left
' corner, is adapted from Silo-Server/silo-roku, AGPL-3.0 (components/views/CatalogCard.bs,
' commit 68f7287): scaled about its centre, a card's edges landed on fractional pixels and Roku drew
' the art a pixel past its rounded frame. Android keeps cards still under reduced motion; Roku
' exposes no such setting (roDeviceInfo has none), so cards always lift.
' The card's outline (r16_ring4 9-patch or card_ring_circle) is a Poster, never a MaskGroup effect,
' so it shows on Rokus without OpenGL too.

' A focused card grows this much (CardOutline.FocusedScale 1.05).
function CardFocus_scale() as float
    return 1.05
end function

' Whole px the card grows on each side when focused, [x, y]: 2.5% of each side, rounded.
function CardFocus_lift(w as float, h as float) as object
    return [Int(w * 0.025 + 0.5), Int(h * 0.025 + 0.5)]
end function

' The card group's transform at focus p (0..1): scale about its top-left corner, moved back by
' the lift so the card grows evenly, every edge on a whole px once p = 1. base is the group's
' resting translation. { scale, translation }.
function CardFocus_transform(w as float, h as float, p as float, base as object) as object
    if w <= 0 or h <= 0 or p <= 0 then return { scale: [1.0, 1.0], translation: [base[0], base[1]] }
    lift = CardFocus_lift(w, h)
    dx = lift[0] * p
    dy = lift[1] * p
    return { scale: [(w + 2 * dx) / w, (h + 2 * dy) / h], translation: [base[0] - dx, base[1] - dy] }
end function

' Where a point (x, y) of the card (in its resting coordinates) is drawn at focus p, relative to
' the card's resting origin: for overlays kept outside the scaled group (calendar badges).
function CardFocus_point(x as float, y as float, w as float, h as float, p as float) as object
    t = CardFocus_transform(w, h, p, [0, 0])
    return [t.translation[0] + x * t.scale[0], t.translation[1] + y * t.scale[1]]
end function

' Applies the look to a card group at focus p. outline and shadow are Posters inside card (they
' scale with it); outlined keeps the outline at rest (the series page's current episode); lifted
' false keeps the size (the current episode while focus is elsewhere). w x h is the card's art.
sub CardFocus_apply(card as object, outline as object, shadow as object, w as float, h as float, p as float, base as object, outlined as boolean)
    t = CardFocus_transform(w, h, p, base)
    card.scaleRotateCenter = [0, 0]
    card.scale = t.scale
    card.translation = t.translation
    o = p
    if outlined then o = 1.0
    outline.opacity = o
    outline.visible = o > 0
    if shadow <> invalid then
        shadow.opacity = p
        shadow.visible = p > 0
    end if
end sub

' Sizes the shadow Poster for a card of w x h: 24 px of blur round the card, 10 px lower (the
' 9-patch's own padding, scripts/make_ui.py card_shadow).
sub CardFocus_layoutShadow(shadow as object, w as float, h as float)
    shadow.width = w + 48
    shadow.height = h + 48
    shadow.translation = [-24, -14]
end sub
