' Level `sealed` of the SiloCast control channel, the Roku receiver's side (port of the phone's
' SiloCastSealed.kt; vectors in tools/lan_vectors.py). Roku sockets have no TLS, so a Roku that
' requires pairing seals each frame itself with keys derived from the 16-byte pairing key the
' phone scanned from Siku's Connect a Phone screen:
'   - each side opens with one plain `sealed_hello` frame {type, v:1, keyId, nonce(base64url)};
'   - HKDF-SHA256 over both nonces (phone's first) derives enc (16), mac (32) and iv (16) keys;
'   - every later frame body is seq(8, big-endian) || iv(16) || AES-128-CBC ciphertext || tag(32),
'     tag = HMAC-SHA256(mac, "silo-cast-sealed-1" || direction || seq || iv || ciphertext),
'     direction 0x01 from the phone, 0x02 from the TV, seq counting from 0 per direction;
'   - the TV's IV is AES-128-ECB(ivKey, direction || seq || zero padding): unique per frame and
'     unpredictable without the key, so no random source is needed per frame.
' Keys and nonces never reach the console.
' SPDX-License-Identifier: AGPL-3.0-or-later

function Sealed_label() as string
    return "silo-cast-sealed-1"
end function

function Sealed_fromPhone() as integer
    return 1
end function

function Sealed_fromTv() as integer
    return 2
end function

function Sealed_hmac(key as object, message as object) as object
    h = CreateObject("roHMAC")
    if h.Setup("sha256", key) <> 0 then return CreateObject("roByteArray")
    return h.Process(message)
end function

' The first 8 hex digits of SHA-256 of the key: TXT `kid` and sealed_hello.keyId.
function Sealed_keyId(key as object) as string
    return Left(Lan_hex(Lan_sha256(key)), 8)
end function

function Sealed_sessionKeys(key as object, phoneNonce as object, tvNonce as object) as object
    prk = Sealed_hmac(Lan_concat([phoneNonce, tvNonce]), key)
    one = Lan_hexBytes("01")
    enc = Sealed_hmac(prk, Lan_concat([Lan_bytes(Sealed_label() + " enc"), one]))
    mac = Sealed_hmac(prk, Lan_concat([Lan_bytes(Sealed_label() + " mac"), one]))
    ivk = Sealed_hmac(prk, Lan_concat([Lan_bytes(Sealed_label() + " iv"), one]))
    return { encKey: Lan_slice(enc, 0, 16), macKey: mac, ivKey: Lan_slice(ivk, 0, 16) }
end function

' One AES-128 block. CBC with a zero IV over one block equals ECB; the simulator's roEVPCipher
' refuses an empty IV, so this form runs in both.
function Sealed_aesBlock(key as object, block as object) as object
    c = CreateObject("roEVPCipher")
    if c.Setup(true, "aes-128-cbc", Lan_hex(key), "00000000000000000000000000000000", 1) <> 0 then return CreateObject("roByteArray")
    out = c.Process(block)
    if out = invalid then return CreateObject("roByteArray")
    return Lan_slice(out, 0, 16)
end function

function Sealed_tvIv(keys as object, direction as integer, seq as integer) as object
    d = CreateObject("roByteArray")
    d.Push(direction)
    block = Lan_concat([d, Lan_seq8(seq), Lan_hexBytes("00000000000000")])
    return Sealed_aesBlock(keys.ivKey, block)
end function

function Sealed_tag(keys as object, direction as integer, signed as object) as object
    d = CreateObject("roByteArray")
    d.Push(direction)
    return Sealed_hmac(keys.macKey, Lan_concat([Lan_bytes(Sealed_label()), d, signed]))
end function

' Seals one frame body. iv invalid: the TV's derived IV.
function Sealed_seal(keys as object, direction as integer, seq as integer, plaintext as object, iv = invalid as dynamic) as object
    if iv = invalid then iv = Sealed_tvIv(keys, direction, seq)
    c = CreateObject("roEVPCipher")
    if c.Setup(true, "aes-128-cbc", Lan_hex(keys.encKey), Lan_hex(iv), 1) <> 0 then return invalid
    ct = c.Process(plaintext)
    if ct = invalid then return invalid
    signed = Lan_concat([Lan_seq8(seq), iv, ct])
    return Lan_concat([signed, Sealed_tag(keys, direction, signed)])
end function

' Opens a body sealed in `direction` with sequence `expectedSeq`, tag first. invalid for any
' failure: tampered, replayed, reordered, misdirected or short.
function Sealed_open(keys as object, direction as integer, expectedSeq as integer, body as object) as dynamic
    if body = invalid or body.Count() < 8 + 16 + 16 + 32 then return invalid
    signed = Lan_slice(body, 0, body.Count() - 32)
    tag = Lan_slice(body, body.Count() - 32, 32)
    if not Lan_bytesEqual(Sealed_tag(keys, direction, signed), tag) then return invalid
    if Lan_hex(Lan_slice(signed, 0, 8)) <> Lan_hex(Lan_seq8(expectedSeq)) then return invalid
    iv = Lan_slice(signed, 8, 16)
    ct = Lan_slice(signed, 24, signed.Count() - 24)
    c = CreateObject("roEVPCipher")
    if c.Setup(false, "aes-128-cbc", Lan_hex(keys.encKey), Lan_hex(iv), 1) <> 0 then return invalid
    out = c.Process(ct)
    return out
end function

function Sealed_helloText(keyId as string, nonce as object) as string
    return FormatJson({ "type": "sealed_hello", "v": 1, "keyId": keyId, "nonce": Lan_base64url(nonce) })
end function

' A peer's sealed_hello as {keyId, nonce}, or invalid for anything else.
function Sealed_readHello(text as dynamic) as dynamic
    if text = invalid then return invalid
    frame = ParseJson(text)
    if frame = invalid or Type(frame) <> "roAssociativeArray" then return invalid
    if Str_orEmpty(frame["type"]) <> "sealed_hello" then return invalid
    kid = LCase(Str_orEmpty(frame.keyId))
    if not CreateObject("roRegex", "^[0-9a-f]{8}$", "").IsMatch(kid) then return invalid
    nonceText = frame.nonce
    if Type(nonceText) <> "String" and Type(nonceText) <> "roString" then return invalid
    nonce = Lan_fromBase64url(nonceText)
    if nonce = invalid or nonce.Count() <> 16 then return invalid
    return { keyId: kid, nonce: nonce }
end function
