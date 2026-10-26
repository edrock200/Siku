' Memory warnings (roAppMemoryMonitor, forwarded by source/main.brs through MainScene).
' A screen under the top of the stack is invisible but keeps its textures: remote artwork Posters
' and the content of its RowLists / MarkupGrids (whose cards hold every poster). On a warning
' MainScene asks each covered screen to release them (BaseScreen.memoryRelease), and the screen
' puts them back when it is shown again, before its onScreenShown runs. Bundled pkg:/ images are
' small UI assets and stay. The approach follows ManavA/silo-roku, AGPL-3.0
' (components/SiloUIRobustness.brs: clear artwork and off-screen content, reload on return).
' Included by BaseScreen.xml; runs in the screen's scope.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub Memory_release(root as object)
    if m.memoryStash <> invalid then return
    stash = { posters: [], lists: [] }
    Memory_walk(root, stash)
    m.memoryStash = stash
    print "[siku-memory] released "; root.subtype(); " posters="; stash.posters.Count(); " lists="; stash.lists.Count()
end sub

sub Memory_walk(node as object, stash as object)
    st = node.subtype()
    if st = "Poster" then
        u = node.uri
        if Type(u) = "roString" or Type(u) = "String" then
            if u <> "" and LCase(Left(u, 5)) <> "pkg:/" then
                stash.posters.Push({ node: node, uri: u })
                node.uri = ""
            end if
        end if
    else if st = "RowList" or st = "ZoomRowList" or st = "MarkupGrid" or st = "PosterGrid" then
        c = node.content
        if c <> invalid then
            if st = "MarkupGrid" or st = "PosterGrid" then focus = node.itemFocused else focus = node.rowItemFocused
            empty = CreateObject("roSGNode", "ContentNode")
            stash.lists.Push({ node: node, content: c, focus: focus, grid: st = "MarkupGrid" or st = "PosterGrid", placeholder: empty })
            node.content = empty
        end if
        return ' the list's item components are its own; dropping the content releases them
    end if
    for each child in node.getChildren(-1, 0)
        Memory_walk(child, stash)
    end for
end sub

' Puts back what Memory_release took, unless the screen replaced it meanwhile.
sub Memory_restore()
    stash = m.memoryStash
    if stash = invalid then return
    m.memoryStash = invalid
    for each p in stash.posters
        if p.node.uri = "" then p.node.uri = p.uri
    end for
    for each l in stash.lists
        cur = l.node.content
        if cur <> invalid and cur.isSameNode(l.placeholder) then
            l.node.content = l.content
            if l.grid then
                if Type(l.focus) = "roInt" or Type(l.focus) = "roInteger" or Type(l.focus) = "Integer" then
                    if l.focus > 0 and l.focus < l.content.getChildCount() then l.node.jumpToItem = l.focus
                end if
            else if Type(l.focus) = "roArray" then
                if l.focus.Count() = 2 then
                    r = l.focus[0]
                    if r >= 0 and r < l.content.getChildCount() and l.focus[1] >= 0 then l.node.jumpToRowItem = [r, l.focus[1]]
                end if
            end if
        end if
    end for
    print "[siku-memory] restored "; m.top.subtype()
end sub
