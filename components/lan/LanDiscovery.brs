' Finding Silo servers on this network: the strict DNS-SD reader for `_silo._tcp` answers and the
' reducer that keeps what a five-second scan has heard (Silo server docs/architecture/
' server-discovery.md; Silo Android #597 is the UX reference). Pure BrightScript over roByteArray:
' LanTask feeds it the packets its 5353 socket receives, tools/lan_vectors.py runs it in brs-cli.
' Adapted from ManavA/silo-roku source/core/LanDiscoveryPolicy.brs, AGPL-3.0 (device evidence on a
' C208X / Roku OS 16.0.4), renamed to Siku's style and with Roku's reserved member names avoided.
'
' What counts as an offer (everything else is ignored, never repaired):
'   - a response (QR set, opcode 0, rcode 0, not truncated) of at most 9000 bytes, from a private
'     IPv4 sender (10/8, 172.16/12, 192.168/16) and source port 5353; at most 64 questions and
'     64 records; every name in bounds, at most 16 compression jumps, no pointer visited twice,
'     at most 255 bytes expanded, labels at most 63 bytes; the records must end the packet exactly;
'   - a PTR `_silo._tcp.local.` -> instance, with that instance's SRV (priority 0, weight 0,
'     port > 0) and TXT (`v=1` once, `id=` once, printable, id 1..128 of [A-Za-z0-9_-]) and an A
'     record for the SRV target whose address is the sender itself, all from one sender;
'   - a record with TTL 0 is a goodbye and removes what it names; two different values for one
'     SRV/TXT, or one instance seen at two addresses, ports or ids, is a conflict and that instance
'     is never offered in this scan; 16 conflicts end the scan; at most 16 servers are offered;
'     64 packets that are about _silo._tcp (or break a rule) end the scan.
' An offer is a hint: the server must answer GET /api/v2/system/identity at http://address:port
' with exactly the TXT id before Siku uses it, and the person confirms the address first.
' SPDX-License-Identifier: AGPL-3.0-or-later

' The query Siku multicasts from port 5353: one QM question, PTR _silo._tcp.local.
function LanDisc_queryHex() as string
    return "000000000001000000000000055F73696C6F045F746370056C6F63616C00000C0001"
end function

function LanDisc_scanMs() as integer
    return 5000
end function

' When the query goes out, in milliseconds after the scan starts.
function LanDisc_schedule() as object
    return [0, 1000, 3000]
end function

' ---------- One packet -> records ----------

' The relevant records of one packet ([] when none is about _silo._tcp), or invalid when the packet
' breaks any rule (wrong sender or port, not a clean response, any malformed byte). selfIp (simulator
' tests only, deep link debugLanSelf=1) also accepts the device's own address `selfIp` as a sender.
function LanDisc_records(packet as object, sender as string, sourcePort as integer, selfIp = "" as string) as dynamic
    none = invalid
    if sourcePort <> 5353 then return none
    if not LanDisc_isPrivate(sender) and not (selfIp <> "" and sender = selfIp) then return none
    size = packet.Count()
    if size < 12 or size > 9000 then return none
    flags = LanDisc_word(packet, 2)
    if (flags and &hF80F) <> &h8000 or (flags and &h0200) <> 0 then return none
    questions = LanDisc_word(packet, 4)
    count = LanDisc_word(packet, 6) + LanDisc_word(packet, 8) + LanDisc_word(packet, 10)
    if questions > 64 or count > 64 then return none
    cursor = 12
    for i = 1 to questions
        owner = LanDisc_name(packet, cursor)
        if owner = invalid then return none
        cursor = owner.after + 4
        if cursor > size then return none
    end for
    records = []
    for i = 1 to count
        owner = LanDisc_name(packet, cursor)
        if owner = invalid then return none
        cursor = owner.after
        if cursor + 10 > size then return none
        rtype = LanDisc_word(packet, cursor)
        cls = LanDisc_word(packet, cursor + 2)
        ttl# = packet[cursor + 4] * 16777216# + packet[cursor + 5] * 65536# + packet[cursor + 6] * 256# + packet[cursor + 7]
        length = LanDisc_word(packet, cursor + 8)
        cursor = cursor + 10
        finish = cursor + length
        if finish > size then return none
        rr = { name: owner.name, rtype: rtype, goodbye: ttl# = 0, ttl: ttl#, sender: sender, value: invalid, port: 0, label: "" }
        if (cls and &h7FFF) = 1 then
            if rtype = 12 or rtype = 33 then
                start = cursor
                if rtype = 33 then start = start + 6
                if start >= finish then return none
                target = LanDisc_name(packet, start)
                if target = invalid then return none
                if target.after <> finish then return none
                rr.value = target.name
                rr.label = target.first
                if rtype = 33 then
                    rr.port = LanDisc_word(packet, cursor + 4)
                    if LanDisc_word(packet, cursor) <> 0 or LanDisc_word(packet, cursor + 2) <> 0 or rr.port = 0 then rr.value = invalid
                end if
            else if rtype = 16 then
                rr.value = LanDisc_txtId(packet, cursor, finish)
            else if rtype = 1 then
                if length <> 4 then return none
                rr.value = packet[cursor].ToStr() + "." + packet[cursor + 1].ToStr() + "." + packet[cursor + 2].ToStr() + "." + packet[cursor + 3].ToStr()
            end if
            relevant = false
            if rtype = 12 then
                relevant = rr.name = "_silo._tcp.local." and rr.value <> invalid
            else if rtype = 33 or rtype = 16 then
                relevant = LanDisc_isInstance(rr.name)
            else if rtype = 1 then
                relevant = rr.value = sender and Right(rr.name, 7) = ".local."
            end if
            if relevant then records.Push(rr)
        end if
        cursor = finish
    end for
    if cursor <> size then return none
    return records
end function

function LanDisc_word(packet as object, offset as integer) as integer
    return packet[offset] * 256 + packet[offset + 1]
end function

' A name at offset: {name (lower case, labels joined by ".", trailing "."; ".", "\" and bytes
' outside 32..126 written as \DDD), first (the first label's printable text, case kept), after}.
function LanDisc_name(packet as object, offset as integer) as dynamic
    cursor = offset
    after = -1
    jumps = 0
    visited = {}
    expanded = 1
    value = ""
    first = invalid
    size = packet.Count()
    while true
        if cursor < 12 or cursor >= size then return invalid
        key = cursor.ToStr()
        if visited.DoesExist(key) then return invalid
        visited[key] = true
        length = packet[cursor]
        if length = 0 then
            if after < 0 then after = cursor + 1
            if first = invalid then first = ""
            return { name: value, first: first, after: after }
        else if length >= 192 then
            if cursor + 1 >= size then return invalid
            jumps = jumps + 1
            if jumps > 16 then return invalid
            if after < 0 then after = cursor + 2
            cursor = (length - 192) * 256 + packet[cursor + 1]
        else
            if length > 63 or cursor + length >= size then return invalid
            expanded = expanded + length + 1
            if expanded > 255 then return invalid
            text = ""
            for i = cursor + 1 to cursor + length
                b = packet[i]
                if b = 46 or b = 92 or b < 32 or b > 126 then
                    value = value + "\" + Right("000" + b.ToStr(), 3)
                    text = text + " "
                else
                    value = value + LCase(Chr(b))
                    text = text + Chr(b)
                end if
            end for
            if first = invalid then first = text
            value = value + "."
            cursor = cursor + length + 1
        end if
    end while
    return invalid
