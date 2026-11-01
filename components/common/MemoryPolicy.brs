' Memory policy: three levels of response to memory warnings and a low-memory device mode chosen at
' launch, as pure functions over plain numbers (host-tested in tests/test_memory_policy.py).
' The level comes from the channel's memory use as a percent of its limit (MainEvents_memoryPressure,
' forwarded by source/main.brs, which also samples GetMemoryLimitPercent() every 2 s while the
' level is raised, so it can come back down):
'   0 normal
'   1 trim      (70 % or more; Roku's first warning is at 80 %): the top screen drops its own caches,
'               only one screen under the top stays fully alive, library grids keep 3 pages and
'               read ahead 5 rows
'   2 pressure  (85 %, or the device-wide "low" level): every covered screen gives back its artwork
'               and lists, at once and whenever it is covered again
'   3 critical  (90 %, or the device-wide "critical" level): library grids keep 2 pages
' A level rises at once and falls one step per sample below 65 %.
' The low-memory device mode (MainEvents_deviceTier: an HD UI, no OpenGL, no memory monitor, or a
' foreground limit under 400 MB) keeps one screen under the top alive, 5 grid pages and reads 5
' rows ahead. Budgets adapted from Silo-Server/silo-roku, AGPL-3.0 (source/memory/policy.bs).
' SPDX-License-Identifier: AGPL-3.0-or-later

function Memory_levelFor(percent as integer) as integer
    if percent >= 90 then return 3
    if percent >= 85 then return 2
    if percent >= 70 then return 1
    return 0
end function

' The level after a sample: up at once to what the sample calls for, down one step at a time and
' only while the sample is below 65 %. A negative sample (unknown) keeps the level.
function Memory_nextLevel(current as integer, percent as integer) as integer
    if percent < 0 then return current
    wanted = Memory_levelFor(percent)
    if wanted > current then return wanted
    if wanted < current and percent < 65 then return current - 1
    return current
end function

function Memory_levelName(level as integer) as string
    if level >= 3 then return "critical"
    if level = 2 then return "pressure"
    if level = 1 then return "trim"
    return "normal"
end function

' How many screens directly under the top one keep their artwork and lists.
function Memory_aliveBelow(level as integer, lowEnd as boolean) as integer
    if level >= 2 then return 0
    if level = 1 or lowEnd then return 1
    return 2
end function

' How many pages a library grid keeps loaded (pages further from focus are dropped and read again
' when the viewer scrolls back to them).
function Memory_gridPages(level as integer, lowEnd as boolean) as integer
    if level >= 3 then return 2
    if level >= 1 then return 3
    if lowEnd then return 5
    return 10
end function

' How many rows before the end of what is loaded the grid asks for more.
function Memory_prefetchRows(level as integer, lowEnd as boolean) as integer
    if level >= 1 or lowEnd then return 5
    return 8
end function

' The app-wide level and device mode (m.global.memoryLevel / lowEnd, set by MainScene and main.brs).
function Memory_currentLevel() as integer
    g = m.global
    if g = invalid then return 0
    if not g.hasField("memoryLevel") then return 0
    v = g.memoryLevel
    t = Type(v)
    if t = "Integer" or t = "roInt" or t = "roInteger" then return v
    return 0
end function

function Memory_isLowEnd() as boolean
    g = m.global
    if g = invalid then return false
    if not g.hasField("lowEnd") then return false
    v = g.lowEnd
    if Type(v) = "Boolean" or Type(v) = "roBoolean" then return v
    return false
end function
