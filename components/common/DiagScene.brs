' MainScene's side of diagnostics (Diag.brs, DiagTask): starts the log, hands over how the last
' launch ended, and after an unexpected close shows a notice once Home is up. Included by
' MainScene only. The notice idea is from Silo-Server/silo-roku, AGPL-3.0
' (components/screens/home/HomeScreen.bs); Siku only points to Settings › Diagnostics.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub Diag_init()
    ' diagReady first: Diag_log reads it once diagLine exists.
    m.global.addFields({ diagExit: {}, diagReady: false, diagBacklog: [] })
    m.global.addField("diagLine", "string", true)
    task = CreateObject("roSGNode", "DiagTask")
    m.global.addFields({ diagTask: task })
    task.control = "RUN"
    m.diagNotice = invalid
    m.global.observeField("diagExit", "Diag_onExit")
end sub

' From the launch arguments: Roku's reason for the last exit. debugExit=<EXIT_CODE> stands in for it
' in the simulator (which records none), e.g. debugExit=EXIT_CHANNEL_MEM_LIMIT_FG.
sub Diag_launchArgs(args as dynamic)
    if Type(args) <> "roAssociativeArray" then return
    reason = Str_orEmpty(args.lastExitOrTerminationReason)
    #if DEBUG
        if not Str_isEmpty(args.debugExit) then reason = Str_orEmpty(args.debugExit)
    #end if
    m.global.diagTask.launchReason = reason
end sub

sub Diag_onExit()
    e = m.global.diagExit
    if Type(e) <> "roAssociativeArray" then return
    ' Read the flag by type: comparing a missing value with true throws on a Roku (pitfall 16).
    if Type(e.fresh) <> "Boolean" and Type(e.fresh) <> "roBoolean" then return
    if not e.fresh then return
    m.diagNotice = e
    Diag_tryNotice()
end sub

' Shows the notice once Home has rendered (launch ready) and is on top, 2 s after it settled.
sub Diag_tryNotice()
    if m.diagNotice = invalid or not m.launch.done then return
    top = topScreen()
    if top = invalid or top.subtype() <> "ShellScreen" then return
    if m.diagTimer = invalid then
        m.diagTimer = CreateObject("roSGNode", "Timer")
        m.diagTimer.duration = 2
        m.diagTimer.observeField("fire", "Diag_showNotice")
    end if
    m.diagTimer.control = "start"
end sub

sub Diag_showNotice()
    e = m.diagNotice
    if e = invalid then return
    m.diagNotice = invalid
    Diag_log(Diag_join(["[siku-diag] notice shown kind=", Str_orEmpty(e.kind)]))
    if not m.global.hasField("toastSeconds") then m.global.addFields({ toastSeconds: 0.0 })
    m.global.toastSeconds = 10
    m.global.toast = TxF("Siku closed unexpectedly last time: {0}. See Settings › Diagnostics.", [Diag_exitWords(Str_orEmpty(e.kind))])
end sub
