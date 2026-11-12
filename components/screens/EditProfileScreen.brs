' EditProfileScreen: rename a profile, set / change / remove its PIN, switch Child Profile, or delete
' it, acting as the household's primary profile (Silo Android TV's TvEditProfileScreen,
' TvEditProfileViewModel and the picker's delete; see the XML). The pure rules are in
' ProfileManage.brs (host-tested); the form pieces are NewProfileScreen's.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.form = m.top.findNode("form")
    m.spinner = m.top.findNode("spinner")
    m.nameField = m.top.findNode("nameField")
    m.pinButton = m.top.findNode("pinButton")
    m.removePinButton = m.top.findNode("removePinButton")
    m.childButton = m.top.findNode("childButton")
    m.errorLabel = m.top.findNode("error")
    m.saveButton = m.top.findNode("saveButton")
    m.cancelButton = m.top.findNode("cancelButton")
    m.deleteButton = m.top.findNode("deleteButton")
    ' AuthTextField's placeholder is not translated with the layout.
    m.nameField.placeholder = Tx("Profile name")
    m.nameField.a11yLabel = Tx("Name")
    m.pinButton.observeField("buttonSelected", "onPinButton")
    m.removePinButton.observeField("buttonSelected", "onRemovePin")
    m.childButton.observeField("buttonSelected", "onChildToggle")
    m.saveButton.observeField("buttonSelected", "onSave")
    m.cancelButton.observeField("buttonSelected", "onCancel")
    m.deleteButton.observeField("buttonSelected", "onDeleteAsked")
    m.saveButton.observeField("width", "layoutButtons")
    m.cancelButton.observeField("width", "layoutButtons")
    m.deleteButton.observeField("width", "layoutButtons")

    m.profileId = ""
    m.manager = invalid
    m.debugName = ""
    m.profiles = []
    m.loaded = invalid       ' the profile as listed
    m.primary = invalid
    m.child = false
    m.pinMode = "keep"       ' keep | set | remove
    m.newPin = ""
    m.canDelete = false
    m.pinDialog = invalid
    m.pinPurpose = ""        ' new | manage
    m.pending = ""           ' the call waiting for the primary's PIN: save | delete
    m.retried = false        ' one retry after a fresh primary token, per call
    m.body = invalid
    m.confirm = invalid
    m.resultData = {}
    m.state = "loading"      ' loading | form | sending | done
    m.focusKey = "name"      ' name | pin | removePin | child | save | cancel | delete
    m.active = false
    m.spinner.visible = true
    m.started = false
    ' MainScene sets params after init.
    m.top.observeField("params", "onParams")
    if m.top.params <> invalid and m.top.params.Count() > 0 then onParams()
end sub

sub onParams()
    if m.started then return
    m.started = true
    p = m.top.params
    if p = invalid then p = {}
    m.profileId = Str_orEmpty(p.profileId)
    if m.profileId = "" then m.profileId = Str_orEmpty(p.itemId) ' debugScreen=EditProfileScreen,debugItem=<id>
    m.manager = invalid
    if Type(p.manager) = "roAssociativeArray" then m.manager = { id: Str_orEmpty(p.manager.id), token: Str_orEmpty(p.manager.token) }
    m.debugName = Str_orEmpty(p.debugName) ' DEBUG builds only (MainScene): the simulator cannot type a name

    ' The current list: the profile as it is now, the primary profile, the names for the duplicate check.
    Api_call({ method: "GET", path: "/api/v2/profiles", profile: false, timeout: 15 }, "onProfiles")
end sub

sub onScreenShown()
    m.active = true
    applyFocus()
end sub

sub onScreenHidden()
    m.active = false
end sub

' ---------- Loading ----------

