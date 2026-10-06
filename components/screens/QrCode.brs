' QR code encoder (ISO/IEC 18004) in plain BrightScript, used by the sign-in screen
' to show verification_uri_complete. Byte mode (UTF-8), error correction M (L when
' M can't fit), versions 1–40 chosen automatically, all eight masks tried with the
' standard penalty score, Reed–Solomon over GF(256) with polynomial 0x11D.
' Based on the structure of Project Nayuki's reference QR generator (MIT).
'
'   qr = QrCode_encode("https://example.com/activate?code=1234")
'   qr.size     modules per side (no quiet zone)
'   qr.modules  flat array, row-major, 1 = dark
'   rects = QrCode_rects(qr)   ' [{x, y, w, h}] dark rectangles in module units
'
' BrightScript has no XOR operator, so QrCode_xor builds it from and/or/not.
' SPDX-License-Identifier: AGPL-3.0-or-later

' Returns {size, modules, version, ecl, mask} or invalid when the text is too long.
function QrCode_encode(text as string) as dynamic
    bytes = QrCode_utf8(text)
    count = bytes.Count()

    ' Pick the smallest version that fits at level M, then at L.
    version = 0
    ecl = ""
    for each level in ["M", "L"]
        for v = 1 to 40
            capacityBits = QrCode_numDataCodewords(v, level) * 8
            ccBits = 8
            if v >= 10 then ccBits = 16
            if count < 65536 and (ccBits = 16 or count < 256) then
                usedBits = 4 + ccBits + count * 8
                if usedBits <= capacityBits then
                    version = v
                    ecl = level
                    exit for
                end if
            end if
        end for
        if version > 0 then exit for
    end for
    if version = 0 then return invalid

    ' ---- Bit stream: mode, count, payload, terminator, padding ----
    bits = []
    QrCode_appendBits(bits, 4, 4) ' byte mode 0100
    ccBits = 8
    if version >= 10 then ccBits = 16
    QrCode_appendBits(bits, count, ccBits)
    for each b in bytes
        QrCode_appendBits(bits, b, 8)
    end for
    capacityBits = QrCode_numDataCodewords(version, ecl) * 8
    terminator = capacityBits - bits.Count()
    if terminator > 4 then terminator = 4
    QrCode_appendBits(bits, 0, terminator)
    while (bits.Count() mod 8) <> 0
        bits.Push(0)
    end while
    padByte = &hEC
    while bits.Count() < capacityBits
        QrCode_appendBits(bits, padByte, 8)
        if padByte = &hEC then padByte = &h11 else padByte = &hEC
    end while

    dataCodewords = []
    i = 0
    while i < bits.Count()
        cw = 0
        for j = 0 to 7
            cw = cw * 2 + bits[i + j]
        end for
        dataCodewords.Push(cw)
        i = i + 8
    end while

    allCodewords = QrCode_addEccAndInterleave(dataCodewords, version, ecl)

    ' ---- Matrix ----
    size = version * 4 + 17
    qr = {
        size: size
        version: version
        ecl: ecl
        mask: 0
        modules: QrCode_filled(size * size, 0)
        isFunction: QrCode_filled(size * size, false)
    }
    QrCode_drawFunctionPatterns(qr)
    QrCode_drawCodewords(qr, allCodewords)

    ' ---- Mask: keep the one with the lowest penalty ----
    bestMask = 0
    bestPenalty = -1
    for msk = 0 to 7
        QrCode_applyMask(qr, msk)
        QrCode_drawFormatBits(qr, msk)
        penalty = QrCode_penalty(qr)
        if bestPenalty < 0 or penalty < bestPenalty then
            bestMask = msk
            bestPenalty = penalty
        end if
        QrCode_applyMask(qr, msk) ' XOR again undoes it
    end for
    QrCode_applyMask(qr, bestMask)
    QrCode_drawFormatBits(qr, bestMask)
    qr.mask = bestMask
    qr.Delete("isFunction")
    return qr
