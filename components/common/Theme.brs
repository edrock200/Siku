' Design tokens ported from the Silo Android TV theme (docs/design-spec.md).
' Geometry: 1 dp = 2 px at 1080p. Text: 1 sp = 1.72 px (Android TV applies a 0.86 font scale).
' SPDX-License-Identifier: AGPL-3.0-or-later

function Theme() as object
    if m.siku_theme <> invalid then return m.siku_theme
    t = {
        ' Colors are 0xRRGGBBAA, as SceneGraph expects.
        colors: {
            background: "0x000000FF"
            surface: "0x0A0A0AFF"
            surfaceVariant: "0x0E0F12FF"
            surfaceElevated: "0x15171CFF"
            ink: "0xEDEDEDFF"           ' primary text and focused fill
            inkSecondary: "0xEDEDEDBF"  ' 75%
            inkMuted: "0xEDEDED9E"      ' 62% inactive tab / body on marquee
            inkTertiary: "0xEDEDED66"   ' 40%
            inkFaint: "0xEDEDED61"      ' 38% section headers
            onInk: "0x000000FF"         ' text on a focused (inverted) control
            selectedFill: "0xFFFFFF24"  ' 14%
            selectedBorder: "0xFFFFFF1A" ' 10%
            glass: "0xFFFFFF14"         ' 8%
            hairline: "0xFFFFFF24"      ' 14%
            outline: "0xFFFFFF1F"       ' 12%
            glow: "0xFFFFFF47"          ' 28%
            progressTrack: "0xFFFFFF33" ' 20%
            progressFill: "0xEDEDEDFF"
            scrim: "0x000000F2"
            panelTop: "0x23252CEB"
            panelBottom: "0x141519F2"
            card: "0x1F1F1FB8"          ' marquee glass card, 72%
            error: "0xFF6961FF"
            success: "0x34C759FF"
            warning: "0xF4C869FF"
            brandBlue: "0x0034FBFF"
            brandRed: "0xF50B4FFF"
            brandOrange: "0xFD7403FF"
        }
        fonts: {
            regular: "pkg:/fonts/Inter-regular.otf"
            medium: "pkg:/fonts/Inter-medium.otf"
            semibold: "pkg:/fonts/Inter-semibold.otf"
            bold: "pkg:/fonts/Inter-bold.otf"
            black: "pkg:/fonts/Inter-black.otf"
        }
        ' Layout, in 1080p pixels.
        safeX: 88
        safeY: 48
        barTop: 56
        barHeight: 64
        contentTop: 188
        railGap: 40
        posterW: 176
        posterH: 264
        landscapeW: 360
        landscapeH: 203
        gridPosterW: 236
        gridPosterH: 354
        cardRadius: 16
        focusScale: 1.10
        animMs: 200
    }
    m.siku_theme = t
    return t
end function

' Returns a Font node for one of the Theme().fonts weights at a size in pixels.
function ThemeFont(weight as string, sizePx as integer) as object
    f = CreateObject("roSGNode", "Font")
    f.uri = Theme().fonts[weight]
    f.size = sizePx
    return f
end function

' Converts Android sp to 1080p pixels (with the TV 0.86 font scale).
function Sp(value as float) as integer
    return Int(value * 1.72 + 0.5)
end function