end function

' The TXT `id` when the record has `v=1` and `id=` exactly once each and only printable entries.
function LanDisc_txtId(packet as object, cursor as integer, finish as integer) as dynamic
    version = ""
    identity = ""
    seenVersion = false
    seenId = false
    while cursor < finish
        length = packet[cursor]
        cursor = cursor + 1
        if cursor + length > finish then return invalid
        entry = ""
        for i = cursor to cursor + length - 1
            b = packet[i]
            if b < 32 or b > 126 then return invalid
            entry = entry + Chr(b)
        end for
        cursor = cursor + length
        if Left(entry, 2) = "v=" then
            if seenVersion then return invalid
            seenVersion = true
            version = Mid(entry, 3)
        else if Left(entry, 3) = "id=" then
            if seenId then return invalid
            seenId = true
            identity = Mid(entry, 4)
        end if
    end while
    if version <> "1" or not Lan_isServerId(identity) then return invalid
    return identity
end function

function LanDisc_isInstance(name as string) as boolean
    suffix = "._silo._tcp.local."
    return Len(name) > Len(suffix) and Right(name, Len(suffix)) = suffix
end function

' A literal private IPv4 address (10/8, 172.16/12, 192.168/16), no leading zeros.
function LanDisc_isPrivate(address as string) as boolean
    parts = address.Split(".")
    if parts.Count() <> 4 then return false
    octets = []
    for each part in parts
        if Len(part) = 0 or Len(part) > 3 then return false
        for i = 1 to Len(part)
            if Instr(1, "0123456789", Mid(part, i, 1)) = 0 then return false
        end for
        n = Int(Val(part))
        if n > 255 or n.ToStr() <> part then return false
        octets.Push(n)
    end for
    a = octets[0]
    b = octets[1]
    return a = 10 or (a = 172 and b >= 16 and b <= 31) or (a = 192 and b = 168)
