' Roku voice transport commands ("pause", "resume", "fast forward", "rewind", "seek forward
' 30 seconds", ...): parsing and seek arithmetic, kept free of SceneGraph so tests/ can run them
' in brs-cli. source/main.brs enables the events and answers them; MainScene.handleTransport routes
' them to the player on top (PlayerScreen.voiceTransport, AudioPlayerScreen.voiceTransport).
' Idea adapted from ManavA/silo-roku, AGPL-3.0 (source/main.brs MainInput,
' components/SiloUIVoice.brs handleTransport): strict validation of `duration`, and an explicit
' rejection whenever the player cannot honour the command right now.
' SPDX-License-Identifier: AGPL-3.0-or-later

' The command an event asks for, or invalid when it is not one Siku carries out:
'   { action: "play" | "pause" | "stop" | "seek", delta: seconds (seek, relative), toStart: bool }
' backSeconds / forwardSeconds are the player's own skip sizes (the remote's rewind / replay and
' fast-forward keys use the same ones), so a voice "rewind" moves as far as the button does.
function Voice_parse(info as dynamic, backSeconds as integer, forwardSeconds as integer) as dynamic
    if Type(info) <> "roAssociativeArray" then return invalid
    cmd = Voice_word(info.Lookup("command"))
    if cmd = "play" or cmd = "resume" then return { action: "play", delta: 0, toStart: false }
    if cmd = "pause" then return { action: "pause", delta: 0, toStart: false }
    if cmd = "stop" then return { action: "stop", delta: 0, toStart: false }
    if cmd = "forward" then return { action: "seek", delta: forwardSeconds, toStart: false }
    if cmd = "rewind" or cmd = "replay" then return { action: "seek", delta: -backSeconds, toStart: false }
    if cmd = "startover" then return { action: "seek", delta: 0, toStart: true }
    if cmd = "seek" then
        secs = Voice_seconds(info.Lookup("duration"))
        if secs <= 0 then return invalid
        dir = Voice_word(info.Lookup("direction"))
        if dir = "forward" then return { action: "seek", delta: secs, toStart: false }
        if dir = "backward" then return { action: "seek", delta: -secs, toStart: false }
    end if
    return invalid
end function

' Seconds from a seek event's `duration`: a string of 1 to 6 ASCII digits (or a whole number in
' the same range), else -1. Anything else ("3x", "-5", "1e9", "", 9999999) is refused.
function Voice_seconds(v as dynamic) as integer
    t = Type(v)
    if t = "Integer" or t = "roInt" or t = "roInteger" then
        if v > 0 and v <= 999999 then return v
        return -1
    end if
    if t <> "String" and t <> "roString" then return -1
    n = Len(v)
    if n < 1 or n > 6 then return -1
    for i = 1 to n
        if Instr(1, "0123456789", Mid(v, i, 1)) = 0 then return -1
    end for
    return Int(Val(v))
end function

' Where a seek lands: { target (seconds), status } with Roku's response status, clamped to the
' title ("success.seek-start" at 0, "success.seek-end" one second before the end, as
' PlayerScreen.seekToSource clamps). invalid when the duration is unknown.
function Voice_target(position as float, delta as integer, toStart as boolean, duration as float) as dynamic
    if duration <= 1 then return invalid
    target = position + delta
    if toStart then target = 0
    status = "success"
    if target < 0 then
        target = 0
        status = "success.seek-start"
    else if target > duration - 1 then
        target = duration - 1
        status = "success.seek-end"
    end if
    return { target: target, status: status }
end function

' "+30s" / "-10s" for the on-screen feedback chip, "" for no movement.
function Voice_feedback(fromPos as float, toPos as float) as string
    d = Int(toPos - fromPos + 0.5)
    if toPos < fromPos then d = -Int(fromPos - toPos + 0.5)
    if d > 0 then return "+" + d.ToStr() + "s"
    if d < 0 then return d.ToStr() + "s"
    return ""
end function

' The console description of an event: "command=seek direction=forward duration=30". Only short
' lower-case words and digits are printed; anything else reads "other" / "invalid".
function Voice_describe(info as dynamic) as string
    if Type(info) <> "roAssociativeArray" then return "command=invalid"
    cmd = Voice_word(info.Lookup("command"))
    if cmd = "" then cmd = "other"
    s = "command=" + cmd
    if cmd = "seek" then
        dir = Voice_word(info.Lookup("direction"))
        if dir = "" then dir = "other"
        secs = Voice_seconds(info.Lookup("duration"))
        dur = "invalid"
        if secs > 0 then dur = secs.ToStr()
        s = s + " direction=" + dir + " duration=" + dur
    end if
    return s
end function

' A lower-case word of 1 to 16 letters, else "".
function Voice_word(v as dynamic) as string
    if Type(v) <> "String" and Type(v) <> "roString" then return ""
    w = LCase(v.Trim())
    n = Len(w)
    if n < 1 or n > 16 then return ""
    for i = 1 to n
        if Instr(1, "abcdefghijklmnopqrstuvwxyz", Mid(w, i, 1)) = 0 then return ""
    end for
    return w
end function

' debugVoice=<command>[:<seconds>] (simulator): the transport event a voice command would send.
' "seek:90" seeks forward 90 s, "seek:-90" back; other commands take no number.
function Voice_debugInfo(spec as string) as object
    info = { "type": "transport", "id": "debug", "command": spec }
    colon = Instr(1, spec, ":")
    if colon > 0 then
        info["command"] = Left(spec, colon - 1)
        num = Mid(spec, colon + 1)
        info["direction"] = "forward"
        if Left(num, 1) = "-" then
            info["direction"] = "backward"
            num = Mid(num, 2)
        end if
        info["duration"] = num
    end if
    return info
end function
