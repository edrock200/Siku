' Byte helpers for the LAN protocols (phone pairing, SiloCast remote control, mDNS).
' Pure BrightScript over roByteArray, so it runs in a Task, on the render thread and in brs-cli
' unit runs (tools/lan_vectors.py). Slices go through hex strings because a per-byte loop is slow
' on a Roku and roByteArray has no native slice.
' SPDX-License-Identifier: AGPL-3.0-or-later

' UTF-8 bytes of a string (roByteArray.FromAsciiString encodes UTF-8).
function Lan_bytes(s as dynamic) as object
    b = CreateObject("roByteArray")
    if s <> invalid and Len(s) > 0 then b.FromAsciiString(s)
    return b
end function

function Lan_hexBytes(hex as string) as object
    b = CreateObject("roByteArray")
    if Len(hex) > 0 then b.FromHexString(hex)
    return b
end function

function Lan_hex(b as object) as string
    if b = invalid or b.Count() = 0 then return ""
    return LCase(b.ToHexString())
end function

' A new array holding every argument's bytes in order (invalid entries are skipped).
function Lan_concat(parts as object) as object
    hex = ""
    for each p in parts
        if p <> invalid and p.Count() > 0 then hex = hex + p.ToHexString()
    end for
    return Lan_hexBytes(hex)
end function

function Lan_slice(b as object, start as integer, count as integer) as object
    if count <= 0 or start >= b.Count() then return CreateObject("roByteArray")
    if start + count > b.Count() then count = b.Count() - start
    return Lan_hexBytes(Mid(b.ToHexString(), start * 2 + 1, count * 2))
end function

' Big-endian unsigned 32-bit length prefix.
function Lan_u32be(n as integer) as object
    b = CreateObject("roByteArray")
    b.Push((n >> 24) and &hFF)
    b.Push((n >> 16) and &hFF)
    b.Push((n >> 8) and &hFF)
    b.Push(n and &hFF)
    return b
end function

' A sequence number as 8 bytes, big-endian (the sealed frame's seq field). Sequence numbers in one
' connection stay far below 2^31, so the top four bytes are zero.
function Lan_seq8(seq as integer) as object
    return Lan_concat([Lan_hexBytes("00000000"), Lan_u32be(seq)])
end function

function Lan_bytesEqual(a as object, b as object) as boolean
    if a = invalid or b = invalid then return false
    if a.Count() <> b.Count() then return false
    ' No early exit: every byte is compared (BrightScript has no xor operator).
    same = 0
    for i = 0 to a.Count() - 1
        if a[i] = b[i] then same = same + 1
    end for
    return same = a.Count()
end function

' RFC 4648 base64url without padding.
function Lan_base64url(b as object) as string
    s = b.ToBase64String()
    s = s.Replace("+", "-").Replace("/", "_").Replace("=", "")
    return s
end function

' base64url (padding optional) to bytes; invalid when it is not base64.
function Lan_fromBase64url(s as dynamic) as dynamic
    if s = invalid then return invalid
    t = s.Trim().Replace("-", "+").Replace("_", "/")
    if t = "" then return invalid
    r = CreateObject("roRegex", "^[A-Za-z0-9+/]+=*$", "")
    if not r.IsMatch(t) then return invalid
    t = t.Replace("=", "")
    while Len(t) mod 4 <> 0
        t = t + "="
    end while
    b = CreateObject("roByteArray")
    b.FromBase64String(t)
    return b
end function

function Lan_base32Alphabet() as string
    return "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
end function

' RFC 4648 base32 without padding (the pairing link's key= form).
function Lan_base32(b as object) as string
    alphabet = Lan_base32Alphabet()
    out = ""
    bits = 0
    value = 0
    for i = 0 to b.Count() - 1
        value = ((value << 8) or b[i]) and &hFFFF
        bits = bits + 8
        while bits >= 5
            bits = bits - 5
            out = out + Mid(alphabet, ((value >> bits) and 31) + 1, 1)
        end while
    end for
    if bits > 0 then out = out + Mid(alphabet, ((value << (5 - bits)) and 31) + 1, 1)
    return out