end function

' Values that may be invalid compared without ever comparing invalid with a string.
function LanDisc_same(a as dynamic, b as dynamic) as boolean
    if a = invalid or b = invalid then return a = invalid and b = invalid
    return a = b
end function

' ---------- Records -> offers ----------

' {instance, label, host, serverId, address, port} for every complete, unconflicted instance.
function LanDisc_candidates(records as object, conflicts as object, limit = 16 as integer) as object
    offers = []
    ' Indexed loops only: a nested `for each` over the same array shares one iterator, so the
    ' outer loop would stop after the first offer.
    for pi = 0 to records.Count() - 1
        ptr = records[pi]
        if ptr.rtype = 12 and not ptr.goodbye and ptr.value <> invalid then
            instance = ptr.value
            blocked = false
            for each c in conflicts
                if c = instance then blocked = true
            end for
            if LanDisc_isInstance(instance) and not blocked then
                srv = LanDisc_unique(records, instance, 33, ptr.sender)
                txt = LanDisc_unique(records, instance, 16, ptr.sender)
                if srv <> invalid and txt <> invalid then
                    addr = LanDisc_unique(records, srv.value, 1, ptr.sender)
                    if addr <> invalid then
                        duplicate = false
                        for oi = 0 to offers.Count() - 1
                            if offers[oi].instance = instance and offers[oi].address = ptr.sender then duplicate = true
                        end for
                        if not duplicate and offers.Count() < limit then
                            offers.Push({ instance: instance, label: ptr.label, host: srv.value, serverId: txt.value, address: ptr.sender, port: srv.port })
                        end if
                    end if
                end if
            end if
        end if
    end for
    return offers
end function

' The one live record of that owner, type and sender; invalid when missing, unusable or ambiguous.
function LanDisc_unique(records as object, owner as string, rtype as integer, sender as string) as dynamic
    found = invalid
    for ri = 0 to records.Count() - 1
        rr = records[ri]
        if rr.name = owner and rr.rtype = rtype and rr.sender = sender and not rr.goodbye then
            if rr.value = invalid then return invalid
            if found <> invalid then
                if not LanDisc_same(rr.value, found.value) then return invalid
                if rtype = 33 and rr.port <> found.port then return invalid
            end if
            found = rr
        end if
    end for
    return found
end function

' ---------- The scan's state ----------

function LanDisc_new(atMs as integer) as object
    return { candidates: [], records: [], conflicts: [], packets: 0, now: atMs, deadline: atMs + LanDisc_scanMs(), closed: false }
end function

' Drops records whose TTL ran out and recomputes the offers.
function LanDisc_advance(state as object, atMs as integer) as object
    if atMs < state.now then return state
    kept = []
    for each rr in state.records
        if rr.expires > atMs then kept.Push(rr)
    end for
    state.records = kept
    state.now = atMs
    if atMs >= state.deadline then state.closed = true
    state.candidates = LanDisc_candidates(state.records, state.conflicts)
    return state
