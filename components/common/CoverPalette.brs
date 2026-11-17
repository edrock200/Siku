' Colours from an audiobook cover for the player's ambient backdrop and accent (Silo Android #975,
' after Apple's AudioCoverPalette). Android samples a 64 px decode of the cover; a Roku cannot read a
' Poster's pixels on the render thread, so Siku decodes the cover's thumbhash (`poster_thumbhash`,
' already a soft few-pixel picture) into a 12x12 grid and samples that the same way: the four
' quadrant averages tint the corners, the whole average the middle, and the most vivid quadrant
' becomes the accent for the progress bar and the current chapter line.
'
' Pure (no SceneGraph, no Utils.brs): host-tested in tests/test_cover_palette.py against the
' reference thumbhash decoder. Colours come back as Roku colour strings "0xRRGGBBFF".
' SPDX-License-Identifier: AGPL-3.0-or-later

' { ok, corners: [top-left, top-right, bottom-left, bottom-right], center, accent }. ok is false
' (with the neutral near-black palette and `fallbackAccent`) when the hash is missing or unreadable.
function CoverPalette_fromThumbhash(hash as dynamic, fallbackAccent = "0xEDEDEDFF" as string) as object
    px = CoverPalette_decode(hash, 12, 12)
    if px = invalid then return CoverPalette_fallback(fallbackAccent)
    return CoverPalette_sample(px, 12, 12, fallbackAccent)
end function

' Near-black with a faint cool cast: shown until a cover is known, or for a cover without colours.
function CoverPalette_fallback(accent as string) as object
    return {
        ok: false,
        corners: [CoverPalette_hex([0.10, 0.11, 0.15]), CoverPalette_hex([0.07, 0.08, 0.12]), CoverPalette_hex([0.06, 0.06, 0.10]), CoverPalette_hex([0.09, 0.09, 0.13])],
        center: CoverPalette_hex([0.07, 0.08, 0.11]),
        accent: accent
    }
end function

' Samples a decoded w x h grid ([[r, g, b], ...] row by row, 0..1) like Android's samplePalette.
function CoverPalette_sample(px as object, w as integer, h as integer, fallbackAccent as string) as object
    if w < 2 or h < 2 or px.Count() < w * h then return CoverPalette_fallback(fallbackAccent)
    hw = Int(w / 2)
    hh = Int(h / 2)
    quads = [CoverPalette_average(px, w, 0, 0, hw, hh), CoverPalette_average(px, w, hw, 0, w, hh), CoverPalette_average(px, w, 0, hh, hw, h), CoverPalette_average(px, w, hw, hh, w, h)]
    whole = CoverPalette_average(px, w, 0, 0, w, h)
    corners = []
    best = invalid
    bestV = -1.0
    for each q in quads
        corners.Push(CoverPalette_hex(CoverPalette_dimmed(q)))
        v = CoverPalette_vividness(q)
        ' The first of equally vivid quadrants wins (Kotlin maxByOrNull).
        if v > bestV then
            bestV = v
            best = q
        end if
    end for
    if best = invalid then best = whole
    accent = fallbackAccent
    boosted = CoverPalette_boosted(best)
    if boosted <> invalid then accent = CoverPalette_hex(boosted)
    return { ok: true, corners: corners, center: CoverPalette_hex(CoverPalette_dimmed(whole)), accent: accent }
end function

function CoverPalette_average(px as object, stride as integer, x0 as integer, y0 as integer, x1 as integer, y1 as integer) as object
    r = 0.0
    g = 0.0
    b = 0.0
    n = 0
    for y = y0 to y1 - 1
        for x = x0 to x1 - 1
            c = px[y * stride + x]
            r = r + c[0]
            g = g + c[1]
            b = b + c[2]
            n = n + 1
        end for
    end for
    if n = 0 then return [0.0, 0.0, 0.0]
    return [r / n, g / n, b / n]
end function

function CoverPalette_max(c as object) as float
    m = c[0]
    if c[1] > m then m = c[1]
    if c[2] > m then m = c[2]
    return m
end function

function CoverPalette_min(c as object) as float
    m = c[0]
    if c[1] < m then m = c[1]
    if c[2] < m then m = c[2]
    return m
end function

function CoverPalette_saturation(c as object) as float
    mx = CoverPalette_max(c)
    if mx <= 0 then return 0.0
    return (mx - CoverPalette_min(c)) / mx
end function

' Saturation weighted by brightness, so neither dark mud nor washed-out highlights win.
function CoverPalette_vividness(c as object) as float
    return CoverPalette_saturation(c) * (0.35 + 0.65 * CoverPalette_max(c))
end function

' Pulled toward the near-black page, with a floor so dark covers still read as tinted.
function CoverPalette_dimmed(c as object) as object
    target = 0.16
    lum = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    if lum <= 0.001 then return [0.05, 0.05, 0.07]
    if lum > target then
        scale = target / lum
    else
        floorLum = lum
        if floorLum < 0.04 then floorLum = 0.04
        scale = target / floorLum
        if scale > 1.6 then scale = 1.6
    end if
    out = []
    for k = 0 to 2
        v = c[k] * scale
        if v > 1 then v = 1.0
        out.Push(v)
    end for
    return out
end function

