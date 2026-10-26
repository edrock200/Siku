' Screen reader speech for Siku's hand-drawn controls (Roku Settings › Accessibility › Screen reader).
' SPDX-License-Identifier: AGPL-3.0-or-later
'
' Roku's audio guide already reads native nodes (RowList / MarkupGrid / LabelList items from their
' ContentNode title and description, keyboard dialogs). Buttons, tabs, settings rows and keypads
' that Siku draws itself are Groups and Posters the reader cannot describe, so they announce
' themselves through A11y_say when they take focus.
' Design adapted from ManavA/silo-roku, AGPL-3.0 (components/SiloUIAccessibility.brs):
'   - one roAudioGuide for the whole app (owned by A11yTask, created by MainScene);
'   - only hand-drawn controls speak, as "label, role, N of M";
'   - text is trimmed and cut to 120 characters, and text that looks like a URL or an e-mail
'     address ("://" or "@") is never read out;
'   - nothing is said for a control that is hidden (visible false or opacity 0 anywhere up the tree)
'     or while a native dialog is up (the dialog speaks for itself);
'   - one utterance per focus: the last identity + text is remembered on m.global.a11yLast and
'     forgotten when a screen is pushed or popped, a dialog opens or closes, or the app regains
'     focus, so returning to the same control speaks again.
' Text fields say their name only, never their value; PIN pads say the key, never the digits typed.
' Any component that includes this file can call these helpers (BaseScreen includes it for screens).

' The words for one control, or "" when there is nothing safe to say. idx is 0-based; the
' position is said only for a group of two or more.
function A11y_text(label as dynamic, role as string, idx as integer, count as integer) as string
    t = A11y_clean(label)
    if t = "" then return ""
    if role <> "" then t = t + ", " + role
    if count > 1 and idx >= 0 and idx < count then t = t + ", " + (idx + 1).ToStr() + " of " + count.ToStr()
    return t
end function

' A label made safe to read: trimmed, at most 120 characters, "" for non-text or for anything that
' looks like an address (a server URL, an e-mail login).
function A11y_clean(label as dynamic) as string
    t = Type(label)
    if t <> "String" and t <> "roString" then return ""
    s = label.Trim()
    if Instr(1, s, "://") > 0 or Instr(1, s, "@") > 0 then return ""
    if Len(s) > 120 then s = Left(s, 120).Trim()
    return s
end function

' Speaks a focused control. identity names the control (A11y_id() for a widget, a stable string for
' a part of a composite control); node is the node whose visibility decides (default m.top).
sub A11y_say(identity as string, label as dynamic, role as string, idx as integer, count as integer, node = invalid as dynamic)
    if not A11y_enabled() then return
    if node = invalid then node = m.top
    if not A11y_visible(node) then return
    scene = node.getScene()
    if scene <> invalid then
        if scene.dialog <> invalid then return
    end if
    text = A11y_text(label, role, idx, count)
    if text = "" then return
    key = identity + "|" + text
    g = m.global
    if g.a11yLast = key then return
    g.a11yLast = key
    task = g.a11yTask
    if task <> invalid then task.say = text
    if g.a11yForce = true then print "[siku-a11y] say: " + text
end sub

' The control lost focus: forget it if it was the last one spoken, so coming back speaks again.
sub A11y_blur(identity as string)
    g = m.global
    if g = invalid then return
    if not g.hasField("a11yLast") then return
    last = g.a11yLast
    if Left(last, Len(identity) + 1) = identity + "|" then g.a11yLast = ""
end sub

' Forget the last utterance (a screen was pushed or popped, a dialog opened or closed).
sub A11y_reset()
    g = m.global
    if g = invalid then return
    if g.hasField("a11yLast") then g.a11yLast = ""
end sub

' True when Roku's screen reader is on (or the simulator forced it with debugA11y=1).
function A11y_enabled() as boolean
    g = m.global
    if g = invalid then return false
    if not g.hasField("a11yTask") then return false
    if g.a11yForce = true then return true
    if m.a11yDevice = invalid then m.a11yDevice = CreateObject("roDeviceInfo")
    enabled = false
    try
        r = m.a11yDevice.IsAudioGuideEnabled()
        enabled = (Type(r) = "roBoolean" or Type(r) = "Boolean") and r
    catch e
        enabled = false ' e: a firmware without the call; treat the reader as off
        if e = invalid then enabled = false
    end try
    return enabled
end function

' False when the node or any ancestor is invisible or fully transparent.
function A11y_visible(node as dynamic) as boolean
    n = node
    while n <> invalid
        if n.visible = false then return false
        op = n.opacity
        if op <> invalid then
            if op <= 0 then return false
        end if
        n = n.getParent()
    end while
    return true
end function

' A per-instance identity for a widget (its subtype and a random tag, made once).
function A11y_id() as string
    if m.a11yId = invalid then m.a11yId = m.top.subtype() + "#" + Rnd(1000000000).ToStr()
    return m.a11yId
end function

' { idx, count }: the node's place among its visible siblings whose subtype is listed in kinds.
function A11y_position(node as object, kinds as object) as object
    parent = node.getParent()
    if parent = invalid then return { idx: 0, count: 1 }
    idx = 0
    count = 0
    for each c in parent.getChildren(-1, 0)
        listed = false
        st = c.subtype()
        for each k in kinds
            if k = st then listed = true
        end for
        if listed and c.visible then
            if c.isSameNode(node) then idx = count
            count = count + 1
        end if
    end for
    return { idx: idx, count: count }
end function
