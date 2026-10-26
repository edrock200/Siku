' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.top.functionName = "speakLoop"
end sub

sub speakLoop()
    guide = CreateObject("roAudioGuide")
    if guide = invalid then
        ' The simulator has no audio guide; the render thread still logs with debugA11y=1.
        print "[siku-a11y] roAudioGuide unavailable"
        return
    end if
    port = CreateObject("roMessagePort")
    m.top.observeField("say", port)
    while true
        msg = Wait(0, port)
        if Type(msg) = "roSGNodeEvent" then
            text = msg.getData()
            if Type(text) = "roString" or Type(text) = "String" then
                ' flushSpeech true: a new focus replaces the previous announcement.
                if text <> "" then guide.Say(text, true, false)
            end if
        end if
    end while
end sub
