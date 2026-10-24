' SPDX-License-Identifier: AGPL-3.0-or-later
' Settings → Playback: buffering quality and the Connection group (Silo Android #636; the server's
' buffering-quality spec, "Reporting and display"). Included by SettingsScreen.xml (m is the screen).
'
'   Lower quality when buffering   playback.buffering_quality_mode (Never / Ask first / Automatically),
'                                  shown when the server's settings manifest is revision 21 or later
'   Limited to 44 Mbps after buffering on Oct 17   [Reset]
'                                  GET /api/v2/playback/connection (buffering_quality_v1), Reset is
'                                  DELETE /api/v2/playback/connection/learned-limit; hidden in Never
'   CONNECTION  Connection speed   [Test speed]  (connection_speed_v1 with a bandwidth_probe_url)
'               "48 Mbps · measured 3 minutes ago on Wi-Fi", "Auto plays videos up to 38 Mbps ..."
' The connection is read again each time the Playback category is opened, after Reset and after a
' speed test, and a late answer never replaces a newer one.

sub Conn_init()
    m.conn = { caps: invalid, state: invalid, reads: 0, shown: 0, testing: false, message: "", resetFailed: false }
    m.connLastCat = ""
end sub

' Called from renderPane with the selected category: entering Playback reads the connection.
sub Conn_onCategory(catId as string)
    if catId = "playback" and m.connLastCat <> "playback" then Conn_load()
    m.connLastCat = catId
end sub

sub Conn_load()
    m.conn.reads = m.conn.reads + 1
    Api_get("/api/v2/playback/capabilities", invalid, "Conn_onCaps", { read: m.conn.reads })
end sub

sub Conn_onCaps(event as object)
    resp = Api_result(event)
    if not resp.ok or Type(resp.data) <> "roAssociativeArray" then return
    d = resp.data
    caps = { buffering: false, speed: false, probeUrl: Str_orEmpty(d.bandwidth_probe_url), targetKbps: Int(Num_or(d.bandwidth_probe_target_kbps, 0)), maxAge: Int(Num_or(d.bandwidth_probe_max_age_seconds, 604800)) }
    for each f in Arr_or(d.features)
        if f = "buffering_quality_v1" then caps.buffering = true
        if f = "connection_speed_v1" then caps.speed = true
    end for
    if caps.probeUrl = "" then caps.speed = false
    m.conn.caps = caps
    if caps.buffering then
        Api_get("/api/v2/playback/connection", invalid, "Conn_onConnection", resp.context)
    else
        m.conn.state = invalid
        Conn_rerender()
    end if
end sub

sub Conn_onConnection(event as object)
    resp = Api_result(event)
    c = resp.context
    readNo = 0
    if c <> invalid then readNo = Int(Num_or(c.read, 0))
    if readNo <= m.conn.shown then return ' a read that started later was shown already
    if resp.ok and Type(resp.data) = "roAssociativeArray" then
        m.conn.shown = readNo
        m.conn.state = resp.data
        Conn_rememberProbe(resp.data.probe)
    else if c <> invalid and c.keepOnFailure = true then
        return
    else
        m.conn.shown = readNo
        m.conn.state = invalid
    end if
    Conn_rerender()
end sub

sub Conn_reread(keepOnFailure as boolean)
    if m.conn.caps = invalid or not m.conn.caps.buffering then return
    m.conn.reads = m.conn.reads + 1
    Api_get("/api/v2/playback/connection", invalid, "Conn_onConnection", { read: m.conn.reads, keepOnFailure: keepOnFailure })
end sub

sub Conn_rerender()
    cat = m.categories[m.catIndex]
    if cat.id = "playback" then renderPane()
end sub

' ---------- Rows ----------

' The rows that follow Maximum Bitrate in Playback → Streaming.
sub Conn_appendStreamingRows(out as object)
    mode = Settings_bufferingQualityMode()
    if Settings_supportsBufferingQualityMode() then
        out.Push({ kind: "row", row: rowDef("bufferingQuality", "choice", "Lower quality when buffering") })
        out.Push({ kind: "footer", text: "What Siku does on Auto when playback keeps buffering. Siku always asks before lowering a quality you picked." })
    end if
    limit = Conn_learnedLimit()
    if limit <> invalid and mode <> "never" then
        ' A long label with a short value ("Reset"): the label takes most of the row.
        out.Push({ kind: "row", row: { id: "learnedLimit", kind: "action", label: Conn_learnedLimitLabel(limit), labelWidth: 820 } })
        if m.conn.resetFailed then out.Push({ kind: "footer", text: "Couldn't reset the limit. Try again." })
    end if
end sub