end function

' The key shown on screen: base32 in groups of four ("AAAQ EAYE ...").
function Lan_groupsOfFour(s as string) as string
    out = ""
    for i = 1 to Len(s) step 4
        if out <> "" then out = out + " "
        out = out + Mid(s, i, 4)
    end for
    return out
end function

' A 16-byte pairing key from base32 (spaces and dashes allowed) or 32 hex digits; invalid otherwise.
function Lan_parseKey(text as dynamic) as dynamic
    if text = invalid then return invalid
    cleaned = text.Replace(" ", "").Replace("-", "").Replace("=", "")
    if Len(cleaned) = 32 and CreateObject("roRegex", "^[0-9a-fA-F]+$", "").IsMatch(cleaned) then return Lan_hexBytes(cleaned)
    alphabet = Lan_base32Alphabet()
    out = CreateObject("roByteArray")
    bits = 0
    value = 0
    up = UCase(cleaned)
    for i = 1 to Len(up)
        digit = Instr(1, alphabet, Mid(up, i, 1)) - 1
        if digit < 0 then return invalid
        value = ((value << 5) or digit) and &hFFFF
        bits = bits + 5
        if bits >= 8 then
            bits = bits - 8
            out.Push((value >> bits) and &hFF)
        end if
    end for
    if out.Count() <> 16 or bits >= 5 then return invalid
    return out
end function

function Lan_sha256(b as object) as object
    d = CreateObject("roEVPDigest")
    d.Setup("sha256")
    return Lan_hexBytes(d.Process(b))
end function

' n unpredictable bytes. Roku has no documented CSPRNG for channels; GetRandomUUID (version 4,
' 122 random bits) is the strongest source we have, so two of them, a counter, the uptime and
' Rnd() are hashed together for every 32 bytes.
function Lan_randomBytes(n as integer) as object
    di = CreateObject("roDeviceInfo")
    if m.lanRandomCounter = invalid then m.lanRandomCounter = 0
    out = CreateObject("roByteArray")
    while out.Count() < n
        m.lanRandomCounter = m.lanRandomCounter + 1
        ts = CreateObject("roTimespan")
        seed = di.GetRandomUUID() + di.GetRandomUUID() + m.lanRandomCounter.ToStr() + ts.TotalMilliseconds().ToStr() + Rnd(2147483647).ToStr()
        out.Append(Lan_sha256(Lan_bytes(seed)))
    end while
    return Lan_slice(out, 0, n)
end function

' Base64url (no padding) of a server URL as the Silo apps key their saved servers
' (AndroidServerRegistry.idFor): the URL trimmed of spaces and trailing slashes.
function Lan_serverIdFor(url as dynamic) as string
    u = Lan_trimUrl(url)
    if u = "" then return ""
    return Lan_base64url(Lan_bytes(u))
end function

function Lan_trimUrl(url as dynamic) as string
    if url = invalid then return ""
    s = url.Trim()
    while Len(s) > 0 and Right(s, 1) = "/"
        s = Left(s, Len(s) - 1)
    end while
    return s
end function

' The URL a server id names, or "" when the id is not a URL-derived one.
function Lan_urlForServerId(id as dynamic) as string
    b = Lan_fromBase64url(id)
    if b = invalid or b.Count() = 0 then return ""
    u = b.ToAsciiString()
    if Lan_serverIdFor(u) <> id then return ""
    l = LCase(u)
    if Left(l, 7) <> "http://" and Left(l, 8) <> "https://" then return ""
    return u
end function

