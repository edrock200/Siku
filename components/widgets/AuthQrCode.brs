' AuthQrCode: renders a QR matrix from QrCode.brs as merged black Rectangles.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.tile = m.top.findNode("tile")
    m.modules = m.top.findNode("modules")
    m.lastKey = ""
    rebuild()
end sub

sub rebuild()
    qrSize = m.top.qrSize
    pad = m.top.padding
    tileSize = qrSize + pad * 2
    m.tile.width = tileSize
    m.tile.height = tileSize
    m.top.tileSize = tileSize

    key = m.top.text + "|" + qrSize.ToStr() + "|" + pad.ToStr()
    if key = m.lastKey then return
    m.lastKey = key
    m.modules.removeChildrenIndex(m.modules.getChildCount(), 0)
    m.top.version = 0
    if m.top.text = "" then return

    qr = QrCode_encode(m.top.text)
    if qr = invalid then return
    m.top.version = qr.version

    total = qr.size + 8 ' 4-module quiet zone on each side
    px = qrSize \ total
    if px < 1 then px = 1
    drawn = px * total
    origin = pad + (qrSize - drawn) \ 2 + 4 * px
    m.modules.translation = [origin, origin]

    nodes = []
    for each r in QrCode_rects(qr)
        rect = CreateObject("roSGNode", "Rectangle")
        rect.color = "0x000000FF"
        rect.translation = [r.x * px, r.y * px]
        rect.width = r.w * px
        rect.height = r.h * px
        nodes.Push(rect)
    end for
    m.modules.appendChildren(nodes)
end sub
