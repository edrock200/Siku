' SPDX-License-Identifier: AGPL-3.0-or-later
' Test-only wrappers for tests/test_card_overlays.py: they parse a document and return plain
' values (ids, colours) that read back cleanly as JSON.

function Ovl_placedOf(raw as dynamic, position as string) as object
    out = []
    for each e in Ovl_placed(Ovl_parse(raw), position)
        out.Push(e.id)
    end for
    return out
end function

function Ovl_resolveIds(raw as dynamic, data as object) as object
    prefs = Ovl_parse(raw)
    groups = Ovl_resolve(prefs, data, Ovl_lookOf(prefs.preset, prefs.style), Ovl_words())
    out = {}
    for each k in groups
        list = []
        for each b in groups[k]
            list.Push(b.id)
        end for
        out[k] = list
    end for
    return out
end function

function Ovl_paintOf(preset as string, style as dynamic, accent as string) as object
    return Ovl_paint(Ovl_lookOf(preset, Ovl_parseStyle(style)), accent)
end function

function Ovl_enabledCountOf(raw as dynamic) as integer
    return Ovl_enabledCount(Ovl_parse(raw))
end function

function Content_overlayKeyPair(a as object, b as object) as boolean
    return Content_overlayKey(a) = Content_overlayKey(b)
end function