sub onProfiles(event as object)
    resp = Api_result(event)
    m.spinner.visible = false
    if not resp.ok or resp.data = invalid or Type(resp.data) <> "roAssociativeArray" then
        Diag_log("[siku-profiles] edit: the profile list failed status=" + Int(Num_or(resp.status, 0)).ToStr())
        m.global.toast = Tx("Failed to load profile")
        leave()
        return
    end if
    items = []
    for each it in Arr_or(resp.data.items)
        if Type(it) = "roAssociativeArray" then items.Push(it)
    end for
    m.profiles = items
    for each it in items
        if Str_orEmpty(it.id) = m.profileId then m.loaded = it
    end for
    if m.loaded = invalid then
        Diag_log("[siku-profiles] edit: the profile is not in the list; closing")
        m.global.toast = Tx("Profile not found")
        setResult({ changed: true })
        leave()
        return
    end if
    m.primary = Accounts_householdPrimary(items)
    if m.primary = invalid then
        Diag_log("[siku-profiles] edit: no primary profile; closing")
        m.global.toast = Tx("Couldn't find the primary profile needed to manage profiles.")
        leave()
        return
    end if
    ' The picker's manager acts as this primary; opened without one (a debug deep link), act as the
    ' listed primary and let the server ask for its PIN (a 403 asks it, as on a stale token).
    if m.manager = invalid or m.manager.id <> Str_orEmpty(m.primary.id) then m.manager = { id: Str_orEmpty(m.primary.id), token: "" }
    name = Str_orEmpty(m.loaded.name)
    if m.debugName <> "" then name = m.debugName
    m.nameField.text = name
    m.child = ProfileManage_flag(m.loaded.is_child)
    m.canDelete = ProfileManage_canDelete(m.loaded)
    m.deleteButton.visible = m.canDelete
    Diag_log("[siku-profiles] edit: shown primary=" + Session_boolWord(ProfileManage_flag(m.loaded.is_primary)) + " has_pin=" + Session_boolWord(ProfileManage_flag(m.loaded.has_pin)) + " child=" + Session_boolWord(m.child) + " can_delete=" + Session_boolWord(m.canDelete) + " primary_token=" + Session_boolWord(m.manager.token <> ""))
    renderPin()
    renderChild()
    layoutButtons()
    m.state = "form"
    m.form.visible = true
    m.focusKey = "name"
    applyFocus()
end sub

' ---------- The form ----------

function pinEnabled() as boolean
    if m.pinMode = "set" then return true
    if m.pinMode = "remove" then return false
    return m.loaded <> invalid and ProfileManage_flag(m.loaded.has_pin)
end function

sub renderPin()
    if m.pinMode = "set" then
        state = Tx("New")
    else if pinEnabled() then
        state = Tx("On")
    else
        state = Tx("Off")
    end if
    m.pinButton.text = TxF("PIN: {0}", [state])
    ' Screen reader: what OK does ("PIN: On, Change PIN").
    if pinEnabled() then m.pinButton.a11yLabel = A11y_join([m.pinButton.text, Tx("Change PIN")]) else m.pinButton.a11yLabel = A11y_join([m.pinButton.text, Tx("Set PIN")])
    m.removePinButton.visible = pinEnabled()
    if not m.removePinButton.visible and m.focusKey = "removePin" then
        m.focusKey = "pin"
        applyFocus()
    end if
end sub

sub renderChild()
    state = Tx("Off")
    if m.child then state = Tx("On")
    m.childButton.text = TxF("Child Profile: {0}", [state])
end sub

sub layoutButtons()
    gap = 24
    w = m.saveButton.width + gap + m.cancelButton.width
    x = (1920 - w) \ 2
    m.saveButton.translation = [x, 0]
    m.cancelButton.translation = [x + m.saveButton.width + gap, 0]
    m.deleteButton.translation = [(1920 - m.deleteButton.width) \ 2, 836]
end sub

sub showError(msg as string)
    m.errorLabel.text = msg
    m.errorLabel.visible = msg <> ""
    if msg <> "" then A11y_say("edit:error", msg, "", -1, 0)
end sub

sub onPinButton()
    if m.state <> "form" then return
    openPin("new")
end sub

' Remove: the profile opens without a PIN once saved (Android TV's Remove beside the PIN field).
sub onRemovePin()
    if m.state <> "form" then return
    if m.loaded <> invalid and ProfileManage_flag(m.loaded.has_pin) then m.pinMode = "remove" else m.pinMode = "keep"
    m.newPin = ""
    Diag_log("[siku-profiles] edit: PIN removal staged")
    m.focusKey = "pin"
    renderPin()
    applyFocus()
end sub

sub onChildToggle()
    if m.state <> "form" then return
    m.child = not m.child
    renderChild()
