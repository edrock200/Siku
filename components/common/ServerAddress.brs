' SPDX-License-Identifier: AGPL-3.0-or-later
' The typed server address with Advanced options' protocol and port (Silo Android TV #758/#771,
' Apple TV's ServerSetupViewModel): pure, host-tested in tests/test_server_address.py.
' Adapted from Silo-Server/silo-roku, AGPL-3.0 (source/onboarding/address.bs) and Silo Android's
' ServerSetupAddress.kt. Unlike Android, Auto never adds http://host:8090 on its own: every
' plain-HTTP address goes through the "Connect without encryption?" question (as sroku decides,
' docs/spec.md), and a port has to be asked for.
'   scheme  "auto" | "https" | "http": a chosen protocol replaces a typed one; Auto keeps a typed
'           one, else tries https:// then http://
'   port    the Port field ("" = auto); a port typed in the address wins over it
' Returns { error: "" | message, candidates: [base URLs to probe, in order] }.

function ServerAddr_candidates(raw as dynamic, scheme as dynamic, port as dynamic) as object
    input = Str_orEmpty(raw).Trim()
    if input = "" then return ServerAddr_fail(Tx("Please enter a server host."))
    typedScheme = ""
    rest = input
    i = Instr(1, input, "://")
    if i > 0 then
        typedScheme = LCase(Left(input, i - 1))
        rest = Mid(input, i + 3)
        if typedScheme <> "http" and typedScheme <> "https" then return ServerAddr_fail(Tx("Use an address that starts with https:// or http://."))
    end if
    ' Authority, then an optional path (a server behind a reverse-proxy prefix).
    cut = Len(rest) + 1
    for each sep in ["/", "?", "#"]
        j = Instr(1, rest, sep)
        if j > 0 and j < cut then cut = j
    end for
    authority = Left(rest, cut - 1)
    path = Mid(rest, cut)
    if Left(path, 1) = "?" or Left(path, 1) = "#" then return ServerAddr_fail(ServerAddr_invalid())
    while Len(path) > 0 and Right(path, 1) = "/"
        path = Left(path, Len(path) - 1)
    end while
    if Instr(1, path, " ") > 0 or Instr(1, path, "?") > 0 or Instr(1, path, "#") > 0 then return ServerAddr_fail(ServerAddr_invalid())
    if Instr(1, authority, "@") > 0 then return ServerAddr_fail(Tx("Remove the user name and password from the address."))
    host = authority
    typedPort = ""
    if Left(authority, 1) = "[" then
        rb = Instr(1, authority, "]")
        if rb = 0 then return ServerAddr_fail(ServerAddr_invalid())
        host = Left(authority, rb)
        after = Mid(authority, rb + 1)
        if after <> "" then
            if Left(after, 1) <> ":" then return ServerAddr_fail(ServerAddr_invalid())
            typedPort = Mid(after, 2)
            if typedPort = "" then return ServerAddr_fail(ServerAddr_invalid())
        end if
        if not ServerAddr_isIpv6(Mid(host, 2, Len(host) - 2)) then return ServerAddr_fail(ServerAddr_invalid())
    else
        colon = Instr(1, authority, ":")
        if colon > 0 then
            host = Left(authority, colon - 1)
            typedPort = Mid(authority, colon + 1)
            if typedPort = "" or Instr(1, typedPort, ":") > 0 then return ServerAddr_fail(ServerAddr_invalid())
        end if
        if not ServerAddr_isHost(host) then return ServerAddr_fail(ServerAddr_invalid())
    end if
    effPort = ""
    if typedPort <> "" then
        if not ServerAddr_isDigits(typedPort) then return ServerAddr_fail(ServerAddr_invalid())
        if not ServerAddr_isPort(typedPort) then return ServerAddr_fail(ServerAddr_portError())
        effPort = ServerAddr_portText(typedPort)
    end if
    fieldPort = Str_orEmpty(port).Trim()
    if fieldPort <> "" then
        if not ServerAddr_isPort(fieldPort) then return ServerAddr_fail(ServerAddr_portError())
        if effPort = "" then effPort = ServerAddr_portText(fieldPort)
    end if
    chosen = LCase(Str_orEmpty(scheme))
    schemes = ["https", "http"]
    if chosen = "https" or chosen = "http" then
        schemes = [chosen]
    else if typedScheme <> "" then
        schemes = [typedScheme]
    end if
    out = []
    for each sc in schemes
        u = sc + "://" + LCase(host)
        if effPort <> "" then u = u + ":" + effPort
        out.Push(u + path)
    end for
    return { error: "", candidates: out }
end function

function ServerAddr_fail(msg as string) as object
    return { error: msg, candidates: [] }
end function

function ServerAddr_invalid() as string
    return Tx("Enter a valid server address.")
end function

function ServerAddr_portError() as string
    return Tx("Port must be a number between 1 and 65535.")
end function

function ServerAddr_isDigits(s as string) as boolean
    if s = "" then return false
    for i = 1 to Len(s)
        c = Asc(Mid(s, i, 1))
        if c < 48 or c > 57 then return false
    end for
    return true
end function

function ServerAddr_isPort(s as string) as boolean
    if not ServerAddr_isDigits(s) or Len(s) > 5 then return false
    n = Val(s)
    return n >= 1 and n <= 65535
end function

' "08090" -> "8090"
function ServerAddr_portText(s as string) as string
    return Int(Val(s)).ToStr()
end function

' A DNS name or IPv4 address: letters, digits, "-", "_" and "."; no empty label, no label that
' starts or ends with "-".
function ServerAddr_isHost(h as string) as boolean
    if h = "" or Len(h) > 253 then return false
    labels = h.Split(".")
    for i = 0 to labels.Count() - 1
        l = labels[i]
        if l = "" then
            ' One trailing dot ("media.example.com.") is still a host.
            if not (i = labels.Count() - 1 and i > 0) then return false
        else
            if Left(l, 1) = "-" or Right(l, 1) = "-" or Len(l) > 63 then return false
            for k = 1 to Len(l)
                c = Asc(Mid(l, k, 1))
                ok = (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c = 45 or c = 95
                if not ok then return false
            end for
        end if
    end for
    return true
end function

function ServerAddr_isIpv6(h as string) as boolean
    if h = "" or Instr(1, h, ":") = 0 then return false
    for k = 1 to Len(h)
        c = Asc(Mid(h, k, 1))
        ok = (c >= 48 and c <= 57) or (c >= 65 and c <= 70) or (c >= 97 and c <= 102) or c = 58 or c = 46
        if not ok then return false
    end for
    return true
end function

' The server's own reason when the last address tried answered an HTTP error with one
' (Silo Android #771), else "" (a bare error, or nothing answered).
function ServerAddr_serverMessage(status as dynamic, err as dynamic) as string
    st = Int(Num_or(status, 0))
    if st < 400 then return ""
    if err = invalid or Type(err) <> "roAssociativeArray" then return ""
    reason = Str_orEmpty(err.detail).Trim()
    if reason <> "" then return reason
    title = Str_orEmpty(err.title).Trim()
    if title <> "" and Left(title, 20) <> "Something went wrong" then return title
    return ""
end function

' The address screen's message when no address answered as a Silo v2 server.
function ServerAddr_unreachableText(scheme as dynamic, serverMessage as dynamic) as string
    msg = Str_orEmpty(serverMessage).Trim()
    if msg <> "" then return TxF("Could not reach server: {0}", [msg])
    if LCase(Str_orEmpty(scheme)) = "https" then return Tx("Could not reach a Silo server at that address over HTTPS.")
    return Tx("Could not reach a Silo server at that address.")
end function
