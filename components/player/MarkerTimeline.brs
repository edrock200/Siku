' SPDX-License-Identifier: AGPL-3.0-or-later
' Marker ranges of one file ({kind, start, end}, PlayerScreen.markersOf), read the way Silo
' Android's MarkerTimeline reads them (Silo Android #694, shared/.../domain/player/MarkerTimeline.kt):
' a kind may occur more than once (two credits ranges around a mid-credits scene). Pure: no node
' access, so tests/test_marker_timeline.py runs it on the host.

' The valid ranges of KIND (finite, start >= 0, end > start), ordered by start then end.
function Markers_ranges(markers as dynamic, kind as string) as object
    out = []
    for each mk in Arr_or(markers)
        if mk <> invalid and Type(mk) = "roAssociativeArray" and LCase(Str_orEmpty(mk.kind)) = kind then
            s = Num_or(mk.start, -1)
            e = Num_or(mk["end"], -1)
            if s >= 0 and e > s then
                ' Insertion keeps the list sorted; a file has a handful of ranges at most.
                at = out.Count()
                for i = 0 to out.Count() - 1
                    if s < out[i].start or (s = out[i].start and e < out[i]["end"]) then
                        at = i
                        exit for
                    end if
                end for
                item = { kind: kind, start: s, "end": e }
                if at = out.Count() then
                    out.Push(item)
                else
                    rebuilt = []
                    for i = 0 to out.Count() - 1
                        if i = at then rebuilt.Push(item)
                        rebuilt.Push(out[i])
                    end for
                    out = rebuilt
                end if
            end if
        end if
    end for
    return out
end function

' Where Up Next may appear because of credits: the start of the LAST credits range, extended back
' over credits ranges that run into it (1 s of rounding allowed), so a scene between two credits
' ranges still plays. -1 when the file has no credits range.
function Markers_upNextCreditsStart(markers as dynamic) as float
    credits = Markers_ranges(markers, "credits")
    n = credits.Count()
    if n = 0 then return -1
    start = credits[n - 1].start
    for i = n - 1 to 0 step -1
        r = credits[i]
        if r["end"] >= start - 1 and r.start < start then start = r.start
    end for
    return start
end function