' Lifted into a control tint bright enough for dark glyphs on top; a near-grey sample keeps a light
' neutral instead of inventing a hue; invalid only for a black sample. Android's black is 0.001; a
' thumbhash quantises brightness in steps of 1/63, so anything below 0.02 is that step's noise (a black
' cover decodes to a faint red) and counts as black here.
function CoverPalette_boosted(c as object) as dynamic
    mx = CoverPalette_max(c)
    if mx <= 0.02 then return invalid
    if CoverPalette_saturation(c) <= 0.12 then return [0.93, 0.93, 0.93]
    scale = 0.92 / mx
    out = []
    for k = 0 to 2
        v = c[k] * scale
        if v > 1 then v = 1.0
        out.Push(v + (1 - v) * 0.18)
    end for
    return out
end function

function CoverPalette_hex(c as object) as string
    digits = "0123456789ABCDEF"
    s = "0x"
    for k = 0 to 2
        v = Int(c[k] * 255 + 0.5)
        if v < 0 then v = 0
        if v > 255 then v = 255
        s = s + Mid(digits, Int(v / 16) + 1, 1) + Mid(digits, (v mod 16) + 1, 1)
    end for
    return s + "FF"
end function

' Decodes a base64 (or base64url) thumbhash into a w x h grid of [r, g, b] (0..1, alpha ignored),
' row by row; invalid when the hash is missing, short or not base64. The DCT follows the reference
' thumbHashToRGBA (Evan Wallace, MIT) for any fixed size.
function CoverPalette_decode(hash as dynamic, w as integer, h as integer) as dynamic
    if hash = invalid then return invalid
    if Type(hash) <> "roString" and Type(hash) <> "String" then return invalid
    s = hash.Trim()
    if Len(s) < 8 then return invalid
    s = s.Replace("-", "+").Replace("_", "/")
    while Len(s) mod 4 <> 0
        s = s + "="
    end while
    ba = CreateObject("roByteArray")
    ' A malformed string decodes to nothing (or too few bytes), which reads as no hash.
    ba.FromBase64String(s)
    if ba.Count() < 6 then return invalid
    h24 = ba[0] + ba[1] * 256 + ba[2] * 65536
    h16 = ba[3] + ba[4] * 256
    lDc = (h24 and 63) / 63
    pDc = (Int(h24 / 64) and 63) / 31.5 - 1
    qDc = (Int(h24 / 4096) and 63) / 31.5 - 1
    lScale = (Int(h24 / 262144) and 31) / 31
    hasAlpha = Int(h24 / 8388608) = 1
    pScale = (Int(h16 / 8) and 63) / 63
    qScale = (Int(h16 / 512) and 63) / 63
    landscape = Int(h16 / 32768) = 1
    lCount = h16 and 7
    if landscape then
        lx = 7
        if hasAlpha then lx = 5
        ly = lCount
    else
        lx = lCount
        ly = 7
        if hasAlpha then ly = 5
    end if
    if lx < 3 then lx = 3
    if ly < 3 then ly = 3
    st = { bytes: ba, idx: 0, start: 5, bad: false }
    if hasAlpha then st.start = 6
    lAc = CoverPalette_channel(st, lx, ly, lScale)
    pAc = CoverPalette_channel(st, 3, 3, pScale * 1.25)
    qAc = CoverPalette_channel(st, 3, 3, qScale * 1.25)
    if st.bad then return invalid

    pi = 3.14159265358979
    nx = lx
    if nx < 3 then nx = 3
    ny = ly
    if ny < 3 then ny = 3
    out = []
    for y = 0 to h - 1
        fy = []
        for cy = 0 to ny - 1
            fy.Push(Cos(pi / h * (y + 0.5) * cy))
        end for
        for x = 0 to w - 1
            fx = []
            for cx = 0 to nx - 1
                fx.Push(Cos(pi / w * (x + 0.5) * cx))
            end for
            l = lDc
            p = pDc
            q = qDc
            j = 0
            for cy = 0 to ly - 1
                cx = 1
                if cy > 0 then cx = 0
                while cx * ly < lx * (ly - cy)
                    l = l + lAc[j] * fx[cx] * fy[cy] * 2
                    j = j + 1
                    cx = cx + 1
                end while
            end for
            j = 0
            for cy = 0 to 2
                cx = 1
                if cy > 0 then cx = 0
                while cx < 3 - cy
                    f = fx[cx] * fy[cy] * 2
                    p = p + pAc[j] * f
                    q = q + qAc[j] * f
                    j = j + 1
                    cx = cx + 1
                end while
            end for
            b = l - 2 / 3 * p
            r = (3 * l - b + q) / 2
            g = r - q
            out.Push([CoverPalette_unit(r), CoverPalette_unit(g), CoverPalette_unit(b)])
        end for
    end for
    return out
end function

function CoverPalette_unit(v as float) as float
    if v < 0 then return 0.0
    if v > 1 then return 1.0
    return v
end function

' One channel's AC coefficients (4 bits each, low nibble first); st.bad when the hash ends early.
function CoverPalette_channel(st as object, nx as integer, ny as integer, scale as float) as object
    ac = []
    for cy = 0 to ny - 1
        cx = 1
        if cy > 0 then cx = 0
        while cx * ny < nx * (ny - cy)
            k = st.start + Int(st.idx / 2)
            if k >= st.bytes.Count() then
                st.bad = true
                return ac
            end if
            byte = st.bytes[k]
            if (st.idx and 1) = 1 then nib = Int(byte / 16) and 15 else nib = byte and 15
            ac.Push((nib / 7.5 - 1) * scale)
            st.idx = st.idx + 1
            cx = cx + 1
        end while
    end for
    return ac
end function
