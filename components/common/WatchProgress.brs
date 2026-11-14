' The watch-progress bar on card art (Silo Android #902 WatchProgressBar, the same bar as Silo's
' web and Apple apps): an inset capsule with a dark, outlined track and a near-white fill, so it
' stays visible on bright artwork. Android TV's sizes doubled to px: 8 tall (4 dp), 20 in from the
' sides (10 dp), 16 up from the art's bottom edge (8 dp), 8 under a bottom-corner label such as a
' box set's film count (4 dp). Bottom badges and captions on the art rise `clearance` px (the
' inset, the bar and a 4 px gap: Android's BadgeClearance, 14 dp) when a card shows progress.
' The fill grows from the left; Siku keeps the TV layout left to right in every language, as Silo
' Android TV does (#833), so there is no right-to-left mirror to draw.
' Drawn with two 9-patches from scripts/make_ui.py (images/ui/progress_track.9.png: track,
' keyline and shadow in one, PAD px of shadow room on each side; progress_fill.9.png: the fill
' and its 1 px hairline). Pure apart from WatchProgress_place, so OverlayDraw (a Task) and the
' host tests can use the numbers. Include with <script uri="pkg:/components/common/WatchProgress.brs" />.
' SPDX-License-Identifier: AGPL-3.0-or-later

function WatchProgress_metrics() as object
    return { height: 8, side: 20, bottom: 16, bottomBelowLabel: 8, clearance: 28, pad: 8, minFill: 9 }
end function

' Where the track and fill Posters go on a w×h art box for fraction (0..1), in px:
' { trackX, trackY, trackW, trackH, fillX, fillY, fillW, fillH } (the Posters' own boxes,
' shadow room and hairline included). belowLabel: a bottom-corner label sits above the bar.
function WatchProgress_geometry(w as dynamic, h as dynamic, fraction as dynamic, belowLabel as boolean) as object
    mt = WatchProgress_metrics()
    bottom = mt.bottom
    if belowLabel then bottom = mt.bottomBelowLabel
    barW = Int(Num_or(w, 0)) - 2 * mt.side
    if barW < mt.minFill then barW = mt.minFill
    y = Int(Num_or(h, 0)) - bottom - mt.height
    f = Num_or(fraction, 0)
    if f < 0 then f = 0
    if f > 1 then f = 1
    fillW = Int(barW * f + 0.5)
    ' The fill's 9-patch cannot draw narrower than its two round ends.
    if fillW < mt.minFill then fillW = mt.minFill
    if fillW > barW then fillW = barW
    return {
        trackX: mt.side - mt.pad, trackY: y - mt.pad, trackW: barW + 2 * mt.pad, trackH: mt.height + 2 * mt.pad
        fillX: mt.side - 1, fillY: y - 1, fillW: fillW + 2, fillH: mt.height + 2
    }
end function

' Shows (or hides) a card's bar: track and fill are the card's progress_track / progress_fill Posters.
sub WatchProgress_place(track as object, fill as object, w as dynamic, h as dynamic, fraction as dynamic, visible as boolean, belowLabel as boolean)
    track.visible = visible
    fill.visible = visible
    if not visible then return
    g = WatchProgress_geometry(w, h, fraction, belowLabel)
    track.translation = [g.trackX, g.trackY]
    track.width = g.trackW
    track.height = g.trackH
    fill.translation = [g.fillX, g.fillY]
    fill.width = g.fillW
    fill.height = g.fillH
end sub
