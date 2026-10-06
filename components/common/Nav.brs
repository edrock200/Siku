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

' Starts playback. params.itemType routes audio items to the audio player:
' audiobooks resume as a book, tracks play as a one-item queue, and albums/artists
' open their detail page (which builds the queue).
sub Nav_play(params as object)
    t = LCase(Str_orEmpty(params.itemType))
    if t = "audiobook" then
        p = { itemId: params.itemId }
        if params.startPosition <> invalid then p.startPosition = params.startPosition
        m.top.navigateTo = { screen: "AudioPlayerScreen", params: p }
    else if t = "track" or t = "song" then
        m.top.navigateTo = { screen: "AudioPlayerScreen", params: { queue: [{ contentId: params.itemId, title: Str_orEmpty(params.title) }], index: 0 } }
    else if Nav_isAudioType(t) then
        Nav_openItem(params.itemId, t)
    else
        m.top.navigateTo = { screen: "PlayerScreen", params: params }
    end if
end sub

' True for item types that open the audio detail page instead of the video one.
function Nav_isAudioType(itemType as dynamic) as boolean
    t = LCase(Str_orEmpty(itemType))
    return t = "album" or t = "artist" or t = "track" or t = "audiobook" or t = "song" or t = "musicalbum" or t = "musicartist"
end function

' Opens the right detail page for a catalog item.
sub Nav_openItem(itemId as string, itemType = "" as dynamic)
    t = Str_orEmpty(itemType)
    if Nav_isAudioType(t) then
        Nav_push("AudioDetailScreen", { itemId: itemId, itemType: LCase(t) })
    else
        Nav_push("DetailScreen", { itemId: itemId, itemType: t })
    end if
end sub