end function

' Dark modules merged into rectangles: horizontal runs per row, then identical runs
' in consecutive rows stacked into one taller rectangle. Keeps the node count low.
function QrCode_rects(qr as object) as object
    size = qr.size
    mods = qr.modules
    out = []
    openRects = {} ' "x,w" -> index into out of a rect that ended on the previous row
    for y = 0 to size - 1
        nextOpen = {}
        x = 0
        while x < size
            if mods[y * size + x] = 1 then
                x0 = x
                while x < size and mods[y * size + x] = 1
                    x = x + 1
                end while
                w = x - x0
                key = x0.ToStr() + "," + w.ToStr()
                idx = openRects[key]
                if idx <> invalid then
                    out[idx].h = out[idx].h + 1
                else
                    out.Push({ x: x0, y: y, w: w, h: 1 })
                    idx = out.Count() - 1
                end if
                nextOpen[key] = idx
            else
                x = x + 1
            end if
        end while
        openRects = nextOpen
    end for
    return out
end function

' ---------- Helpers ----------

function QrCode_xor(a as integer, b as integer) as integer
    return (a or b) and (not (a and b))
end function

function QrCode_filled(n as integer, value as dynamic) as object
    arr = CreateObject("roArray", n, false)
    for i = 0 to n - 1
        arr[i] = value
    end for
    return arr
end function

sub QrCode_appendBits(bits as object, value as integer, count as integer)
    i = count - 1
    while i >= 0
        bits.Push((value >> i) and 1)
        i = i - 1
    end while
end sub

' Encodes a string as UTF-8 bytes (Asc returns the Unicode code point of a character).
function QrCode_utf8(text as string) as object
    out = []
    n = Len(text)
    for i = 1 to n
        c = Asc(Mid(text, i, 1))
        if c < &h80 then
            out.Push(c)
        else if c < &h800 then
            out.Push(&hC0 or (c >> 6))
            out.Push(&h80 or (c and &h3F))
        else if c < &h10000 then
            out.Push(&hE0 or (c >> 12))
            out.Push(&h80 or ((c >> 6) and &h3F))
            out.Push(&h80 or (c and &h3F))
        else
            out.Push(&hF0 or (c >> 18))
            out.Push(&h80 or ((c >> 12) and &h3F))
            out.Push(&h80 or ((c >> 6) and &h3F))
            out.Push(&h80 or (c and &h3F))
        end if
    end for
    return out
end function

function QrCode_tables() as object
    if m.qrTables <> invalid then return m.qrTables
    ' Index 0 is unused so the version number indexes directly.
    t = {
        eccPerBlock: {
            L: [0, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30]
            M: [0, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28]
        }
        numBlocks: {
            L: [0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25]
            M: [0, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49]
        }
        formatBits: { L: 1, M: 0 }
        expTable: []
        logTable: []
    }
    ' GF(256) exp/log tables for x^8 + x^4 + x^3 + x^2 + 1 (0x11D).
    t.logTable = QrCode_filled(256, 0)
    x = 1
    for i = 0 to 254
        t.expTable.Push(x)
        t.logTable[x] = i
        x = x * 2
        if x >= 256 then x = QrCode_xor(x, &h11D)
    end for
    m.qrTables = t
    return t
end function

function QrCode_gfMul(a as integer, b as integer) as integer
    if a = 0 or b = 0 then return 0
    t = QrCode_tables()
    return t.expTable[(t.logTable[a] + t.logTable[b]) mod 255]
end function

' Modules available for data and ECC after the function patterns, in bits.
function QrCode_numRawDataModules(ver as integer) as integer
    result = (16 * ver + 128) * ver + 64
    if ver >= 2 then
        numAlign = ver \ 7 + 2
        result = result - ((25 * numAlign - 10) * numAlign - 55)
        if ver >= 7 then result = result - 36
    end if
    return result
