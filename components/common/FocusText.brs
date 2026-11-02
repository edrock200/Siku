' SPDX-License-Identifier: AGPL-3.0-or-later
'
' Focused text drawn at its own size, not resampled. Adapted from Silo-Server/silo-roku, AGPL-3.0
' (components/theme/helpers.bs theme.placeUnscaled and theme.font(style, scale), commits d776b67
' and 3fd96f1): Roku resamples a scaled Label's glyphs, which smears Inter's hinted stems, so when a
' focus highlight scales the Group that holds a Label, the Label takes the inverse scale about the
' same point, lands on whole pixels, grows its box by the scale, and is set in a font that size
' times the scale, rounded DOWN (rounded to nearest, "Enter server address" at 29 x 1.06 = 31 px
' ellipsized in its box on a TCL Roku).

' The size a label of `size` px is set at under a highlight of `scale`: rounded down (with a hair
' of slack so 25 x 1.04, 25.999998 in single precision, still gives 26).
function FocusText_size(size as integer, scale as float) as integer
    return Int(size * scale + 0.001)
end function

' Records a label's resting box and font once (call after every layout of the label): returns the
' `rest` record FocusText_place takes.
function FocusText_rest(label as object) as object
    t = label.translation
    return { rect: [t[0], t[1], label.width, label.height], font: label.font }
end function

' A Font like `font` at `size` px, made once per component (cache: an AA kept in m).
function FocusText_font(font as object, size as integer, cache as object) as object
    if font = invalid then return invalid
    u = font.uri
    if Type(u) <> "roString" and Type(u) <> "String" then return font
    if u = "" or size <= 0 then return font
    key = u + "@" + size.ToStr()
    f = cache[key]
    if f = invalid then
        f = CreateObject("roSGNode", "Font")
        f.uri = u
        f.size = size
        cache[key] = f
    end if
    return f
end function

' Places `label`, a child of a Group drawn at scale [sx, sy] about `center` (the Group's
' scaleRotateCenter, in the Group's coordinates), at its own size: at scale 1 it goes back to
' `rest` (FocusText_rest). Call it when the scale settles; mid-animation leave it at rest.
sub FocusText_place(label as object, rest as object, center as object, sx as float, sy as float, cache as object)
    rb = rest.rect
    if Abs(sx - 1) < 0.0005 and Abs(sy - 1) < 0.0005 then
        label.setFields({ translation: [rb[0], rb[1]], width: rb[2], height: rb[3], scale: [1.0, 1.0], scaleRotateCenter: [0.0, 0.0] })
        if rest.font <> invalid then label.font = rest.font
        return
    end if
    x = Int(center[0] + sx * (rb[0] - center[0]) + 0.5)
    y = Int(center[1] + sy * (rb[1] - center[1]) + 0.5)
    s = sx
    if sy < s then s = sy
    if rest.font <> invalid then label.font = FocusText_font(rest.font, FocusText_size(rest.font.size, s), cache)
    label.setFields({ translation: [x, y], width: rb[2] * sx, height: rb[3] * sy, scaleRotateCenter: [center[0] - x, center[1] - y], scale: [1 / sx, 1 / sy] })
end sub
