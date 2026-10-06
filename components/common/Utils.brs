' Shared helpers. Include with <script type="text/brightscript" uri="pkg:/components/common/Utils.brs" />
' SPDX-License-Identifier: AGPL-3.0-or-later

' ---------- Registry (persistent storage) ----------

function Registry_read(key as string, default = invalid as dynamic) as dynamic
    sec = CreateObject("roRegistrySection", "siku")
    if not sec.Exists(key) then return default
    raw = sec.Read(key)
    parsed = ParseJson(raw)
    if parsed = invalid then return default
    return parsed.v
end function

sub Registry_write(key as string, value as dynamic)
    sec = CreateObject("roRegistrySection", "siku")
    sec.Write(key, FormatJson({ v: value }))
    sec.Flush()
end sub

sub Registry_delete(key as string)
    sec = CreateObject("roRegistrySection", "siku")
    sec.Delete(key)
    sec.Flush()
end sub

' ---------- Strings ----------

function Str_isEmpty(v as dynamic) as boolean
    if v = invalid then return true
    if Type(v) = "roString" or Type(v) = "String" then return Len(v.Trim()) = 0
    return false
end function

function Str_orEmpty(v as dynamic) as string
    if v = invalid then return ""
    t = Type(v)
    if t = "roString" or t = "String" then return v
    if t = "roInt" or t = "roInteger" or t = "Integer" or t = "roLongInteger" or t = "LongInteger" then return v.ToStr()
    if t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double" then return Str(v).Trim()
    if t = "roBoolean" or t = "Boolean" then
        if v then return "true"
        return "false"
    end if
    return ""
end function

' Joins non-empty parts with " · ".
function Str_joinDots(parts as object, sep = " · " as string) as string
    out = ""
    for each p in parts
        s = Str_orEmpty(p)
        if s <> ""
            if out <> "" then out = out + sep
            out = out + s
        end if
    end for
    return out
end function

' Percent-encodes a URL component (RFC 3986 unreserved characters pass through).
' Written by hand because roUrlTransfer cannot be created in SceneGraph components on a
' real Roku (CreateObject returns invalid there); it is only available in Tasks.
function Str_urlEncode(s as string) as string
    if s = "" then return ""
    ba = CreateObject("roByteArray")
    ba.FromAsciiString(s)
    hexDigits = "0123456789ABCDEF"
    out = ""
    for i = 0 to ba.Count() - 1
        b = ba[i]
        isAlpha = (b >= 65 and b <= 90) or (b >= 97 and b <= 122)
        isDigit = b >= 48 and b <= 57
        if isAlpha or isDigit or b = 45 or b = 46 or b = 95 or b = 126 then
            out = out + Chr(b)
        else
            out = out + "%" + Mid(hexDigits, Int(b / 16) + 1, 1) + Mid(hexDigits, (b mod 16) + 1, 1)
        end if
    end for
    return out
end function

' Builds "a=1&b=2" from an associative array (skips invalid values).
' An array value repeats the key (`keys=a&keys=b`), as the settings endpoints expect.
function Str_queryString(params as object) as string
    if params = invalid then return ""
    out = ""
    for each k in params
        v = params[k]
        if v <> invalid
            values = []
            if Type(v) = "roArray" then values = v else values.Push(v)
            for each one in values
                if one <> invalid then
                    if out <> "" then out = out + "&"
                    out = out + Str_urlEncode(k) + "=" + Str_urlEncode(Str_orEmpty(one))
                end if
            end for
        end if
    end for
    return out
end function

function Str_padLeft(s as string, width as integer, ch = "0" as string) as string
    while Len(s) < width
        s = ch + s
    end while
    return s
end function

' ---------- Time ----------