' Canonical form for comparing two server URLs: lower-case scheme and host, default port dropped,
' trailing slashes trimmed.
function Lan_canonicalUrl(url as dynamic) as string
    s = Lan_trimUrl(url)
    i = Instr(1, s, "://")
    if i = 0 then return LCase(s)
    scheme = LCase(Left(s, i - 1))
    rest = Mid(s, i + 3)
    slash = Instr(1, rest, "/")
    path = ""
    host = rest
    if slash > 0 then
        host = Left(rest, slash - 1)
        path = Mid(rest, slash)
    end if
    host = LCase(host)
    if scheme = "https" and Right(host, 4) = ":443" then host = Left(host, Len(host) - 4)
    if scheme = "http" and Right(host, 3) = ":80" then host = Left(host, Len(host) - 3)
    return scheme + "://" + host + path
end function

' Whether two server references name one deployment (AndroidServerRegistry.serversMatch): the same
' URL-derived id (or URL), or the same verified deployment identity.
function Lan_serversMatch(aId as dynamic, aIdentity as dynamic, bId as dynamic, bIdentity as dynamic) as boolean
    ai = Str_orEmpty(aId)
    bi = Str_orEmpty(bId)
    if ai <> "" and bi <> "" then
        if ai = bi then return true
        au = Lan_urlForServerId(ai)
        bu = Lan_urlForServerId(bi)
        if au <> "" and bu <> "" and Lan_canonicalUrl(au) = Lan_canonicalUrl(bu) then return true
    end if
    x = Str_orEmpty(aIdentity).Trim()
    y = Str_orEmpty(bIdentity).Trim()
    return x <> "" and x = y
end function

' ---------- Length-prefixed frames (PairingFrame / SiloCastFrame) ----------
' Each payload is a 4-byte big-endian length and that many bytes; at most 1 MiB. The buffer keeps
' undelivered bytes as hex, so appending and cutting stay native string operations.

function Lan_maxFrameBytes() as integer
    return 1048576
end function

function Lan_frame(payload as object) as object
    return Lan_concat([Lan_u32be(payload.Count()), payload])
end function

' max: the largest payload this buffer accepts (LanTask lowers it until a connection's hello).
function LanFrames_new() as object
    return { hex: "", failed: false, max: Lan_maxFrameBytes() }
end function

' Appends received bytes and returns every complete payload now available. A declared length over
' fb.max sets fb.failed (the connection must be closed) and returns nothing more.
function LanFrames_append(fb as object, bytes as object) as object
    out = []
    if fb.failed then return out
    if bytes <> invalid and bytes.Count() > 0 then fb.hex = fb.hex + bytes.ToHexString()
    while Len(fb.hex) >= 8
        n# = 0
        for i = 0 to 3
            n# = n# * 256 + Val(Mid(fb.hex, i * 2 + 1, 2), 16)
        end for
        limit = Lan_maxFrameBytes()
        if fb.max <> invalid then limit = fb.max
        if n# > limit then
            fb.failed = true
            fb.hex = ""
            return out
        end if
        n = Int(n#)
        if Len(fb.hex) < 8 + n * 2 then exit while
        out.Push(Lan_hexBytes(Mid(fb.hex, 9, n * 2)))
        fb.hex = Mid(fb.hex, 9 + n * 2)
    end while
    return out
end function

' True only for a real boolean true. Comparing invalid (a missing JSON field) with "= true"
' throws Type Mismatch on a Roku, so every flag read from the wire or a config goes through here.
function Lan_isTrue(v as dynamic) as boolean
    t = Type(v)
    if t = "Boolean" or t = "roBoolean" then return v
    return false
end function

function Lan_boolText(v as dynamic) as string
    if Lan_isTrue(v) then return "true"
    return "false"
end function

' A deployment identity (`server_id`) in the shape Siku stores and compares: 1..128 characters of
' [A-Za-z0-9_-] (Silo's are UUIDs). Anything else is treated as no identity.
function Lan_isServerId(id as dynamic) as boolean
    t = Type(id)
    if t <> "String" and t <> "roString" then return false
    n = Len(id)
    if n < 1 or n > 128 then return false
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
    for i = 1 to n
        if Instr(1, allowed, Mid(id, i, 1)) = 0 then return false
    end for
    return true
end function