end sub

sub onCancel()
    if m.state = "sending" then return
    leave()
end sub

sub leave()
    m.state = "done"
    Nav_close()
end sub

' The result the picker reads when this screen closes (Back included): merged, never replaced.
sub setResult(extra as object)
    for each k in extra
        m.resultData[k] = extra[k]
    end for
    m.top.result = m.resultData
end sub

' ---------- Save ----------

sub onSave()
    if m.state <> "form" then return
    name = m.nameField.text
    problem = ProfileManage_editProblem(m.profiles, m.profileId, name, m.newPin)
    m.nameField.error = problem = "name" or problem = "taken" or problem = "long"
    if problem = "name" then
        showError(Tx("Profile name is required"))
    else if problem = "taken" then
        showError(Tx("A profile with this name already exists"))
    else if problem = "long" then
        showError(Tx("Use 64 characters or fewer."))
    else if problem = "pin" then
        showError(Tx("PIN must be 4 digits"))
    end if
    if problem <> "" then
        if problem = "pin" then m.focusKey = "pin" else m.focusKey = "name"
        applyFocus()
        return
    end if
    showError("")
    m.body = ProfileManage_updateBody(m.loaded, name, m.pinMode, m.newPin, m.child)
    m.retried = false
    sendSave()
end sub

sub sendSave()
    m.state = "sending"
    m.saveButton.text = Tx("Saving...")
    ' Never the name or the PIN in the log.
    Diag_log("[siku-profiles] edit: save sent fields=" + ProfileManage_describe(m.body) + " primary_token=" + Session_boolWord(m.manager.token <> ""))
    Api_call({ method: "PATCH", path: "/api/v2/profiles/" + Str_urlEncode(m.profileId), body: m.body, profile: false, headers: ProfileManage_headers(m.manager), timeout: 20 }, "onSaved")
end sub

sub onSaved(event as object)
    resp = Api_result(event)
    if m.state <> "sending" then return
    status = Int(Num_or(resp.status, 0))
    outcome = ProfileManage_saveOutcome(status, Api_errorCode(resp))
    Diag_log("[siku-profiles] edit: save outcome=" + outcome + " status=" + status.ToStr())
    m.saveButton.text = Tx("Save Changes")
    if outcome = "saved" then
        setResult({ changed: true })
        leave()
    else if outcome = "verify" and not m.retried then
        m.pending = "save"
        askPrimaryPin()
    else if outcome = "gone" then
        m.global.toast = Tx("Profile not found")
        setResult({ changed: true })
        leave()
    else
        m.state = "form"
        if outcome = "network" then
            showError(Tx("Network error. Please try again."))
        else if outcome = "verify" then
            showError(Tx("Enter the primary profile's PIN to manage profiles."))
        else if outcome = "taken" then
            showError(Api_reasonText(resp, Tx("A profile with this name already exists")))
        else
            showError(Api_reasonText(resp, Tx("Failed to update profile")))
        end if
        m.focusKey = "save"
        applyFocus()
    end if
end sub

' ---------- Delete ----------

sub onDeleteAsked()
    if m.state <> "form" or not m.canDelete or m.confirm <> invalid then return
    name = Str_orEmpty(m.loaded.name)
    title = TxF("Delete {0}?", [name])
    body = Tx("This removes the profile's watch history and preferences. This can't be undone.")
    if Str_orEmpty(m.global.session.profileId) = m.profileId then body = Tx("You're signed in as this profile. Deleting it removes its watch history and preferences, and you'll pick another profile to continue.")
    dlg = CreateObject("roSGNode", "StandardMessageDialog")
    if dlg <> invalid then
        dlg.title = title
        dlg.message = [body]
    else
        dlg = CreateObject("roSGNode", "Dialog")
        dlg.title = title
        dlg.message = body
    end if
    ' Cancel first, so it takes focus (the safe choice, as Sign Out and Remove request do).
    dlg.buttons = [Tx("Cancel"), Tx("Delete profile")]
    dlg.observeField("buttonSelected", "onDeleteButton")
    dlg.observeField("wasClosed", "onDeleteClosed")
    m.confirm = dlg
    m.top.getScene().dialog = dlg
    Diag_log("[siku-profiles] edit: delete asked")
