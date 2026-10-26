' A minimal Multicast DNS / DNS-SD responder (RFC 6762, RFC 6763) for Siku's two services:
'   _silocast-roku._tcp  remote control (TXT v, id, deviceId, name, server, serverName,
'                        serverIdentity, playing, sec, kid)
'   _silopair-roku._tcp  phone sign-in, only while the server or sign-in screen is up
'                        (TXT v, name, id, sid, st, srv)
' It answers PTR queries for those types (and the _services._dns-sd._udp meta query), SRV/TXT for
' the instance, A for the host, and builds unsolicited announcements and goodbyes. Parsing and
' building are pure so tools/lan_vectors.py checks them against Python; LanTask owns the socket.
' Known-answer suppression, probing and name-conflict renaming are left out: instance and host
' names carry 8 hex digits of the device id, so a collision on one network is not expected.
' SPDX-License-Identifier: AGPL-3.0-or-later

function Mdns_service(serviceType as string, instance as string, port as integer, txt as object) as object
    return { serviceType: serviceType, instance: instance, port: port, txt: txt }
end function

' ---------- Parsing ----------

' {id, isResponse, questions: [{name (lower case, no trailing dot), qtype, unicast}]} or invalid.
function Mdns_parse(b as object) as dynamic
    if b = invalid or b.Count() < 12 then return invalid
    flags = b[2] * 256 + b[3]
    q = { id: b[0] * 256 + b[1], isResponse: (flags and &h8000) <> 0, questions: [] }
    if q.isResponse then return q
    qd = b[4] * 256 + b[5]
    offset = 12
    for i = 1 to qd
        nameRes = Mdns_readName(b, offset)
        if nameRes = invalid then return q
        offset = nameRes.offset
        if offset + 4 > b.Count() then return q
        qtype = b[offset] * 256 + b[offset + 1]
        qclass = b[offset + 2] * 256 + b[offset + 3]
        offset = offset + 4
        q.questions.Push({ name: LCase(nameRes.name), qtype: qtype, unicast: (qclass and &h8000) <> 0 })
    end for
    return q
end function

' A (possibly compressed) name at offset: {name, offset after it}, or invalid.
function Mdns_readName(b as object, offset as integer) as dynamic
    labels = []
    cursor = offset
    after = -1
    jumps = 0
    while true
        if cursor >= b.Count() then return invalid
        n = b[cursor]
        if n = 0 then
            cursor = cursor + 1
            exit while
        else if (n and &hC0) = &hC0 then
            if cursor + 1 >= b.Count() then return invalid
            if after < 0 then after = cursor + 2
            cursor = ((n and &h3F) * 256) + b[cursor + 1]
            jumps = jumps + 1
            if jumps > 16 then return invalid
        else
            if cursor + 1 + n > b.Count() then return invalid
            labels.Push(Lan_slice(b, cursor + 1, n).ToAsciiString())
            cursor = cursor + 1 + n
        end if
    end while
    if after < 0 then after = cursor
    name = ""
    for each l in labels
        if name <> "" then name = name + "."
        name = name + l
    end for
    return { name: name, offset: after }
end function

' ---------- Building ----------

function Mdns_hex16(n as integer) as string
    return Right("0000" + StrI(n and &hFFFF, 16), 4)
end function

function Mdns_hex32(n as integer) as string
    return Mdns_hex16((n >> 16) and &hFFFF) + Mdns_hex16(n and &hFFFF)
end function

function Mdns_nameHex(name as string) as string
    hex = ""
    for each label in name.Split(".")
        if label <> "" then
            lb = Lan_bytes(label)
            n = lb.Count()
            if n > 63 then
                lb = Lan_slice(lb, 0, 63)
                n = 63
            end if
            hex = hex + Right("00" + StrI(n, 16), 2) + lb.ToHexString()
        end if
    end for
    return hex + "00"
end function

function Mdns_txtHex(txt as object) as string
    hex = ""
    for each kv in txt
        entry = Lan_bytes(kv[0] + "=" + Str_orEmpty(kv[1]))
        if entry.Count() > 255 then entry = Lan_slice(entry, 0, 255)
        hex = hex + Right("00" + StrI(entry.Count(), 16), 2) + entry.ToHexString()
    end for
    if hex = "" then hex = "00"
    return hex
end function

function Mdns_aHex(ip as string) as string
    hex = ""
    for each part in ip.Split(".")
        hex = hex + Right("00" + StrI(Int(Val(part)) and 255, 16), 2)
    end for
    return hex
end function