' Playback → Connection, after the Streaming group.
sub Conn_appendConnectionGroup(out as object)
    caps = m.conn.caps
    if caps = invalid or not caps.speed then return
    out.Push({ kind: "header", text: "Connection" })
    out.Push({ kind: "row", row: { id: "connectionSpeed", kind: "action", label: "Connection speed" } })
    out.Push({ kind: "footer", text: Conn_speedLine() })
    if m.conn.message <> "" then out.Push({ kind: "footer", text: m.conn.message })
    budget = 0
    if m.conn.state <> invalid then budget = Int(Num_or(m.conn.state.auto_budget_kbps, 0))
    ' In Never the server's budget counts a learned limit that Never ignores, so it hides then.
    if Settings_bufferingQualityMode() = "never" and Conn_learnedLimit() <> invalid then budget = 0
    if budget > 0 then out.Push({ kind: "footer", text: "Auto plays videos up to " + Conn_rateLabel(budget) + " without converting them." })
end sub

function Conn_learnedLimit() as dynamic
    s = m.conn.state
    if s = invalid or s.learned_limit = invalid or Type(s.learned_limit) <> "roAssociativeArray" then return invalid
    if Num_or(s.learned_limit.kbps, 0) <= 0 then return invalid
    return s.learned_limit
end function

' "Limited to 44 Mbps after buffering on Oct 17" (or without the date when it is unreadable).
function Conn_learnedLimitLabel(limit as object) as string
    rate = Conn_rateLabel(Int(Num_or(limit.kbps, 0)))
    day = Conn_shortDate(Str_orEmpty(limit.observed_at))
    if day = "" then return "Limited to " + rate + " after buffering"
    return "Limited to " + rate + " after buffering on " + day
end function

' connectionRate: rounded down so a bound or budget never overstates the link: "850 kbps",
' "1.4 Mbps" below 10 Mbps, whole megabits from there ("44 Mbps").
function Conn_rateLabel(kbps as integer) as string
    if kbps < 1000 then
        if kbps < 0 then kbps = 0
        return kbps.ToStr() + " kbps"
    end if
    if kbps < 10000 then
        tenths = kbps \ 100
        if tenths mod 10 = 0 then return (tenths \ 10).ToStr() + " Mbps"
        return (tenths \ 10).ToStr() + "." + (tenths mod 10).ToStr() + " Mbps"
    end if
    return (kbps \ 1000).ToStr() + " Mbps"
end function

' "Oct 17" in the Roku's time zone, from an RFC 3339 time; "" when unreadable.
function Conn_shortDate(iso as string) as string
    secs = Conn_epochSeconds(iso)
    if secs <= 0 then return ""
    dt = CreateObject("roDateTime")
    dt.FromSeconds(secs)
    dt.ToLocalTime()
    months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    mo = dt.GetMonth()
    if mo < 1 or mo > 12 then return ""
    return months[mo - 1] + " " + dt.GetDayOfMonth().ToStr()
end function

function Conn_epochSeconds(iso as string) as integer
    if Len(iso) < 19 then return 0
    dt = CreateObject("roDateTime")
    dt.FromISO8601String(iso)
    return dt.AsSeconds()
end function

' The speed line: the newer of the server's probe reading and this Roku's own last test, else the
' playback sample (a lower bound), else "Not measured yet".
function Conn_speedLine() as string
    if m.conn.testing then return "Testing…"
    reading = invalid
    s = m.conn.state
    if s <> invalid and s.probe <> invalid and Type(s.probe) = "roAssociativeArray" then
        reading = { kbps: Int(Num_or(s.probe.kbps, 0)), at: Conn_epochSeconds(Str_orEmpty(s.probe.measured_at)), transport: Str_orEmpty(s.probe.transport), lowerBound: Conn_truthy(s.probe.lower_bound), playback: false }
    end if
    own = m.global.bandwidthProbe
    if own <> invalid and Type(own) = "roAssociativeArray" and own.serverUrl = m.global.session.serverUrl then
        if reading = invalid or own.at > reading.at then reading = { kbps: own.kbps, at: own.at, transport: own.transport, lowerBound: own.lowerBound, playback: false }
    end if
    if reading = invalid and s <> invalid and s.playback_sample <> invalid and Type(s.playback_sample) = "roAssociativeArray" then
        reading = { kbps: Int(Num_or(s.playback_sample.kbps, 0)), at: Conn_epochSeconds(Str_orEmpty(s.playback_sample.measured_at)), transport: "", lowerBound: true, playback: true }
    end if
    if reading = invalid or reading.kbps <= 0 then return "Not measured yet"
    rate = Conn_rateLabel(reading.kbps)
    ago = Conn_ago(reading.at)
    if reading.playback then
        if ago = "" then return "Faster than " + rate + " · seen during playback"
        return "Faster than " + rate + " · seen during playback " + ago
    end if
    network = "this connection"
    if reading.transport = "wifi" then network = "Wi-Fi"
    if reading.transport = "ethernet" then network = "Ethernet"
    if reading.lowerBound then rate = "Faster than " + rate
    if ago = "" then return rate + " · measured on " + network
    return rate + " · measured " + ago + " on " + network
end function