' 5025 -> "1:23:45"; 125 -> "2:05"
function Time_clock(seconds as dynamic) as string
    if seconds = invalid then return "0:00"
    s = Int(seconds)
    if s < 0 then s = 0
    h = Int(s / 3600)
    mnt = Int((s mod 3600) / 60)
    sec = s mod 60
    if h > 0 then return h.ToStr() + ":" + Str_padLeft(mnt.ToStr(), 2) + ":" + Str_padLeft(sec.ToStr(), 2)
    return mnt.ToStr() + ":" + Str_padLeft(sec.ToStr(), 2)
end function

' 7140 -> "1h 59m"; 3120 -> "52 min"
function Time_runtime(seconds as dynamic) as string
    if seconds = invalid then return ""
    mins = Int(seconds / 60 + 0.5)
    if mins <= 0 then return ""
    if mins < 60 then return mins.ToStr() + " min"
    h = Int(mins / 60)
    r = mins mod 60
    if r = 0 then return h.ToStr() + "h"
    return h.ToStr() + "h " + r.ToStr() + "m"
end function

function Time_nowSeconds() as integer
    d = CreateObject("roDateTime")
    return d.AsSeconds()
end function

' Parses an ISO-8601 timestamp to roDateTime (UTC). Returns invalid on failure.
function Time_parseIso(s as dynamic) as dynamic
    if Str_isEmpty(s) then return invalid
    d = CreateObject("roDateTime")
    d.FromISO8601String(s)
    if d.AsSeconds() = 0 and Left(s, 4) <> "1970" then return invalid
    return d
end function

' ---------- Collections ----------

function Arr_or(v as dynamic) as object
    if v = invalid then return []
    if Type(v) = "roArray" then return v
    return []
end function

function AA_get(aa as dynamic, key as string, default = invalid as dynamic) as dynamic
    if aa = invalid then return default
    if Type(aa) <> "roAssociativeArray" and Type(aa) <> "roSGNode" then return default
    v = aa[key]
    if v = invalid then return default
    return v
end function

' Shallow-copy an associative array.
function AA_copy(aa as object) as object
    out = {}
    if aa = invalid then return out
    for each k in aa
        out[k] = aa[k]
    end for
    return out
end function

' ---------- Long OK press ----------
' Roku's RowList / MarkupGrid set rowItemSelected / itemSelected on the OK *press* and return true,
' so the host never sees that press and cannot time it from the key down. What the host can see is
' the OK *release* (press = false), which the lists don't consume. The scheme used by the Skyline
' feed and the library grid:
'   1. The list's selection event parks the selection as "pending" and starts a 600 ms timer.
'   2. The OK release before the timer fires performs the normal action (open the detail), so a
'      short press costs only the time the finger rests on the key.
'   3. The timer firing first means the key is still held: the card menu opens and the release
'      that follows finds nothing pending.
' A platform that never delivers key releases to the host would turn every press into a menu, so
' the scheme is armed only after one key release has been observed while a list had focus
' (m.global.keyReleaseSeen). Until then OK opens the detail immediately, as before. The options
' (*) key always opens the menu.
sub LongPress_init()
    if not m.global.hasField("keyReleaseSeen") then m.global.addFields({ keyReleaseSeen: false })
end sub

function LongPress_enabled() as boolean
    return m.global.hasField("keyReleaseSeen") and m.global.keyReleaseSeen = true
end function

sub LongPress_sawRelease()
    if m.global.hasField("keyReleaseSeen") and m.global.keyReleaseSeen <> true then m.global.keyReleaseSeen = true
end sub

' ---------- Device ----------

function Device_info() as object
    di = CreateObject("roDeviceInfo")
    return {
        id: di.GetChannelClientId()
        model: di.GetModel()
        name: di.GetFriendlyName()
        osVersion: di.GetOSVersion()
        displayMode: di.GetDisplayMode()
    }
end function

function App_version() as string
    ai = CreateObject("roAppInfo")
    return ai.GetVersion()
end function

