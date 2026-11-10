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
    if mins < 60 then return TxF("{0} min", [mins])
    h = Int(mins / 60)
    r = mins mod 60
    if r = 0 then return TxF("{0}h", [h])
    return TxF("{0}h {1}m", [h, r])
end function

' Month and weekday names in the interface language (English is the lookup key). index is 0-based:
' 0 = January / Sunday (roDateTime.GetMonth() - 1, GetDayOfWeek()). "" when out of range.
function Time_monthShort(index as integer) as string
    months = [Tx("Jan"), Tx("Feb"), Tx("Mar"), Tx("Apr"), Tx("May"), Tx("Jun"), Tx("Jul"), Tx("Aug"), Tx("Sep"), Tx("Oct"), Tx("Nov"), Tx("Dec")]
    if index < 0 or index > 11 then return ""
    return months[index]
end function

function Time_monthLong(index as integer) as string
    months = [Tx("January"), Tx("February"), Tx("March"), Tx("April"), Tx("May"), Tx("June"), Tx("July"), Tx("August"), Tx("September"), Tx("October"), Tx("November"), Tx("December")]
    if index < 0 or index > 11 then return ""
    return months[index]
end function

function Time_dayShort(index as integer) as string
    days = [Tx("Sun"), Tx("Mon"), Tx("Tue"), Tx("Wed"), Tx("Thu"), Tx("Fri"), Tx("Sat")]
    if index < 0 or index > 6 then return ""
    return days[index]
end function

function Time_dayLong(index as integer) as string
    days = [Tx("Sunday"), Tx("Monday"), Tx("Tuesday"), Tx("Wednesday"), Tx("Thursday"), Tx("Friday"), Tx("Saturday")]
    if index < 0 or index > 6 then return ""
    return days[index]
end function

function Time_nowSeconds() as integer
    d = CreateObject("roDateTime")
    return d.AsSeconds()
end function

' True for a date without a time ("2024-05-01"), as Silo sends release, air and birth dates.
function Time_isDateOnly(s as dynamic) as boolean
    if Type(s) <> "roString" and Type(s) <> "String" then return false
    if Len(s) <> 10 then return false
    if Mid(s, 5, 1) <> "-" or Mid(s, 8, 1) <> "-" then return false
    digits = Left(s, 4) + Mid(s, 6, 2) + Right(s, 2)
    for i = 1 to 8
        c = Asc(Mid(digits, i, 1))
        if c < 48 or c > 57 then return false
    end for
    return true
end function

' The string handed to FromISO8601String. Roku OS 15.3.4 reads a date-only string as the epoch
' (1970), so a date gets midnight UTC appended; its day is then read in UTC (never ToLocalTime),
' which keeps it the same calendar day in every time zone. Adapted from Silo-Server/silo-roku,
' AGPL-3.0 (source/catalog/detail.bs, source/catalog/cards.bs).
function Time_isoForParse(s as dynamic) as string
    if Time_isDateOnly(s) then return s + "T00:00:00Z"
    return Str_orEmpty(s)
end function

' Parses an ISO-8601 timestamp (or a YYYY-MM-DD date, as midnight UTC) to roDateTime (UTC).
' Returns invalid on failure.
function Time_parseIso(s as dynamic) as dynamic
    if Str_isEmpty(s) then return invalid
    d = CreateObject("roDateTime")
    d.FromISO8601String(Time_isoForParse(s))
    if d.AsSeconds() = 0 and Left(s, 4) <> "1970" then return invalid
    return d
end function

' "May 1, 2024" from a date or timestamp read in UTC (a date-only value never shifts a day);
' "" when unreadable.
function Time_longDate(s as dynamic) as string
    dt = Time_parseIso(s)
    if dt = invalid then return ""
    mi = dt.GetMonth() - 1
    if mi < 0 or mi > 11 then return ""
    return Time_monthShort(mi) + " " + dt.GetDayOfMonth().ToStr() + ", " + dt.GetYear().ToStr()
end function

' ---------- Numbers ----------

' Whole seconds (an epoch time) from a JSON number or numeric string, exactly: Num_or's single-
' precision float rounds today's epoch seconds to steps of 128 s. 0 for anything else.
function Num_seconds(v as dynamic) as integer
    t = Type(v)
    if t = "roInt" or t = "roInteger" or t = "Integer" or t = "roLongInteger" or t = "LongInteger" then return v
    if t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double" then return Int(v)
    if t = "roString" or t = "String" then return v.Trim().ToInt()
    return 0
