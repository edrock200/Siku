' SPDX-License-Identifier: AGPL-3.0-or-later
' Audiobook skip intervals, as Android TV's AudiobookPlayerViewModel / TvAudiobookSkipIntervalPanel:
' on a server whose settings manifest reaches revision 9 the profile-wide
' player.audiobook_skip_back_seconds / player.audiobook_skip_forward_seconds with the contract's
' choices (5-90 s); on an older server this device's pref with Android's 10 / 15 / 30 / 60 s, 30 s
' by default (AudiobookSettingsStore.ALLOWED_SKIP / DEFAULT_SKIP). Reads m.global.settings and
' m.global.prefs only: tests/test_audio_skip.py runs it in brs-cli.

function AudioSkip_profileWide() as boolean
    return Settings_available() and Settings_manifestRevision() >= 9
end function

function AudioSkip_key(direction as string) as string
    if direction = "back" then return "player.audiobook_skip_back_seconds"
    return "player.audiobook_skip_forward_seconds"
end function

function AudioSkip_prefKey(direction as string) as string
    if direction = "back" then return "audiobookSkipBack"
    return "audiobookSkipForward"
end function

function AudioSkip_deviceChoices() as object
    return [10, 15, 30, 60]
end function

function AudioSkip_choices() as object
    if AudioSkip_profileWide() then return [5, 10, 15, 30, 45, 60, 90]
    return AudioSkip_deviceChoices()
end function

' Seconds the skip button for `direction` ("back" | "forward") jumps.
function AudioSkip_seconds(direction as string) as integer
    if AudioSkip_profileWide() then
        v = Int(Content_numOr(Settings_value(AudioSkip_key(direction), invalid), 0))
        if v > 0 then return v
    end if
    prefs = Settings_prefs()
    v = Int(Content_numOr(prefs[AudioSkip_prefKey(direction)], 0))
    for each c in AudioSkip_deviceChoices()
        if c = v then return v
    end for
    return 30
end function
