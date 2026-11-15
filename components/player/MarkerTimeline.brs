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

' The scrubber's marker bands (Silo Android #933 / #934; adapted from silo-roku 42249ca): every
' intro, recap, credits and preview range, each occurrence its own band, clamped to the file's
' duration, in TheIntroDB's segment palette that every Silo client shares, at 34% opacity (45% while
' the scrubber is focused or scrubbing). Drawn kind by kind in that order, so a later kind lies over
' an earlier one where they overlap. Other kinds and empty ranges are left out.
' Returns [{ kind, start, end, color }] with color "0xRRGGBBAA".
function Markers_bands(markers as dynamic, duration as dynamic, emphasised as boolean) as object
    out = []
    dur = Num_or(duration, 0)
    if dur <= 0 then return out
    alpha = "57"
    if emphasised then alpha = "73"
    for each kind in ["intro", "recap", "credits", "preview"]
        for each r in Markers_ranges(markers, kind)
            s = r.start
            e = r["end"]
            if s < 0 then s = 0
            if e > dur then e = dur
            if e > s then out.Push({ kind: kind, start: s, "end": e, color: Markers_bandColor(kind) + alpha })
        end for
    end for
    return out
end function

' TheIntroDB's segment colours (Tailwind v4 400 shades) without alpha: intro #51A2FF, recap
' #FF8904, credits #C27AFF, preview #00D3F2.
function Markers_bandColor(kind as string) as string
    if kind = "intro" then return "0x51A2FF"
    if kind = "recap" then return "0xFF8904"
    if kind = "preview" then return "0x00D3F2"
    return "0xC27AFF"
end function
