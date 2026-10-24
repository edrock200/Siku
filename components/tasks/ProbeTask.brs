' SPDX-License-Identifier: AGPL-3.0-or-later
' The connection speed test, on a Task thread (roUrlTransfer, roFileSystem, roMessagePort).
'
' Android reads the probe body as it arrives and counts bytes in 500 ms windows from the first
' byte (SpeedTestMeter): window 0 (TCP ramp-up) never counts, and the rate is the bytes of the last
' complete windows (up to 6, the accurate test's 3 seconds) over their time. A Roku app cannot read
' a download as it streams, so the probe goes to a tmp: file whose size is sampled every 100 ms.
' When the file grows as the bytes arrive the windows are measured the same way (method "windows").
' When it does not (the size appears only at the end), or the whole download ends before one
' complete window after window 0, the result is the average over the whole transfer, reported as a
' lower bound ("Faster than ..."), since request latency and ramp-up only make it smaller
' (method "average"). The test stops 10 s after the first byte, or 10 s without one.

function Probe_const() as object
    return { WINDOW_MS: 500, SETTLE_WINDOWS: 6, MAX_MS: 10000, FIRST_BYTE_MS: 10000, MIN_KBPS: 100, MAX_KBPS: 1000000, MIN_BYTES: 2000000, MAX_BYTES: 48000000 }
end function

sub init()
    m.top.functionName = "runProbe"
end sub

sub runProbe()
    c = Probe_const()
    req = m.top.request
    if req = invalid then req = {}
    session = m.global.session
    ' Bytes asked for: four seconds at the server's target rate, within 2 MB .. 48 MB (tmp: is RAM).
    target = Int(Num_or(req.targetKbps, 0))
    if target <= 0 then target = 50000
    size = target * 125 * 4
    if size < c.MIN_BYTES then size = c.MIN_BYTES
    if size > c.MAX_BYTES then size = c.MAX_BYTES
    url = Str_orEmpty(req.url)
    if Instr(1, url, "?") > 0 then url = url + "&size=" + size.ToStr() else url = url + "?size=" + size.ToStr()

    path = "tmp:/siku-probe.bin"
    fs = CreateObject("roFileSystem")
    fs.Delete(path)
    xfer = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    xfer.SetUrl(url)
    xfer.RetainBodyOnError(true)
    if LCase(Left(url, 5)) = "https" then
        xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
        xfer.InitClientCertificates()
    end if
    headers = Http_deviceHeaders(session)
    headers["Accept"] = "application/octet-stream"
    headers["Authorization"] = "Bearer " + Str_orEmpty(session.accessToken)
    if not Str_isEmpty(session.profileId) then headers["X-Profile-Id"] = session.profileId
    for each k in headers
        xfer.AddHeader(k, headers[k])
    end for
    clock = CreateObject("roTimespan")
    clock.Mark()
    if not xfer.AsyncGetToFile(path) then
        m.top.result = { outcome: "failed", status: 0 }
        return
    end if

    firstAt = -1
    samples = []      ' [ms since the first byte, bytes so far]
    status = -1
    respHeaders = {}
    endAt = -1
    while true
        msg = Wait(100, port)
        now = clock.TotalMilliseconds()
        sz = Probe_size(fs, path)
        if Type(msg) = "roUrlEvent" then
            status = msg.GetResponseCode()
            respHeaders = msg.GetResponseHeaders()
            if sz > 0 and firstAt < 0 then firstAt = now
            if firstAt >= 0 then samples.Push([now - firstAt, sz])
            endAt = now
            exit while
        end if
        if sz > 0 then
            if firstAt < 0 then firstAt = now
            samples.Push([now - firstAt, sz])
        end if
        if firstAt < 0 and now >= c.FIRST_BYTE_MS then
            xfer.AsyncCancel()
            exit while
        end if
        if firstAt >= 0 and now - firstAt >= c.MAX_MS then
            xfer.AsyncCancel()
            status = 200
            exit while
        end if
    end while
    fs.Delete(path)

    if status = 429 then
        retry = 30
        if respHeaders <> invalid and respHeaders["retry-after"] <> invalid then retry = Int(Val(Str_orEmpty(respHeaders["retry-after"])))
        if retry <= 0 then retry = 30
        m.top.result = { outcome: "rate_limited", retryAfter: retry, status: 429 }
        return
    end if
    if status <> 200 then
        outcome = "unavailable"
        if status <= 0 then outcome = "failed"
        m.top.result = { outcome: outcome, status: status }
        return
    end if

    measured = Probe_measure(samples, endAt - firstAt, c)
    if measured = invalid and samples.Count() > 0 and endAt > 0 then
        ' The size showed only at the end: the whole transfer from the request, a lower bound.
        total = samples[samples.Count() - 1][1]
        measured = { kbps: Int(total * 8.0 / endAt), lowerBound: true, bytes: total, durationMs: endAt, method: "average" }
    end if
    if measured = invalid or measured.kbps < c.MIN_KBPS then
        m.top.result = { outcome: "failed", status: status }
        return
    end if
    if measured.kbps > c.MAX_KBPS then
        measured.kbps = c.MAX_KBPS
        measured.lowerBound = true
    end if

    measured.transport = Probe_transport()
    body = { kbps: measured.kbps, bytes: measured.bytes, duration_ms: measured.durationMs, transport: measured.transport, manual: true }
    if measured.lowerBound then body.lower_bound = true
    postHeaders = Http_deviceHeaders(session)
    postHeaders["Authorization"] = "Bearer " + Str_orEmpty(session.accessToken)
    if not Str_isEmpty(session.profileId) then postHeaders["X-Profile-Id"] = session.profileId
    ' The result goes to the API server, whichever host served the probe.
    posted = Http_send("POST", Str_orEmpty(session.serverUrl) + "/api/v2/playback/bandwidth-probe/results", postHeaders, body, 15)
    measured.outcome = "measured"
    measured.saved = posted.status >= 200 and posted.status < 300
    measured.status = status
    m.top.result = measured
