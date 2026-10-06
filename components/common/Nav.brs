' Navigation helpers for screens. SPDX-License-Identifier: AGPL-3.0-or-later

' Opens a screen on top of this one.
sub Nav_push(screen as string, params = {} as object)
    m.top.navigateTo = { screen: screen, params: params }
end sub

' Replaces this screen with another.
sub Nav_replace(screen as string, params = {} as object)
    m.top.navigateTo = { screen: screen, params: params, replace: true }
end sub

' Clears the whole stack and opens a screen.
sub Nav_reset(screen as string, params = {} as object)
    m.top.navigateTo = { screen: screen, params: params, reset: true }
end sub

' Closes this screen, optionally passing a result to the one below.
sub Nav_close(result = invalid as dynamic)
    if result <> invalid then m.top.result = result
    m.top.close = true
end sub

sub Nav_play(params as object)
    m.top.navigateTo = { screen: "PlayerScreen", params: params }
end sub
