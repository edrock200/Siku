' Runs Siku's LAN byte and crypto code over cases.json and prints the results as one JSON line
' ("LAN-VECTORS <json>") for tools/lan_vectors.py to compare with the phone's vectors and its
' Python reference. brs-cli only; not part of the channel.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub main()
    cases = ParseJson(ReadAsciiFile("pkg:/cases.json"))
    out = { sealed: [], keys: [], links: [], mdns: [], frames: [] }
    for each c in cases.sealed
        key = Lan_hexBytes(c.key)
        keys = Sealed_sessionKeys(key, Lan_hexBytes(c.phoneNonce), Lan_hexBytes(c.tvNonce))
        r = { keyId: Sealed_keyId(key), enc: Lan_hex(keys.encKey), mac: Lan_hex(keys.macKey), iv: Lan_hex(keys.ivKey) }
        r["tvIv"] = Lan_hex(Sealed_tvIv(keys, Sealed_fromTv(), c.tvSeq))
        sealedBody = Sealed_seal(keys, Sealed_fromTv(), c.tvSeq, Lan_bytes(c.tvPlain))
        r["tvSealed"] = Lan_hex(sealedBody)
        opened = Sealed_open(keys, Sealed_fromPhone(), c.phoneSeq, Lan_hexBytes(c.phoneSealed))
        if opened = invalid then r["phoneOpened"] = invalid else r["phoneOpened"] = opened.ToAsciiString()
        ' Refusals: replayed seq, other direction, tampered byte.
        r["replayRefused"] = Sealed_open(keys, Sealed_fromPhone(), c.phoneSeq + 1, Lan_hexBytes(c.phoneSealed)) = invalid
        r["directionRefused"] = Sealed_open(keys, Sealed_fromTv(), c.phoneSeq, Lan_hexBytes(c.phoneSealed)) = invalid
        t = Lan_hexBytes(c.phoneSealed)
        t[30] = (t[30] + 1) and 255
        r["tamperRefused"] = Sealed_open(keys, Sealed_fromPhone(), c.phoneSeq, t) = invalid
        r["helloText"] = Sealed_helloText(Sealed_keyId(key), Lan_hexBytes(c.tvNonce))
        h = Sealed_readHello(c.phoneHello)
        if h = invalid then r["phoneHello"] = invalid else r["phoneHello"] = { keyId: h.keyId, nonce: Lan_hex(h.nonce) }
        out.sealed.Push(r)
    end for
    for each k in cases.keys
        parsed = Lan_parseKey(k.text)
        if parsed = invalid then p = invalid else p = Lan_hex(parsed)
        out.keys.Push({ text: k.text, parsed: p, base32: Lan_base32(Lan_hexBytes(k.hex)) })
    end for
    for each u in cases.servers
        out.links.Push({ url: u, id: Lan_serverIdFor(u), back: Lan_urlForServerId(Lan_serverIdFor(u)) })
    end for
    rnd = Lan_randomBytes(16)
    out["random"] = { count: rnd.Count(), differs: Lan_hex(rnd) <> Lan_hex(Lan_randomBytes(16)) }
    out["match"] = {
        sameId: Lan_serversMatch(Lan_serverIdFor("https://a.example/"), "", Lan_serverIdFor("https://A.example"), "")
        sameIdentity: Lan_serversMatch("x", "srv-1", "y", "srv-1")
        different: Lan_serversMatch(Lan_serverIdFor("https://a.example"), "srv-1", Lan_serverIdFor("https://b.example"), "srv-2")
    }
    ' mDNS: answer the query bytes the Python side built, for the advertised services.
    for each q in cases.mdns
        services = [Mdns_service("_silocast-roku._tcp", "Siku-0123abcd", 52817, [["v", "2"], ["id", "roku-1"], ["name", "Den Roku"], ["sec", "sealed"], ["kid", "be45cb26"]])]
        query = Mdns_parse(Lan_hexBytes(q))
        resp = Mdns_respond(query, services, "siku-0123abcd.local", "192.168.1.20")
        if resp = invalid then out.mdns.Push(invalid) else out.mdns.Push(Lan_hex(resp.bytes))
    end for
    out["announce"] = Lan_hex(Mdns_announcement([Mdns_service("_silopair-roku._tcp", "Siku-0123abcd", 52819, [["v", "1"], ["st", "setup"]])], "siku-0123abcd.local", "192.168.1.20", 4500))
    ' Framing: a split stream yields whole frames.
    fb = LanFrames_new()
    stream = Lan_concat([Lan_u32be(3), Lan_bytes("abc"), Lan_u32be(2), Lan_bytes("de")])
    got = []
    for each part in [Lan_slice(stream, 0, 2), Lan_slice(stream, 2, 5), Lan_slice(stream, 7, 6)]
        for each f in LanFrames_append(fb, part)
            got.Push(f.ToAsciiString())
        end for
    end for
    out["frames"] = got
    tooBig = LanFrames_new()
    LanFrames_append(tooBig, Lan_hexBytes("80000000"))
    out["tooBigRefused"] = tooBig.failed = true
    print "LAN-VECTORS " + FormatJson(out)
end sub