function Conn_ago(at as integer) as string
    if at <= 0 then return ""
    now = CreateObject("roDateTime").AsSeconds()
    minutes = (now - at) \ 60
    if minutes < 1 then return "just now"
    if minutes < 60 then return Conn_plural(minutes, "minute") + " ago"
    if minutes < 24 * 60 then return Conn_plural(minutes \ 60, "hour") + " ago"
    return Conn_plural(minutes \ (24 * 60), "day") + " ago"
end function

function Conn_truthy(v as dynamic) as boolean
    t = Type(v)
    if t = "roBoolean" or t = "Boolean" then return v
    return LCase(Str_orEmpty(v)) = "true"
end function

function Conn_plural(n as integer, unit as string) as string
    if n = 1 then return "1 " + unit
    return n.ToStr() + " " + unit + "s"
end function

' A probe reading the server stored for this device, kept for playback starts while it is current.
sub Conn_rememberProbe(probe as dynamic)
    if probe = invalid or Type(probe) <> "roAssociativeArray" then return
    at = Conn_epochSeconds(Str_orEmpty(probe.measured_at))
    kbps = Int(Num_or(probe.kbps, 0))
    if at <= 0 or kbps <= 0 then return
    own = m.global.bandwidthProbe
    if own <> invalid and Type(own) = "roAssociativeArray" and own.serverUrl = m.global.session.serverUrl and own.at >= at then return
    Conn_storeProbe({ kbps: kbps, at: at, transport: Str_orEmpty(probe.transport), lowerBound: Conn_truthy(probe.lower_bound) })
end sub

sub Conn_storeProbe(reading as object)
    reading.serverUrl = m.global.session.serverUrl
    maxAge = 604800
    if m.conn.caps <> invalid and m.conn.caps.maxAge > 0 then maxAge = m.conn.caps.maxAge
    reading.maxAge = maxAge
    if not m.global.hasField("bandwidthProbe") then m.global.addFields({ bandwidthProbe: {} })
    m.global.bandwidthProbe = reading
end sub

' ---------- Values, choices, actions ----------

function Conn_rowValue(id as string) as dynamic
    if id = "bufferingQuality" then return Conn_modeLabel(Settings_bufferingQualityMode())
    if id = "learnedLimit" then return "Reset"
    if id = "connectionSpeed" then
        if m.conn.testing then return "Testing…"
        return "Test speed"
    end if
    return invalid
end function

function Conn_modeLabel(mode as string) as string
    if mode = "never" then return "Never"
    if mode = "ask" then return "Ask first"
    return "Automatically"
end function

function Conn_modeOptions() as object
    return [{ value: "never", label: "Never" }, { value: "ask", label: "Ask first" }, { value: "always", label: "Automatically" }]
end function

sub Conn_resetLimit()
    m.conn.resetFailed = false
    Api_send("DELETE", "/api/v2/playback/connection/learned-limit", invalid, "Conn_onReset")
end sub

sub Conn_onReset(event as object)
    resp = Api_result(event)
    m.conn.resetFailed = not resp.ok
    if resp.ok then
        ' Both the limit row and Auto's budget line come from the next read.
        Conn_reread(false)
    else
        Conn_rerender()
    end if
end sub

' Test speed: the accurate test now, then the connection read again. A second press is ignored.
sub Conn_testSpeed()
    caps = m.conn.caps
    if m.conn.testing or caps = invalid or not caps.speed then return
    m.conn.testing = true
    m.conn.message = ""
    task = CreateObject("roSGNode", "ProbeTask")
    task.observeField("result", "Conn_onProbe")
    task.request = { url: Url_resolve(caps.probeUrl), targetKbps: caps.targetKbps }
    task.control = "RUN"
    m.connProbeTask = task
    refreshValues()
    Conn_rerender()
end sub

sub Conn_onProbe()
    task = m.connProbeTask
    if task = invalid then return
    r = task.result
    m.connProbeTask = invalid
    m.conn.testing = false
    if r = invalid then r = { outcome: "failed" }
    print "[siku-playback] speed test outcome=" + Str_orEmpty(r.outcome) + " kbps=" + Str_orEmpty(r.kbps) + " lower_bound=" + Str_orEmpty(r.lowerBound) + " bytes=" + Str_orEmpty(r.bytes) + " ms=" + Str_orEmpty(r.durationMs) + " method=" + Str_orEmpty(r.method) + " status=" + Str_orEmpty(r.status) + " saved=" + Str_orEmpty(r.saved)
    if r.outcome = "measured" then
        Conn_storeProbe({ kbps: r.kbps, at: CreateObject("roDateTime").AsSeconds(), transport: Str_orEmpty(r.transport), lowerBound: r.lowerBound = true })
        if r.saved <> true then m.conn.message = "Couldn't save the speed test. Try again."
    else if r.outcome = "rate_limited" then
        secs = Int(Num_or(r.retryAfter, 30))
        m.conn.message = "Try again in " + Conn_plural(secs, "second") + "."
    else
        m.conn.message = "Couldn't measure the connection speed. Try again."
    end if
    Conn_reread(true)
    Conn_rerender()
end sub
