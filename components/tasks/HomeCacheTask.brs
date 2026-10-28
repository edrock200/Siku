' SPDX-License-Identifier: AGPL-3.0-or-later
' Home cache file I/O (see HomeCache.brs and HomeCacheTask.xml). Every failure of the storage
' (evicted, full, unsupported, corrupt) is an ordinary miss; nothing here may throw to the user.
' Log lines are `[siku-home] cache ...` and never carry URLs, ids or tokens.

sub init()
    m.top.functionName = "runHomeCache"
end sub

sub runHomeCache()
    job = m.top.job
    action = ""
    if job <> invalid then action = Str_orEmpty(job.action)
    result = { action: action, ok: false, status: "miss", reason: "", ownerSource: "" }
    if job <> invalid then result.ownerSource = Str_orEmpty(job.ownerSource)
    try
        m.hcFs = CreateObject("roFileSystem")
        if m.hcFs = invalid then
            result.reason = "unsupported"
        else if action = "purge" then
            result = homeCachePurge(job, result)
        else if action = "read" then
            result = homeCacheRead(result)
        else if action = "write" then
            result = homeCacheWrite(job, result)
        end if
    catch e
        result.ok = false
        result.status = "miss"
        result.reason = "error"
        print "[siku-home] cache error action="; action; " "; e.message
    end try
    m.hcFs = invalid
    m.top.result = result
end sub

' True while the job's owner is still the active session's (sign-out or a profile switch while
' the job ran drops it).
function homeCacheCurrent(ownerSource as string) as boolean
    if ownerSource = "" then return false
    return HomeCache_ownerSource(m.global.session) = ownerSource
end function

function homeCacheHash(ownerSource as string) as string
    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString(ownerSource)
    digest = CreateObject("roEVPDigest")
    if digest = invalid then return ""
    if digest.Setup("sha256") <> 0 then return ""
    return LCase(digest.Process(bytes))
end function

function homeCachePath(ownerHash as string) as string
    return "cachefs:/" + HomeCache_fileName(ownerHash)
end function

' Deletes every Home cache file except the one named `keepName` ("") and its temp file (a write
' for that owner may be running). Returns the count deleted.
function homeCacheDeleteAll(keepName as string) as integer
    n = 0
    files = m.hcFs.GetDirectoryListing("cachefs:/")
    if files = invalid then return 0
    for each name in files
        nm = Str_orEmpty(name)
        kept = keepName <> "" and (nm = keepName or Left(nm, Len(keepName) + 1) = keepName + ".")
        if not kept and HomeCache_isOwnedName(nm) then
            m.hcFs.Delete("cachefs:/" + nm)
            n = n + 1
        end if
    end for
    return n
end function

function homeCachePurge(job as object, result as object) as object
    keep = ""
    keepSource = Str_orEmpty(job.keepOwnerSource)
    if keepSource <> "" then
        h = homeCacheHash(keepSource)
        if h <> "" then keep = HomeCache_fileName(h)
    end if
    n = homeCacheDeleteAll(keep)
    result.ok = true
    result.status = "purged"
    result.reason = Str_orEmpty(job.reason)
    result.files = n
    if keep = "" or n > 0 then print "[siku-home] cache purge reason="; result.reason; " files="; n
    return result
end function

