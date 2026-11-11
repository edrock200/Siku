' NewProfileScreen: the profile menu's Add Profile (Silo Android #881; see the XML). The form's
' rules and its outcome reading are adapted from Silo-Server/silo-roku, AGPL-3.0
' (source/onboarding/createProfile.bs); the pure parts live in Accounts.brs.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.form = m.top.findNode("form")
    m.spinner = m.top.findNode("spinner")
    m.nameField = m.top.findNode("nameField")
    m.pinField = m.top.findNode("pinField")
    m.childButton = m.top.findNode("childButton")
    m.errorLabel = m.top.findNode("error")
    m.buttonsGroup = m.top.findNode("buttons")
    m.createButton = m.top.findNode("createButton")
    m.cancelButton = m.top.findNode("cancelButton")
    ' AuthTextField's placeholders are not translated with the layout.
    m.nameField.placeholder = Tx("Profile name")
    m.pinField.placeholder = Tx("PIN (optional)")
    m.nameField.a11yLabel = Tx("Name")
    m.createButton.observeField("buttonSelected", "onCreate")
    m.cancelButton.observeField("buttonSelected", "onCancel")
    m.childButton.observeField("buttonSelected", "onChildToggle")
    m.createButton.observeField("width", "layoutButtons")
    m.cancelButton.observeField("width", "layoutButtons")

    m.child = false
    m.primary = invalid
    m.primaryToken = ""
    m.pinDialog = invalid
    m.state = "loading"     ' loading | form | sending | done
    m.focusKey = "name"     ' name | pin | child | create | cancel
    m.active = false
    renderChild()
    layoutButtons()
    m.spinner.visible = true
    ' The current list says which profile is the primary one and whether it has a PIN.
    Api_call({ method: "GET", path: "/api/v2/profiles", profile: false, timeout: 15 }, "onProfiles")
end sub

sub onScreenShown()
    m.active = true
    applyFocus()
end sub

sub onScreenHidden()
    m.active = false
end sub

' ---------- The primary profile ----------

sub onProfiles(event as object)
    resp = Api_result(event)
    m.spinner.visible = false
    if not resp.ok or resp.data = invalid or Type(resp.data) <> "roAssociativeArray" then
        Diag_log("[siku-profiles] add profile: the profile list failed status=" + Int(Num_or(resp.status, 0)).ToStr())
        m.global.toast = Api_errorText(resp)
        Nav_close()
        return
    end if
    items = Arr_or(resp.data.items)
    s = m.global.session
    if not Accounts_isTemporary(s) then Accounts_setProfiles(Str_orEmpty(s.accountId), items.Count(), Accounts_maxProfilesOf(resp.data))
    p = Accounts_householdPrimary(items)
    if p = invalid then
        ' No primary known: the picker, where the account's profiles are chosen (Android TV).
        Diag_log("[siku-profiles] add profile: no primary profile; showing the picker")
        openPicker()
        return
    end if
    m.primary = p
    if isTrue(p.has_pin) then
        Diag_log("[siku-profiles] add profile: asking the primary profile's PIN")
        openPin(p)
        return
    end if
    Diag_log("[siku-profiles] add profile: form shown")
    showForm()
end sub

sub openPin(p as object)
    dlg = CreateObject("roSGNode", "AuthPinDialog")
    dlg.profile = p
    dlg.observeField("pinEntered", "onPinEntered")
    dlg.observeField("dismissed", "onPinDismissed")
    m.top.appendChild(dlg)
    m.pinDialog = dlg
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
end sub

' Cancel on the primary profile's PIN: back where the menu was.
sub onPinDismissed()
    closePin()
    Diag_log("[siku-profiles] add profile: PIN cancelled")
    Nav_close()
end sub

sub onPinEntered()
    dlg = m.pinDialog
    if dlg = invalid or m.primary = invalid then return
    dlg.error = ""
    dlg.verifying = true
    id = Str_orEmpty(m.primary.id)
    Api_call({ method: "POST", path: "/api/v2/profiles/" + Str_urlEncode(id) + "/verify-pin", body: { pin: dlg.pinEntered }, profile: false, timeout: 15, context: { id: id } }, "onPinVerified")
end sub

sub onPinVerified(event as object)
    resp = Api_result(event)
    dlg = m.pinDialog
    if dlg = invalid or m.primary = invalid or Str_orEmpty(m.primary.id) <> Str_orEmpty(resp.context.id) then return
    dlg.verifying = false
    if resp.ok and resp.data <> invalid and Type(resp.data) = "roAssociativeArray" and not Str_isEmpty(resp.data.profile_token) then
        m.primaryToken = Str_orEmpty(resp.data.profile_token)
        closePin()
        Diag_log("[siku-profiles] add profile: primary PIN accepted; form shown")
        showForm()
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

' ---------- The form ----------

sub showForm()
    m.state = "form"
    m.form.visible = true
    m.focusKey = "name"
    applyFocus()
end sub

sub renderChild()
    state = Tx("Off")
    if m.child then state = Tx("On")
    m.childButton.text = TxF("Child Profile: {0}", [state])
end sub

sub layoutButtons()
    gap = 24
    w = m.createButton.width + gap + m.cancelButton.width
    x = (1920 - w) \ 2
    m.createButton.translation = [x, 0]
    m.cancelButton.translation = [x + m.createButton.width + gap, 0]
end sub

sub onChildToggle()
    if m.state <> "form" then return
    m.child = not m.child
    renderChild()
end sub

sub showError(msg as string)
    m.errorLabel.text = msg
    m.errorLabel.visible = msg <> ""
end sub

sub onCreate()
    if m.state <> "form" then return
    name = m.nameField.text
    pin = m.pinField.text.Trim()
    problem = Accounts_newProfileProblem(name, pin)
    m.nameField.error = problem = "name"
    m.pinField.error = problem = "pin"
    if problem = "name" then
        showError(Tx("Please enter a name."))
        m.focusKey = "name"
        applyFocus()
        return
    else if problem = "pin" then
        showError(Tx("Enter all 4 digits, or leave the PIN empty for no PIN."))
        m.focusKey = "pin"
        applyFocus()
        return
    end if
    showError("")
    m.state = "sending"
    m.createButton.text = Tx("Creating…")
    headers = { "X-Profile-Id": Str_orEmpty(m.primary.id) }
    if m.primaryToken <> "" then headers["X-Profile-Token"] = m.primaryToken
    ' Never the name or the PIN in the log.
    Diag_log("[siku-profiles] add profile: create sent child=" + Session_boolWord(m.child) + " pin=" + Session_boolWord(pin <> ""))
    Api_call({ method: "POST", path: "/api/v2/profiles", body: Accounts_newProfileBody(name, pin, m.child), profile: false, headers: headers, timeout: 20 }, "onCreated")
end sub

sub onCreated(event as object)
    resp = Api_result(event)
    if m.state <> "sending" then return
    status = Int(Num_or(resp.status, 0))
    code = ""
    if resp.error <> invalid and Type(resp.error) = "roAssociativeArray" then code = Str_orEmpty(resp.error.code)
    outcome = Accounts_createOutcome(status, code)
    Diag_log("[siku-profiles] add profile: create outcome=" + outcome + " status=" + status.ToStr())
    if outcome = "created" then
        openPicker()
    else if outcome = "unconfirmed" then
        ' It may exist: the picker's fresh list says (never sent twice).
        m.global.toastSeconds = 6
        m.global.toast = Tx("No answer came from the server. Check the profile list before trying again.")
        openPicker()
    else if outcome = "verify" then
        m.global.toast = Tx("Enter the primary profile's PIN again, then try again.")
        m.state = "done"
        Nav_close()
    else
        m.state = "form"
        m.createButton.text = Tx("Create Profile")
        showError(Api_reasonText(resp, Tx("Something went wrong. Try again.")))
        m.focusKey = "create"
        applyFocus()
    end if
end sub

' The account's picker with no profile open, as Switch Profile leads there after a new profile
' (Android TV clears the active profile and opens ProfileSelection).
sub openPicker()
    m.state = "done"
    s = m.global.session
    if not Accounts_isTemporary(s) then
        c = AA_copy(s)
        c.profileId = ""
        c.profileToken = ""
        c.profileName = ""
        c.profileAvatar = ""
        Session_save(c)
    end if
    m.global.homeDirty = true
    Nav_reset("ProfileScreen", { switching: true })
end sub

sub onCancel()
    if m.state = "sending" then return
    Nav_close()
end sub

' ---------- Focus and keys ----------

function focusOrder() as object
    return ["name", "pin", "child", "create"]
end function

function nodeFor(k as string) as object
    if k = "name" then return m.nameField
    if k = "pin" then return m.pinField
    if k = "child" then return m.childButton
    if k = "cancel" then return m.cancelButton
    return m.createButton
end function

sub applyFocus()
    if not m.active then return
    if m.pinDialog <> invalid then
        m.pinDialog.setFocus(true)
        return
    end if
    if m.state = "loading" then
        m.top.setFocus(true)
        return
    end if
    nodeFor(m.focusKey).setFocus(true)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.pinDialog <> invalid then return true ' the dialog handles its own keys
    if key = "back" then
        ' Leaving while a create is on its way would hide its answer: wait for it.
        if m.state = "sending" then return true
        return false
    end if
    if m.state <> "form" then return true
    order = focusOrder()
    k = m.focusKey
    if k = "cancel" then k = "create"
    idx = 0
    for i = 0 to order.Count() - 1
        if order[i] = k then idx = i
    end for
    if key = "up" and idx > 0 then
        m.focusKey = order[idx - 1]
    else if key = "down" and idx < order.Count() - 1 then
        m.focusKey = order[idx + 1]
    else if key = "right" and m.focusKey = "create" then
        m.focusKey = "cancel"
    else if key = "left" and m.focusKey = "cancel" then
        m.focusKey = "create"
    end if
    applyFocus()
    return true
end function

function isTrue(v as dynamic) as boolean
    t = Type(v)
    if t = "Boolean" or t = "roBoolean" then return v
    return false
end function
