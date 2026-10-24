' YouTubeHandoffDialog: the fallback when the YouTube channel could not be opened.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.qr = m.top.findNode("qr")
    m.titleLabel = m.top.findNode("titleLabel")
    m.messageLabel = m.top.findNode("messageLabel")
    m.urlLabel = m.top.findNode("urlLabel")
    m.closeBtn = m.top.findNode("closeBtn")
    m.closeBtn.observeField("buttonSelected", "onClose")
    m.top.observeField("focusedChild", "onFocusChanged")
end sub

' Focus handed to the dialog goes to its only control.
sub onFocusChanged()
    if m.top.hasFocus() then m.closeBtn.setFocus(true)
end sub

sub onUrl()
    m.qr.text = m.top.url
    layout()
end sub

sub layout()
    m.titleLabel.text = m.top.videoTitle
    m.messageLabel.text = m.top.message
    m.urlLabel.text = m.top.url
    y = 104 + Label_height(m.titleLabel) + 24
    m.messageLabel.translation = [500, y]
    y = y + Label_height(m.messageLabel) + 24
    m.urlLabel.translation = [500, y]
end sub

sub onClose()
    m.top.dismissed = true
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "back" then
        m.top.dismissed = true
        return true
    end if
    ' Modal: nothing behind the dialog reacts while it is open.
    return true
end function