function homeCacheRead(result as object) as object
    owner = result.ownerSource
    if not homeCacheCurrent(owner) then
        result.status = "skipped"
        result.reason = "session"
        return result
    end if
    h = homeCacheHash(owner)
    if h = "" then
        result.reason = "unsupported"
        print "[siku-home] cache miss reason=unsupported"
        return result
    end if
    ' A profile switch leaves the previous owner's file behind: one owner is kept at a time.
    homeCacheDeleteAll(HomeCache_fileName(h))
    path = homeCachePath(h)
    if not m.hcFs.Exists(path) then
        result.reason = "none"
        print "[siku-home] cache miss reason=none"
        return result
    end if
    lim = HomeCache_limits()
    st = m.hcFs.Stat(path)
    size = -1
    if st <> invalid and Type(st) = "roAssociativeArray" then size = Num_or(st.size, -1)
    if size <= 0 or size > lim.bytes then
        m.hcFs.Delete(path)
        result.reason = "size"
        print "[siku-home] cache miss reason=size"
        return result
    end if
    bytes = CreateObject("roByteArray")
    if not bytes.ReadFile(path) then
        result.reason = "unreadable"
        print "[siku-home] cache miss reason=unreadable"
        return result
    end if
    snapshot = ParseJson(bytes.ToAsciiString())
    now = CreateObject("roDateTime").AsSeconds()
    chk = HomeCache_check(snapshot, h, now)
    if chk.status <> "hit" then
        m.hcFs.Delete(path)
        result.status = chk.status
        result.reason = chk.reason
        print "[siku-home] cache "; chk.status; " reason="; chk.reason
        return result
    end if
    ' The session may have changed while the file was read and parsed.
    if not homeCacheCurrent(owner) then
        result.status = "skipped"
        result.reason = "session"
        return result
    end if
    result.ok = true
    result.status = "hit"
    result.age = chk.age
    result.sections = chk.sections
    print "[siku-home] cache hit age="; chk.age; "s sections="; chk.sections.Count(); " bytes="; size
    return result
end function

function homeCacheWrite(job as object, result as object) as object
    owner = result.ownerSource
    payload = job.payload
    if not homeCacheCurrent(owner) or payload = invalid or Type(payload) <> "roAssociativeArray" then
        result.status = "skipped"
        result.reason = "session"
        return result
    end if
    h = homeCacheHash(owner)
    if h = "" then
        result.reason = "unsupported"
        print "[siku-home] cache write skipped reason=unsupported"
        return result
    end if
    homeCacheDeleteAll(HomeCache_fileName(h))
    snapshot = { schema: HomeCache_schema(), owner: h, savedAt: CreateObject("roDateTime").AsSeconds(), sections: Arr_or(payload.sections) }
    text = FormatJson(snapshot)
    lim = HomeCache_limits()
    ' Bytes, not characters: the reader checks the file size, and non-ASCII text takes 2-4 bytes
    ' a character (FromAsciiString copies the string's UTF-8 bytes).
    bytes = CreateObject("roByteArray")
    if text <> "" then bytes.FromAsciiString(text)
    if bytes.Count() = 0 or bytes.Count() > lim.bytes then
        result.reason = "size"
        print "[siku-home] cache write skipped reason=size bytes="; bytes.Count()
        return result
    end if
    path = homeCachePath(h)
    ' Temp file then rename: an interrupted write leaves no half file under the real name. The
    ' temp name is unique per write, so two writes (two Home pages) never share one.
    part = path + "." + LCase(CreateObject("roDeviceInfo").GetRandomUUID()) + ".part"
    if not bytes.WriteFile(part) then
        m.hcFs.Delete(part)
        result.reason = "storage"
        print "[siku-home] cache write failed reason=storage"
        return result
    end if
    if not homeCacheCurrent(owner) then
        m.hcFs.Delete(part)
        result.status = "skipped"
        result.reason = "session"
        return result
    end if
    ' Rename replaces the previous file; a storage that refuses to rename over a file gets the
    ' old one deleted first (the only window in which a reader finds no cache, i.e. a miss).
    renamed = m.hcFs.Rename(part, path)
    if not renamed and m.hcFs.Exists(part) then
        m.hcFs.Delete(path)
        renamed = m.hcFs.Rename(part, path)
    end if
    if not renamed then
        m.hcFs.Delete(part)
        result.reason = "storage"
        print "[siku-home] cache write failed reason=rename"
        return result
    end if
    result.ok = true
    result.status = "written"
    result.bytes = bytes.Count()
    print "[siku-home] cache write sections="; snapshot.sections.Count(); " bytes="; bytes.Count()
    return result
end function