end function

' A JSON number as a float. Real servers may send numbers as strings ("12"), which crash
' arithmetic and comparisons (pitfall 6), so numeric strings are parsed; anything else is `fallback`.
function Num_or(v as dynamic, fallback = 0.0 as float) as float
    if v = invalid then return fallback
    t = Type(v)
    if t = "roInt" or t = "roInteger" or t = "Integer" or t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double" or t = "roLongInteger" or t = "LongInteger" then return v * 1.0
    if t = "roString" or t = "String" then
        if v.Trim() = "" then return fallback
        return Val(v)
    end if
    return fallback
end function

' ---------- Launch ----------

' Tells MainScene the first screen is up (Home drawn, a deep-linked title's details shown, video
' playing), so it signals Roku's AppLaunchComplete beacon once. Later calls do nothing.
sub Launch_ready(what as string)
    g = m.global
    if g = invalid then return
    if not g.hasField("launchReady") then return
    if g.launchReady <> "" then return
    g.launchReady = what
end sub

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

' ---------- Diagnostics log ----------

' Prints a console line and, once MainScene has started DiagTask, keeps it (redacted) in the
' on-device diagnostics log that Settings › Diagnostics shows (Diag.brs, DiagTask). Use for
' `[siku-*]` lines a user report would need; never pass tokens or signed URLs (the log scrubs
' URLs, addresses, ids and tokens anyway).
sub Diag_log(line as string)
    print line
    g = m.global
    if g = invalid then return
    if not g.hasField("diagLine") then return
    ' Lines from before DiagTask listens wait in diagBacklog (DiagTask reads it once it is ready).
    if not g.diagReady then
        b = g.diagBacklog
        if Type(b) = "roArray" and b.Count() < 50 then
            b.Push(line)
            g.diagBacklog = b
        end if
    end if
    g.diagLine = line
end sub

' The text `print a; b; c` would show, for Diag_log (tools/diag_log_convert.py writes these calls).
function Diag_join(parts as object) as string
    s = ""
    for each p in parts
        t = Type(p)
        if t = "String" or t = "roString" then
            s = s + p
        else if t = "Invalid" or t = "roInvalid" or t = "<uninitialized>" then
            s = s + "invalid"
        else
            v = Str_orEmpty(p)
            if v = "" then v = "<" + t + ">"
            s = s + v
        end if
    end for
    return s
end function

' ---------- Interface language (I18n) ----------
' Interface text is written in English in the code and marked Tx("…") / TxF("… {0}", [x]) /
' TxP("one …", "{0} others", n); layout XML keeps English in text/title/hintText and is translated
' when a screen is built (I18n_translateTree). m.global.strings maps English to the applied
' language's text (pkg:/locale/<folder>/strings.json, built by tools/i18n_build.py from Silo's
' AGPL catalogs and i18n/siku); a missing entry shows the English. m.global.appLocale is the
' applied folder ("en", "es", "de", "fr", "pt_BR"); MainScene applies it (I18n_apply) from the
' profile's ui.app_language, else the Roku's language. Each component copies the table once:
' a language change rebuilds the screens.

function I18n_folders() as object
    return ["en", "es", "de", "fr", "pt_BR"]
end function

' The applied language folder.
function I18n_locale() as string
    if m.global <> invalid and m.global.hasField("appLocale") then
        v = m.global.appLocale
        if v <> invalid and v <> "" then return v
    end if
    return "en"
end function

function I18n_table() as object
    loc = I18n_locale()
    if m.i18nTable = invalid or m.i18nLocale <> loc then
        m.i18nLocale = loc
        t = invalid
        if loc <> "en" and m.global <> invalid and m.global.hasField("strings") then t = m.global.strings
        if Type(t) <> "roAssociativeArray" then t = {}
        m.i18nTable = t
    end if
    return m.i18nTable
end function

' The interface text for English `text` in the applied language.
function Tx(text as string) as string
    if text = "" then return ""
    t = I18n_table()
    v = t[text]
    if Type(v) = "roString" or Type(v) = "String" then
        if v <> "" then return v
    end if
    return text
end function

' Server text by Silo catalog key (home.section.*, error.*): the translation of `key` with its
' {name} placeholders filled from `args` (an AA, e.g. a section's title_args), else `fallback`
' (the server's English) when the language lacks the key or an argument is missing.
function TxKey(key as dynamic, args as dynamic, fallback as string) as string
    if key = invalid or (Type(key) <> "roString" and Type(key) <> "String") or key = "" then return fallback
    if I18n_locale() = "en" then return fallback
    t = I18n_table()
    v = t["@" + key]
    if Type(v) <> "roString" and Type(v) <> "String" then return fallback
    if Type(args) = "roAssociativeArray" then
        for each name in args
            a = args[name]
            if a = invalid then
                a = ""
            else if Type(a) <> "roString" and Type(a) <> "String" then
                if GetInterface(a, "ifToStr") <> invalid then a = a.ToStr() else a = ""
            end if
            v = v.Replace("{" + name + "}", a)
        end for
    end if
    if Instr(1, v, "{") > 0 then return fallback
    return v
