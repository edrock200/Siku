' Temporary passwords (Silo Android #790, silo-server docs/auth-api.md "Temporary passwords").
' SPDX-License-Identifier: AGPL-3.0-or-later
'
' An admin can make an account's password temporary. Until it is changed, the server refuses
' everything except GET /api/v2/account/me, GET /api/v2/account/password/capability,
' POST /api/v2/account/password and sign-out with 403 problem `password_change_required`.
' Like Android TV (and tvOS), Siku has no form for it: the password is changed in Silo's phone app
' or on the web, which ends this Roku's session, so Retry then leads to sign-in.
' Pure functions: used by Http.brs (Task threads) and ProfileScreen (render thread); host-tested in
' tests/test_password_change.py. Idea also in Silo-Server/silo-roku (AGPL-3.0,
' source/onboarding/profiles.bs loadErrorKey).

function PasswordChange_code() as string
    return "password_change_required"
end function

' Whether a failed answer ({status, error: {code}}, as ApiTask returns it) is the refusal.
function PasswordChange_isRequired(resp as dynamic) as boolean
    if resp = invalid or Type(resp) <> "roAssociativeArray" then return false
    if Int(Num_or(resp.status, 0)) <> 403 then return false
    err = resp.error
    if err = invalid or Type(err) <> "roAssociativeArray" then return false
    return Str_orEmpty(err.code) = PasswordChange_code()
end function

' The profile picker's message (TV_PASSWORD_CHANGE_REQUIRED_MESSAGE in Silo Android TV).
function PasswordChange_pickerMessage() as string
    return Tx("Your password needs to be reset. Use the Silo mobile app or website to set a new one, then come back.")
end function

' What any other screen shows in place of the server's detail, which is a protocol instruction
' ("Change the temporary password with POST ..."). Android's phone wording says to sign in again
' to choose one; a TV cannot, so this says where to change it.
function PasswordChange_message() as string
    return Tx("An admin set a temporary password for this account. Set a new one in the Silo mobile app or on the website, then sign in again.")
end function
