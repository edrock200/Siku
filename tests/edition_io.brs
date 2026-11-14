' SPDX-License-Identifier: AGPL-3.0-or-later
' Test-only wrappers for tests/test_edition.py: they run Edition_resolve / Edition_list and return
' plain values (file ids, edition ids) that read back cleanly as JSON.

function EditionT_pick(detail as object, pinned as string, editionId as dynamic, quality as dynamic) as dynamic
    r = Edition_resolve(detail, pinned, editionId, quality)
    if r.version = invalid then return invalid
    return Str_orEmpty(r.version.file_id)
end function

function EditionT_source(detail as object, pinned as string, editionId as dynamic, quality as dynamic) as string
    return Edition_resolve(detail, pinned, editionId, quality).source
end function

function EditionT_list(versions as object, variants as object) as object
    out = []
    for each e in Edition_list(versions, variants)
        files = []
        for each v in e.files
            files.Push(Str_orEmpty(v.file_id))
        end for
        ids = []
        for each k in e.fileIds
            ids.Push(k)
        end for
        ids.Sort()
        out.Push({ "id": e.id, "label": e.label, "files": files, "fileIds": ids })
    end for
    return out
end function

function EditionT_firstPart(versions as object, fileId as string) as string
    for i = 0 to versions.Count() - 1
        if Str_orEmpty(versions[i].file_id) = fileId then return Str_orEmpty(Edition_firstPart(versions, versions[i]).file_id)
    end for
    return ""
end function