end function

' Adds one received packet to the scan.
function LanDisc_reduce(state as object, packet as object, sender as string, sourcePort as integer, atMs as integer, selfIp = "" as string) as object
    if atMs < state.now then return state
    state = LanDisc_advance(state, atMs)
    if state.closed then return state
    incomingRecords = LanDisc_records(packet, sender, sourcePort, selfIp)
    ' The 64-packet budget counts packets about _silo._tcp and packets that break the rules, not
    ' other devices' ordinary mDNS traffic (a Siku change: a busy network ended scans early).
    if incomingRecords = invalid then
        incomingRecords = []
        state.packets = state.packets + 1
    else if incomingRecords.Count() > 0 then
        state.packets = state.packets + 1
    end if
    for each incoming in incomingRecords
        retained = []
        for each cached in state.records
            sameKey = cached.name = incoming.name and cached.rtype = incoming.rtype and cached.sender = incoming.sender
            if sameKey and incoming.rtype = 12 then sameKey = LanDisc_same(cached.value, incoming.value)
            if sameKey then
                sameValue = LanDisc_same(cached.value, incoming.value)
                if incoming.rtype = 33 and cached.port <> incoming.port then sameValue = false
                if incoming.goodbye then
                    if not sameValue then retained.Push(cached)
                else if not sameValue then
                    ' Two values for one record: neither is believed.
                    incoming.value = invalid
                end if
            else
                retained.Push(cached)
            end if
        end for
        if not incoming.goodbye then
            ' Only expiry within this scan matters (no uint32 TTL arithmetic).
            lifetime = 6000
            if incoming.ttl < 6 then lifetime = Int(incoming.ttl * 1000)
            incoming.expires = atMs + lifetime
            if retained.Count() < 64 then retained.Push(incoming)
            if incoming.value = invalid and (incoming.rtype = 33 or incoming.rtype = 16) then LanDisc_block(state.conflicts, incoming.name)
        end if
        state.records = retained
    end for
    all = LanDisc_candidates(state.records, state.conflicts, 64)
    for ai = 0 to all.Count() - 1
        a = all[ai]
        for bi = 0 to all.Count() - 1
            b = all[bi]
            if a.instance = b.instance and (a.address <> b.address or a.port <> b.port or a.serverId <> b.serverId) then LanDisc_block(state.conflicts, a.instance)
        end for
    end for
    if state.conflicts.Count() >= 16 then
        state.records = []
        state.candidates = []
        state.closed = true
    else
        state.candidates = LanDisc_candidates(state.records, state.conflicts)
    end if
    if state.packets >= 64 then state.closed = true
    return state
end function

sub LanDisc_block(conflicts as object, instance as string)
    for each c in conflicts
        if c = instance then return
    end for
    if conflicts.Count() < 16 then conflicts.Push(instance)
end sub

' ---------- What the screen shows ----------

' The instance's own name, kept short and printable (the literal address is shown beside it).
function LanDisc_displayName(label as dynamic) as string
    t = Type(label)
    if t <> "String" and t <> "roString" then return ""
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ._-()'&"
    out = ""
    lastSpace = true
    for i = 1 to Len(label)
        ch = Mid(label, i, 1)
        if Instr(1, allowed, ch) = 0 then ch = " "
        if ch = " " then
            if not lastSpace then out = out + " "
            lastSpace = true
        else
            out = out + ch
            lastSpace = false
        end if
        if Len(out) >= 48 then exit for
    end for
    return out.Trim()
end function

' The offers as the screen lists them: {name, url, address, port, serverId}.
function LanDisc_servers(candidates as object) as object
    out = []
    for each c in candidates
        url = "http://" + c.address + ":" + c.port.ToStr()
        out.Push({ name: LanDisc_displayName(c.label), url: url, address: c.address, port: c.port, serverId: c.serverId })
    end for
    return out
end function