' One resource record. rtype: 1 A, 12 PTR, 16 TXT, 33 SRV. unique records set the cache-flush bit.
function Mdns_record(name as string, rtype as integer, unique as boolean, ttl as integer, rdataHex as string) as string
    cls = 1
    if unique then cls = &h8001
    return Mdns_nameHex(name) + Mdns_hex16(rtype) + Mdns_hex16(cls) + Mdns_hex32(ttl) + Mdns_hex16(Len(rdataHex) \ 2) + rdataHex
end function

function Mdns_fullType(s as object) as string
    return s.serviceType + ".local"
end function

function Mdns_fullInstance(s as object) as string
    return s.instance + "." + s.serviceType + ".local"
end function

function Mdns_ptrRecord(s as object, ttl as integer) as string
    return Mdns_record(Mdns_fullType(s), 12, false, ttl, Mdns_nameHex(Mdns_fullInstance(s)))
end function

function Mdns_srvRecord(s as object, host as string, ttl as integer) as string
    return Mdns_record(Mdns_fullInstance(s), 33, true, ttl, "00000000" + Mdns_hex16(s.port) + Mdns_nameHex(host))
end function

function Mdns_txtRecord(s as object, ttl as integer) as string
    return Mdns_record(Mdns_fullInstance(s), 16, true, ttl, Mdns_txtHex(s.txt))
end function

function Mdns_aRecord(host as string, ip as string, ttl as integer) as string
    return Mdns_record(host, 1, true, ttl, Mdns_aHex(ip))
end function

function Mdns_message(answers as object, additionals as object) as object
    hex = "0000" + "8400" + "0000" + Mdns_hex16(answers.Count()) + "0000" + Mdns_hex16(additionals.Count())
    for each r in answers
        hex = hex + r
    end for
    for each r in additionals
        hex = hex + r
    end for
    return Lan_hexBytes(hex)
end function

' The answer to a parsed query, {bytes, unicast} (unicast: some question asked for a unicast
' reply), or invalid when nothing in it is ours.
function Mdns_respond(query as dynamic, services as object, host as string, ip as string) as dynamic
    if query = invalid or query.isResponse then return invalid
    answers = []
    additionals = []
    seen = {}
    unicast = false
    hostL = LCase(host)
    for each q in query.questions
        matched = false
        anyType = q.qtype = 255
        if q.name = "_services._dns-sd._udp.local" and (q.qtype = 12 or anyType) then
            for each s in services
                answers.Push(Mdns_record("_services._dns-sd._udp.local", 12, false, 4500, Mdns_nameHex(Mdns_fullType(s))))
                matched = true
            end for
        end if
        for each s in services
            if q.name = LCase(Mdns_fullType(s)) and (q.qtype = 12 or anyType) then
                answers.Push(Mdns_ptrRecord(s, 4500))
                Mdns_addOnce(additionals, seen, "srv" + s.instance + s.serviceType, Mdns_srvRecord(s, host, 120))
                Mdns_addOnce(additionals, seen, "txt" + s.instance + s.serviceType, Mdns_txtRecord(s, 4500))
                Mdns_addOnce(additionals, seen, "a", Mdns_aRecord(host, ip, 120))
                matched = true
            else if q.name = LCase(Mdns_fullInstance(s)) then
                if q.qtype = 33 or anyType then
                    answers.Push(Mdns_srvRecord(s, host, 120))
                    Mdns_addOnce(additionals, seen, "a", Mdns_aRecord(host, ip, 120))
                    matched = true
                end if
                if q.qtype = 16 or anyType then
                    answers.Push(Mdns_txtRecord(s, 4500))
                    matched = true
                end if
            end if
        end for
        if q.name = hostL and (q.qtype = 1 or anyType) then
            answers.Push(Mdns_aRecord(host, ip, 120))
            matched = true
        end if
        if matched and q.unicast then unicast = true
    end for
    if answers.Count() = 0 then return invalid
    return { bytes: Mdns_message(answers, additionals), unicast: unicast }
end function

sub Mdns_addOnce(list as object, seen as object, key as string, record as string)
    if seen.DoesExist(key) then return
    seen[key] = true
    list.Push(record)
end sub

' Every record of every service at once: the unsolicited announcement (ttl 4500/120) or, with
' ttl 0, the goodbye that removes them from the phones' caches.
function Mdns_announcement(services as object, host as string, ip as string, ttl as integer) as object
    answers = []
    short = 120
    if ttl = 0 then short = 0
    for each s in services
        answers.Push(Mdns_ptrRecord(s, ttl))
        answers.Push(Mdns_srvRecord(s, host, short))
        answers.Push(Mdns_txtRecord(s, ttl))
    end for
    answers.Push(Mdns_aRecord(host, ip, short))
    return Mdns_message(answers, [])
end function