end sub

function Probe_size(fs as object, path as string) as integer
    st = fs.Stat(path)
    if st = invalid or Type(st) <> "roAssociativeArray" then return 0
    return Int(Num_or(st.size, 0))
end function

' The windowed rate from [t, bytes] samples, or invalid when the file never showed its growth.
function Probe_measure(samples as object, endMs as integer, c as object) as dynamic
    if samples.Count() < 3 then return invalid
    lastT = samples[samples.Count() - 1][0]
    total = samples[samples.Count() - 1][1]
    complete = Int(lastT / c.WINDOW_MS)   ' windows 0 .. complete-1 are complete
    if complete < 2 then
        ' Everything arrived before one complete window after window 0: the whole transfer's
        ' average from the first byte, as a lower bound.
        if endMs <= 0 then return invalid
        return { kbps: Int(total * 8.0 / endMs), lowerBound: true, bytes: total, durationMs: endMs, method: "average" }
    end if
    first = complete - c.SETTLE_WINDOWS
    if first < 1 then first = 1
    fromBytes = Probe_bytesAt(samples, first * c.WINDOW_MS)
    toBytes = Probe_bytesAt(samples, complete * c.WINDOW_MS)
    windows = complete - first
    kbps = Int((toBytes - fromBytes) * 8.0 / (windows * c.WINDOW_MS))
    return { kbps: kbps, lowerBound: false, bytes: total, durationMs: lastT, method: "windows" }
end function

' Bytes received by time t (the last sample at or before it).
function Probe_bytesAt(samples as object, t as integer) as integer
    b = 0
    for each s in samples
        if s[0] <= t then b = s[1]
    end for
    return b
end function

function Probe_transport() as string
    di = CreateObject("roDeviceInfo")
    t = LCase(Str_orEmpty(di.GetConnectionType()))
    if Instr(1, t, "wifi") > 0 then return "wifi"
    if Instr(1, t, "wired") > 0 then return "ethernet"
    return "other"
end function
