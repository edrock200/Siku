' Shared helpers. Include with <script type="text/brightscript" uri="pkg:/components/common/Utils.brs" />
' SPDX-License-Identifier: AGPL-3.0-or-later

' ---------- Registry (persistent storage) ----------

function Registry_read(key as string, default = invalid as dynamic) as dynamic
    sec = CreateObject("roRegistrySection", "soku")
    if not sec.Exists(key) then return default
    raw = sec.Read(key)
    parsed = ParseJson(raw)
    if parsed = invalid then return default
    return parsed.v
end function

sub Registry_write(key as string, value as dynamic)
    sec = CreateObject("roRegistrySection", "soku")
    sec.Write(key, FormatJson({ v: value }))
    sec.Flush()
end sub

sub Registry_delete(key as string)
    sec = CreateObject("roRegistrySection", "soku")
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
    if t = "roInt" or t = "Integer" or t = "roLongInteger" or t = "LongInteger" then return v.ToStr()
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

function Str_urlEncode(s as string) as string
    t = CreateObject("roUrlTransfer")
    return t.Escape(s)
end function

' Builds "a=1&b=2" from an associative array (skips invalid values).
function Str_queryString(params as object) as string
    if params = invalid then return ""
    out = ""
    for each k in params
        v = params[k]
        if v <> invalid
            if out <> "" then out = out + "&"
            out = out + Str_urlEncode(k) + "=" + Str_urlEncode(Str_orEmpty(v))
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
