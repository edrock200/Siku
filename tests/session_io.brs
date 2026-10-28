' SPDX-License-Identifier: AGPL-3.0-or-later
' Test driver for Session_homeCacheCheck in brs-cli (tests/test_home_cache.py): what it asked
' MainScene to do, read back from the plain-array m.global.

function SessionIo_check(prev as dynamic) as object
    Session_homeCacheCheck(prev)
    ' brs-cli keeps ParseJson keys case-sensitive while dot assignment stores lower case, so the
    ' seeded field and the written one can be two keys: read both.
    out = { purge: 0, reason: "" }
    for each k in m.global
        lk = LCase(k)
        v = m.global[k]
        if lk = "homecachepurge" and v > out.purge then out.purge = v
        if lk = "homecachepurgereason" and v <> "" then out.reason = v
    end for
    return out
end function
