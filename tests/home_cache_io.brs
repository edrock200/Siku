' SPDX-License-Identifier: AGPL-3.0-or-later
' Test driver for HomeCacheTask's file functions in brs-cli (tests/test_home_cache.py). brs-cli's
' cachefs: is an in-memory volume, so each call starts from an empty one.

function HomeCacheIo_run(steps as object) as object
    m.hcFs = CreateObject("roFileSystem")
    out = []
    for each st in steps
        owner = HomeCache_ownerSource(m.global.session)
        if st.op = "write" then
            r = homeCacheWrite({ payload: st.payload }, { action: "write", ok: false, status: "miss", reason: "", ownerSource: owner })
        else if st.op = "read" then
            r = homeCacheRead({ action: "read", ok: false, status: "miss", reason: "", ownerSource: owner })
            r.Delete("sections")
        else if st.op = "purge" then
            keep = ""
            if st.keep = true then keep = owner
            r = homeCachePurge({ reason: "test", keepOwnerSource: keep }, { action: "purge", ok: false, status: "", reason: "", ownerSource: "" })
        else if st.op = "corrupt" then
            b = CreateObject("roByteArray")
            b.FromAsciiString("{not json")
            b.WriteFile("cachefs:/" + HomeCache_fileName(homeCacheHash(owner)))
            r = { status: "corrupted" }
        else if st.op = "foreign" then
            b = CreateObject("roByteArray")
            b.FromAsciiString("{}")
            b.WriteFile("cachefs:/siku-home-v1-" + String(64, "b") + ".json")
            b.WriteFile("cachefs:/other-app.json")
            r = { status: "foreign" }
        else if st.op = "switch" then
            s = m.global.session
            s["profileId"] = st.profileId ' brs-cli ParseJson keys are case-sensitive
            m.global.session = s
            r = { status: "switched" }
        else if st.op = "list" then
            names = []
            for each n in m.hcFs.GetDirectoryListing("cachefs:/")
                names.Push(n)
            end for
            names.Sort()
            r = { status: "list", names: names }
        end if
        out.Push(r)
    end for
    return out
end function