end sub

sub closeConfirm()
    dlg = m.confirm
    m.confirm = invalid
    if dlg = invalid then return
    dlg.unobserveField("buttonSelected")
    dlg.unobserveField("wasClosed")
    dlg.close = true
    scene = m.top.getScene()
    if scene.dialog <> invalid and scene.dialog.isSameNode(dlg) then scene.dialog = invalid
end sub

sub onDeleteButton()
    dlg = m.confirm
    if dlg = invalid then return
    choice = dlg.buttonSelected
    closeConfirm()
    if choice = 1 then
        m.retried = false
        sendDelete()
    else
        Diag_log("[siku-profiles] edit: delete kept")
        m.focusKey = "delete"
        applyFocus()
    end if
end sub

' Back on the dialog keeps the profile.
sub onDeleteClosed()
    if m.confirm = invalid then return
    closeConfirm()
    Diag_log("[siku-profiles] edit: delete kept")
    m.focusKey = "delete"
    applyFocus()
end sub

sub sendDelete()
    m.state = "sending"
    showError("")
    Diag_log("[siku-profiles] edit: delete sent primary_token=" + Session_boolWord(m.manager.token <> ""))
    Api_call({ method: "DELETE", path: "/api/v2/profiles/" + Str_urlEncode(m.profileId), profile: false, headers: ProfileManage_headers(m.manager), timeout: 20 }, "onDeleted")
end sub

sub onDeleted(event as object)
    resp = Api_result(event)
    if m.state <> "sending" then return
    status = Int(Num_or(resp.status, 0))
    outcome = ProfileManage_deleteOutcome(status, Api_errorCode(resp))
    Diag_log("[siku-profiles] edit: delete outcome=" + outcome + " status=" + status.ToStr())
    if outcome = "deleted" or outcome = "gone" then
        setResult({ changed: true, deletedId: m.profileId })
        leave()
    else if outcome = "verify" and not m.retried then
        m.pending = "delete"
        askPrimaryPin()
    else
        m.state = "form"
        if outcome = "network" then
            showError(Tx("Network error. Please try again."))
        else if outcome = "verify" then
            showError(Tx("Enter the primary profile's PIN to manage profiles."))
        else
            showError(Api_reasonText(resp, Tx("Failed to delete profile")))
        end if
        m.focusKey = "delete"
        applyFocus()
    end if
end sub

' ---------- PIN pad: a new PIN, or the primary profile's PIN again ----------

' The primary's token is stale (a PIN or child change bumped the access-policy revision) or was
' never issued: ask its PIN, then send the call once more (HouseholdManagementSession.run).
sub askPrimaryPin()
    Diag_log("[siku-profiles] primary PIN needed again (403); asking")
    openPin("manage")
end sub

sub openPin(purpose as string)
    dlg = CreateObject("roSGNode", "AuthPinDialog")
    if purpose = "manage" then
        dlg.prompt = Tx("Enter this PIN to manage profiles")
        dlg.profile = m.primary
    else
        dlg.prompt = Tx("Enter a new 4-digit PIN")
        dlg.profile = m.loaded
    end if
    dlg.observeField("pinEntered", "onPinEntered")
    dlg.observeField("dismissed", "onPinDismissed")
    m.top.appendChild(dlg)
    m.pinDialog = dlg
    m.pinPurpose = purpose
    m.form.visible = false
    if m.active then dlg.setFocus(true)
end sub

sub closePin()
    dlg = m.pinDialog
    if dlg = invalid then return
    m.pinDialog = invalid
    dlg.unobserveField("pinEntered")
    dlg.unobserveField("dismissed")
    m.top.removeChild(dlg)
    m.form.visible = true
end sub

sub onPinDismissed()
    purpose = m.pinPurpose
    closePin()
    if purpose = "manage" then
        ' Cancel on the re-prompt ends manage mode (cancelReverify); the form stays with the reason.
        Diag_log("[siku-profiles] primary PIN cancelled; manage mode ends")
        m.manager.token = ""
        setResult({ manageEnded: true })
        m.pending = ""
        m.state = "form"
        showError(Tx("Enter the primary profile's PIN to manage profiles."))
        m.focusKey = "save"
    end if
    applyFocus()
end sub