end function

function QrCode_numDataCodewords(ver as integer, ecl as string) as integer
    t = QrCode_tables()
    return QrCode_numRawDataModules(ver) \ 8 - t.eccPerBlock[ecl][ver] * t.numBlocks[ecl][ver]
end function

' Reed–Solomon generator polynomial (without the leading 1), highest degree first.
function QrCode_rsDivisor(degree as integer) as object
    result = QrCode_filled(degree, 0)
    result[degree - 1] = 1
    root = 1
    for i = 0 to degree - 1
        for j = 0 to degree - 1
            result[j] = QrCode_gfMul(result[j], root)
            if j + 1 < degree then result[j] = QrCode_xor(result[j], result[j + 1])
        end for
        root = QrCode_gfMul(root, 2)
    end for
    return result
end function

function QrCode_rsRemainder(dat as object, divisor as object) as object
    degree = divisor.Count()
    result = QrCode_filled(degree, 0)
    for each b in dat
        factor = QrCode_xor(b, result[0])
        result.Shift()
        result.Push(0)
        for i = 0 to degree - 1
            result[i] = QrCode_xor(result[i], QrCode_gfMul(divisor[i], factor))
        end for
    end for
    return result
end function

function QrCode_addEccAndInterleave(dat as object, ver as integer, ecl as string) as object
    t = QrCode_tables()
    numBlocks = t.numBlocks[ecl][ver]
    blockEccLen = t.eccPerBlock[ecl][ver]
    rawCodewords = QrCode_numRawDataModules(ver) \ 8
    numShortBlocks = numBlocks - (rawCodewords mod numBlocks)
    shortBlockLen = rawCodewords \ numBlocks

    divisor = QrCode_rsDivisor(blockEccLen)
    blocks = []
    k = 0
    for i = 0 to numBlocks - 1
        datLen = shortBlockLen - blockEccLen
        if i >= numShortBlocks then datLen = datLen + 1
        block = []
        for j = 0 to datLen - 1
            block.Push(dat[k + j])
        end for
        k = k + datLen
        ecc = QrCode_rsRemainder(block, divisor)
        if i < numShortBlocks then block.Push(0) ' placeholder so all blocks line up
        block.Append(ecc)
        blocks.Push(block)
    end for

    result = []
    blockLen = blocks[0].Count()
    for i = 0 to blockLen - 1
        for j = 0 to numBlocks - 1
            if i <> shortBlockLen - blockEccLen or j >= numShortBlocks then
                result.Push(blocks[j][i])
            end if
        end for
    end for
    return result
end function

' ---------- Matrix drawing ----------

sub QrCode_setFunction(qr as object, x as integer, y as integer, dark as boolean)
    idx = y * qr.size + x
    if dark then qr.modules[idx] = 1 else qr.modules[idx] = 0
    qr.isFunction[idx] = true
end sub

sub QrCode_drawFunctionPatterns(qr as object)
    size = qr.size
    ' Timing patterns.
    for i = 0 to size - 1
        QrCode_setFunction(qr, 6, i, (i mod 2) = 0)
        QrCode_setFunction(qr, i, 6, (i mod 2) = 0)
    end for
    ' Finder patterns with separators.
    QrCode_drawFinder(qr, 3, 3)
    QrCode_drawFinder(qr, size - 4, 3)
    QrCode_drawFinder(qr, 3, size - 4)
    ' Alignment patterns, skipping the three finder corners.
    aligns = QrCode_alignmentPositions(qr.version)
    n = aligns.Count()
    for i = 0 to n - 1
        for j = 0 to n - 1
            corner = (i = 0 and j = 0) or (i = 0 and j = n - 1) or (i = n - 1 and j = 0)
            if not corner then QrCode_drawAlignment(qr, aligns[i], aligns[j])
        end for
    end for
    ' Reserve the format areas (real bits are drawn per mask), then version info.
    QrCode_drawFormatBits(qr, 0)
    QrCode_drawVersion(qr)