' ---------- Text measurement ----------
' Label.boundingRect() can report 0 on a real Roku when it runs before the label's font is
' ready (seen on device: top-bar tabs and badges collapsed to dots). The SceneGraph Font
' node measures synchronously via getOneLineWidth, and unlike roFontRegistry it may be used
' on the render thread. Keep the larger of the two measurements.
' Font.getOneLineWidth/getOneLineHeight exist on Roku OS; the brs-engine simulator lacks
' them, so the calls are guarded and fall back to 0 (callers then use boundingRect).
function Text_width(text as string, fontUri as string, sizePx as integer) as float
    if text = "" then return 0
    fnt = Text_font(fontUri, sizePx)
    if fnt = invalid then return 0
    w = 0
    try
        w = fnt.getOneLineWidth(text, 100000)
    catch e
        w = 0 ' e: the simulator's Font node lacks getOneLineWidth; any error means "unmeasured"
        if e = invalid then w = 0
    end try
    if w = invalid then return 0
    return w
end function

function Text_height(fontUri as string, sizePx as integer) as float
    fnt = Text_font(fontUri, sizePx)
    if fnt = invalid then return sizePx * 1.3
    h = 0
    try
        h = fnt.getOneLineHeight()
    catch e
        h = 0 ' e: same as Text_width; the caller falls back to a size-based estimate
        if e = invalid then h = 0
    end try
    if h = invalid or h <= 0 then return sizePx * 1.3
    return h
end function

' Cached Font nodes keyed by uri and size (creating one per measurement would churn nodes).
function Text_font(fontUri as string, sizePx as integer) as object
    if Str_isEmpty(fontUri) then return invalid
    if m.soku_fonts = invalid then m.soku_fonts = {}
    key = fontUri + "|" + sizePx.ToStr()
    fnt = m.soku_fonts[key]
    if fnt = invalid then
        fnt = CreateObject("roSGNode", "Font")
        if fnt = invalid then return invalid
        fnt.uri = fontUri
        fnt.size = sizePx
        m.soku_fonts[key] = fnt
    end if
    return fnt
end function

' One-line width of a Label's text.
function Label_width(lbl as object) as float
    if lbl = invalid then return 0
    caption = lbl.text
    if Str_isEmpty(caption) then return 0
    measured = 0
    fnt = lbl.font
    if fnt <> invalid then
        if not Str_isEmpty(fnt.uri) then measured = Text_width(caption, fnt.uri, fnt.size)
    end if
    rectW = lbl.boundingRect().width
    if rectW > measured then return rectW
    return measured
end function

' Height of a Label's text block, with a font-based fallback when boundingRect reports 0
' (single line, or an estimate from the wrap width when the label wraps).
function Label_height(lbl as object) as float
    if lbl = invalid then return 0
    rectH = lbl.boundingRect().height
    if rectH > 0 then return rectH
    caption = lbl.text
    if Str_isEmpty(caption) then return 0
    fnt = lbl.font
    if fnt = invalid or Str_isEmpty(fnt.uri) then return 0
    lineH = Text_height(fnt.uri, fnt.size)
    lines = 1
    if lbl.wrap = true and lbl.width > 0 then
        textW = Text_width(caption, fnt.uri, fnt.size)
        lines = Int(textW / lbl.width) + 1
        if lbl.maxLines > 0 and lines > lbl.maxLines then lines = lbl.maxLines
    end if
    return lineH * lines
end function

' ---------- Nodes ----------

' Finds `id` in the subtree under `parent` (parent included). Use this instead of
' parent.findNode(id) for anything created at runtime: on a real Roku, findNode searches from
' the nearest enclosing *component*, not from the node it is called on, so rows built with
' shared child ids ("label", "bg") all resolve to the first row's nodes. brs-engine searches
' the subtree, which hides the bug in the simulator.
function Node_find(parent as object, id as string) as object
    if parent = invalid then return invalid
    if parent.id = id then return parent
    queue = [parent]
    while queue.Count() > 0
        n = queue.Shift()
        for each kid in n.getChildren(-1, 0)
            if kid.id = id then return kid
            queue.Push(kid)
        end for
    end while
    return invalid
end function