sub onPinEntered()
    dlg = m.pinDialog
    if dlg = invalid then return
    if m.pinPurpose = "new" then
        ' Staged only: Save sends it (never logged).
        m.newPin = dlg.pinEntered
        m.pinMode = "set"
        closePin()
        Diag_log("[siku-profiles] edit: new PIN entered")
        renderPin()
        showError("")
        m.focusKey = "pin"
        applyFocus()
        return
    end if
    dlg.error = ""
    dlg.verifying = true
    id = Str_orEmpty(m.primary.id)
    Api_call({ method: "POST", path: "/api/v2/profiles/" + Str_urlEncode(id) + "/verify-pin", body: { pin: dlg.pinEntered }, profile: false, timeout: 15, context: { id: id } }, "onPinVerified")
end sub

sub onPinVerified(event as object)
    resp = Api_result(event)
    dlg = m.pinDialog
    if dlg = invalid or m.pinPurpose <> "manage" or Str_orEmpty(m.primary.id) <> Str_orEmpty(resp.context.id) then return
    dlg.verifying = false
    if resp.ok and resp.data <> invalid and Type(resp.data) = "roAssociativeArray" and not Str_isEmpty(resp.data.profile_token) then
        m.manager.token = Str_orEmpty(resp.data.profile_token)
        ' The picker keeps the new token for its next call (in memory only).
        setResult({ token: m.manager.token, manageEnded: false })
        closePin()
        Diag_log("[siku-profiles] primary PIN accepted; sending again")
        m.retried = true
        pending = m.pending
        m.pending = ""
        if pending = "delete" then sendDelete() else sendSave()
        return
    end if
    if resp.status = 0 then
        dlg.error = Tx("Network error. Please try again.")
    else if resp.status = 429 then
        dlg.error = Tx("Too many attempts. Wait a moment, then try again.")
    else if resp.ok or (resp.status >= 400 and resp.status < 500) then
        dlg.error = Tx("That PIN didn't work. Try again.")
    else
        dlg.error = Api_errorText(resp)
    end if
end sub

' ---------- Focus and keys ----------

function nodeFor(k as string) as object
    if k = "name" then return m.nameField
    if k = "pin" then return m.pinButton
    if k = "removePin" then return m.removePinButton
    if k = "child" then return m.childButton
    if k = "cancel" then return m.cancelButton
    if k = "delete" then return m.deleteButton
    return m.saveButton
end function

' Rows top to bottom; the second item of a row is reached with Right.
function focusRows() as object
    rows = [["name"], ["pin", "removePin"], ["child"], ["save", "cancel"]]
    if m.canDelete then rows.Push(["delete"])
    return rows
end function

sub applyFocus()
    if not m.active then return
    if m.pinDialog <> invalid then
        m.pinDialog.setFocus(true)
        return
    end if
    if m.confirm <> invalid then return ' the dialog holds focus
    if m.state = "loading" or m.state = "done" then
        m.top.setFocus(true)
        return
    end if
    if m.focusKey = "removePin" and not m.removePinButton.visible then m.focusKey = "pin"
    if m.focusKey = "delete" and not m.canDelete then m.focusKey = "save"
    nodeFor(m.focusKey).setFocus(true)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.pinDialog <> invalid then return true ' the dialog handles its own keys
    if key = "back" then
        ' Leaving while a call is on its way would hide its answer: wait for it.
        if m.state = "sending" then return true
        return false
    end if
    if m.state <> "form" then return true
    rows = focusRows()
    r = 0
    c = 0
    for i = 0 to rows.Count() - 1
        for j = 0 to rows[i].Count() - 1
            if rows[i][j] = m.focusKey then
                r = i
                c = j
            end if
        end for
    end for
    if key = "up" and r > 0 then
        m.focusKey = rows[r - 1][0]
    else if key = "down" and r < rows.Count() - 1 then
        m.focusKey = rows[r + 1][0]
    else if key = "right" and c = 0 and rows[r].Count() > 1 then
        nxt = rows[r][1]
        if nxt <> "removePin" or m.removePinButton.visible then m.focusKey = nxt
    else if key = "left" and c = 1 then
        m.focusKey = rows[r][0]
    end if
    applyFocus()
    return true
end function