end sub

sub QrCode_drawFinder(qr as object, cx as integer, cy as integer)
    size = qr.size
    for dy = -4 to 4
        for dx = -4 to 4
            dist = dx
            if dist < 0 then dist = -dist
            if dy > dist then dist = dy
            if -dy > dist then dist = -dy
            xx = cx + dx
            yy = cy + dy
            if xx >= 0 and xx < size and yy >= 0 and yy < size then
                QrCode_setFunction(qr, xx, yy, dist <> 2 and dist <> 4)
            end if
        end for
    end for
end sub

sub QrCode_drawAlignment(qr as object, cx as integer, cy as integer)
    for dy = -2 to 2
        for dx = -2 to 2
            dist = dx
            if dist < 0 then dist = -dist
            if dy > dist then dist = dy
            if -dy > dist then dist = -dy
            QrCode_setFunction(qr, cx + dx, cy + dy, dist <> 1)
        end for
    end for
end sub

function QrCode_alignmentPositions(ver as integer) as object
    if ver = 1 then return []
    numAlign = ver \ 7 + 2
    spacing = (ver * 8 + numAlign * 3 + 5) \ (numAlign * 4 - 4) * 2
    result = QrCode_filled(numAlign, 0)
    result[0] = 6
    p = ver * 4 + 17 - 7
    i = numAlign - 1
    while i >= 1
        result[i] = p
        p = p - spacing
        i = i - 1
    end while
    return result
end function

sub QrCode_drawFormatBits(qr as object, msk as integer)
    t = QrCode_tables()
    size = qr.size
    dat = t.formatBits[qr.ecl] * 8 + msk ' (ecl << 3) | mask
    r = dat
    for i = 1 to 10
        r = QrCode_xor(r << 1, (r >> 9) * &h537)
    end for
    bits = QrCode_xor((dat << 10) or r, &h5412)

    ' First copy, around the top-left finder.
    for i = 0 to 5
        QrCode_setFunction(qr, 8, i, ((bits >> i) and 1) <> 0)
    end for
    QrCode_setFunction(qr, 8, 7, ((bits >> 6) and 1) <> 0)
    QrCode_setFunction(qr, 8, 8, ((bits >> 7) and 1) <> 0)
    QrCode_setFunction(qr, 7, 8, ((bits >> 8) and 1) <> 0)
    for i = 9 to 14
        QrCode_setFunction(qr, 14 - i, 8, ((bits >> i) and 1) <> 0)
    end for
    ' Second copy, split between the other two finders.
    for i = 0 to 7
        QrCode_setFunction(qr, size - 1 - i, 8, ((bits >> i) and 1) <> 0)
    end for
    for i = 8 to 14
        QrCode_setFunction(qr, 8, size - 15 + i, ((bits >> i) and 1) <> 0)
    end for
    QrCode_setFunction(qr, 8, size - 8, true) ' always-dark module
end sub

sub QrCode_drawVersion(qr as object)
    ver = qr.version
    if ver < 7 then return
    r = ver
    for i = 1 to 12
        r = QrCode_xor(r << 1, (r >> 11) * &h1F25)
    end for
    bits = (ver << 12) or r
    size = qr.size
    for i = 0 to 17
        bit = ((bits >> i) and 1) <> 0
        a = size - 11 + (i mod 3)
        b = i \ 3
        QrCode_setFunction(qr, a, b, bit)
        QrCode_setFunction(qr, b, a, bit)
    end for
end sub