end function

' Tx with {0}, {1}, … replaced by args (strings or numbers).
function TxF(text as string, args as object) as string
    out = Tx(text)
    if Type(args) <> "roArray" then args = [args]
    for i = 0 to args.Count() - 1
        a = args[i]
        if a = invalid then
            a = ""
        else if Type(a) <> "roString" and Type(a) <> "String" then
            if GetInterface(a, "ifToStr") <> invalid then a = a.ToStr() else a = ""
        end if
        out = out.Replace("{" + i.ToStr() + "}", a)
    end for
    return out
end function

' A count: `one` for the language's singular, `other` otherwise; {0} is n.
function TxP(one as string, other as string, n as dynamic) as string
    count = 0
    if n <> invalid then
        if Type(n) = "roString" or Type(n) = "String" then count = Int(Val(n)) else count = Int(n)
    end if
    form = other
    if I18n_isOne(I18n_locale(), count) then form = one
    return TxF(form, [count])
end function

' CLDR plural "one" for integers: French and Brazilian Portuguese count 0 and 1 as one.
function I18n_isOne(folder as string, n as integer) as boolean
    if folder = "fr" or folder = "pt_BR" then return n = 0 or n = 1
    return n = 1
end function

' The folder for a ui.app_language value (a BCP 47 tag; "" or invalid = the device's language)
' and the Roku's locale (GetCurrentLocale, e.g. "de_DE"). A regional tag matches its language
' (es-MX → es, pt-PT → pt_BR); an unshipped language falls back to English.
function I18n_resolve(override as dynamic, deviceLocale as string) as string
    tag = ""
    if override <> invalid and (Type(override) = "roString" or Type(override) = "String") then tag = override
    if tag = "" then tag = deviceLocale
    f = I18n_match(tag)
    if f = "" and tag <> deviceLocale then f = I18n_match(deviceLocale)
    if f = "" then f = "en"
    return f
end function

' The shipped folder for a tag, "" when none (pseudo-locales en-XA / ar-XB never match).
function I18n_match(tag as string) as string
    t = LCase(tag.Trim()).Replace("_", "-")
    if t = "" then return ""
    parts = t.Split("-")
    lang = parts[0]
    if parts.Count() > 1 then
        r = parts[parts.Count() - 1]
        if r = "xa" or r = "xb" then return ""
    end if
    if lang = "pt" then return "pt_BR"
    for each f in ["en", "es", "de", "fr"]
        if lang = f then return f
    end for
    return ""
end function

' The ui.app_language tag Silo's apps write for a folder.
function I18n_tagOf(folder as string) as string
    if folder = "pt_BR" then return "pt-BR"
    return folder
end function

' The language's own name, for the App language picker.
function I18n_nativeName(folder as string) as string
    names = { en: "English", es: "Español", de: "Deutsch", fr: "Français", pt_BR: "Português (Brasil)" }
    v = names[folder]
    if v = invalid then return folder
    return v
end function

' Translates the English text the layout XML gave `node` and its children (Label, Button,
' StandardMessageDialog, …): text, title and hintText fields that are in the table.
sub I18n_translateTree(node as dynamic)
    if node = invalid or I18n_locale() = "en" then return
    t = I18n_table()
    I18n_translateNode(node, t, 0)
end sub

sub I18n_translateNode(node as object, t as object, depth as integer)
    if depth > 24 then return
    for each f in ["text", "title", "hintText"]
        if node.hasField(f) then
            v = node.getField(f)
            if (Type(v) = "roString" or Type(v) = "String") and v <> "" then
                tr = t[v]
                if tr <> invalid and tr <> "" then node.setField(f, tr)
            end if
        end if
    end for
    n = node.getChildCount()
    for i = 0 to n - 1
        I18n_translateNode(node.getChild(i), t, depth + 1)
    end for
end sub
