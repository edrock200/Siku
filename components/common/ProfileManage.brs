' SPDX-License-Identifier: AGPL-3.0-or-later
' Profile management on the picker (Silo Android TV's TvProfileSelectionScreen manage mode,
' TvEditProfileScreen / TvEditProfileViewModel, HouseholdManagementSession): the pure rules, shared
' by ProfileScreen, EditProfileScreen and NewProfileScreen and host-tested in
' tests/test_profile_manage.py. Include with Accounts.brs and Utils.brs.
'
' The server lets only the household's verified primary profile create, edit or delete profiles
' (any account role): every management call carries X-Profile-Id of the primary profile and, when
' it has a PIN, the X-Profile-Token its verify-pin issued. That token is held in memory for manage
' mode only (never saved, never selected). A PIN, child or limit change bumps the account's
' access-policy revision, which makes the held token stale: the next call answers 403
' profile_verification_required and the primary's PIN is asked again, then the call is retried once.

' Manage is offered while the list names a household primary (Android TV: householdPrimary() !=
' null), never on a phone's borrowed profile (that list holds only its own profile).
function ProfileManage_canManage(profiles as dynamic, temporary as boolean) as boolean
    if temporary then return false
    return Accounts_householdPrimary(profiles) <> invalid
end function

' The server never deletes the primary profile (409 primary_profile_protected): not offered.
function ProfileManage_canDelete(profile as dynamic) as boolean
    if Type(profile) <> "roAssociativeArray" then return false
    if Str_orEmpty(profile.id) = "" then return false
    v = profile.is_primary
    if (Type(v) = "Boolean" or Type(v) = "roBoolean") and v then return false
    return true
end function

' Add profile in manage mode while the account has room (max_profiles; -1 = unknown, which keeps
' offering it and lets the create answer 409).
function ProfileManage_canAdd(count as integer, maxProfiles as integer) as boolean
    if maxProfiles < 0 then return true
    return count < maxProfiles
end function

' The headers a management call acts with: the primary profile, and its token when it has one.
function ProfileManage_headers(manager as dynamic) as object
    h = {}
    if Type(manager) <> "roAssociativeArray" then return h
    id = Str_orEmpty(manager.id)
    if id = "" then return h
    h["X-Profile-Id"] = id
    t = Str_orEmpty(manager.token)
    if t <> "" then h["X-Profile-Token"] = t
    return h
end function

' Whether an answer means the primary's token is missing or stale (HouseholdManagementSession's
' needsProfileVerification): 403 profile_verification_required or profile_unverified.
function ProfileManage_needsVerification(status as integer, code as string) as boolean
    return status = 403 and (code = "profile_verification_required" or code = "profile_unverified")
end function

' Another profile already has this name, trimmed and ignoring case (hasProfileNamed).
function ProfileManage_nameTaken(profiles as dynamic, name as string, exceptId as string) as boolean
    want = LCase(name.Trim())
    items = Arr_or(profiles)
    for i = 0 to items.Count() - 1
        p = items[i]
        if Type(p) = "roAssociativeArray" then
            if Str_orEmpty(p.id) <> exceptId and LCase(Str_orEmpty(p.name).Trim()) = want then return true
        end if
    end for
    return false
end function

' What stops an edit being saved (TvEditProfileViewModel.onSaveClick): "" when nothing does,
' "name" (blank), "taken" (another profile's name), "long" (over the server's 64 characters) or
' "pin" (a new PIN that is not four digits).
function ProfileManage_editProblem(profiles as dynamic, profileId as string, name as string, newPin as string) as string
    n = name.Trim()
    if n = "" then return "name"
    if Len(n) > 64 then return "long"
    if ProfileManage_nameTaken(profiles, n, profileId) then return "taken"
    if newPin <> "" and Accounts_newProfileProblem("x", newPin) = "pin" then return "pin"
    return ""
end function

' The PATCH /api/v2/profiles/{id} body (TvEditProfileViewModel + UpdateProfileRequest.withAccessLimits):
' - name: always, trimmed;
' - pin: a new 4-digit PIN sets or replaces it; "remove" on a profile that had one sends null (the
'   v2 clearing form; an empty string is refused); otherwise left out (unchanged);
' - is_child: always;
' - the rating ceiling follows Child as Android's ProfileAccessLimits.withChild does: turning Child
'   on fills PG when the profile has no ceiling; turning it off clears the ceiling (null) and the
'   library restriction it had. Siku has no rating or library pickers, so nothing else changes.
' loaded: the profile as listed. pinMode: "keep" | "set" | "remove".
function ProfileManage_updateBody(loaded as object, name as string, pinMode as string, newPin as string, child as boolean) as object
    out = { "name": name.Trim() }
    hadPin = ProfileManage_flag(loaded.has_pin)
    if pinMode = "set" and newPin <> "" then
        out["pin"] = newPin
    else if pinMode = "remove" and hadPin then
        out["pin"] = invalid
    end if
    out["is_child"] = child
    wasChild = ProfileManage_flag(loaded.is_child)
    rating = Str_orEmpty(loaded.max_content_rating)
    if child and not wasChild and rating = "" then
        out["max_content_rating"] = "PG"
    else if not child and wasChild then
        if rating <> "" then out["max_content_rating"] = invalid
        if ProfileManage_flag(loaded.library_restrictions_enabled) then out["library_restrictions_enabled"] = false
    end if
    return out
end function

' What an update answer means: "saved" (2xx), "verify" (the primary's PIN is needed again),
' "network" (no answer; a PATCH is never retried), "gone" (404: deleted meanwhile), "taken" (409),
' "refused" (403/422 with the server's reason) or "failed".
function ProfileManage_saveOutcome(status as integer, code as string) as string
    if status >= 200 and status < 300 then return "saved"
    if ProfileManage_needsVerification(status, code) then return "verify"
    if status = 0 then return "network"
    if status = 404 then return "gone"
    if status = 409 then return "taken"
    if status = 403 or status = 422 or status = 400 then return "refused"
    return "failed"
end function

' What a delete answer means: "deleted" (2xx), "gone" (404: already deleted, the list drops it
' too), "protected" (409 primary_profile_protected), "verify", "network" or "failed".
function ProfileManage_deleteOutcome(status as integer, code as string) as string
    if status >= 200 and status < 300 then return "deleted"
    if ProfileManage_needsVerification(status, code) then return "verify"
    if status = 0 then return "network"
    if status = 404 then return "gone"
    if status = 409 then return "protected"
    return "failed"
end function

' The fields of an update body for the console: names and PINs are never printed.
function ProfileManage_describe(body as object) as string
    parts = []
    if body.DoesExist("name") then parts.Push("name")
    if body.DoesExist("pin") then
        t = Type(body["pin"])
        if t = "Invalid" or t = "roInvalid" then parts.Push("pin=clear") else parts.Push("pin=set")
    end if
    if body.DoesExist("is_child") then
        if body["is_child"] then parts.Push("child=on") else parts.Push("child=off")
    end if
    if body.DoesExist("max_content_rating") then parts.Push("rating")
    if body.DoesExist("library_restrictions_enabled") then parts.Push("libraries")
    out = ""
    for i = 0 to parts.Count() - 1
        if i > 0 then out = out + ","
        out = out + parts[i]
    end for
    return out
end function

function ProfileManage_flag(v as dynamic) as boolean
    if Type(v) = "Boolean" or Type(v) = "roBoolean" then return v
    return false
end function