' Places the codeword bits in the zigzag order, skipping function modules.
sub QrCode_drawCodewords(qr as object, codewords as object)
    size = qr.size
    totalBits = codewords.Count() * 8
    i = 0
    col = size - 1
    while col >= 1
        if col = 6 then col = 5
        for vert = 0 to size - 1
            for j = 0 to 1
                x = col - j
                upward = ((col + 1) and 2) = 0
                if upward then y = size - 1 - vert else y = vert
                idx = y * size + x
                if not qr.isFunction[idx] and i < totalBits then
                    cw = codewords[i >> 3]
                    qr.modules[idx] = (cw >> (7 - (i and 7))) and 1
                    i = i + 1
                end if
            end for
        end for
        col = col - 2
    end while
end sub

' XORs the mask pattern into every non-function module (applying twice undoes it).
sub QrCode_applyMask(qr as object, msk as integer)
    size = qr.size
    mods = qr.modules
    fn = qr.isFunction
    for y = 0 to size - 1
        for x = 0 to size - 1
            idx = y * size + x
            if not fn[idx] then
                if msk = 0 then
                    inv = ((x + y) mod 2) = 0
                else if msk = 1 then
                    inv = (y mod 2) = 0
                else if msk = 2 then
                    inv = (x mod 3) = 0
                else if msk = 3 then
                    inv = ((x + y) mod 3) = 0
                else if msk = 4 then
                    inv = ((x \ 3 + y \ 2) mod 2) = 0
                else if msk = 5 then
                    inv = ((x * y) mod 2 + (x * y) mod 3) = 0
                else if msk = 6 then
                    inv = (((x * y) mod 2 + (x * y) mod 3) mod 2) = 0
                else
                    inv = (((x + y) mod 2 + (x * y) mod 3) mod 2) = 0
                end if
                if inv then mods[idx] = 1 - mods[idx]
            end if
        end for
    end for
end sub

' Standard penalty: runs of 5+, 2x2 blocks, finder look-alikes, dark balance.
function QrCode_penalty(qr as object) as integer
    size = qr.size
    mods = qr.modules
    result = 0
    dark = 0

    ' N1: runs of five or more same-colored modules in rows and columns.
    for a = 0 to size - 1
        rowColor = -1
        rowRun = 0
        colColor = -1
        colRun = 0
        for b = 0 to size - 1
            c = mods[a * size + b]
            dark = dark + c
            if c = rowColor then
                rowRun = rowRun + 1
                if rowRun = 5 then
                    result = result + 3
                else if rowRun > 5 then
                    result = result + 1
                end if
            else
                rowColor = c
                rowRun = 1
            end if
            c = mods[b * size + a]
            if c = colColor then
                colRun = colRun + 1
                if colRun = 5 then
                    result = result + 3
                else if colRun > 5 then
                    result = result + 1
                end if
            else
                colColor = c
                colRun = 1
            end if
        end for
    end for

    ' N2: 2x2 blocks of one color.
    for y = 0 to size - 2
        for x = 0 to size - 2
            c = mods[y * size + x]
            if c = mods[y * size + x + 1] and c = mods[(y + 1) * size + x] and c = mods[(y + 1) * size + x + 1] then
                result = result + 3
            end if
        end for
    end for

    ' N3: 1:1:3:1:1 finder look-alikes with four light modules on one side.
    pat1 = [1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0]
    pat2 = [0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1]
    for a = 0 to size - 1
        for b = 0 to size - 11
            m1 = true
            m2 = true
            n1 = true
            n2 = true
            for k = 0 to 10
                h = mods[a * size + b + k]
                v = mods[(b + k) * size + a]
                if h <> pat1[k] then m1 = false
                if h <> pat2[k] then m2 = false
                if v <> pat1[k] then n1 = false
                if v <> pat2[k] then n2 = false
            end for
            if m1 then result = result + 40
            if m2 then result = result + 40
            if n1 then result = result + 40
            if n2 then result = result + 40
        end for
    end for

    ' N4: distance of the dark share from 50%, in 5% steps.
    total = size * size
    diff = dark * 20 - total * 10
    if diff < 0 then diff = -diff
    k = (diff + total - 1) \ total - 1
    if k > 0 then result = result + k * 10
    return result
end function
