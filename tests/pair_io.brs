' SPDX-License-Identifier: AGPL-3.0-or-later
' Test driver for the phone session binding in LanBytes.brs (tests/test_pair_session.py): byte
' arrays cannot cross brs-cli's JSON boundary, so hex goes in and strings come out.

function PairIo_binding(hex as string) as object
    return Lan_bindingFor(Lan_hexBytes(hex))
end function

' Two new secrets: their lengths and whether they differ (never their values).
function PairIo_secrets() as object
    a = Lan_bindingSecret("dev-1")
    b = Lan_bindingSecret("dev-1")
    return { "a": a.Count(), "b": b.Count(), "differ": Lan_hex(a) <> Lan_hex(b) }
end function
